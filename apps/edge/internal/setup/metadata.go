// Package setup provisions a same-user Windows POS host, never restaurant authority.
package setup

import (
	"bytes"
	"context"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"regexp"
	"time"

	"vynic.local/edge/internal/updater"
)

const SignatureDomain = "VYNIC-BOOTSTRAP-v1\n"
const EdgeExecutable = "VynicEdge.exe"
const SetupExecutable = "VynicSetup.exe"

// Distribution is embedded by the release build, or supplied explicitly by an
// administrator. Network metadata cannot replace these trust roots.
type Distribution struct {
	BootstrapURL string                        `json:"bootstrapURL"`
	Channel      string                        `json:"channel"`
	Keys         map[string]updater.TrustedKey `json:"keys"`
}
type Bootstrap struct {
	POSBinaryLayout int              `json:"posBinaryLayout"`
	Product         string           `json:"product"`
	Protocol        int              `json:"protocol"`
	Release         uint64           `json:"release"`
	OS              string           `json:"os"`
	Arch            string           `json:"arch"`
	Channel         string           `json:"channel"`
	Expires         time.Time        `json:"expires"`
	Edge            updater.Manifest `json:"edge"`
	POS             json.RawMessage  `json:"pos"`
	POSFeed         string           `json:"posFeed"`
	// Renewed, signed metadata for this baseline / exact active POS version.
	RepairBase     string `json:"repairBase"`
	POSReleaseBase string `json:"posReleaseBase"`
}

var version = regexp.MustCompile(`^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$`)

func strict(b []byte, v any) error {
	d := json.NewDecoder(bytes.NewReader(b))
	d.DisallowUnknownFields()
	if e := d.Decode(v); e != nil {
		return e
	}
	if d.Decode(new(any)) != io.EOF {
		return errors.New("trailing JSON")
	}
	return nil
}
func https(raw string) bool {
	u, e := url.Parse(raw)
	return e == nil && u.Scheme == "https" && u.Host != "" && u.User == nil && u.Fragment == ""
}
func (d Distribution) Validate() error {
	if !https(d.BootstrapURL) || d.Channel == "" || len(d.Keys) == 0 {
		return errors.New("HTTPS bootstrap endpoint, channel and pinned public keys required")
	}
	return nil
}
func Verify(raw []byte, d Distribution, now time.Time) (Bootstrap, updater.Manifest, error) {
	var b Bootstrap
	var p updater.Manifest
	if e := d.Validate(); e != nil {
		return b, p, e
	}
	payload, e := updater.VerifyEnvelope(raw, d.Keys, SignatureDomain, now)
	if e != nil {
		return b, p, e
	}
	if e = strict(payload, &b); e != nil {
		return b, p, e
	}
	m := b.Edge
	digest, de := hex.DecodeString(m.SHA256)
	if b.POSBinaryLayout != 2 || b.Product != "vynic-bootstrap" || b.Protocol != 1 || b.Release == 0 || b.OS != "windows" || b.Arch != "amd64" || b.Channel != d.Channel || !now.Before(b.Expires) || b.Expires.After(now.Add(31*24*time.Hour)) ||
		m.Product != "vynic-edge" || !version.MatchString(m.Version) || m.Release == 0 || m.OS != "windows" || m.Arch != "amd64" || m.Channel != b.Channel || m.UpdaterProtocol != 1 || m.EdgeSchema != 2 || m.HiveSchema != 9 || m.DataPolicy != "edge2-no-migration" || !now.Before(m.Expires) || m.Expires.After(now.Add(31*24*time.Hour)) || !https(m.URL) || de != nil || len(digest) != 32 || m.Size < 1 || m.Size > updater.MaxArtifact || !https(b.POSFeed) || !https(b.RepairBase) || !https(b.POSReleaseBase) {
		return b, p, errors.New("bootstrap compatibility/policy rejected")
	}
	p, e = updater.Verify(b.POS, d.Keys, d.Channel, "0.0.0", 0, now)
	return b, p, e
}

// SecureClient keeps fixture TLS roots while refusing HTTP redirects even when
// the caller injected a test client. No InsecureSkipVerify is used.
func SecureClient(base *http.Client) *http.Client {
	c := http.Client{Timeout: 30 * time.Minute}
	if base != nil {
		c = *base
	}
	if c.Timeout == 0 {
		c.Timeout = 30 * time.Minute
	}
	c.CheckRedirect = func(r *http.Request, via []*http.Request) error {
		if len(via) > 5 || !https(r.URL.String()) {
			return errors.New("unsafe release redirect")
		}
		return nil
	}
	return &c
}
func fetch(ctx context.Context, c *http.Client, u string, limit int64) ([]byte, error) {
	if !https(u) {
		return nil, errors.New("HTTPS required")
	}
	r, e := http.NewRequestWithContext(ctx, "GET", u, nil)
	if e != nil {
		return nil, e
	}
	resp, e := c.Do(r)
	if e != nil {
		return nil, e
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("release HTTP %d", resp.StatusCode)
	}
	b, e := io.ReadAll(io.LimitReader(resp.Body, limit+1))
	if int64(len(b)) > limit {
		return nil, errors.New("metadata too large")
	}
	return b, e
}
func download(ctx context.Context, c *http.Client, m updater.Manifest, path string, report func(string)) error {
	if !https(m.URL) {
		return errors.New("HTTPS artifact required")
	}
	if updater.VerifyArtifact(path, m) == nil {
		return nil
	}
	r, e := http.NewRequestWithContext(ctx, "GET", m.URL, nil)
	if e != nil {
		return e
	}
	resp, e := c.Do(r)
	if e != nil {
		return e
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return fmt.Errorf("artifact HTTP %d", resp.StatusCode)
	}
	part := path + ".part"
	f, e := os.OpenFile(part, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0600)
	if e != nil {
		return e
	}
	defer os.Remove(part)
	report("Downloading " + m.Product + " " + m.Version)
	_, e = io.Copy(f, io.LimitReader(resp.Body, m.Size+1))
	e = errors.Join(e, f.Sync(), f.Close())
	if e != nil {
		return e
	}
	if e = updater.VerifyArtifact(part, m); e != nil {
		return e
	}
	return replaceFile(part, path)
}
