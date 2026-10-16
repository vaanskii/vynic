package printerprovisioning

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"errors"
	"strings"
	"testing"

	"vynic.local/edge/internal/printqueue"
)

func TestStrictSignedAndBodyJSONRejectsAliasesAndUnknownFields(t *testing.T) {
	cases := []struct {
		name    string
		wrapper bool
		mutate  func([]byte) []byte
	}{
		{"wrapperUnknown", true, func(b []byte) []byte { return append([]byte(`{"issuerPublicKey":"attacker",`), b[1:]...) }},
		{"wrapperCase", true, func(b []byte) []byte { return bytes.Replace(b, []byte(`"body"`), []byte(`"Body"`), 1) }},
		{"wrapperDuplicate", true, func(b []byte) []byte { return append([]byte(`{"signature":"AA==",`), b[1:]...) }},
		{"wrapperNull", true, func(b []byte) []byte { return []byte(`{"body":null,"signature":"AA=="}`) }},
		{"wrapperInvalidBase64", true, func(b []byte) []byte { return []byte(`{"body":"!","signature":"!"}`) }},
		{"wrapperTrailing", true, func(b []byte) []byte { return append(b, []byte(` {}`)...) }},
		{"bodyUnknown", false, func(b []byte) []byte { return append([]byte(`{"physicalAllowed":true,`), b[1:]...) }},
		{"bodyCase", false, func(b []byte) []byte { return bytes.Replace(b, []byte(`"grantId"`), []byte(`"GrantId"`), 1) }},
		{"bodyDuplicate", false, func(b []byte) []byte { return append([]byte(`{"version":1,`), b[1:]...) }},
		{"nestedCase", false, func(b []byte) []byte { return bytes.Replace(b, []byte(`"clientId"`), []byte(`"ClientId"`), 1) }},
		{"nestedEscapedDuplicate", false, func(b []byte) []byte {
			return bytes.Replace(b, []byte(`"authorization":{`), []byte(`"authorization":{"\u0063lientId":"duplicate",`), 1)
		}},
		{"nestedUnknown", false, func(b []byte) []byte {
			return bytes.Replace(b, []byte(`"authorization":{`), []byte(`"authorization":{"active":true,`), 1)
		}},
		{"bodyTrailing", false, func(b []byte) []byte { return append(b, []byte(` {}`)...) }},
		{"bodyInvalidUTF8", false, func(b []byte) []byte { return bytes.Replace(b, []byte(Purpose), []byte{0xff}, 1) }},
		{"bodyVersion", false, func(b []byte) []byte { return bytes.Replace(b, []byte(`"version":1`), []byte(`"version":2`), 1) }},
		{"fractionGeneration", false, func(b []byte) []byte {
			return bytes.Replace(b, []byte(`"generation":17`), []byte(`"generation":17.0`), 1)
		}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			f := fresh(t, "tcp", Local)
			raw := f.grant
			if tc.wrapper {
				raw = tc.mutate(bytes.Clone(raw))
			} else {
				body := tc.mutate(encode(t, f.body))
				raw = f.signRaw(t, body)
				f.state.CurrentGrantBodySHA256 = SHA256(body)
			}
			if _, e := ValidateCandidate(raw, f.state, f.peer, f.jobRaw); !errors.Is(e, ErrInvalid) {
				t.Fatal(e)
			}
		})
	}
	for _, tc := range []struct {
		name  string
		grant []byte
	}{
		{"oversizedGrant", bytes.Repeat([]byte(" "), MaxGrantBytes+1)},
		{"oversizedBody", []byte(`{"body":"` + base64.StdEncoding.EncodeToString(bytes.Repeat([]byte(" "), MaxBodyBytes+1)) + `","signature":"` + base64.StdEncoding.EncodeToString(make([]byte, 64)) + `"}`)},
	} {
		t.Run(tc.name, func(t *testing.T) {
			f := fresh(t, "tcp", Local)
			if _, e := ValidateCandidate(tc.grant, f.state, f.peer, f.jobRaw); !errors.Is(e, ErrInvalid) {
				t.Fatal(e)
			}
		})
	}
}

func TestCompleteFrozenIdentityAndRouteCannotRetarget(t *testing.T) {
	mutations := []struct {
		name   string
		mutate func(*printqueue.FrozenJob)
		want   error
	}{
		{"venue", func(j *printqueue.FrozenJob) { j.VenueID = uuid(11) }, ErrScope},
		{"device", func(j *printqueue.FrozenJob) { j.DeviceID = uuid(11) }, ErrScope},
		{"installation", func(j *printqueue.FrozenJob) { j.InstallationID = uuid(11) }, ErrScope},
		{"host", func(j *printqueue.FrozenJob) { j.Destination.WorkerHostID = uuid(11) }, ErrScope},
		{"epoch", func(j *printqueue.FrozenJob) { j.AuthorityEpoch++ }, ErrScope},
		{"terminal", func(j *printqueue.FrozenJob) { j.TerminalID = uuid(11) }, ErrScope},
		{"origin", func(j *printqueue.FrozenJob) { j.OriginInstallationID = uuid(11) }, ErrScope},
		{"physical", func(j *printqueue.FrozenJob) {
			j.PhysicalPrinterID = uuid(11)
			j.Destination.PhysicalPrinterID = j.PhysicalPrinterID
		}, ErrBinding},
		{"alias", func(j *printqueue.FrozenJob) { j.AliasID = uuid(11) }, ErrBinding},
		{"routeRevision", func(j *printqueue.FrozenJob) { j.RouteRevision++ }, ErrBinding},
		{"configRevision", func(j *printqueue.FrozenJob) { j.ConfigRevision++ }, ErrBinding},
		{"bindingRevision", func(j *printqueue.FrozenJob) { j.BindingRevision++ }, ErrBinding},
		{"registryRevision", func(j *printqueue.FrozenJob) { j.RegistryRevision++ }, ErrBinding},
		{"IP", func(j *printqueue.FrozenJob) { j.Destination.Host = "192.168.10.21" }, ErrBinding},
		{"IPAlias", func(j *printqueue.FrozenJob) { j.Destination.Host = "::ffff:192.168.10.20" }, ErrBinding},
		{"port", func(j *printqueue.FrozenJob) { j.Destination.Port++ }, ErrBinding},
		{"profileDimension", func(j *printqueue.FrozenJob) {
			j.CapabilityProfile = bytes.Replace(j.CapabilityProfile, []byte(`"rasterWidthDots":576`), []byte(`"rasterWidthDots":512`), 1)
		}, ErrBinding},
		{"profileUnknownLanguage", func(j *printqueue.FrozenJob) {
			j.CapabilityProfile = bytes.Replace(j.CapabilityProfile, []byte(`"escposRaster"`), []byte(`"windowsDriverRendered"`), 1)
		}, ErrInvalid},
		{"profileReorder", func(j *printqueue.FrozenJob) {
			j.CapabilityProfile = bytes.Replace(j.CapabilityProfile, []byte(`"protocol":1,"paperWidthMm":80`), []byte(`"paperWidthMm":80,"protocol":1`), 1)
		}, ErrBinding},
		{"changedPrimaryWithoutHash", func(j *printqueue.FrozenJob) { j.PrimaryBytes[0] ^= 1 }, ErrInvalid},
	}
	for _, tc := range mutations {
		t.Run(tc.name, func(t *testing.T) {
			f := fresh(t, "tcp", Local)
			tc.mutate(&f.job)
			if _, e := ValidateCandidate(f.grant, f.state, f.peer, encode(t, f.job)); !errors.Is(e, tc.want) {
				t.Fatalf("wanted %v; got %v", tc.want, e)
			}
		})
	}
	for _, field := range []string{"queue", "driver", "port"} {
		t.Run("windows/"+field, func(t *testing.T) {
			f := fresh(t, "windowsSpooler", Local)
			switch field {
			case "queue":
				f.job.Destination.QueueName = strings.ToLower(f.job.Destination.QueueName)
			case "driver":
				f.job.Destination.ExpectedDriverName += " changed"
			case "port":
				f.job.Destination.ExpectedPortName += " changed"
			}
			if _, e := ValidateCandidate(f.grant, f.state, f.peer, encode(t, f.job)); !errors.Is(e, ErrBinding) {
				t.Fatal(e)
			}
		})
	}
}

func TestSignedConfigurationBytesAndHashesAreExact(t *testing.T) {
	for _, tc := range []struct {
		name   string
		mutate func([]byte) []byte
	}{
		{"reorderedConfiguration", func(b []byte) []byte {
			return bytes.Replace(b, []byte(`"version":1,"physicalPrinterId"`), []byte(`"physicalPrinterId"`), 1)
		}},
		{"routeUnknown", func(b []byte) []byte { return append([]byte(`{"autoDetect":true,`), b[1:]...) }},
		{"routeCase", func(b []byte) []byte { return bytes.Replace(b, []byte(`"aliasId"`), []byte(`"AliasId"`), 1) }},
		{"destinationCase", func(b []byte) []byte { return bytes.Replace(b, []byte(`"port"`), []byte(`"Port"`), 1) }},
		{"destinationDuplicate", func(b []byte) []byte {
			return bytes.Replace(b, []byte(`"destination":{`), []byte(`"destination":{"host":"duplicate",`), 1)
		}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			f := fresh(t, "tcp", Local)
			changed := tc.mutate(bytes.Clone(f.body.RouteRaw))
			if tc.name == "reorderedConfiguration" {
				changed = append(changed[:len(changed)-1], []byte(`,"version":1}`)...)
			}
			f.body.RouteRaw = changed
			f.body.RouteSHA256 = SHA256(changed)
			f.resign(t)
			if _, e := ValidateCandidate(f.grant, f.state, f.peer, f.jobRaw); !errors.Is(e, ErrBinding) {
				t.Fatal(e)
			}
			f.state.RouteRaw = bytes.Clone(changed)
			if tc.name != "reorderedConfiguration" {
				if _, e := ValidateCandidate(f.grant, f.state, f.peer, f.jobRaw); !errors.Is(e, ErrState) {
					t.Fatal("malformed trusted config was accepted", e)
				}
			}
		})
	}
	f := fresh(t, "tcp", Local)
	f.body.RouteSHA256 = strings.Repeat("a", 64)
	f.resign(t)
	if _, e := ValidateCandidate(f.grant, f.state, f.peer, f.jobRaw); !errors.Is(e, ErrInvalid) {
		t.Fatal(e)
	}
	f = fresh(t, "tcp", Local)
	var route Route
	if e := json.Unmarshal(f.state.RouteRaw, &route); e != nil {
		t.Fatal(e)
	}
	route.CapabilityProfileSHA256 = strings.Repeat("a", 64)
	f.state.RouteRaw = encode(t, route)
	if _, e := ValidateCandidate(f.grant, f.state, f.peer, f.jobRaw); !errors.Is(e, ErrState) {
		t.Fatal(e)
	}
}

func TestStrictJobKeysAndZeroValueCannotProduceAJob(t *testing.T) {
	f := fresh(t, "tcp", Local)
	for _, raw := range [][]byte{bytes.Replace(f.jobRaw, []byte(`"jobId"`), []byte(`"JobId"`), 1), append([]byte(`{"version":1,`), f.jobRaw[1:]...), append([]byte(`{"physical":true,`), f.jobRaw[1:]...)} {
		if _, e := ValidateCandidate(f.grant, f.state, f.peer, raw); !errors.Is(e, ErrInvalid) {
			t.Fatal(e)
		}
	}
	var zero ValidatedJob
	if _, e := zero.FrozenJob(); e == nil || zero.AdmissionBlockedReason() != AdmissionHold {
		t.Fatal("zero artifact could authorize a job")
	}
}
