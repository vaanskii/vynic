package setup

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"testing"
)

func TestOfflineBundlePreservesSignatureHashAndInstallChecks(t *testing.T) {
	for _, corrupt := range []string{"", "/edge.zip", "/bootstrap.json"} {
		t.Run("corruption="+corrupt, func(t *testing.T) {
			f := newFixture(t)
			dir := t.TempDir()
			index := map[string]string{}
			n := 0
			for path, raw := range f.responses {
				n++
				name := fmt.Sprintf("bundle-%d.dat", n)
				index[f.s.URL+path] = name
				if path == corrupt {
					raw = []byte("corrupt")
				}
				must(t, os.WriteFile(filepath.Join(dir, name), raw, 0600))
			}
			raw, err := json.Marshal(index)
			must(t, err)
			must(t, os.WriteFile(filepath.Join(dir, "bundle-index.json"), raw, 0600))
			f.i.Client, err = OfflineBundleClient(dir)
			must(t, err)
			f.s.Close() // A successful installation must require zero network access.
			err = f.i.Install(context.Background(), false)
			if corrupt == "" {
				must(t, err)
			} else if err == nil {
				t.Fatal("corrupt offline bundle admitted")
			}
		})
	}
}

func TestOfflineBundleNeverFallsBackOrTraversesFiles(t *testing.T) {
	dir := t.TempDir()
	for _, name := range []string{"../secret", "C:\\secret", "/secret", "."} {
		raw, _ := json.Marshal(map[string]string{"https://example.invalid/file": name})
		must(t, os.WriteFile(filepath.Join(dir, "bundle-index.json"), raw, 0600))
		if _, err := OfflineBundleClient(dir); err == nil {
			t.Fatal("unsafe bundle path admitted")
		}
	}
	raw, _ := json.Marshal(map[string]string{"https://example.invalid/file": "absent"})
	must(t, os.WriteFile(filepath.Join(dir, "bundle-index.json"), raw, 0600))
	c, err := OfflineBundleClient(dir)
	must(t, err)
	if _, err = fetch(context.Background(), c, "https://example.invalid/unlisted", 100); err == nil {
		t.Fatal("missing offline file admitted")
	}
}
