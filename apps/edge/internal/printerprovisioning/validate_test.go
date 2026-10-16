package printerprovisioning

import (
	"bytes"
	"crypto/ed25519"
	"crypto/rand"
	"crypto/x509"
	"encoding/json"
	"errors"
	"math/big"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"vynic.local/edge/internal/printqueue"
)

type fixture struct {
	key    ed25519.PrivateKey
	state  TrustedState
	peer   AuthenticatedPeer
	body   GrantBody
	grant  []byte
	jobRaw []byte
	job    printqueue.FrozenJob
}

func uuid(n int) string {
	return "00000000-0000-4000-8000-" + strings.Repeat("0", 11) + string("0123456789abcdef"[n])
}

func encode(t *testing.T, v any) []byte {
	t.Helper()
	b, e := json.Marshal(v)
	if e != nil {
		t.Fatal(e)
	}
	return b
}

func (f *fixture) signRaw(t *testing.T, body []byte) []byte {
	t.Helper()
	return encode(t, SignedGrant{Body: body, Signature: ed25519.Sign(f.key, SignatureInput(body))})
}

func (f *fixture) resign(t *testing.T) {
	t.Helper()
	body := encode(t, f.body)
	f.grant = f.signRaw(t, body)
	f.state.CurrentGrantBodySHA256 = SHA256(body)
}

func fresh(t *testing.T, kind string, scope Scope) *fixture {
	t.Helper()
	raw, e := os.ReadFile(filepath.Join("..", "printqueue", "testdata", "dart_"+kind+".json"))
	if e != nil {
		t.Fatal(e)
	}
	j, e := printqueue.DecodeFrozenJob(raw)
	if e != nil {
		t.Fatal(e)
	}
	pub, key, e := ed25519.GenerateKey(rand.Reader)
	if e != nil {
		t.Fatal(e)
	}
	clientPub, clientKey, e := ed25519.GenerateKey(rand.Reader)
	if e != nil {
		t.Fatal(e)
	}
	now := time.Unix(1900000000, 0).UTC()
	clientID := uuid(12)
	uri := &url.URL{Scheme: "spiffe", Host: "vynic-printer-agent", Path: "/" + j.Destination.WorkerHostID + "/" + clientID}
	cert := &x509.Certificate{SerialNumber: big.NewInt(1), BasicConstraintsValid: true, KeyUsage: x509.KeyUsageDigitalSignature, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageClientAuth}, URIs: []*url.URL{uri}, NotBefore: now.Add(-time.Minute), NotAfter: now.Add(time.Hour)}
	der, e := x509.CreateCertificate(rand.Reader, cert, cert, clientPub, clientKey)
	if e != nil {
		t.Fatal(e)
	}
	// All artifacts are test-owned temporary data. No private key, trust store,
	// enrollment, real certificate or live installation is read or modified.
	tmp := t.TempDir()
	if e = os.WriteFile(filepath.Join(tmp, "synthetic-client.der"), der, 0600); e != nil {
		t.Fatal(e)
	}
	destination := j.Destination
	destination.DocumentName = ""
	route := Route{Version: Version, PhysicalPrinterID: j.PhysicalPrinterID, AliasID: j.AliasID, RouteRevision: j.RouteRevision, ConfigRevision: j.ConfigRevision, BindingRevision: j.BindingRevision, RegistryRevision: j.RegistryRevision, Destination: destination, CapabilityProfile: bytes.Clone(j.CapabilityProfile), CapabilityProfileSHA256: SHA256(j.CapabilityProfile)}
	routeRaw := encode(t, route)
	a := Authorization{VenueID: j.VenueID, DeviceID: j.DeviceID, InstallationID: j.InstallationID, HostID: j.Destination.WorkerHostID, AuthorityEpoch: j.AuthorityEpoch, TerminalID: j.TerminalID, OriginInstallationID: j.OriginInstallationID, ClientID: clientID, ClientCertificateSHA256: SHA256(der), Generation: 17}
	b := GrantBody{Version: Version, Purpose: Purpose, GrantID: uuid(13), Authorization: a, IssuedAt: now.Unix() - 45, NotBefore: now.Unix() - 30, ExpiresAt: now.Unix() + 300, Scope: scope, RouteRaw: routeRaw, RouteSHA256: SHA256(routeRaw)}
	if scope == VenueShared {
		b.ClusterID = uuid(14)
		b.MembershipSHA256 = strings.Repeat("a", 64)
	}
	f := &fixture{key: key, jobRaw: raw, job: j, peer: AuthenticatedPeer{ClientID: clientID, CertificateDER: der}, body: b, state: TrustedState{IssuerPublicKey: pub, Authorization: a, CurrentGrantID: b.GrantID, HighWaterGeneration: 17, Scope: scope, ClusterID: b.ClusterID, MembershipSHA256: b.MembershipSHA256, RouteRaw: bytes.Clone(routeRaw), Now: now, MaxLifetimeSeconds: 600}}
	f.resign(t)
	if e = os.WriteFile(filepath.Join(tmp, "candidate-grant.json"), f.grant, 0600); e != nil {
		t.Fatal(e)
	}
	return f
}

func TestCandidatePreservesCompleteFrozenBytesAndNeverAdmits(t *testing.T) {
	for _, kind := range []string{"tcp", "windowsSpooler"} {
		for _, scope := range []Scope{Local, VenueShared} {
			t.Run(kind+"/"+string(scope), func(t *testing.T) {
				f := fresh(t, kind, scope)
				v, e := ValidateCandidate(f.grant, f.state, f.peer, f.jobRaw)
				if e != nil {
					t.Fatal(e)
				}
				if !bytes.Equal(v.Raw(), f.jobRaw) || v.Digest() != f.job.Digest() || !bytes.Equal(v.GrantRaw(), f.grant) || !bytes.Equal(v.RouteRaw(), f.state.RouteRaw) || v.RouteSHA256() != f.body.RouteSHA256 || v.GrantBodySHA256() != f.state.CurrentGrantBodySHA256 || v.Scope() != scope || v.AdmissionBlockedReason() != AdmissionHold {
					t.Fatal("validation changed immutable evidence or cleared hold")
				}
				j, e := v.FrozenJob()
				if e != nil {
					t.Fatal(e)
				}
				if j.JobID != f.job.JobID || j.RequestID != f.job.RequestID || j.EffectID != f.job.EffectID || j.AttemptID != f.job.AttemptID || j.BeepAttemptID != f.job.BeepAttemptID || j.Destination != f.job.Destination || !bytes.Equal(j.PrimaryBytes, f.job.PrimaryBytes) || !bytes.HasSuffix(j.PrimaryBytes, []byte{0x1d, 0x56, 0x01}) {
					t.Fatal("IDs, captured destination, raster or cut changed")
				}
				for _, raw := range [][]byte{v.Raw(), v.GrantRaw(), v.RouteRaw()} {
					raw[0] ^= 1
				}
				f.grant[0] ^= 1
				f.jobRaw[0] ^= 1
				f.state.RouteRaw[0] ^= 1
				f.peer.CertificateDER[0] ^= 1
				j.PrimaryBytes[0] ^= 1
				j.CapabilityProfile[0] ^= 1
				again, e := v.FrozenJob()
				if e != nil || again.Digest() != v.Digest() || again.PrimarySHA256 != SHA256(again.PrimaryBytes) {
					t.Fatal("caller mutation changed retained job")
				}
			})
		}
	}
}

func TestPinnedIssuerAndPrinterOnlySignatureDomain(t *testing.T) {
	f := fresh(t, "tcp", Local)
	var signed SignedGrant
	if e := json.Unmarshal(f.grant, &signed); e != nil {
		t.Fatal(e)
	}
	wrongPub, wrongKey, e := ed25519.GenerateKey(rand.Reader)
	if e != nil {
		t.Fatal(e)
	}
	for _, tc := range []struct {
		name   string
		mutate func() []byte
	}{
		{"wrongIssuer", func() []byte {
			return encode(t, SignedGrant{Body: signed.Body, Signature: ed25519.Sign(wrongKey, SignatureInput(signed.Body))})
		}},
		{"bodyWhitespaceTamper", func() []byte {
			return encode(t, SignedGrant{Body: append(bytes.Clone(signed.Body), ' '), Signature: signed.Signature})
		}},
		{"noDomain", func() []byte {
			return encode(t, SignedGrant{Body: signed.Body, Signature: ed25519.Sign(f.key, []byte(SHA256(signed.Body)))})
		}},
		{"oldProofDomain", func() []byte {
			return encode(t, SignedGrant{Body: signed.Body, Signature: ed25519.Sign(f.key, append([]byte("vynic/operational-proof/v1\x00"), SignatureInput(signed.Body)[len(SignatureDomain):]...))})
		}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if _, e := ValidateCandidate(tc.mutate(), f.state, f.peer, f.jobRaw); !errors.Is(e, ErrSignature) {
				t.Fatalf("%v", e)
			}
		})
	}
	f.state.IssuerPublicKey = wrongPub
	if _, e := ValidateCandidate(f.grant, f.state, f.peer, f.jobRaw); !errors.Is(e, ErrSignature) {
		t.Fatal(e)
	}
	for _, purpose := range []string{"FOUNDATION_ONLY", "ISOLATED_PROOF", "VYNIC_OPERATIONAL_PROOF", "printer", ""} {
		t.Run(purpose, func(t *testing.T) {
			f := fresh(t, "tcp", Local)
			f.body.Purpose = purpose
			f.resign(t)
			if _, e := ValidateCandidate(f.grant, f.state, f.peer, f.jobRaw); !errors.Is(e, ErrInvalid) {
				t.Fatal(e)
			}
		})
	}
}

func TestLifetimeGenerationRevocationAndTrustedStateFailClosed(t *testing.T) {
	cases := []struct {
		name   string
		mutate func(*fixture)
		want   error
	}{
		{"expired", func(f *fixture) { f.body.ExpiresAt = f.state.Now.Unix(); f.resign(t) }, ErrLifetime},
		{"futureIssue", func(f *fixture) {
			f.body.IssuedAt = f.state.Now.Unix() + 1
			f.body.NotBefore = f.body.IssuedAt
			f.resign(t)
		}, ErrLifetime},
		{"futureNotBefore", func(f *fixture) { f.body.NotBefore = f.state.Now.Unix() + 1; f.resign(t) }, ErrLifetime},
		{"zeroIssue", func(f *fixture) { f.body.IssuedAt = 0; f.resign(t) }, ErrLifetime},
		{"reversedWindow", func(f *fixture) { f.body.NotBefore = f.body.ExpiresAt; f.resign(t) }, ErrLifetime},
		{"policyLifetimeExceeded", func(f *fixture) { f.body.ExpiresAt = f.body.IssuedAt + 601; f.resign(t) }, ErrLifetime},
		{"oldGeneration", func(f *fixture) { f.body.Authorization.Generation--; f.resign(t) }, ErrStale},
		{"futureGeneration", func(f *fixture) { f.body.Authorization.Generation++; f.resign(t) }, ErrStale},
		{"revokedCurrent", func(f *fixture) { f.state.RevokedThroughGeneration = 17 }, ErrRevoked},
		{"differentCurrentGrant", func(f *fixture) { f.state.CurrentGrantID = uuid(11) }, ErrStale},
		{"differentCurrentBodyHash", func(f *fixture) { f.state.CurrentGrantBodySHA256 = strings.Repeat("a", 64) }, ErrStale},
		{"unpersistedGeneration", func(f *fixture) { f.state.HighWaterGeneration++ }, ErrState},
		{"rollbackCurrentGeneration", func(f *fixture) { f.state.Authorization.Generation-- }, ErrState},
		{"missingIssuerPin", func(f *fixture) { f.state.IssuerPublicKey = nil }, ErrState},
		{"missingCurrentStateHash", func(f *fixture) { f.state.CurrentGrantBodySHA256 = "" }, ErrState},
		{"missingClock", func(f *fixture) { f.state.Now = time.Time{} }, ErrState},
		{"missingLifetimePolicy", func(f *fixture) { f.state.MaxLifetimeSeconds = 0 }, ErrState},
		{"unknownScope", func(f *fixture) { f.state.Scope = "AUTO" }, ErrState},
		{"localWithCluster", func(f *fixture) { f.state.ClusterID = uuid(14) }, ErrState},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			f := fresh(t, "tcp", Local)
			tc.mutate(f)
			if _, e := ValidateCandidate(f.grant, f.state, f.peer, f.jobRaw); !errors.Is(e, tc.want) {
				t.Fatalf("wanted %v; got %v", tc.want, e)
			}
		})
	}
}

func TestSignedWrongContextAndAuthenticatedDERRefused(t *testing.T) {
	for _, field := range []string{"venueId", "deviceId", "installationId", "hostId", "authorityEpoch", "terminalId", "originInstallationId", "clientId", "clientCertificateSha256"} {
		t.Run(field, func(t *testing.T) {
			f := fresh(t, "tcp", Local)
			var auth map[string]any
			if e := json.Unmarshal(encode(t, f.body.Authorization), &auth); e != nil {
				t.Fatal(e)
			}
			if field == "authorityEpoch" {
				auth[field] = 42
			} else if field == "clientCertificateSha256" {
				auth[field] = strings.Repeat("a", 64)
			} else {
				auth[field] = uuid(11)
			}
			if e := json.Unmarshal(encode(t, auth), &f.body.Authorization); e != nil {
				t.Fatal(e)
			}
			f.resign(t)
			if _, e := ValidateCandidate(f.grant, f.state, f.peer, f.jobRaw); !errors.Is(e, ErrScope) {
				t.Fatal(e)
			}
		})
	}
	for _, tc := range []struct {
		name   string
		mutate func(*fixture)
	}{
		{"wrongObservedClient", func(f *fixture) { f.peer.ClientID = uuid(11) }},
		{"wrongDER", func(f *fixture) { f.peer.CertificateDER[0] ^= 1 }},
		{"emptyDER", func(f *fixture) { f.peer.CertificateDER = nil }},
		{"invalidPinnedDER", func(f *fixture) {
			f.peer.CertificateDER = []byte("not a certificate")
			f.state.Authorization.ClientCertificateSHA256 = SHA256(f.peer.CertificateDER)
			f.body.Authorization = f.state.Authorization
			f.resign(t)
		}},
		{"expiredLeaf", func(f *fixture) {
			f.state.Now = f.state.Now.Add(2 * time.Hour)
			f.body.IssuedAt = f.state.Now.Unix() - 30
			f.body.NotBefore = f.body.IssuedAt
			f.body.ExpiresAt = f.state.Now.Unix() + 300
			f.resign(t)
		}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			f := fresh(t, "tcp", Local)
			tc.mutate(f)
			if _, e := ValidateCandidate(f.grant, f.state, f.peer, f.jobRaw); !errors.Is(e, ErrScope) {
				t.Fatal(e)
			}
		})
	}
	for _, tc := range []struct {
		name   string
		mutate func(*fixture)
	}{
		{"signedSharedOnLocal", func(f *fixture) {
			f.body.Scope = VenueShared
			f.body.ClusterID = uuid(14)
			f.body.MembershipSHA256 = strings.Repeat("a", 64)
			f.resign(t)
		}},
		{"wrongSharedMembership", func(f *fixture) { f.body.MembershipSHA256 = strings.Repeat("b", 64); f.resign(t) }},
		{"wrongSharedCluster", func(f *fixture) { f.body.ClusterID = uuid(11); f.resign(t) }},
	} {
		t.Run(tc.name, func(t *testing.T) {
			f := fresh(t, "tcp", VenueShared)
			if tc.name == "signedSharedOnLocal" {
				f = fresh(t, "tcp", Local)
			}
			tc.mutate(f)
			if _, e := ValidateCandidate(f.grant, f.state, f.peer, f.jobRaw); !errors.Is(e, ErrScope) {
				t.Fatal(e)
			}
		})
	}
}
