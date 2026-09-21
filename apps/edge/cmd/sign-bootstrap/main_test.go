package main

import (
	"bytes"
	"crypto/ed25519"
	"crypto/rand"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"os"
	"path/filepath"
	"testing"
	"time"
	"vynic.local/edge/internal/setup"
	"vynic.local/edge/internal/updater"
)

func TestOfflinePublisherRoundTrip(t *testing.T) {
	pub, private, e := ed25519.GenerateKey(rand.Reader)
	if e != nil {
		t.Fatal(e)
	}
	now := time.Now()
	d := setup.Distribution{BootstrapURL: "https://example.invalid/bootstrap.json", Channel: "stable", Keys: map[string]updater.TrustedKey{"fixture": {Public: base64.StdEncoding.EncodeToString(pub), Expires: now.Add(2 * time.Hour)}}}
	p := updater.Manifest{Product: "vynic-pos", Version: "1.8.0", Release: 18, OS: "windows", Arch: "amd64", Channel: "stable", URL: "https://example.invalid/pos.zip", SHA256: "0000000000000000000000000000000000000000000000000000000000000000", Size: 1, Expires: now.Add(time.Hour), UpdaterProtocol: 1, HiveSchema: 9, EdgeSchema: 2, DataPolicy: "hive9-no-migration"}
	payload, _ := json.Marshal(p)
	envelope, _ := json.Marshal(updater.Envelope{KeyID: "fixture", Payload: base64.StdEncoding.EncodeToString(payload), Signature: base64.StdEncoding.EncodeToString(ed25519.Sign(private, append([]byte("VYNIC-POS-RELEASE-v1\n"), payload...)))})
	edge := p
	edge.Product = "vynic-edge"
	edge.Version = "1.0.0"
	edge.DataPolicy = "edge2-no-migration"
	b := setup.Bootstrap{POSBinaryLayout: 2, Product: "vynic-bootstrap", Protocol: 1, Release: 1, OS: "windows", Arch: "amd64", Channel: "stable", Expires: now.Add(time.Hour), Edge: edge, POS: envelope, POSFeed: "https://example.invalid/pos.json", RepairBase: "https://example.invalid/repair", POSReleaseBase: "https://example.invalid/pos-releases"}
	root := t.TempDir()
	key, _ := x509.MarshalPKCS8PrivateKey(private)
	files := map[string][]byte{"key.pem": pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: key}), "edge.zip": []byte("fixture bytes hashed by offline publisher")}
	files["metadata.json"], _ = json.Marshal(b)
	files["distribution.json"], _ = json.Marshal(d)
	for name, raw := range files {
		if e = os.WriteFile(filepath.Join(root, name), raw, 0600); e != nil {
			t.Fatal(e)
		}
	}
	args := []string{"--manifest", filepath.Join(root, "metadata.json"), "--edge-artifact", filepath.Join(root, "edge.zip"), "--private-key", filepath.Join(root, "key.pem"), "--key-id", "fixture", "--distribution", filepath.Join(root, "distribution.json")}
	var out bytes.Buffer
	if e = run(args, &out); e != nil {
		t.Fatal(e)
	}
	got, _, e := setup.Verify(out.Bytes(), d, now)
	if e != nil {
		t.Fatal(e)
	}
	if e = updater.VerifyArtifact(filepath.Join(root, "edge.zip"), got.Edge); e != nil {
		t.Fatal(e)
	}
}
