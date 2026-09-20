package updater

import (
	"database/sql"
	"errors"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
)

// OpenExisting is for provisioned host startup and setup repair. Unlike initial
// provisioning, a missing database/decision row must never seed an old baseline
// or reset the durable release high-water mark.
func OpenExisting(c Config, p Process) (*Service, error) {
	path := filepath.Join(c.Root, "updater.sqlite")
	if _, e := os.Stat(path); e != nil {
		return nil, fmt.Errorf("retained updater state missing: %w", e)
	}
	uriPath := filepath.ToSlash(path)
	if filepath.VolumeName(path) != "" {
		uriPath = "/" + uriPath
	}
	uri := url.URL{Scheme: "file", Path: uriPath, RawQuery: "mode=ro"}
	db, e := sql.Open("sqlite", uri.String())
	if e != nil {
		return nil, e
	}
	var schema int
	e = db.QueryRow("SELECT version FROM updater_state WHERE id=1").Scan(&schema)
	e = errors.Join(e, db.Close())
	if e != nil {
		return nil, fmt.Errorf("retained updater decision unavailable; preserve files: %w", e)
	}
	if schema != 1 {
		return nil, errors.New("incompatible retained updater schema")
	}
	return Open(c, p)
}
