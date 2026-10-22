package printerprovisioning

import (
	"bytes"
	"context"
	"crypto/tls"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// Pull renews using the existing POS Device credential provided transiently by
// its owner. It is never persisted by the Go identity store. No redirect may
// forward it to another host. Production Cloud ingress must support TLS 1.3.
func (s *ProductionStore) Pull(ctx context.Context, baseURL, deviceCredential string) error {
	u, e := url.Parse(baseURL)
	if e != nil || u.Scheme != "https" || u.Host == "" || u.User != nil || u.RawQuery != "" || u.Fragment != "" || (u.Path != "" && u.Path != "/") {
		return ErrScope
	}
	transport := &http.Transport{TLSClientConfig: &tls.Config{MinVersion: tls.VersionTLS13}, Proxy: http.ProxyFromEnvironment}
	defer transport.CloseIdleConnections()
	client := &http.Client{Transport: transport, Timeout: 30 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	return s.pull(ctx, client, strings.TrimSuffix(baseURL, "/"), deviceCredential)
}
func (s *ProductionStore) pull(ctx context.Context, client *http.Client, baseURL, credential string) error {
	parts := strings.Split(credential, ".")
	if len(parts) != 3 || parts[0] != "vynic-device-v1" || parts[1] != s.device {
		return ErrScope
	}
	body, e := s.MarshalEnrollment()
	if e != nil {
		return e
	}
	req, e := http.NewRequestWithContext(ctx, http.MethodPost, baseURL+"/edge/printer-provisioning/enroll", bytes.NewReader(body))
	if e != nil {
		return e
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-POS-Sync-Key", credential)
	response, e := client.Do(req)
	if e != nil {
		return e
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusCreated {
		return fmt.Errorf("printer enrollment HTTP %d", response.StatusCode)
	}
	raw, e := io.ReadAll(io.LimitReader(response.Body, MaxProductionGrant+1))
	if e != nil {
		return e
	}
	return s.Apply(raw)
}
