package setup

import (
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"strings"
)

// OfflineBundleClient reads the complete, separately authorized download from
// beside Setup. The index supplies transport locations only: the existing pinned
// signatures, expiry, compatibility, SHA-256 and ZIP checks still admit bytes.
// It never falls back to a public network URL or persists a download credential.
func OfflineBundleClient(dir string) (*http.Client, error) {
	index := filepath.Join(dir, "bundle-index.json")
	info, err := os.Lstat(index)
	if os.IsNotExist(err) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	if !info.Mode().IsRegular() || info.Size() > 16<<10 {
		return nil, errors.New("invalid offline bundle index")
	}
	if err = checkReparse(index); err != nil {
		return nil, err
	}
	raw, err := os.ReadFile(index)
	if err != nil {
		return nil, err
	}
	var files map[string]string
	if err = json.Unmarshal(raw, &files); err != nil {
		return nil, err
	}
	if len(files) == 0 || len(files) > 16 {
		return nil, errors.New("invalid offline bundle size")
	}
	for url, name := range files {
		if !https(url) || name == "" || name == "." || name != filepath.Base(name) || strings.ContainsAny(name, "/\\:") {
			return nil, errors.New("invalid offline bundle location")
		}
	}
	return SecureClient(&http.Client{Transport: bundleTransport{dir, files}}), nil
}

type bundleTransport struct {
	dir   string
	files map[string]string
}

func (t bundleTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	name, ok := t.files[req.URL.String()]
	if !ok || req.Method != "GET" {
		return nil, errors.New("release is absent from this offline bundle; obtain a current authorized package")
	}
	path := filepath.Join(t.dir, name)
	info, err := os.Lstat(path)
	if err != nil {
		return nil, err
	}
	if !info.Mode().IsRegular() {
		return nil, errors.New("offline bundle links refused")
	}
	if err = checkReparse(path); err != nil {
		return nil, err
	}
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	return &http.Response{StatusCode: 200, Header: make(http.Header), Body: f, ContentLength: info.Size(), Request: req}, nil
}
