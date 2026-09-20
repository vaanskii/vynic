package main

import (
	"archive/zip"
	"bytes"
	"crypto/ed25519"
	"crypto/rand"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"flag"
	"os"
	"path/filepath"
	"testing"
	"time"
	"vynic.local/edge/internal/updater"
)

func TestOfflinePublisherEnvelopeAcceptedByUpdater(t *testing.T) {
	dir := t.TempDir()
	pub, key, e := ed25519.GenerateKey(rand.Reader)
	if e != nil {
		t.Fatal(e)
	}
	der, e := x509.MarshalPKCS8PrivateKey(key)
	if e != nil {
		t.Fatal(e)
	}
	private := filepath.Join(dir, "development-only.pem")
	if e = os.WriteFile(private, pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der}), 0600); e != nil {
		t.Fatal(e)
	}
	var zipBytes bytes.Buffer
	archive := zip.NewWriter(&zipBytes)
	file, _ := archive.Create(updater.Executable)
	_, _ = file.Write([]byte("synthetic windows bundle"))
	_ = archive.Close()
	artifact := filepath.Join(dir, "pos.zip")
	_ = os.WriteFile(artifact, zipBytes.Bytes(), 0600)
	m := updater.Manifest{Product: updater.Product, Version: "1.9.0", Release: 19, OS: "windows", Arch: "amd64", Channel: "stable", URL: "https://example.invalid/pos.zip", Expires: time.Now().Add(time.Hour), UpdaterProtocol: 1, HiveSchema: 9, EdgeSchema: 2, DataPolicy: "hive9-no-migration"}
	metadata := filepath.Join(dir, "metadata.json")
	b, _ := json.Marshal(m)
	_ = os.WriteFile(metadata, b, 0600)
	output, e := os.Create(filepath.Join(dir, "signed.json"))
	if e != nil {
		t.Fatal(e)
	}
	args, flags, stdout := os.Args, flag.CommandLine, os.Stdout
	defer func() { os.Args = args; flag.CommandLine = flags; os.Stdout = stdout }()
	flag.CommandLine = flag.NewFlagSet("sign", flag.ContinueOnError)
	os.Stdout = output
	os.Args = []string{"sign", "--manifest", metadata, "--artifact", artifact, "--private-key", private, "--key-id", "fixture"}
	e = run()
	_ = output.Close()
	if e != nil {
		t.Fatal(e)
	}
	signed, e := os.ReadFile(output.Name())
	if e != nil {
		t.Fatal(e)
	}
	verified, e := updater.Verify(signed, map[string]updater.TrustedKey{"fixture": {Public: base64.StdEncoding.EncodeToString(pub), Expires: time.Now().Add(time.Hour)}}, "stable", "1.8.0", 18, time.Now())
	if e != nil {
		t.Fatal(e)
	}
	if verified.Size != int64(zipBytes.Len()) {
		t.Fatal("publisher size mismatch")
	}
}
