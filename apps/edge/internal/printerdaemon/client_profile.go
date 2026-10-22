package printerdaemon

import (
	"bytes"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"encoding/hex"
	"encoding/pem"
	"fmt"
	"path/filepath"
	"strings"
	"time"

	"vynic.local/edge/internal/printeragent"
	"vynic.local/edge/internal/printhost"
	"vynic.local/edge/internal/printqueue"
)

// Matches the read-only Flutter profile exactly. There is deliberately no CA
// trust fallback on the client: the current server leaf must match its DER pin.
type ClientProfile struct {
	Version                     int            `json:"version"`
	ProvisionStatus             string         `json:"provisionStatus"`
	ListenAddress               string         `json:"listenAddress"`
	ClientID                    string         `json:"clientId"`
	CurrentDeviceInstallationID string         `json:"currentDeviceInstallationId"`
	Pins                        printhost.Pins `json:"pins"`
	ServerCertificatePath       string         `json:"serverCertificatePath"`
	ServerCertificateSHA256     string         `json:"serverCertificateSha256"`
	ClientCertificatePath       string         `json:"clientCertificatePath"`
	ClientPrivateKeyPath        string         `json:"clientPrivateKeyPath"`
	ClientCertificateSHA256     string         `json:"clientCertificateSha256"`
}

func leafCertificate(path string) (*x509.Certificate, error) {
	raw, err := readRegular(path, 256<<10)
	if err != nil {
		return nil, err
	}
	block, rest := pem.Decode(raw)
	if block == nil || block.Type != "CERTIFICATE" || len(bytes.TrimSpace(rest)) != 0 {
		return nil, fmt.Errorf("%w: one pinned certificate leaf required", ErrConfig)
	}
	certificate, err := x509.ParseCertificate(block.Bytes)
	if err != nil || time.Now().Before(certificate.NotBefore) || !time.Now().Before(certificate.NotAfter) {
		return nil, fmt.Errorf("%w: current certificate required", ErrConfig)
	}
	return certificate, nil
}

func validateClientProfile(artifact Artifact, config Config) error {
	raw, err := checkArtifact(artifact, MaxConfigBytes)
	if err != nil {
		return err
	}
	var profile ClientProfile
	if err = strictJSON(raw, &profile); err != nil {
		return err
	}
	if err = requiredObject(raw, profile); err != nil {
		return err
	}
	if profile.Version != 1 || profile.ProvisionStatus != ProvisioningHeld || !printqueue.CanonicalUUID(profile.CurrentDeviceInstallationID) || profile.ListenAddress != config.ListenAddress || strings.HasSuffix(profile.ListenAddress, ":0") || profile.Pins != config.Pins {
		return fmt.Errorf("%w: explicit client profile binding/fixed port required", ErrConfig)
	}
	for _, path := range []string{profile.ServerCertificatePath, profile.ClientCertificatePath, profile.ClientPrivateKeyPath} {
		relative, err := filepath.Rel(filepath.Dir(artifact.Path), path)
		if !absolutePath(path) || err != nil || relative == ".." || strings.HasPrefix(relative, ".."+string(filepath.Separator)) || filepath.IsAbs(relative) {
			return fmt.Errorf("%w: client assets must stay in profile directory", ErrConfig)
		}
	}
	server, err := leafCertificate(profile.ServerCertificatePath)
	if err != nil {
		return err
	}
	configured, err := leafCertificate(config.TLS.ServerCertificatePath)
	if err != nil {
		return err
	}
	serverHash := sha256.Sum256(server.Raw)
	if !bytes.Equal(server.Raw, configured.Raw) || hex.EncodeToString(serverHash[:]) != profile.ServerCertificateSHA256 {
		return fmt.Errorf("%w: pinned server leaf mismatch", ErrConfig)
	}
	client, err := leafCertificate(profile.ClientCertificatePath)
	if err != nil {
		return err
	}
	clientHash := sha256.Sum256(client.Raw)
	clientDigest := hex.EncodeToString(clientHash[:])
	wantURI, err := printeragent.ClientURI(config.Pins.HostID, profile.ClientID)
	if err != nil || client.IsCA || !client.BasicConstraintsValid || client.KeyUsage&x509.KeyUsageDigitalSignature == 0 || len(client.ExtKeyUsage) != 1 || client.ExtKeyUsage[0] != x509.ExtKeyUsageClientAuth || len(client.DNSNames) != 0 || len(client.IPAddresses) != 0 || len(client.EmailAddresses) != 0 || len(client.URIs) != 1 || client.URIs[0].String() != wantURI.String() || clientDigest != profile.ClientCertificateSHA256 {
		return fmt.Errorf("%w: client purpose/host/leaf binding", ErrConfig)
	}
	ca, err := leafCertificate(config.TLS.ClientCAPath)
	if err != nil || !ca.IsCA || !ca.BasicConstraintsValid || ca.KeyUsage&x509.KeyUsageCertSign == 0 {
		return fmt.Errorf("%w: configured client CA invalid", ErrConfig)
	}
	roots := x509.NewCertPool()
	roots.AddCert(ca)
	if _, err = client.Verify(x509.VerifyOptions{Roots: roots, CurrentTime: time.Now(), KeyUsages: []x509.ExtKeyUsage{x509.ExtKeyUsageClientAuth}}); err != nil {
		return fmt.Errorf("%w: client leaf is not issued by the configured CA", ErrConfig)
	}
	matched := false
	for _, pin := range config.Clients {
		if pin.ClientID == profile.ClientID && pin.CertificateSHA256 == clientDigest {
			matched = true
		}
	}
	if !matched {
		return fmt.Errorf("%w: client observation pin absent", ErrConfig)
	}
	certificatePEM, err := readRegular(profile.ClientCertificatePath, 256<<10)
	if err != nil {
		return err
	}
	keyPEM, err := readRegular(profile.ClientPrivateKeyPath, 256<<10)
	if err != nil {
		return fmt.Errorf("%w: client key unavailable", ErrConfig)
	}
	if _, err = tls.X509KeyPair(certificatePEM, keyPEM); err != nil {
		return fmt.Errorf("%w: client certificate/key mismatch", ErrConfig)
	}
	return nil
}
