package printerdaemon

import (
	"context"
	"debug/pe"
	"encoding/binary"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"vynic.local/edge/internal/printhost"
)

// Only a non-executable structural PE fixture is needed for unit negatives.
// Final bundles use independently qualified actual helper and agent binaries.
func syntheticPE(machine uint16, tag string) []byte {
	raw := make([]byte, 128)
	copy(raw, []byte("MZ"))
	binary.LittleEndian.PutUint32(raw[60:64], 64)
	copy(raw[64:68], []byte{'P', 'E', 0, 0})
	binary.LittleEndian.PutUint16(raw[68:70], machine)
	return append(raw, []byte(tag)...)
}
func installerFixture(t *testing.T) (softwareFixture, PlanDocument) {
	t.Helper()
	f := fixture(t, "")
	f.config.Agent = writeBytes(t, filepath.Join(f.root, "agent.exe"), syntheticPE(pe.IMAGE_FILE_MACHINE_AMD64, "synthetic-agent"))
	helper := writeBytes(t, filepath.Join(f.root, "helper.exe"), syntheticPE(pe.IMAGE_FILE_MACHINE_AMD64, "synthetic-helper"))
	f.config.Helper.Path = helper.Path
	f.config.Helper.SHA256 = helper.SHA256
	f.config.Pins.HostBinarySHA256 = f.config.Agent.SHA256
	f.config.Pins.HelperBinarySHA256 = helper.SHA256
	f.config.ListenAddress = fixedLoopback(t)
	principal := Principal{Kind: "gmsa", AccountName: "FIXTURE\\printer$", SID: "S-1-5-21-100-200-300-400"}
	principal.Qualification = writeJSON(t, filepath.Join(f.root, "synthetic-principal-qualification.json"), PrincipalQualification{Version: 1, Purpose: QualificationPurpose, HostID: f.config.Pins.HostID, Role: f.config.Pins.Role, Scope: f.config.Pins.Scope, Kind: principal.Kind, AccountName: principal.AccountName, SID: principal.SID, SoftwareServiceQualified: true, InventoryIdentitySID: principal.SID, PhysicalQualification: "PENDING"})
	f.config.ServicePrincipal = principal
	f.save(t)
	dir := filepath.Join(f.root, "new-bundle")
	if _, err := BuildBundle(f.config, dir); err != nil {
		t.Fatal(err)
	}
	doc, err := CreateInstallerPlan(f.configPath, fileArtifact(t, filepath.Join(dir, "manifest.json")), fileArtifact(t, f.clientPath))
	if err != nil {
		t.Fatal(err)
	}
	return f, doc
}

type fakeInstaller struct {
	calls, mutations int
	admin            bool
	sid              string
	existing         *InstalledService
	sc               string
	argv             []string
}

func (b *fakeInstaller) IsAdmin(context.Context) (bool, error) { b.calls++; return b.admin, nil }
func (b *fakeInstaller) AccountSID(context.Context, string) (string, error) {
	b.calls++
	return b.sid, nil
}
func (b *fakeInstaller) Inspect(context.Context, string) (*InstalledService, error) {
	b.calls++
	return b.existing, nil
}
func (b *fakeInstaller) SystemSCPath() (string, error) { b.calls++; return b.sc, nil }
func (b *fakeInstaller) RunSC(_ context.Context, _ string, args []string) error {
	b.calls++
	b.mutations++
	b.argv = append([]string(nil), args...)
	return nil
}
func backendFor(f softwareFixture) *fakeInstaller {
	return &fakeInstaller{admin: true, sid: f.config.ServicePrincipal.SID, sc: filepath.Join(f.root, "System32", "sc.exe")}
}
func TestInstallerDefaultsPlanOnlyZeroExternalCalls(t *testing.T) {
	_, doc := installerFixture(t)
	backend := &fakeInstaller{}
	if err := ApplyInstallerPlan(context.Background(), doc, "", false, backend); err != nil {
		t.Fatal(err)
	}
	if backend.calls != 0 || backend.mutations != 0 {
		t.Fatal("PlanOnly touched backend")
	}
	if doc.Plan.PhysicalEligible || doc.Plan.ProvisionStatus != ProvisioningHeld || doc.Plan.Mode != PlanOnly {
		t.Fatal("plan misstates activation")
	}
	raw, _ := json.Marshal(doc)
	if _, err := DecodePlan(raw); err != nil {
		t.Fatal(err)
	}
}
func TestFutureExplicitApplySourceBuildsExactStoppedManualCreate(t *testing.T) {
	f, doc := installerFixture(t)
	backend := backendFor(f)
	if err := ApplyInstallerPlan(context.Background(), doc, doc.PlanSHA256, true, backend); err != nil {
		t.Fatal(err)
	}
	args := backend.argv
	if backend.mutations != 1 || len(args) != 12 || args[0] != "create" || args[1] != printhost.ServiceName(f.config.Pins.HostID) || args[2] != "binPath=" || args[4] != "type=" || args[5] != "own" || args[6] != "start=" || args[7] != "demand" || args[8] != "obj=" || args[9] != f.config.ServicePrincipal.AccountName || args[10] != "DisplayName=" {
		t.Fatalf("invalid reviewed argv: %v", args)
	}
	if !strings.Contains(args[3], quoteWindows(f.config.Agent.Path)+" service --config "+quoteWindows(f.configPath)) {
		t.Fatal("SC binary/config tuple differs")
	}
	// Only the fake backend ran; no SCM call or service creation is performed.
}
func TestFutureApplySourceRefusesChangedInputsPrincipalAndService(t *testing.T) {
	for _, name := range []string{"missing-reviewed-hash", "not-admin", "wrong-sid", "existing-mismatch", "non-System32", "changed-config", "changed-helper", "changed-client", "changed-qualification", "shared-role"} {
		t.Run(name, func(t *testing.T) {
			f, doc := installerFixture(t)
			backend := backendFor(f)
			reviewed := doc.PlanSHA256
			switch name {
			case "missing-reviewed-hash":
				reviewed = ""
			case "not-admin":
				backend.admin = false
			case "wrong-sid":
				backend.sid = "S-1-5-21-100-200-300-999"
			case "existing-mismatch":
				backend.existing = &InstalledService{ExecutablePath: "foreign"}
			case "non-System32":
				backend.sc = filepath.Join(f.root, "bin", "sc.exe")
			case "changed-config":
				writeBytes(t, f.configPath, []byte("{}"))
			case "changed-helper":
				writeBytes(t, f.config.Helper.Path, []byte("different helper"))
			case "changed-client":
				writeBytes(t, f.clientPath, []byte("{}"))
			case "changed-qualification":
				writeBytes(t, f.config.ServicePrincipal.Qualification.Path, []byte("{}"))
			case "shared-role":
				doc.Plan.Pins.Scope = printhost.VenueShared
				doc.PlanSHA256 = planHash(doc.Plan)
				reviewed = doc.PlanSHA256
			}
			if err := ApplyInstallerPlan(context.Background(), doc, reviewed, true, backend); err == nil {
				t.Fatal("unsafe/mismatched plan accepted")
			}
			if backend.mutations != 0 {
				t.Fatal("backend mutated before refusal")
			}
		})
	}
}
func TestFutureApplySourcePreservesExactExistingService(t *testing.T) {
	f, doc := installerFixture(t)
	backend := backendFor(f)
	backend.existing = &InstalledService{ExecutablePath: doc.Plan.ExecutablePath, Arguments: doc.Plan.Arguments, AccountName: doc.Plan.Principal.AccountName, SID: doc.Plan.Principal.SID, ServiceType: 16, StartType: 3}
	if err := ApplyInstallerPlan(context.Background(), doc, doc.PlanSHA256, true, backend); err != nil {
		t.Fatal(err)
	}
	if backend.mutations != 0 {
		t.Fatal("existing service changed")
	}
}
func TestServicePrincipalRequiresItsOwnQualifiedInventoryAndNeverSystem(t *testing.T) {
	f, _ := installerFixture(t)
	for _, name := range []string{"system", "unqualified", "wrong-inventory", "wrong-role"} {
		t.Run(name, func(t *testing.T) {
			principal := f.config.ServicePrincipal
			if name == "system" {
				principal.SID = "S-1-5-18"
				principal.AccountName = "LocalSystem"
			} else {
				var receipt PrincipalQualification
				raw, _ := os.ReadFile(principal.Qualification.Path)
				json.Unmarshal(raw, &receipt)
				switch name {
				case "unqualified":
					receipt.SoftwareServiceQualified = false
				case "wrong-inventory":
					receipt.InventoryIdentitySID = "S-1-5-21-9-9-9-9"
				case "wrong-role":
					receipt.Role = printhost.POSAgent
				}
				principal.Qualification = writeJSON(t, filepath.Join(f.root, name+".json"), receipt)
			}
			if err := ValidatePrincipal(principal, f.config.Pins); err == nil {
				t.Fatal("unqualified principal accepted")
			}
		})
	}
}
func TestBundlePinsExactBytesArchitectureAndContainsNoCredentials(t *testing.T) {
	for _, architecture := range []struct {
		name    string
		machine uint16
	}{{"amd64", pe.IMAGE_FILE_MACHINE_AMD64}, {"arm64", pe.IMAGE_FILE_MACHINE_ARM64}} {
		t.Run(architecture.name, func(t *testing.T) {
			f := fixture(t, "")
			f.config.Agent = writeBytes(t, filepath.Join(f.root, "agent.exe"), syntheticPE(architecture.machine, "agent"))
			helper := writeBytes(t, filepath.Join(f.root, "helper.exe"), syntheticPE(architecture.machine, "helper"))
			f.config.Helper.Path = helper.Path
			f.config.Helper.SHA256 = helper.SHA256
			f.config.Pins.HostBinarySHA256 = f.config.Agent.SHA256
			f.config.Pins.HelperBinarySHA256 = helper.SHA256
			dir := filepath.Join(f.root, "new-bundle")
			manifest, err := BuildBundle(f.config, dir)
			if err != nil {
				t.Fatal(err)
			}
			path := filepath.Join(dir, "manifest.json")
			if manifest.AgentArchitecture != architecture.name || manifest.HelperArchitecture != architecture.name {
				t.Fatal("wrong frozen byte architecture")
			}
			if _, err = VerifyBundle(path, f.config); err != nil {
				t.Fatal(err)
			}
			files, err := os.ReadDir(dir)
			if err != nil || len(files) != 4 {
				t.Fatal("bundle extra/secret files", err)
			}
			if _, err = BuildBundle(f.config, dir); err == nil {
				t.Fatal("existing bundle overwritten")
			}
			writeBytes(t, filepath.Join(dir, "vynic-print-helper.exe"), syntheticPE(pe.IMAGE_FILE_MACHINE_I386, "replacement"))
			if _, err = VerifyBundle(path, f.config); err == nil {
				t.Fatal("hash-changed helper accepted")
			}
		})
	}
	f := fixture(t, "")
	f.config.Agent = writeBytes(t, filepath.Join(f.root, "agent.exe"), syntheticPE(pe.IMAGE_FILE_MACHINE_AMD64, "agent"))
	h := writeBytes(t, filepath.Join(f.root, "helper.exe"), syntheticPE(pe.IMAGE_FILE_MACHINE_ARM64, "helper"))
	f.config.Helper.Path = h.Path
	f.config.Helper.SHA256 = h.SHA256
	f.config.Pins.HostBinarySHA256 = f.config.Agent.SHA256
	f.config.Pins.HelperBinarySHA256 = h.SHA256
	if _, err := BuildBundle(f.config, filepath.Join(f.root, "mixed-bundle")); err == nil {
		t.Fatal("unqualified mixed architecture admitted")
	}
}
func TestBundleAndPlanRejectNestedAliasesAndNulls(t *testing.T) {
	f, doc := installerFixture(t)
	for _, name := range []string{"bundle-pin-alias", "bundle-pin-null", "artifact-alias", "artifact-null", "plan-alias", "plan-pin-null", "plan-artifact-null", "plan-principal-alias"} {
		t.Run(name, func(t *testing.T) {
			if strings.HasPrefix(name, "plan-") {
				m := jsonMap(t, doc)
				p := m["plan"].(map[string]any)
				switch name {
				case "plan-alias":
					p["ServiceName"] = p["serviceName"]
					delete(p, "serviceName")
				case "plan-pin-null":
					p["pins"].(map[string]any)["hostId"] = nil
				case "plan-artifact-null":
					p["config"].(map[string]any)["path"] = nil
				case "plan-principal-alias":
					a := p["principal"].(map[string]any)
					a["Sid"] = a["sid"]
					delete(a, "sid")
				}
				raw, _ := json.Marshal(m)
				// Re-hash cannot turn an alias/null schema into a reviewed plan.
				var aliased PlanDocument
				json.Unmarshal(raw, &aliased)
				m["planSha256"] = planHash(aliased.Plan)
				raw, _ = json.Marshal(m)
				if _, err := DecodePlan(raw); err == nil {
					t.Fatal("nested malformed plan accepted")
				}
			} else {
				raw, _ := os.ReadFile(doc.Plan.Bundle.Path)
				var manifest BundleManifest
				json.Unmarshal(raw, &manifest)
				m := jsonMap(t, manifest)
				switch name {
				case "bundle-pin-alias":
					p := m["pins"].(map[string]any)
					p["HostId"] = p["hostId"]
					delete(p, "hostId")
				case "bundle-pin-null":
					m["pins"].(map[string]any)["clusterId"] = nil
				case "artifact-alias":
					a := m["artifacts"].([]any)[0].(map[string]any)
					a["Name"] = a["name"]
					delete(a, "name")
				case "artifact-null":
					m["artifacts"].([]any)[0].(map[string]any)["architecture"] = nil
				}
				path := doc.Plan.Bundle.Path
				writeJSON(t, path, m)
				defer writeBytes(t, path, raw)
				if _, err := VerifyBundle(path, f.config); err == nil {
					t.Fatal("nested malformed bundle accepted")
				}
			}
		})
	}
}

func TestWindowsBackendUsesExactBoundedCreateArgv(t *testing.T) {
	f, doc := installerFixture(t)
	backend := backendFor(f)
	if err := ApplyInstallerPlan(context.Background(), doc, doc.PlanSHA256, true, backend); err != nil {
		t.Fatal(err)
	}
	if err := validateCreateArguments(backend.argv); err != nil {
		t.Fatal("generated argv refused by actual backend validator", err)
	}
	for _, mutation := range []func([]string) []string{
		func(a []string) []string { return a[:11] },
		func(a []string) []string { return append(a, "extra", "extra") },
		func(a []string) []string { a[0] = "start"; return a },
		func(a []string) []string { a[1] = "unrelated-service"; return a },
		func(a []string) []string { a[7] = "auto"; return a },
		func(a []string) []string { a[9] = ""; return a },
		func(a []string) []string { a[3] += "\r\n"; return a },
	} {
		if err := validateCreateArguments(mutation(append([]string(nil), backend.argv...))); err == nil {
			t.Fatal("unreviewed SCM argv accepted")
		}
	}
}
