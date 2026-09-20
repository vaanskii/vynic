// Package updater installs only signed Windows POS bundles. It never owns data.
package updater

import (
	"archive/zip"
	"bytes"
	"crypto/ed25519"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

const Product = "vynic-pos"
const Executable = "vynic_pos.exe"
const MaxArtifact = 512 << 20
const MaxExpanded = 1536 << 20
const signatureDomain = "VYNIC-POS-RELEASE-v1\n"

type Manifest struct {
	Product         string    `json:"product"`
	Version         string    `json:"version"`
	Release         uint64    `json:"release"`
	OS              string    `json:"os"`
	Arch            string    `json:"arch"`
	Channel         string    `json:"channel"`
	URL             string    `json:"url"`
	SHA256          string    `json:"sha256"`
	Size            int64     `json:"size"`
	Expires         time.Time `json:"expires"`
	UpdaterProtocol int       `json:"updaterProtocol"`
	HiveSchema      int       `json:"hiveSchema"`
	EdgeSchema      int       `json:"edgeSchema"`
	DataPolicy      string    `json:"dataPolicy"`
}
type Envelope struct {
	KeyID     string `json:"keyId"`
	Payload   string `json:"payload"`
	Signature string `json:"signature"`
}
type TrustedKey struct {
	Public  string    `json:"public"`
	Expires time.Time `json:"expires"`
}

var versionRE = regexp.MustCompile(`^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$`)

func newer(a, b string) bool {
	if !versionRE.MatchString(a) || !versionRE.MatchString(b) {
		return false
	}
	var x, y [3]uint64
	if _, e := fmt.Sscanf(a, "%d.%d.%d", &x[0], &x[1], &x[2]); e != nil {
		return false
	}
	if _, e := fmt.Sscanf(b, "%d.%d.%d", &y[0], &y[1], &y[2]); e != nil {
		return false
	}
	for i := range x {
		if x[i] != y[i] {
			return x[i] > y[i]
		}
	}
	return false
}
func decodeStrict(b []byte, v any) error {
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
func Verify(raw []byte, keys map[string]TrustedKey, channel, current string, high uint64, now time.Time) (Manifest, error) {
	var e Envelope
	var m Manifest
	if err := decodeStrict(raw, &e); err != nil {
		return m, err
	}
	k, ok := keys[e.KeyID]
	if !ok || !now.Before(k.Expires) {
		return m, errors.New("untrusted/expired release key")
	}
	pub, err := base64.StdEncoding.DecodeString(k.Public)
	if err != nil || len(pub) != ed25519.PublicKeySize {
		return m, errors.New("invalid trusted key")
	}
	payload, err := base64.StdEncoding.DecodeString(e.Payload)
	if err != nil {
		return m, err
	}
	sig, err := base64.StdEncoding.DecodeString(e.Signature)
	if err != nil || !ed25519.Verify(pub, append([]byte(signatureDomain), payload...), sig) {
		return m, errors.New("invalid release signature")
	}
	if err = decodeStrict(payload, &m); err != nil {
		return m, err
	}
	u, err := url.Parse(m.URL)
	digest, de := hex.DecodeString(m.SHA256)
	if m.Product != Product || m.OS != "windows" || m.Arch != "amd64" || m.Channel != channel || !newer(m.Version, current) || m.Release <= high || m.UpdaterProtocol != 1 || m.HiveSchema != 9 || m.EdgeSchema != 2 || m.DataPolicy != "hive9-no-migration" || !now.Before(m.Expires) || m.Expires.After(now.Add(31*24*time.Hour)) || err != nil || u.Scheme != "https" || u.Host == "" || u.User != nil || de != nil || len(digest) != 32 || m.Size < 1 || m.Size > MaxArtifact {
		return m, errors.New("release compatibility/policy rejected")
	}
	return m, nil
}
func verifyFile(path string, m Manifest) error {
	f, e := os.Open(path)
	if e != nil {
		return e
	}
	defer f.Close()
	h := sha256.New()
	n, e := io.Copy(h, io.LimitReader(f, MaxArtifact+1))
	if e != nil {
		return e
	}
	if n != m.Size || hex.EncodeToString(h.Sum(nil)) != m.SHA256 {
		return errors.New("artifact hash/size mismatch")
	}
	return nil
}

// Extract only regular, portable relative paths. No scripts or installer is run.
func extract(artifact, dest string) error {
	z, e := zip.OpenReader(artifact)
	if e != nil {
		return e
	}
	defer z.Close()
	if len(z.File) > 20000 {
		return errors.New("too many bundle files")
	}
	seen := map[string]bool{}
	var total uint64
	hasEXE := false
	for _, f := range z.File {
		name := strings.TrimSuffix(f.Name, "/")
		lower := strings.ToLower(name)
		if name == "" || strings.ContainsAny(name, `\:<>"|?*`) || strings.HasPrefix(name, "/") || seen[lower] || f.Mode()&os.ModeSymlink != 0 {
			return errors.New("unsafe bundle path")
		}
		for _, part := range strings.Split(name, "/") {
			base := strings.ToUpper(strings.Split(part, ".")[0])
			if part == "." || part == ".." || strings.TrimRight(part, " .") != part || part == "" || regexp.MustCompile(`^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$`).MatchString(base) {
				return errors.New("unsafe Windows bundle path")
			}
		}
		seen[lower] = true
		if f.UncompressedSize64 > MaxExpanded-total {
			return errors.New("expanded bundle too large")
		}
		total += f.UncompressedSize64
		target := filepath.Join(dest, filepath.FromSlash(name))
		if f.FileInfo().IsDir() {
			if e = os.MkdirAll(target, 0700); e != nil {
				return e
			}
			continue
		}
		if !f.Mode().IsRegular() {
			return errors.New("non-regular bundle entry")
		}
		if e = os.MkdirAll(filepath.Dir(target), 0700); e != nil {
			return e
		}
		in, e := f.Open()
		if e != nil {
			return e
		}
		out, e := os.OpenFile(target, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
		if e != nil {
			in.Close()
			return e
		}
		_, e = io.Copy(out, io.LimitReader(in, int64(f.UncompressedSize64)+1))
		e = errors.Join(e, out.Sync(), out.Close(), in.Close())
		if e != nil {
			return e
		}
		if name == Executable {
			hasEXE = true
		}
	}
	if !hasEXE {
		return errors.New("POS executable absent")
	}
	return nil
}
