package printerprovisioning

import (
	"bytes"
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"crypto/tls"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"testing"
	"time"

	guuid "github.com/google/uuid"
	"vynic.local/edge/internal/printstation"
	"vynic.local/edge/internal/printtransport"
)

func productionCatalog(venue string, revision uint64, stores []*ProductionStore) printstation.Catalog {
	c := printstation.Catalog{Version: 1, VenueID: venue, Revision: revision, Rules: []printstation.Rule{}}
	for i, s := range stores {
		controller, printer, station := guuid.NewString(), guuid.NewString(), guuid.NewString()
		c.Controllers = append(c.Controllers, printstation.Controller{ID: controller, InstallationID: s.id, DeviceID: s.device, Name: "Controller"})
		c.Printers = append(c.Printers, printstation.PhysicalPrinter{ID: printer, Name: "Printer", ControllerID: controller, Destination: printtransport.Destination{PhysicalPrinterID: printer, WorkerHostID: controller, Transport: printtransport.WindowsSpooler, QueueName: "test-queue", ExpectedDriverName: "test-driver", ExpectedPortName: "test-port", DocumentName: "ticket"}, Profile: json.RawMessage(`{"protocol":1,"paperWidthMm":80,"rasterWidthDots":576,"language":"escposRaster","cutter":"none","encoding":"georgianViaRaster"}`), Enabled: true, FailoverMode: printstation.FixedController})
		scope, owner := printstation.Local, s.device
		if i == 0 {
			scope, owner = printstation.Shared, ""
		}
		c.Stations = append(c.Stations, printstation.Station{ID: station, Name: "Station", Role: "custom", Scope: scope, OwnerDeviceID: owner, Enabled: true, Routes: []string{printer}})
	}
	return c
}
func productionBody(stores []*ProductionStore, now time.Time) ProductionBody {
	b := ProductionBody{Version: 1, Purpose: ProductionPurpose, VenueID: guuid.NewString(), ClusterID: guuid.NewString(), Generation: 1, Revision: 1, IssuedAt: now.Unix(), NotBefore: now.Unix(), ExpiresAt: now.Unix() + OfflineSeconds, OfflineMaxSeconds: OfflineSeconds, Topology: "SINGLE_REPLICA", Members: []ProductionMember{}}
	for i, s := range stores {
		e := s.Enrollment()
		role := "CLIENT"
		if i == 0 {
			role = "VOTER"
		}
		b.Members = append(b.Members, ProductionMember{e.InstallationID, s.device, e.PublicKey, SHA256(e.Certificate), true, role, ""})
	}
	b.CatalogRaw = printstation.Encode(productionCatalog(b.VenueID, 1, stores))
	return b
}
func signedProduction(t *testing.T, key ed25519.PrivateKey, b ProductionBody) []byte {
	t.Helper()
	raw, e := json.Marshal(b)
	if e != nil {
		t.Fatal(e)
	}
	out, e := json.Marshal(SignedGrant{raw, ed25519.Sign(key, productionInput(raw))})
	if e != nil {
		t.Fatal(e)
	}
	return out
}
func newProductionTestStore(t *testing.T, pub ed25519.PublicKey, now *time.Time) *ProductionStore {
	t.Helper()
	s, e := openProduction(t.TempDir(), guuid.NewString(), pub, "disposable-machine", func() time.Time { return *now })
	if e != nil {
		t.Fatal(e)
	}
	t.Cleanup(func() { s.Close() })
	return s
}
func TestProductionSignedBoundary(t *testing.T) {
	now := time.Now().Truncate(time.Second)
	pub, key, _ := ed25519.GenerateKey(rand.Reader)
	s := newProductionTestStore(t, pub, &now)
	other := newProductionTestStore(t, pub, &now)
	b := productionBody([]*ProductionStore{s, other}, now)
	cases := []struct {
		name   string
		change func(*ProductionBody)
		want   error
	}{
		{"foundation purpose", func(b *ProductionBody) { b.Purpose = "FOUNDATION_ONLY" }, ErrInvalid},
		{"isolated purpose", func(b *ProductionBody) { b.Purpose = "ISOLATED_PROOF" }, ErrInvalid},
		{"candidate purpose", func(b *ProductionBody) { b.Purpose = Purpose }, ErrInvalid},
		{"expired", func(b *ProductionBody) {
			b.IssuedAt -= OfflineSeconds
			b.NotBefore = b.IssuedAt
			b.ExpiresAt -= OfflineSeconds
		}, ErrLifetime},
		{"future", func(b *ProductionBody) { b.IssuedAt++; b.NotBefore++; b.ExpiresAt++ }, ErrLifetime},
		{"unbounded offline", func(b *ProductionBody) { b.ExpiresAt++ }, ErrLifetime},
		{"foreign device", func(b *ProductionBody) {
			b.Members[0].DeviceID = guuid.NewString()
			b.CatalogRaw = []byte{}
			b.Topology = "LOCAL_ONLY"
			b.Members[0].Role = "CLIENT"
		}, ErrScope},
		{"foreign installation", func(b *ProductionBody) {
			b.Members[0].InstallationID = guuid.NewString()
			b.CatalogRaw = []byte{}
			b.Topology = "LOCAL_ONLY"
			b.Members[0].Role = "CLIENT"
		}, ErrScope},
		{"foreign controller", func(b *ProductionBody) {
			c, _ := b.catalog()
			c.Controllers[0].DeviceID = guuid.NewString()
			b.CatalogRaw = printstation.Encode(c)
		}, ErrScope},
		{"two voters", func(b *ProductionBody) { b.Members[1].Role = "VOTER" }, ErrBinding},
		{"automatic RAW failover", func(b *ProductionBody) {
			c, _ := b.catalog()
			c.Printers[0].FailoverMode = printstation.QualifiedFencedFailover
			b.CatalogRaw = printstation.Encode(c)
		}, ErrBinding},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			copy := b
			copy.Members = append([]ProductionMember{}, b.Members...)
			tc.change(&copy)
			if e := s.Apply(signedProduction(t, key, copy)); !errors.Is(e, tc.want) {
				t.Fatalf("got %v want %v", e, tc.want)
			}
		})
	}
	raw := signedProduction(t, key, b)
	if e := s.Apply(raw); e != nil {
		t.Fatal(e)
	}
	if e := s.Apply(raw); e != nil {
		t.Fatal("exact retry", e)
	}
	var tamper SignedGrant
	json.Unmarshal(raw, &tamper)
	tamper.Signature[0] ^= 1
	changed, _ := json.Marshal(tamper)
	if e := s.Apply(changed); !errors.Is(e, ErrSignature) {
		t.Fatal(e)
	}
	wrong, _, _ := ed25519.GenerateKey(rand.Reader)
	if _, e := VerifyProduction(raw, wrong, now); !errors.Is(e, ErrSignature) {
		t.Fatal(e)
	}
	b.Generation++
	b.Revision++
	c, _ := b.catalog()
	c.Revision = b.Revision
	b.CatalogRaw = printstation.Encode(c) // use prior catalog below because revision changed
	var cat printstation.Catalog
	json.Unmarshal(productionBody([]*ProductionStore{s, other}, now).CatalogRaw, &cat)
	cat.VenueID = b.VenueID
	cat.Revision = b.Revision
	b.CatalogRaw = printstation.Encode(cat)
	if e := s.Apply(signedProduction(t, key, b)); e != nil {
		t.Fatal(e)
	}
	if e := s.Apply(raw); !errors.Is(e, ErrStale) {
		t.Fatal("stale", e)
	}
	foreign := b
	foreign.Generation++
	foreign.VenueID = guuid.NewString()
	cat.VenueID = foreign.VenueID
	foreign.CatalogRaw = printstation.Encode(cat)
	if e := s.Apply(signedProduction(t, key, foreign)); !errors.Is(e, ErrScope) {
		t.Fatal("foreign Venue", e)
	}
}
func TestProductionRestartOfflineAndRevocation(t *testing.T) {
	now := time.Now().Truncate(time.Second)
	pub, key, _ := ed25519.GenerateKey(rand.Reader)
	dir := t.TempDir()
	device := guuid.NewString()
	open := func(machine string) (*ProductionStore, error) {
		return openProduction(dir, device, pub, machine, func() time.Time { return now })
	}
	s, e := open("machine-a")
	if e != nil {
		t.Fatal(e)
	}
	original := s.Enrollment()
	b := productionBody([]*ProductionStore{s}, now)
	raw := signedProduction(t, key, b)
	if e = s.Apply(raw); e != nil {
		t.Fatal(e)
	}
	if _, e = open("machine-a"); e == nil {
		t.Fatal("two service owners")
	}
	if e = s.Close(); e != nil {
		t.Fatal(e)
	}
	if _, e = open("machine-b"); !errors.Is(e, ErrScope) {
		t.Fatal("restored foreign machine", e)
	}
	s, e = open("machine-a")
	if e != nil {
		t.Fatal(e)
	}
	if !bytes.Equal(printstation.Encode(original), printstation.Encode(s.Enrollment())) {
		t.Fatal("restart changed identity")
	}
	now = now.Add(6 * 24 * time.Hour)
	if _, e = s.Inventory(); e != nil {
		t.Fatal("offline valid", e)
	}
	s.Close()
	s, e = open("machine-a")
	if e != nil {
		t.Fatal(e)
	}
	now = now.Add(-time.Second)
	if _, e = s.Inventory(); !errors.Is(e, ErrLifetime) {
		t.Fatal("clock rollback", e)
	}
	now = time.Unix(b.ExpiresAt, 0)
	if _, e = s.Inventory(); !errors.Is(e, ErrLifetime) {
		t.Fatal("offline expiry", e)
	}
	// Renew without removing the old high-water mark, then cache a learned revoke.
	b.Generation++
	b.IssuedAt = now.Unix()
	b.NotBefore = b.IssuedAt
	b.ExpiresAt = b.IssuedAt + OfflineSeconds
	b.Members[0].Authorized = false
	if e = s.Apply(signedProduction(t, key, b)); e != nil {
		t.Fatal(e)
	}
	s.Close()
	s, e = open("machine-a")
	if e != nil {
		t.Fatal(e)
	}
	defer s.Close()
	if _, e = s.Inventory(); !errors.Is(e, ErrRevoked) {
		t.Fatal("revoked after restart", e)
	}
	b.Generation++
	b.Members[0].Authorized = true
	if e = s.Apply(signedProduction(t, key, b)); !errors.Is(e, ErrRevoked) {
		t.Fatal("revoked resurrection", e)
	}
	fresh := newProductionTestStore(t, pub, &now)
	if fresh.id == original.InstallationID {
		t.Fatal("fresh installation copied identity")
	}
}
func handshakeProduction(t *testing.T, server, client *ProductionStore, expected string) (AuthenticatedMember, error) {
	t.Helper()
	sc, e := server.TLSConfig(true, "")
	if e != nil {
		return AuthenticatedMember{}, e
	}
	cc, e := client.TLSConfig(false, expected)
	if e != nil {
		return AuthenticatedMember{}, e
	}
	ln, e := tls.Listen("tcp", "127.0.0.1:0", sc)
	if e != nil {
		t.Fatal(e)
	}
	defer ln.Close()
	type result struct {
		peer AuthenticatedMember
		err  error
	}
	done := make(chan result, 1)
	go func() {
		conn, e := ln.Accept()
		if e != nil {
			done <- result{err: e}
			return
		}
		defer conn.Close()
		c := conn.(*tls.Conn)
		c.SetDeadline(time.Now().Add(5 * time.Second))
		if e = c.Handshake(); e != nil {
			done <- result{err: e}
			return
		}
		p, e := server.Authenticate(c.ConnectionState())
		if e == nil {
			_, e = c.Write([]byte{1})
		}
		done <- result{p, e}
	}()
	conn, e := tls.DialWithDialer(&net.Dialer{Timeout: 5 * time.Second}, "tcp", ln.Addr().String(), cc)
	if e == nil {
		defer conn.Close()
		conn.SetDeadline(time.Now().Add(5 * time.Second))
		var b [1]byte
		_, e = conn.Read(b[:])
	}
	r := <-done
	if e != nil {
		return AuthenticatedMember{}, e
	}
	return r.peer, r.err
}
func TestProductionMutualTLSAndRights(t *testing.T) {
	now := time.Now().Truncate(time.Second)
	pub, key, _ := ed25519.GenerateKey(rand.Reader)
	a := newProductionTestStore(t, pub, &now)
	b := newProductionTestStore(t, pub, &now)
	body := productionBody([]*ProductionStore{a, b}, now)
	raw := signedProduction(t, key, body)
	for _, s := range []*ProductionStore{a, b} {
		if e := s.Apply(raw); e != nil {
			t.Fatal(e)
		}
	}
	peer, e := handshakeProduction(t, a, b, a.id)
	if e != nil {
		t.Fatal(e)
	}
	cat, _ := body.catalog()
	if _, e = a.Authorize(peer, cat.Stations[0].ID, ""); e != nil {
		t.Fatal(e)
	}
	if _, e = a.Authorize(peer, cat.Stations[1].ID, ""); e != nil {
		t.Fatal(e)
	}
	reverse, e := handshakeProduction(t, b, a, b.id)
	if e != nil {
		t.Fatal(e)
	}
	if _, e = b.Authorize(reverse, cat.Stations[1].ID, ""); !errors.Is(e, ErrScope) {
		t.Fatal("foreign LOCAL", e)
	}
	if _, e = a.Authorize(peer, "", cat.Controllers[0].ID); !errors.Is(e, ErrScope) {
		t.Fatal("leader/controller confusion", e)
	}
	if _, e = a.Authorize(peer, "", cat.Controllers[1].ID); e != nil {
		t.Fatal(e)
	}
	if _, e = a.Authorize(AuthenticatedMember{}, cat.Stations[0].ID, ""); e == nil {
		t.Fatal("forged member")
	}
	if _, e = handshakeProduction(t, a, b, b.id); e == nil {
		t.Fatal("wrong endpoint peer")
	}
	body.Generation++
	body.Members[1].Authorized = false
	if e = a.Apply(signedProduction(t, key, body)); e != nil {
		t.Fatal(e)
	}
	if _, e = a.Authorize(peer, cat.Stations[0].ID, ""); !errors.Is(e, ErrRevoked) {
		t.Fatal("existing TLS session revocation", e)
	}
	if _, e = handshakeProduction(t, a, b, a.id); e == nil {
		t.Fatal("revoked handshake")
	}
}
func TestProductionCloudPull(t *testing.T) {
	now := time.Now().Truncate(time.Second)
	pub, key, _ := ed25519.GenerateKey(rand.Reader)
	s := newProductionTestStore(t, pub, &now)
	b := productionBody([]*ProductionStore{s}, now)
	raw := signedProduction(t, key, b)
	credential := "vynic-device-v1." + s.device + ".disposable-test-secret"
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/edge/printer-provisioning/enroll" || r.Header.Get("X-POS-Sync-Key") != credential {
			t.Error("wrong pull request")
		}
		w.WriteHeader(201)
		w.Write(raw)
	}))
	defer server.Close()
	if e := s.pull(context.Background(), server.Client(), server.URL, credential); e != nil {
		t.Fatal(e)
	}
	if e := s.Pull(context.Background(), "http://127.0.0.1", credential); !errors.Is(e, ErrScope) {
		t.Fatal("cleartext allowed", e)
	}
	if e := s.pull(context.Background(), server.Client(), server.URL, "vynic-device-v1."+guuid.NewString()+".secret"); !errors.Is(e, ErrScope) {
		t.Fatal(e)
	}
}

// Backend integration invokes these with a disposable exchange directory. Only
// public requests/grants leave the dedicated test identity stores.
type productionExchange struct {
	Issuer  string   `json:"issuer"`
	Devices []string `json:"devices"`
}

func exchangeSetup(t *testing.T) (string, productionExchange, ed25519.PublicKey) {
	t.Helper()
	dir := os.Getenv("VYNIC_POS02A_EXCHANGE")
	if dir == "" {
		t.Skip("real backend exchange not requested")
	}
	raw, e := os.ReadFile(filepath.Join(dir, "setup.json"))
	if e != nil {
		t.Fatal(e)
	}
	var setup productionExchange
	if e = json.Unmarshal(raw, &setup); e != nil {
		t.Fatal(e)
	}
	pub, e := base64.StdEncoding.DecodeString(setup.Issuer)
	if e != nil {
		t.Fatal(e)
	}
	return dir, setup, ed25519.PublicKey(pub)
}
func TestProductionBackendExport(t *testing.T) {
	dir, setup, pub := exchangeSetup(t)
	requests := []EnrollmentRequest{}
	for i, device := range setup.Devices {
		s, e := openProduction(filepath.Join(dir, device), device, pub, "exchange-machine-"+device, time.Now)
		if e != nil {
			t.Fatal(e)
		}
		requests = append(requests, s.Enrollment())
		if i == 0 {
			cross := s.Enrollment()
			cross.Proof = ed25519.Sign(s.key, []byte(EnrollmentDomain+setup.Devices[4]+"\x00"+s.id+"\x00"+SHA256(s.cert)))
			raw, _ := json.Marshal(cross)
			if e := os.WriteFile(filepath.Join(dir, "cross-device.json"), raw, 0600); e != nil {
				t.Fatal(e)
			}
		}
		s.Close()
		_ = i
	}
	raw, _ := json.Marshal(requests)
	if e := os.WriteFile(filepath.Join(dir, "requests.json"), raw, 0600); e != nil {
		t.Fatal(e)
	}
}
func TestProductionBackendVerify(t *testing.T) {
	dir, setup, pub := exchangeSetup(t)
	stores := []*ProductionStore{}
	for _, device := range setup.Devices {
		s, e := openProduction(filepath.Join(dir, device), device, pub, "exchange-machine-"+device, time.Now)
		if e != nil {
			t.Fatal(e)
		}
		stores = append(stores, s)
		t.Cleanup(func() { s.Close() })
	}
	read := func(name string) []byte {
		b, e := os.ReadFile(filepath.Join(dir, name+".json"))
		if e != nil {
			t.Fatal(e)
		}
		return b
	}
	for _, s := range stores[:3] {
		if e := s.Apply(read("configured")); e != nil {
			t.Fatal("backend signed config", e)
		}
	}
	b, e := stores[0].Inventory()
	if e != nil || b.Topology != "THREE_REPLICAS" {
		t.Fatal(e, b.Topology)
	}
	peer, e := handshakeProduction(t, stores[0], stores[1], stores[0].id)
	if e != nil {
		t.Fatal(e)
	}
	c, _ := b.catalog()
	if _, e = stores[0].Authorize(peer, c.Stations[0].ID, ""); e != nil {
		t.Fatal(e)
	}
	if e = stores[0].Apply(read("joined")); e != nil {
		t.Fatal(e)
	}
	joined, e := stores[0].Inventory()
	if e != nil || len(joined.Members) != 4 {
		t.Fatal("join inventory", e)
	}
	if e = stores[3].Apply(read("joined")); e != nil {
		t.Fatal(e)
	}
	// Last identity belongs to another Venue and must not accept this configuration.
	if e = stores[4].Apply(read("joined")); !errors.Is(e, ErrScope) {
		t.Fatal("foreign Device/installation", e)
	}
	if e = stores[0].Apply(read("revoked")); e != nil {
		t.Fatal(e)
	}
	if _, e = stores[0].Authorize(peer, c.Stations[0].ID, ""); !errors.Is(e, ErrRevoked) {
		t.Fatal("revoked member", e)
	}
	if e = stores[0].Apply(read("configured")); !errors.Is(e, ErrStale) {
		t.Fatal("backend stale", e)
	}
	if e = stores[1].Apply(read("revoked")); e != nil {
		t.Fatal(e)
	}
	if _, e = stores[1].Inventory(); !errors.Is(e, ErrRevoked) {
		t.Fatal("revoked self", e)
	}
	t.Log("Real PostgreSQL/HTTP issuer -> Go durable verification -> mutual TLS -> station authority -> learned revocation: PASS")
}

func TestProductionTopologyCounts(t *testing.T) {
	for _, count := range []int{1, 2, 3, 4, 10} {
		t.Run(strconv.Itoa(count), func(t *testing.T) {
			now := time.Now().Truncate(time.Second)
			pub, key, _ := ed25519.GenerateKey(rand.Reader)
			stores := []*ProductionStore{}
			for i := 0; i < count; i++ {
				stores = append(stores, newProductionTestStore(t, pub, &now))
			}
			b := productionBody(stores, now)
			voters := 1
			if count >= 3 {
				b.Topology = "THREE_REPLICAS"
				voters = 3
				for i := 0; i < 3; i++ {
					b.Members[i].Role = "VOTER"
				}
			}
			raw := signedProduction(t, key, b)
			if e := stores[0].Apply(raw); e != nil {
				t.Fatal(e)
			}
			actual, e := stores[0].Inventory()
			if e != nil {
				t.Fatal(e)
			}
			n := 0
			for _, m := range actual.Members {
				if m.Role == "VOTER" {
					n++
				}
			}
			if n != voters {
				t.Fatal(n)
			}
			// New discovery addresses or a role change at the same config revision cannot
			// promote a client. Explicit backend configuration is the only transition.
			changed := b
			changed.Generation++
			changed.Members = append([]ProductionMember{}, b.Members...)
			changed.Members[0].EndpointHint = "127.0.0.1:9999"
			if e = stores[0].Apply(signedProduction(t, key, changed)); !errors.Is(e, ErrStale) {
				t.Fatal("uncontrolled discovery change", e)
			}
		})
	}
}
func TestProductionForeignPeerAndCorruptCache(t *testing.T) {
	now := time.Now().Truncate(time.Second)
	pub, key, _ := ed25519.GenerateKey(rand.Reader)
	a := newProductionTestStore(t, pub, &now)
	foreign := newProductionTestStore(t, pub, &now)
	local := productionBody([]*ProductionStore{a}, now)
	other := productionBody([]*ProductionStore{foreign}, now)
	if e := a.Apply(signedProduction(t, key, local)); e != nil {
		t.Fatal(e)
	}
	if e := foreign.Apply(signedProduction(t, key, other)); e != nil {
		t.Fatal(e)
	}
	if _, e := handshakeProduction(t, a, foreign, a.id); e == nil {
		t.Fatal("arbitrary LAN/foreign Venue peer authenticated")
	}
	if _, e := a.db.Exec("UPDATE authorization SET grant=?", []byte(`{"body":"bad","signature":"bad"}`)); e != nil {
		t.Fatal(e)
	}
	if _, e := a.Inventory(); e == nil {
		t.Fatal("corrupt cache granted rights")
	}
}
func TestProductionDurableCommitFailure(t *testing.T) {
	now := time.Now().Truncate(time.Second)
	pub, key, _ := ed25519.GenerateKey(rand.Reader)
	s := newProductionTestStore(t, pub, &now)
	b := productionBody([]*ProductionStore{s}, now)
	if e := s.Apply(signedProduction(t, key, b)); e != nil {
		t.Fatal(e)
	}
	if _, e := s.db.Exec(`CREATE TRIGGER fail_cache BEFORE UPDATE ON authorization BEGIN SELECT RAISE(ABORT,'test durability failure'); END`); e != nil {
		t.Fatal(e)
	}
	b.Generation++
	if e := s.Apply(signedProduction(t, key, b)); e == nil {
		t.Fatal("failed commit reported accepted")
	}
	if _, e := s.Inventory(); e == nil {
		t.Fatal("time persistence failure granted authority")
	}
	if _, e := s.db.Exec("DROP TRIGGER fail_cache"); e != nil {
		t.Fatal(e)
	}
	current, e := s.Inventory()
	if e != nil || current.Generation != 1 {
		t.Fatal("failed write changed high-water", e)
	}
}

func TestProductionProcessRestart(t *testing.T) {
	if dir := os.Getenv("VYNIC_POS02A_CHILD_DIR"); dir != "" {
		pub, e := base64.StdEncoding.DecodeString(os.Getenv("VYNIC_POS02A_CHILD_ISSUER"))
		if e != nil {
			t.Fatal(e)
		}
		s, e := openProduction(dir, os.Getenv("VYNIC_POS02A_CHILD_DEVICE"), ed25519.PublicKey(pub), "child-test-machine", time.Now)
		if e != nil {
			t.Fatal(e)
		}
		defer s.Close()
		b, e := s.Inventory()
		if e != nil {
			t.Fatal(e)
		}
		if s.id != os.Getenv("VYNIC_POS02A_CHILD_ID") || b.Generation != 2 {
			t.Fatal("process restart lost identity or high-water")
		}
		return
	}
	now := time.Now().Truncate(time.Second)
	pub, key, _ := ed25519.GenerateKey(rand.Reader)
	dir := t.TempDir()
	device := guuid.NewString()
	s, e := openProduction(dir, device, pub, "child-test-machine", time.Now)
	if e != nil {
		t.Fatal(e)
	}
	b := productionBody([]*ProductionStore{s}, now)
	b.Generation = 2
	if e = s.Apply(signedProduction(t, key, b)); e != nil {
		t.Fatal(e)
	}
	id := s.id
	if e = s.Close(); e != nil {
		t.Fatal(e)
	}
	executable, e := os.Executable()
	if e != nil {
		t.Fatal(e)
	}
	for i := 0; i < 2; i++ {
		cmd := exec.Command(executable, "-test.run=^TestProductionProcessRestart$", "-test.v=true")
		cmd.Env = append(os.Environ(), "VYNIC_POS02A_CHILD_DIR="+dir, "VYNIC_POS02A_CHILD_DEVICE="+device, "VYNIC_POS02A_CHILD_ISSUER="+base64.StdEncoding.EncodeToString(pub), "VYNIC_POS02A_CHILD_ID="+id)
		if output, e := cmd.CombinedOutput(); e != nil {
			t.Fatalf("child %d: %v %s", i, e, output)
		}
	}
}
