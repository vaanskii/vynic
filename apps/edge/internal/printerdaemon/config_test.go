package printerdaemon

import (
	"bytes"
	"crypto/x509"
	"encoding/json"
	"net"
	"net/url"
	"os"
	"path/filepath"
	"testing"

	"vynic.local/edge/internal/printeragent"
	"vynic.local/edge/internal/store"
)

func jsonMap(t *testing.T, value any) map[string]any {
	t.Helper()
	raw, err := json.Marshal(value)
	if err != nil {
		t.Fatal(err)
	}
	var result map[string]any
	if err = json.Unmarshal(raw, &result); err != nil {
		t.Fatal(err)
	}
	return result
}
func TestConfigStrictNestedSchemaAndHeldProfile(t *testing.T) {
	f := fixture(t, "")
	raw, _ := json.Marshal(f.config)
	if _, err := DecodeConfig(raw); err != nil {
		t.Fatal(err)
	}
	cases := map[string]func(map[string]any){
		"dispatch-enabled": func(m map[string]any) { m["dispatchPolicy"] = "ENABLED" },
		"unknown-root":     func(m map[string]any) { m["spawnWriter"] = true },
		"aliased-client": func(m map[string]any) {
			p := m["clients"].([]any)[0].(map[string]any)
			p["ClientId"] = p["clientId"]
			delete(p, "clientId")
		},
		"duplicate-case-client": func(m map[string]any) { p := m["clients"].([]any)[0].(map[string]any); p["ClientId"] = p["clientId"] },
		"null-client":           func(m map[string]any) { m["clients"] = []any{nil} },
		"null-client-id":        func(m map[string]any) { m["clients"].([]any)[0].(map[string]any)["clientId"] = nil },
		"missing-pins-key":      func(m map[string]any) { delete(m["pins"].(map[string]any), "hostId") },
		"alias-pins-key": func(m map[string]any) {
			p := m["pins"].(map[string]any)
			p["HostId"] = p["hostId"]
			delete(p, "hostId")
		},
		"null-helper-protocol": func(m map[string]any) { m["helper"].(map[string]any)["protocolVersion"] = nil },
		"null-qualification":   func(m map[string]any) { m["servicePrincipal"].(map[string]any)["qualification"] = nil },
		"alias-qualification": func(m map[string]any) {
			p := m["servicePrincipal"].(map[string]any)["qualification"].(map[string]any)
			p["Path"] = p["path"]
			delete(p, "path")
		},
		"old-reader":          func(m map[string]any) { m["pins"].(map[string]any)["minimumReaderVersion"] = 1 },
		"old-schema":          func(m map[string]any) { m["pins"].(map[string]any)["databaseSchemaVersion"] = 5 },
		"unknown-role":        func(m map[string]any) { m["pins"].(map[string]any)["role"] = "admin" },
		"role-scope-mismatch": func(m map[string]any) { m["profile"] = SharedHeld },
		"non-loopback":        func(m map[string]any) { m["listenAddress"] = "0.0.0.0:6001" },
		"relative-state":      func(m map[string]any) { m["stateDirectory"] = "edge" },
	}
	for name, change := range cases {
		t.Run(name, func(t *testing.T) {
			m := jsonMap(t, f.config)
			change(m)
			raw, _ := json.Marshal(m)
			if _, err := DecodeConfig(raw); err == nil {
				t.Fatal("malformed configuration accepted")
			}
		})
	}
	duplicate := bytes.Replace(raw, []byte("\"version\":1"), []byte("\"version\":1,\"version\":1"), 1)
	if _, err := DecodeConfig(duplicate); err == nil {
		t.Fatal("exact duplicate accepted")
	}
	if _, err := DecodeConfig(append(raw, []byte("{}")...)); err == nil {
		t.Fatal("trailing JSON accepted")
	}
}
func TestPreflightRejectsWrongRootIdentityRoleAndSchemaWithoutReset(t *testing.T) {
	for _, name := range []string{"missing-marker", "marker-installation", "old-schema", "foreign-installation", "wrong-executable", "driver-rendered-profile"} {
		t.Run(name, func(t *testing.T) {
			f := fixture(t, "")
			executable := f.config.Agent.Path
			switch name {
			case "missing-marker":
				if err := os.Remove(filepath.Join(f.config.StateDirectory, StateMarkerFilename)); err != nil {
					t.Fatal(err)
				}
			case "marker-installation":
				marker := StateMarker{Version: 1, Purpose: StatePurpose, SchemaVersion: store.SchemaVersion, Pins: f.config.Pins}
				marker.Pins.InstallationID = marker.Pins.DeviceID
				writeJSON(t, filepath.Join(f.config.StateDirectory, StateMarkerFilename), marker)
			case "old-schema", "foreign-installation":
				s, err := store.Open(f.config.StateDirectory, false)
				if err != nil {
					t.Fatal(err)
				}
				query := "PRAGMA user_version=5"
				if name == "foreign-installation" {
					query = "UPDATE installation SET id='" + f.config.Pins.DeviceID + "' WHERE singleton=1"
				}
				if _, err = s.DB.Exec(query); err != nil {
					t.Fatal(err)
				}
				s.Close()
			case "wrong-executable":
				executable = f.config.Helper.Path
			case "driver-rendered-profile":
				raw, _ := os.ReadFile(f.config.CapabilityProfile.Path)
				f.config.CapabilityProfile = writeBytes(t, f.config.CapabilityProfile.Path, bytes.Replace(raw, []byte("escposRaster"), []byte("windowsDriverRendered"), 1))
				f.config.Pins.CapabilityProfileSHA256 = f.config.CapabilityProfile.SHA256
				f.save(t)
			}
			path := filepath.Join(f.config.StateDirectory, "edge.db")
			before, err := os.ReadFile(path)
			if err != nil {
				t.Fatal(err)
			}
			if _, err = New(f.config, executable); err == nil {
				t.Fatal("foreign/unqualified preflight accepted")
			}
			after, err := os.ReadFile(path)
			if err != nil || !bytes.Equal(before, after) {
				t.Fatal("preflight rewrote existing state", err)
			}
		})
	}
}
func TestCanonicalLocalPathsAndReparseRefusal(t *testing.T) {
	for _, path := range []string{`\\server\share\state`, `\\?\C:\state`, `\\.\C:\state`, `Z:relative\state`, "/network/state"} {
		if err := validateWindowsVolume(path, 3); err == nil {
			t.Fatal("non-local Windows namespace admitted:", path)
		}
	}
	if err := validateWindowsVolume(`Z:\state`, 4); err == nil {
		t.Fatal("mapped DRIVE_REMOTE admitted")
	}
	if err := validateWindowsVolume(`C:\state`, 3); err != nil {
		t.Fatal("ordinary fixed volume rejected", err)
	}
	f := fixture(t, "")
	linked := filepath.Join(f.root, "linked-helper")
	if err := os.Symlink(f.config.Helper.Path, linked); err != nil {
		t.Skip("OS cannot create synthetic symlink without privileges:", err)
	}
	f.config.Helper.Path = linked
	if _, err := New(f.config, f.config.Agent.Path); err == nil {
		t.Fatal("symlink artifact accepted")
	}
}

func TestSQLiteReadOnlyURIPreservesLocalDriveAndEscapesPath(t *testing.T) {
	for _, test := range []struct{ path, want string }{
		{"C:\\fixture space\\edge#1.db", "/C:/fixture space/edge#1.db"},
		{"C:/fixture/edge.db", "/C:/fixture/edge.db"},
		{"/private/tmp/fixture space/edge#1.db", "/private/tmp/fixture space/edge#1.db"},
	} {
		uri, err := url.Parse(sqliteReadOnlyURI(test.path))
		if err != nil || uri.Scheme != "file" || uri.Host != "" || uri.Path != test.want || uri.Query().Get("mode") != "ro" || len(uri.Query()) != 1 || uri.Fragment != "" {
			t.Fatalf("incorrect local SQLite URI: %v %v", uri, err)
		}
	}
}
func TestClientProfileExactNestedPinsAndDistinctDeviceInstallation(t *testing.T) {
	f := fixture(t, "")
	f.config.ListenAddress = fixedLoopback(t)
	f.save(t)
	if f.client.CurrentDeviceInstallationID == f.config.Pins.InstallationID {
		t.Fatal("fixture must use distinct Device and Go installations")
	}
	if err := validateClientProfile(fileArtifact(t, f.clientPath), f.config); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"alias-pin", "null-pin", "missing-pos-installation", "null-pos-installation"} {
		t.Run(name, func(t *testing.T) {
			m := jsonMap(t, f.client)
			switch name {
			case "alias-pin":
				p := m["pins"].(map[string]any)
				p["HostId"] = p["hostId"]
				delete(p, "hostId")
			case "null-pin":
				m["pins"].(map[string]any)["clusterId"] = nil
			case "missing-pos-installation":
				delete(m, "currentDeviceInstallationId")
			case "null-pos-installation":
				m["currentDeviceInstallationId"] = nil
			}
			artifact := writeJSON(t, f.clientPath, m)
			if err := validateClientProfile(artifact, f.config); err == nil {
				t.Fatal("malformed profile accepted")
			}
		})
	}
}
func TestClientProfileRejectsUnrelatedCAAndExtraSANOrPurpose(t *testing.T) {
	for _, name := range []string{"foreign-ca", "dns", "ip", "email", "dual-purpose", "no-digital-signature", "no-basic-constraints"} {
		t.Run(name, func(t *testing.T) {
			f := fixture(t, "")
			f.config.ListenAddress = fixedLoopback(t)
			template := baseLeaf()
			template.ExtKeyUsage = []x509.ExtKeyUsage{x509.ExtKeyUsageClientAuth}
			uri, _ := printeragent.ClientURI(f.config.Pins.HostID, f.client.ClientID)
			template.URIs = []*url.URL{uri}
			ca, key := f.ca, f.caKey
			switch name {
			case "foreign-ca":
				caTemplate := baseLeaf()
				caTemplate.IsCA = true
				caTemplate.KeyUsage = x509.KeyUsageCertSign
				_, _, ca, key = certPair(t, caTemplate, nil, nil)
			case "dns":
				template.DNSNames = []string{"unexpected.local"}
			case "ip":
				template.IPAddresses = []net.IP{net.ParseIP("127.0.0.1")}
			case "email":
				template.EmailAddresses = []string{"fixture@example.invalid"}
			case "dual-purpose":
				template.ExtKeyUsage = append(template.ExtKeyUsage, x509.ExtKeyUsageServerAuth)
			case "no-digital-signature":
				template.KeyUsage = x509.KeyUsageKeyEncipherment
			case "no-basic-constraints":
				template.BasicConstraintsValid = false
			}
			raw, keyPEM, leaf, _ := certPair(t, template, ca, key)
			writeBytes(t, f.client.ClientCertificatePath, raw)
			writeBytes(t, f.client.ClientPrivateKeyPath, keyPEM)
			f.client.ClientCertificateSHA256 = bytesHash(leaf.Raw)
			f.config.Clients[0].CertificateSHA256 = f.client.ClientCertificateSHA256
			f.save(t)
			if err := validateClientProfile(fileArtifact(t, f.clientPath), f.config); err == nil {
				t.Fatal("unusable client profile passed")
			}
		})
	}
}
