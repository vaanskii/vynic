package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestDistributionRefusesSecretsAndMissingBuildConfiguration(t *testing.T) {
	old := distributionBase64
	distributionBase64 = ""
	defer func() { distributionBase64 = old }()
	if _, e := distribution(""); e == nil {
		t.Fatal("unconfigured setup accepted")
	}
	p := filepath.Join(t.TempDir(), "distribution.json")
	raw := `{"bootstrapURL":"https://example.invalid/bootstrap.json","channel":"stable","keys":{"fixture":{"public":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=","expires":"2027-01-01T00:00:00Z","private":"must-not-embed"}}}`
	if e := os.WriteFile(p, []byte(raw), 0600); e != nil {
		t.Fatal(e)
	}
	if _, e := distribution(p); e == nil {
		t.Fatal("unknown private-key field accepted")
	}
}
