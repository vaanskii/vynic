package printerdaemon

import (
	"bytes"
	"context"
	"crypto/sha256"
	"debug/pe"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"vynic.local/edge/internal/printhost"
	"vynic.local/edge/internal/printqueue"
)

const PlanOnly = "PlanOnly"
const QualificationPurpose = "PRINTER_AGENT_HELD_SERVICE_ACCOUNT"

type PrincipalQualification struct {
	Version                  int             `json:"version"`
	Purpose                  string          `json:"purpose"`
	HostID                   string          `json:"hostId"`
	Role                     printhost.Role  `json:"role"`
	Scope                    printhost.Scope `json:"scope"`
	Kind                     string          `json:"kind"`
	AccountName              string          `json:"accountName"`
	SID                      string          `json:"sid"`
	SoftwareServiceQualified bool            `json:"softwareServiceQualified"`
	InventoryIdentitySID     string          `json:"inventoryIdentitySid"`
	PhysicalQualification    string          `json:"physicalQualification"`
}

var sidPattern = regexp.MustCompile(`^S-1-[0-9]+(?:-[0-9]+){1,15}$`)

func ValidatePrincipal(principal Principal, pins printhost.Pins) error {
	name := strings.ToLower(principal.AccountName)
	if principal.AccountName == "" || strings.TrimSpace(principal.AccountName) != principal.AccountName || strings.ContainsAny(principal.AccountName, "\x00\r\n\t") || !sidPattern.MatchString(principal.SID) || principal.SID == "S-1-5-18" || principal.SID == "S-1-5-19" || principal.SID == "S-1-5-20" || strings.Contains(name, "localsystem") || strings.HasPrefix(name, `nt authority\`) {
		return fmt.Errorf("%w: explicit non-System qualified principal required", ErrConfig)
	}
	switch principal.Kind {
	case "virtualService":
		if principal.AccountName != `NT SERVICE\`+printhost.ServiceName(pins.HostID) {
			return fmt.Errorf("%w: exact virtual-service account required", ErrConfig)
		}
	case "gmsa":
		parts := strings.Split(principal.AccountName, `\`)
		if len(parts) != 2 || parts[0] == "" || len(parts[1]) < 2 || !strings.HasSuffix(parts[1], "$") {
			return fmt.Errorf("%w: exact preprovisioned gMSA required", ErrConfig)
		}
	default:
		return fmt.Errorf("%w: passwordless qualified service account kind required", ErrConfig)
	}
	if !absolutePath(principal.Qualification.Path) || !canonicalHash(principal.Qualification.SHA256) {
		return fmt.Errorf("%w: principal qualification receipt required", ErrConfig)
	}
	raw, err := checkArtifact(principal.Qualification, MaxConfigBytes)
	if err != nil {
		return err
	}
	var evidence PrincipalQualification
	if err = strictJSON(raw, &evidence); err != nil {
		return err
	}
	if err = requiredObject(raw, evidence); err != nil {
		return err
	}
	if evidence.Version != 1 || evidence.Purpose != QualificationPurpose || evidence.HostID != pins.HostID || evidence.Role != pins.Role || evidence.Scope != pins.Scope || evidence.Kind != principal.Kind || evidence.AccountName != principal.AccountName || evidence.SID != principal.SID || !evidence.SoftwareServiceQualified || evidence.InventoryIdentitySID != principal.SID || evidence.PhysicalQualification != "PENDING" {
		return fmt.Errorf("%w: selected principal evidence mismatch; foreground inventory cannot qualify SCM identity", ErrConfig)
	}
	return nil
}

type BundleArtifact struct {
	Name         string `json:"name"`
	SHA256       string `json:"sha256"`
	Architecture string `json:"architecture"`
}

type BundleManifest struct {
	Version               int              `json:"version"`
	Product               string           `json:"product"`
	Profile               string           `json:"profile"`
	Pins                  printhost.Pins   `json:"pins"`
	AgentArchitecture     string           `json:"agentArchitecture"`
	HelperArchitecture    string           `json:"helperArchitecture"`
	HelperProtocolVersion uint16           `json:"helperProtocolVersion"`
	PhysicalEligible      bool             `json:"physicalEligible"`
	ProvisionStatus       string           `json:"provisionStatus"`
	Artifacts             []BundleArtifact `json:"artifacts"`
}

func peArchitecture(raw []byte) (string, error) {
	file, err := pe.NewFile(bytes.NewReader(raw))
	if err != nil {
		return "", fmt.Errorf("%w: Windows PE artifact required", ErrConfig)
	}
	defer file.Close()
	switch file.Machine {
	case pe.IMAGE_FILE_MACHINE_AMD64:
		return "amd64", nil
	case pe.IMAGE_FILE_MACHINE_ARM64:
		return "arm64", nil
	default:
		return "", fmt.Errorf("%w: unsupported PE architecture", ErrConfig)
	}
}

// BuildBundle writes only three pinned artifacts and a manifest into a NEW
// local directory. Certificates/private keys are never embedded or generated.
func BuildBundle(config Config, directory string) (BundleManifest, error) {
	if err := config.Validate(); err != nil {
		return BundleManifest{}, err
	}
	if !absolutePath(directory) {
		return BundleManifest{}, ErrConfig
	}
	if err := noReparse(filepath.Dir(directory)); err != nil {
		return BundleManifest{}, err
	}
	inputs := []struct {
		name     string
		artifact Artifact
	}{{"vynic-printer-agent.exe", config.Agent}, {"vynic-print-helper.exe", Artifact{Path: config.Helper.Path, SHA256: config.Helper.SHA256}}, {"capability-profile.json", config.CapabilityProfile}}
	raw := make([][]byte, len(inputs))
	for i, input := range inputs {
		var err error
		raw[i], err = checkArtifact(input.artifact, 128<<20)
		if err != nil {
			return BundleManifest{}, err
		}
	}
	if err := printqueue.ValidatePrimaryProfile(raw[2]); err != nil {
		return BundleManifest{}, err
	}
	agentArch, err := peArchitecture(raw[0])
	if err != nil {
		return BundleManifest{}, err
	}
	helperArch, err := peArchitecture(raw[1])
	if err != nil {
		return BundleManifest{}, err
	}
	if agentArch != helperArch {
		return BundleManifest{}, fmt.Errorf("%w: agent/helper architecture combination unqualified", ErrConfig)
	}
	manifest := BundleManifest{Version: 1, Product: "vynic-printer-agent", Profile: "source-held-v1", Pins: config.Pins, AgentArchitecture: agentArch, HelperArchitecture: helperArch, HelperProtocolVersion: config.Helper.ProtocolVersion, PhysicalEligible: false, ProvisionStatus: ProvisioningHeld}
	if err = os.Mkdir(directory, 0700); err != nil {
		return BundleManifest{}, err
	}
	success := false
	defer func() {
		if !success {
			_ = os.RemoveAll(directory)
		}
	}() // only the directory created exclusively above
	for i, input := range inputs {
		architecture := ""
		if i == 0 {
			architecture = agentArch
		}
		if i == 1 {
			architecture = helperArch
		}
		manifest.Artifacts = append(manifest.Artifacts, BundleArtifact{Name: input.name, SHA256: input.artifact.SHA256, Architecture: architecture})
		if err = os.WriteFile(filepath.Join(directory, input.name), raw[i], 0600); err != nil {
			return BundleManifest{}, err
		}
	}
	encoded, err := json.MarshalIndent(manifest, "", "  ")
	if err != nil {
		return BundleManifest{}, err
	}
	if err = os.WriteFile(filepath.Join(directory, "manifest.json"), append(encoded, '\n'), 0600); err != nil {
		return BundleManifest{}, err
	}
	success = true
	return manifest, nil
}

func VerifyBundle(path string, config Config) (BundleManifest, error) {
	raw, err := readRegular(path, MaxConfigBytes)
	if err != nil {
		return BundleManifest{}, err
	}
	var manifest BundleManifest
	if err = strictJSON(raw, &manifest); err != nil {
		return BundleManifest{}, err
	}
	if err = requiredObject(raw, manifest); err != nil {
		return BundleManifest{}, err
	}
	if manifest.Version != 1 || manifest.Product != "vynic-printer-agent" || manifest.Profile != "source-held-v1" || manifest.Pins != config.Pins || manifest.HelperProtocolVersion != config.Helper.ProtocolVersion || manifest.PhysicalEligible || manifest.ProvisionStatus != ProvisioningHeld || len(manifest.Artifacts) != 3 {
		return BundleManifest{}, ErrConfig
	}
	expected := []BundleArtifact{{Name: "vynic-printer-agent.exe", SHA256: config.Agent.SHA256, Architecture: manifest.AgentArchitecture}, {Name: "vynic-print-helper.exe", SHA256: config.Helper.SHA256, Architecture: manifest.HelperArchitecture}, {Name: "capability-profile.json", SHA256: config.CapabilityProfile.SHA256}}
	if manifest.AgentArchitecture != manifest.HelperArchitecture || manifest.AgentArchitecture != "amd64" && manifest.AgentArchitecture != "arm64" {
		return BundleManifest{}, ErrConfig
	}
	for i, artifact := range manifest.Artifacts {
		if artifact != expected[i] {
			return BundleManifest{}, ErrConfig
		}
		artifactPath := filepath.Join(filepath.Dir(path), artifact.Name)
		bytes, err := checkArtifact(Artifact{Path: artifactPath, SHA256: artifact.SHA256}, 128<<20)
		if err != nil {
			return BundleManifest{}, err
		}
		if i < 2 {
			arch, err := peArchitecture(bytes)
			if err != nil || arch != artifact.Architecture {
				return BundleManifest{}, errors.Join(ErrConfig, err)
			}
		} else if err = printqueue.ValidatePrimaryProfile(bytes); err != nil {
			return BundleManifest{}, err
		}
	}
	files, err := os.ReadDir(filepath.Dir(path))
	if err != nil || len(files) != 4 {
		return BundleManifest{}, fmt.Errorf("%w: bundle contains undeclared files", ErrConfig)
	}
	return manifest, nil
}

type InstallerPlan struct {
	Version               int            `json:"version"`
	Mode                  string         `json:"mode"`
	Config                Artifact       `json:"config"`
	Bundle                Artifact       `json:"bundle"`
	ClientProfile         Artifact       `json:"clientProfile"`
	Pins                  printhost.Pins `json:"pins"`
	ServiceName           string         `json:"serviceName"`
	Principal             Principal      `json:"principal"`
	ExecutablePath        string         `json:"executablePath"`
	Arguments             []string       `json:"arguments"`
	Action                string         `json:"action"`
	ExistingServicePolicy string         `json:"existingServicePolicy"`
	PhysicalEligible      bool           `json:"physicalEligible"`
	ProvisionStatus       string         `json:"provisionStatus"`
}

type PlanDocument struct {
	Plan       InstallerPlan `json:"plan"`
	PlanSHA256 string        `json:"planSha256"`
}

func planHash(plan InstallerPlan) string {
	raw, _ := json.Marshal(plan)
	digest := sha256.Sum256(raw)
	return hex.EncodeToString(digest[:])
}

func CreateInstallerPlan(configPath string, bundle Artifact, clientProfile Artifact) (PlanDocument, error) {
	config, err := LoadConfig(configPath)
	if err != nil {
		return PlanDocument{}, err
	}
	if _, err = New(config, config.Agent.Path); err != nil {
		return PlanDocument{}, err
	} // static artifact/TLS/state preflight; opens no writer
	if err = ValidatePrincipal(config.ServicePrincipal, config.Pins); err != nil {
		return PlanDocument{}, err
	}
	if _, err = checkArtifact(bundle, MaxConfigBytes); err != nil {
		return PlanDocument{}, err
	}
	if _, err = VerifyBundle(bundle.Path, config); err != nil {
		return PlanDocument{}, err
	}
	if err = validateClientProfile(clientProfile, config); err != nil {
		return PlanDocument{}, err
	}
	raw, err := readRegular(configPath, MaxConfigBytes)
	if err != nil {
		return PlanDocument{}, err
	}
	sum := sha256.Sum256(raw)
	plan := InstallerPlan{Version: 1, Mode: PlanOnly, Config: Artifact{Path: configPath, SHA256: hex.EncodeToString(sum[:])}, Bundle: bundle, ClientProfile: clientProfile, Pins: config.Pins, ServiceName: printhost.ServiceName(config.Pins.HostID), Principal: config.ServicePrincipal, ExecutablePath: config.Agent.Path, Arguments: []string{"service", "--config", configPath}, Action: "CREATE_STOPPED_MANUAL_SERVICE", ExistingServicePolicy: "PRESERVE_EXACT_OR_REFUSE", PhysicalEligible: false, ProvisionStatus: ProvisioningHeld}
	return PlanDocument{Plan: plan, PlanSHA256: planHash(plan)}, nil
}

type InstalledService struct {
	ExecutablePath string
	Arguments      []string
	AccountName    string
	SID            string
	ServiceType    uint32
	StartType      uint32
}

type InstallerBackend interface {
	IsAdmin(context.Context) (bool, error)
	AccountSID(context.Context, string) (string, error)
	Inspect(context.Context, string) (*InstalledService, error)
	SystemSCPath() (string, error)
	RunSC(context.Context, string, []string) error
}

// ApplyInstallerPlan defaults to pure PlanOnly. A future explicit Apply rechecks
// the reviewed hash, every artifact/profile/account and current service. It can
// create only a stopped manual own-process service, never alter/start/delete an
// existing service or grant ACL/logon/firewall/credential/driver permissions.
func ApplyInstallerPlan(ctx context.Context, document PlanDocument, reviewedHash string, explicitApply bool, backend InstallerBackend) error {
	if document.PlanSHA256 != planHash(document.Plan) || !canonicalHash(document.PlanSHA256) {
		return fmt.Errorf("%w: reviewed plan digest mismatch", ErrConfig)
	}
	if !explicitApply {
		return nil
	} // deliberately zero external backend calls
	if reviewedHash != document.PlanSHA256 || backend == nil {
		return fmt.Errorf("%w: explicit Apply and exact reviewed hash required", ErrConfig)
	}
	plan := document.Plan
	if plan.Version != 1 || plan.Mode != PlanOnly || plan.Action != "CREATE_STOPPED_MANUAL_SERVICE" || plan.ExistingServicePolicy != "PRESERVE_EXACT_OR_REFUSE" || plan.PhysicalEligible || plan.ProvisionStatus != ProvisioningHeld || plan.Pins.Scope != printhost.Local {
		return fmt.Errorf("%w: unsupported current role/profile for Apply", ErrConfig)
	}
	if _, err := checkArtifact(plan.Config, MaxConfigBytes); err != nil {
		return err
	}
	rebuilt, err := CreateInstallerPlan(plan.Config.Path, plan.Bundle, plan.ClientProfile)
	if err != nil {
		return err
	}
	if rebuilt.PlanSHA256 != document.PlanSHA256 {
		return fmt.Errorf("%w: reviewed inputs changed", ErrConfig)
	}
	admin, err := backend.IsAdmin(ctx)
	if err != nil || !admin {
		return errors.Join(fmt.Errorf("%w: elevated administrator required; no automatic elevation", ErrConfig), err)
	}
	sid, err := backend.AccountSID(ctx, plan.Principal.AccountName)
	if err != nil || sid != plan.Principal.SID {
		return errors.Join(fmt.Errorf("%w: current account/SID mismatch", ErrConfig), err)
	}
	existing, err := backend.Inspect(ctx, plan.ServiceName)
	if err != nil {
		return err
	}
	if existing != nil {
		if existing.ExecutablePath != plan.ExecutablePath || strings.Join(existing.Arguments, "\x00") != strings.Join(plan.Arguments, "\x00") || existing.AccountName != plan.Principal.AccountName || existing.SID != plan.Principal.SID || existing.ServiceType != 16 || existing.StartType != 3 {
			return fmt.Errorf("%w: preserve existing service; configuration mismatch", ErrConfig)
		}
		return nil
	}
	sc, err := backend.SystemSCPath()
	if err != nil {
		return err
	}
	if !absolutePath(sc) || !strings.EqualFold(filepath.Base(sc), "sc.exe") || !strings.EqualFold(filepath.Base(filepath.Dir(sc)), "System32") {
		return fmt.Errorf("%w: exact System32 sc.exe required", ErrConfig)
	}
	command := quoteWindows(plan.ExecutablePath)
	for _, arg := range plan.Arguments {
		command += " " + quoteWindows(arg)
	}
	args := []string{"create", plan.ServiceName, "binPath=", command, "type=", "own", "start=", "demand", "obj=", plan.Principal.AccountName, "DisplayName=", "Vynic Printer Agent " + plan.Pins.HostID}
	if err := validateCreateArguments(args); err != nil {
		return err
	}
	return backend.RunSC(ctx, sc, args)
}

func validateCreateArguments(args []string) error {
	if len(args) != 12 || args[0] != "create" || args[2] != "binPath=" || args[4] != "type=" || args[5] != "own" || args[6] != "start=" || args[7] != "demand" || args[8] != "obj=" || args[10] != "DisplayName=" || !strings.HasPrefix(args[1], "VynicPrinterHost-") || !printqueue.CanonicalUUID(strings.TrimPrefix(args[1], "VynicPrinterHost-")) {
		return ErrConfig
	}
	for _, arg := range args {
		if arg == "" || strings.ContainsAny(arg, "\x00\r\n") {
			return ErrConfig
		}
	}
	return nil
}

func ReferenceFile(path string) (Artifact, error) {
	raw, err := readRegular(path, MaxConfigBytes)
	if err != nil {
		return Artifact{}, err
	}
	sum := sha256.Sum256(raw)
	return Artifact{Path: path, SHA256: hex.EncodeToString(sum[:])}, nil
}

func LoadPlan(path string) (PlanDocument, error) {
	raw, err := readRegular(path, MaxConfigBytes)
	if err != nil {
		return PlanDocument{}, err
	}
	return DecodePlan(raw)
}

func quoteWindows(value string) string {
	if value != "" && !strings.ContainsAny(value, " \t\"") {
		return value
	}
	var out strings.Builder
	out.WriteByte('"')
	slashes := 0
	for _, r := range value {
		if r == '\\' {
			slashes++
			continue
		}
		if r == '"' {
			out.WriteString(strings.Repeat("\\", slashes*2+1))
		} else {
			out.WriteString(strings.Repeat("\\", slashes))
		}
		slashes = 0
		out.WriteRune(r)
	}
	out.WriteString(strings.Repeat("\\", slashes*2))
	out.WriteByte('"')
	return out.String()
}

func DecodePlan(raw []byte) (PlanDocument, error) {
	var document PlanDocument
	if err := strictJSON(raw, &document); err != nil {
		return document, err
	}
	if err := requiredObject(raw, document); err != nil {
		return document, err
	}
	if document.PlanSHA256 != planHash(document.Plan) {
		return PlanDocument{}, ErrConfig
	}
	return document, nil
}
