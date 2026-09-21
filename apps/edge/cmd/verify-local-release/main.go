// Development-only release endpoint validation using the installer's own policy.
package main

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"time"

	"vynic.local/edge/internal/setup"
	"vynic.local/edge/internal/updater"
)

func main() {
	if e := run(); e != nil {
		fmt.Fprintln(os.Stderr, e)
		os.Exit(1)
	}
}
func run() error {
	distribution := flag.String("distribution", "", "local distribution JSON")
	ca := flag.String("ca", "", "mkcert public CA certificate")
	flag.Parse()
	raw, e := os.ReadFile(*distribution)
	if e != nil {
		return e
	}
	var d setup.Distribution
	if e = json.Unmarshal(raw, &d); e != nil {
		return e
	}
	u, e := url.Parse(d.BootstrapURL)
	if e != nil {
		return e
	}
	ip := net.ParseIP(u.Hostname())
	if d.Channel != "local-development" || u.Scheme != "https" || ip == nil || (!ip.IsPrivate() && !ip.IsLoopback()) {
		return errors.New("only private/loopback local-development feeds are allowed")
	}
	pem, e := os.ReadFile(*ca)
	if e != nil {
		return e
	}
	pool := x509.NewCertPool()
	if !pool.AppendCertsFromPEM(pem) {
		return errors.New("invalid CA")
	}
	c := setup.SecureClient(&http.Client{Transport: &http.Transport{TLSClientConfig: &tls.Config{RootCAs: pool, MinVersion: tls.VersionTLS12}}, Timeout: 2 * time.Minute})
	c.CheckRedirect = func(r *http.Request, via []*http.Request) error {
		if len(via) > 5 || r.URL.Scheme != "https" || r.URL.Host != u.Host {
			return errors.New("redirect leaves local HTTPS origin")
		}
		return nil
	}
	get := func(endpoint string, limit int64) ([]byte, error) {
		endpointURL, e := url.Parse(endpoint)
		if e != nil || endpointURL.Scheme != "https" || endpointURL.Host != u.Host {
			return nil, errors.New("artifact must stay on this local HTTPS origin")
		}
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
		defer cancel()
		q, e := http.NewRequestWithContext(ctx, "GET", endpoint, nil)
		if e != nil {
			return nil, e
		}
		r, e := c.Do(q)
		if e != nil {
			return nil, e
		}
		defer r.Body.Close()
		if r.StatusCode != 200 {
			return nil, fmt.Errorf("%s: HTTP %d", endpoint, r.StatusCode)
		}
		b, e := io.ReadAll(io.LimitReader(r.Body, limit+1))
		if int64(len(b)) > limit {
			return nil, errors.New("response too large")
		}
		return b, e
	}
	raw, e = get(d.BootstrapURL, 128<<10)
	if e != nil {
		return e
	}
	b, p, e := setup.Verify(raw, d, time.Now())
	if e != nil {
		return e
	}
	feed, e := get(b.POSFeed, 64<<10)
	if e != nil {
		return e
	}
	current, e := updater.Verify(feed, d.Keys, d.Channel, "0.0.0", 0, time.Now())
	if e != nil {
		return e
	}
	if current.Version != p.Version || current.SHA256 != p.SHA256 {
		return errors.New("bootstrap and POS feed disagree")
	}
	temp, e := os.MkdirTemp("", "vynic-local-verify-")
	if e != nil {
		return e
	}
	defer os.RemoveAll(temp)
	for _, m := range []updater.Manifest{b.Edge, p} {
		blob, e := get(m.URL, updater.MaxArtifact)
		if e != nil {
			return e
		}
		path := filepath.Join(temp, m.Product+".zip")
		if e = os.WriteFile(path, blob, 0600); e != nil {
			return e
		}
		if e = updater.VerifyArtifact(path, m); e != nil {
			return e
		}
		executable := updater.Executable
		if m.Product == "vynic-edge" {
			executable = setup.EdgeExecutable
		}
		if e = updater.ExtractBundle(path, filepath.Join(temp, m.Product), executable); e != nil {
			return e
		}
	}
	repair, e := get(fmt.Sprintf("%s/%d.json", b.RepairBase, b.Release), 128<<10)
	if e != nil {
		return e
	}
	if _, _, e = setup.Verify(repair, d, time.Now()); e != nil {
		return e
	}
	perVersion, e := get(b.POSReleaseBase+"/"+p.Version+".json", 64<<10)
	if e != nil {
		return e
	}
	if _, e = updater.Verify(perVersion, d.Keys, d.Channel, "0.0.0", 0, time.Now()); e != nil {
		return e
	}
	fmt.Println("Verified HTTPS bootstrap, POS feed, repair metadata, signatures, compatibility, artifact hashes and ZIPs; no Windows artifact executed")
	return nil
}
