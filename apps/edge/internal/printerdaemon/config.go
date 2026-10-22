// Package printerdaemon is the runnable, physically held printer agent.
// Configuration and certificates are provisioned inputs, never authority issued
// by this package. It never opens the current POS Hive or a default Edge root.
package printerdaemon

import (
	"bytes"
	"crypto/sha256"
	"crypto/tls"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/url"
	"os"
	"path/filepath"
	"reflect"
	"strconv"
	"strings"

	"vynic.local/edge/internal/printhost"
	"vynic.local/edge/internal/printqueue"
	"vynic.local/edge/internal/store"
)

const (
	ConfigVersion       = 1
	LocalHeld           = "LOCAL_HELD"
	SharedHeld          = "VENUE_SHARED_HELD"
	DispatchHeld        = "HELD"
	ProvisioningHeld    = "HELD_PROVISIONING"
	PhysicalHoldReason  = "PHYSICAL_ACTIVATION_PENDING"
	StatePurpose        = "PRINTER_AGENT_SOFTWARE_HELD"
	StateMarkerFilename = "printer-agent.state.json"
	MaxConfigBytes      = 65536
)

var ErrConfig = errors.New("printer agent configuration refused")

type Artifact struct {
	Path   string `json:"path"`
	SHA256 string `json:"sha256"`
}

type HelperArtifact struct {
	Path            string `json:"path"`
	SHA256          string `json:"sha256"`
	ProtocolVersion uint16 `json:"protocolVersion"`
}

type TLSPaths struct {
	ServerCertificatePath string `json:"serverCertificatePath"`
	ServerPrivateKeyPath  string `json:"serverPrivateKeyPath"`
	ClientCAPath          string `json:"clientCAPath"`
}

type ClientPin struct {
	ClientID          string `json:"clientId"`
	CertificateSHA256 string `json:"certificateSha256"`
}

// Principal is a selected, separately qualified future SCM identity. Foreground
// inventory never establishes access for it; no password or account is issued.
type Principal struct {
	Kind          string   `json:"kind"`
	AccountName   string   `json:"accountName"`
	SID           string   `json:"sid"`
	Qualification Artifact `json:"qualification"`
}

type Config struct {
	Version           int            `json:"version"`
	Profile           string         `json:"profile"`
	DispatchPolicy    string         `json:"dispatchPolicy"`
	Pins              printhost.Pins `json:"pins"`
	StateDirectory    string         `json:"stateDirectory"`
	ListenAddress     string         `json:"listenAddress"`
	Agent             Artifact       `json:"agent"`
	Helper            HelperArtifact `json:"helper"`
	CapabilityProfile Artifact       `json:"capabilityProfile"`
	TLS               TLSPaths       `json:"tls"`
	Clients           []ClientPin    `json:"clients"`
	ServicePrincipal  Principal      `json:"servicePrincipal"`
}

type StateMarker struct {
	Version       int            `json:"version"`
	Purpose       string         `json:"purpose"`
	SchemaVersion int            `json:"schemaVersion"`
	Pins          printhost.Pins `json:"pins"`
}

func canonicalHash(value string) bool {
	decoded, err := hex.DecodeString(value)
	return err == nil && len(decoded) == sha256.Size && hex.EncodeToString(decoded) == value
}

func absolutePath(path string) bool {
	if path == "" || !filepath.IsAbs(path) || filepath.Clean(path) != path || strings.TrimSpace(path) != path || strings.HasPrefix(path, `\\`) || strings.HasPrefix(path, `//`) {
		return false
	}
	for _, c := range path {
		if c < 32 || c == 127 {
			return false
		}
	}
	return true
}

// uniqueJSON avoids decoder aliases from duplicate fields at any level.
func uniqueJSON(decoder *json.Decoder, depth int) error {
	if depth > 32 {
		return ErrConfig
	}
	token, err := decoder.Token()
	if err != nil {
		return err
	}
	delimiter, compound := token.(json.Delim)
	if !compound {
		return nil
	}
	switch delimiter {
	case '{':
		seen := map[string]bool{}
		for decoder.More() {
			key, err := decoder.Token()
			name, ok := key.(string)
			if err != nil || !ok || seen[name] {
				return ErrConfig
			}
			seen[name] = true
			if err = uniqueJSON(decoder, depth+1); err != nil {
				return err
			}
		}
	case '[':
		for decoder.More() {
			if err = uniqueJSON(decoder, depth+1); err != nil {
				return err
			}
		}
	default:
		return ErrConfig
	}
	_, err = decoder.Token()
	return err
}

func strictJSON(raw []byte, target any) error {
	if len(raw) == 0 || len(raw) > MaxConfigBytes {
		return ErrConfig
	}
	check := json.NewDecoder(bytes.NewReader(raw))
	check.UseNumber()
	if err := uniqueJSON(check, 0); err != nil {
		return fmt.Errorf("%w: duplicate/malformed JSON", ErrConfig)
	}
	if _, err := check.Token(); err != io.EOF {
		return fmt.Errorf("%w: trailing JSON", ErrConfig)
	}
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		return fmt.Errorf("%w: %v", ErrConfig, err)
	}
	return nil
}

func requiredObject(raw []byte, value any) error {
	return requiredShape(raw, reflect.TypeOf(value))
}

// encoding/json accepts case aliases and null for several Go values. A saved
// installation plan is an exact schema, including its nested pins/artifacts.
func requiredShape(raw []byte, typeOf reflect.Type) error {
	if bytes.Equal(bytes.TrimSpace(raw), []byte("null")) {
		return fmt.Errorf("%w: null field", ErrConfig)
	}
	if typeOf.Kind() == reflect.Slice || typeOf.Kind() == reflect.Array {
		var items []json.RawMessage
		if json.Unmarshal(raw, &items) != nil {
			return ErrConfig
		}
		for _, item := range items {
			if err := requiredShape(item, typeOf.Elem()); err != nil {
				return err
			}
		}
		return nil
	}
	if typeOf.Kind() != reflect.Struct {
		return nil
	}
	var fields map[string]json.RawMessage
	if json.Unmarshal(raw, &fields) != nil || fields == nil {
		return ErrConfig
	}
	if len(fields) != typeOf.NumField() {
		return fmt.Errorf("%w: missing fields", ErrConfig)
	}
	for i := 0; i < typeOf.NumField(); i++ {
		key := strings.Split(typeOf.Field(i).Tag.Get("json"), ",")[0]
		field, ok := fields[key]
		if !ok || bytes.Equal(bytes.TrimSpace(field), []byte("null")) {
			return fmt.Errorf("%w: missing %s", ErrConfig, key)
		}
		if err := requiredShape(field, typeOf.Field(i).Type); err != nil {
			return err
		}
	}
	return nil
}

func DecodeConfig(raw []byte) (Config, error) {
	var config Config
	if err := strictJSON(raw, &config); err != nil {
		return Config{}, err
	}
	if err := requiredObject(raw, config); err != nil {
		return Config{}, err
	}
	var fields map[string]json.RawMessage
	_ = json.Unmarshal(raw, &fields) // already checked above
	for _, nested := range []struct {
		name  string
		value any
	}{{"pins", config.Pins}, {"agent", config.Agent}, {"helper", config.Helper}, {"capabilityProfile", config.CapabilityProfile}, {"tls", config.TLS}, {"servicePrincipal", config.ServicePrincipal}} {
		if err := requiredObject(fields[nested.name], nested.value); err != nil {
			return Config{}, err
		}
	}
	var principalFields map[string]json.RawMessage
	_ = json.Unmarshal(fields["servicePrincipal"], &principalFields)
	if err := requiredObject(principalFields["qualification"], config.ServicePrincipal.Qualification); err != nil {
		return Config{}, err
	}
	var clients []json.RawMessage
	_ = json.Unmarshal(fields["clients"], &clients)
	for _, client := range clients {
		if err := requiredObject(client, ClientPin{}); err != nil {
			return Config{}, err
		}
	}
	if err := config.Validate(); err != nil {
		return Config{}, err
	}
	config.Clients = append([]ClientPin(nil), config.Clients...)
	return config, nil
}

func LoadConfig(path string) (Config, error) {
	raw, err := readRegular(path, MaxConfigBytes)
	if err != nil {
		return Config{}, fmt.Errorf("%w: config file: %w", ErrConfig, err)
	}
	return DecodeConfig(raw)
}

func (config Config) Validate() error {
	if config.Version != ConfigVersion || config.DispatchPolicy != DispatchHeld {
		return fmt.Errorf("%w: version/dispatch must remain held", ErrConfig)
	}
	if err := config.Pins.Validate(); err != nil {
		return errors.Join(ErrConfig, err)
	}
	if config.Profile != LocalHeld && config.Profile != SharedHeld || config.Profile == LocalHeld && config.Pins.Scope != printhost.Local || config.Profile == SharedHeld && config.Pins.Scope != printhost.VenueShared {
		return fmt.Errorf("%w: role/scope profile", ErrConfig)
	}
	if !absolutePath(config.StateDirectory) {
		return fmt.Errorf("%w: dedicated absolute state directory required", ErrConfig)
	}
	host, port, err := net.SplitHostPort(config.ListenAddress)
	value, portErr := strconv.Atoi(port)
	if err != nil || host != "127.0.0.1" || portErr != nil || value < 0 || value > 65535 || strconv.Itoa(value) != port {
		return fmt.Errorf("%w: explicit loopback listener required", ErrConfig)
	}
	for _, artifact := range []Artifact{config.Agent, {Path: config.Helper.Path, SHA256: config.Helper.SHA256}, config.CapabilityProfile} {
		if !absolutePath(artifact.Path) || !canonicalHash(artifact.SHA256) {
			return fmt.Errorf("%w: absolute artifact and digest required", ErrConfig)
		}
	}
	if config.Agent.SHA256 != config.Pins.HostBinarySHA256 || config.Helper.SHA256 != config.Pins.HelperBinarySHA256 || config.CapabilityProfile.SHA256 != config.Pins.CapabilityProfileSHA256 || config.Helper.ProtocolVersion != config.Pins.HelperProtocolVersion {
		return fmt.Errorf("%w: artifact/profile binding", ErrConfig)
	}
	for _, path := range []string{config.TLS.ServerCertificatePath, config.TLS.ServerPrivateKeyPath, config.TLS.ClientCAPath} {
		if !absolutePath(path) {
			return fmt.Errorf("%w: read-only absolute certificate path required", ErrConfig)
		}
	}
	if len(config.Clients) == 0 || len(config.Clients) > 64 {
		return fmt.Errorf("%w: explicit client pins required", ErrConfig)
	}
	seen := map[string]bool{}
	for _, client := range config.Clients {
		if !printqueue.CanonicalUUID(client.ClientID) || !canonicalHash(client.CertificateSHA256) || seen[client.ClientID] {
			return fmt.Errorf("%w: invalid/duplicate client", ErrConfig)
		}
		seen[client.ClientID] = true
	}
	return nil
}

func readRegular(path string, limit int64) ([]byte, error) {
	if err := noReparse(path); err != nil {
		return nil, err
	}
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil || !info.Mode().IsRegular() || info.Size() > limit {
		return nil, errors.Join(ErrConfig, err)
	}
	raw, err := io.ReadAll(io.LimitReader(file, limit+1))
	if err != nil || int64(len(raw)) > limit {
		return nil, errors.Join(ErrConfig, err)
	}
	current, err := os.Stat(path)
	if err != nil || !os.SameFile(info, current) {
		return nil, fmt.Errorf("%w: file changed while reading", ErrConfig)
	}
	return raw, nil
}

func checkArtifact(artifact Artifact, limit int64) ([]byte, error) {
	raw, err := readRegular(artifact.Path, limit)
	if err != nil {
		return nil, fmt.Errorf("%w: artifact unavailable: %w", ErrConfig, err)
	}
	digest := sha256.Sum256(raw)
	if hex.EncodeToString(digest[:]) != artifact.SHA256 {
		return nil, fmt.Errorf("%w: artifact checksum mismatch", ErrConfig)
	}
	return raw, nil
}

type validatedConfig struct {
	config      Config
	certificate tls.Certificate
	clientCA    []byte
	profile     []byte
}

func preflight(config Config, executable string) (validatedConfig, error) {
	if err := config.Validate(); err != nil {
		return validatedConfig{}, err
	}
	if executable != config.Agent.Path {
		return validatedConfig{}, fmt.Errorf("%w: running executable binding", ErrConfig)
	}
	for _, artifact := range []Artifact{config.Agent, {Path: config.Helper.Path, SHA256: config.Helper.SHA256}} {
		if _, err := checkArtifact(artifact, 128<<20); err != nil {
			return validatedConfig{}, err
		}
	}
	profile, err := checkArtifact(config.CapabilityProfile, 65536)
	if err != nil {
		return validatedConfig{}, err
	}
	if err = printqueue.ValidatePrimaryProfile(profile); err != nil {
		return validatedConfig{}, fmt.Errorf("%w: capability profile: %w", ErrConfig, err)
	}
	certificatePEM, err := readRegular(config.TLS.ServerCertificatePath, 256<<10)
	if err != nil {
		return validatedConfig{}, fmt.Errorf("%w: server certificate: %w", ErrConfig, err)
	}
	keyPEM, err := readRegular(config.TLS.ServerPrivateKeyPath, 256<<10)
	if err != nil {
		return validatedConfig{}, fmt.Errorf("%w: server key file unavailable", ErrConfig)
	}
	certificate, err := tls.X509KeyPair(certificatePEM, keyPEM)
	if err != nil {
		return validatedConfig{}, fmt.Errorf("%w: server certificate/key mismatch", ErrConfig)
	}
	clientCA, err := readRegular(config.TLS.ClientCAPath, 256<<10)
	if err != nil {
		return validatedConfig{}, fmt.Errorf("%w: client CA unavailable: %w", ErrConfig, err)
	}
	if err = verifyState(config); err != nil {
		return validatedConfig{}, err
	}
	config.Clients = append([]ClientPin(nil), config.Clients...)
	return validatedConfig{config: config, certificate: certificate, clientCA: clientCA, profile: append([]byte(nil), profile...)}, nil
}

func verifyMarker(config Config) error {
	raw, err := readRegular(filepath.Join(config.StateDirectory, StateMarkerFilename), MaxConfigBytes)
	if err != nil {
		return fmt.Errorf("%w: dedicated printer state marker required: %w", ErrConfig, err)
	}
	var marker StateMarker
	if err = strictJSON(raw, &marker); err != nil {
		return err
	}
	if err = requiredObject(raw, marker); err != nil {
		return err
	}
	var fields map[string]json.RawMessage
	_ = json.Unmarshal(raw, &fields)
	if err = requiredObject(fields["pins"], marker.Pins); err != nil {
		return err
	}
	if marker.Version != ConfigVersion || marker.Purpose != StatePurpose || marker.SchemaVersion != store.SchemaVersion || marker.Pins != config.Pins {
		return fmt.Errorf("%w: dedicated state identity/profile mismatch", ErrConfig)
	}
	return nil
}

// Inspect before store.Open so foreign/old roots are refused before its migration
// preparation. No default path, initialization, binding or key issuance occurs.
func verifyState(config Config) error {
	if err := verifyMarker(config); err != nil {
		return err
	}
	databasePath := filepath.Join(config.StateDirectory, "edge.db")
	if err := noReparse(databasePath); err != nil {
		return err
	}
	database, err := sql.Open("sqlite", sqliteReadOnlyURI(databasePath))
	if err != nil {
		return err
	}
	defer database.Close()
	var version int
	var installation, venue string
	if err = database.QueryRow("PRAGMA user_version").Scan(&version); err != nil || version != store.SchemaVersion {
		return fmt.Errorf("%w: dedicated state schema mismatch", ErrConfig)
	}
	if err = database.QueryRow("SELECT id,venue_id FROM installation WHERE singleton=1").Scan(&installation, &venue); err != nil || installation != config.Pins.InstallationID || venue != config.Pins.VenueID {
		return fmt.Errorf("%w: dedicated state installation/Venue binding", ErrConfig)
	}
	return nil
}

func sqliteReadOnlyURI(path string) string {
	localPath := filepath.ToSlash(path)
	if len(path) >= 3 && path[1] == ':' {
		// file://C:/... would make C: a remote URI authority. SQLite's local
		// Windows drive URI is file:///C:/..., with URL-escaped path bytes.
		localPath = "/" + strings.ReplaceAll(path, "\\", "/")
	}
	return (&url.URL{Scheme: "file", Path: localPath, RawQuery: "mode=ro"}).String()
}
