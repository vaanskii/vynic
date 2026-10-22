package printcluster

import (
	"bytes"
	"encoding/json"
	"fmt"
	"reflect"
	"sort"
	"strconv"
	"strings"
	"time"

	"vynic.local/edge/internal/printstation"
)

type rowKey struct{ Kind, Key string }
type durableRow struct {
	Value   any
	Payload []byte
}
type blobRef struct {
	Digest string `json:"digest"`
	Length int    `json:"length"`
}
type legacyJobRow struct {
	Record  storedJob `json:"record"`
	Payload blobRef   `json:"payload"`
}
type stationJobRow struct {
	Job     printstation.Job `json:"job"`
	Payload blobRef          `json:"payload"`
}
type storageHeader struct {
	Version int         `json:"storageVersion"`
	State   *projection `json:"state"`
	Rows    int         `json:"rows"`
	Digest  string      `json:"rowsDigest"`
}

// normalized decomposes state into independently durable records. No payload is
// encoded into a row: its address and length are stored beside immutable metadata.
func normalized(s *projection) (*projection, map[rowKey]durableRow) {
	rows := map[rowKey]durableRow{}
	put := func(kind, key string, value any) { rows[rowKey{kind, key}] = durableRow{Value: value} }
	putBlob := func(kind, key string, value any, payload []byte) {
		rows[rowKey{kind, key}] = durableRow{value, payload}
	}
	h := *s
	h.Members = nil
	h.Configs = nil
	h.CurrentConfigs = nil
	h.Requests = nil
	h.Stages = nil
	h.Jobs = nil
	h.Effects = nil
	h.NextSequence = nil
	h.Attempts = nil
	h.Audit = nil
	for k, v := range s.Members {
		put("member", k, v)
	}
	for k, v := range s.Configs {
		putBlob("config", k, blobRef{k, len(v)}, v)
	}
	for k, v := range s.CurrentConfigs {
		put("current_config", k, v)
	}
	for k, v := range s.Requests {
		put("receipt", k, v)
	}
	for k, v := range s.Stages {
		put("stage", k, true)
		for i, b := range v.Chunks {
			putBlob("chunk", fmt.Sprintf("%s/%d", k, i), blobRef{s.Requests[k].ChunkHashes[i], len(b)}, b)
		}
	}
	for k, v := range s.Jobs {
		r := *v
		r.Raw = nil
		putBlob("legacy_job", k, legacyJobRow{r, blobRef{v.Receipt.InputSHA256, len(v.Raw)}}, v.Raw)
	}
	for k, v := range s.Effects {
		put("effect", k, v)
	}
	for k, v := range s.NextSequence {
		put("sequence", k, v)
	}
	for k, v := range s.Attempts {
		put("assignment", k, v)
	}
	for i, v := range s.Audit {
		put("audit", strconv.Itoa(i), v)
	}
	if s.Stations != nil {
		x := *s.Stations
		x.Catalogs = nil
		x.Jobs = nil
		x.Sequences = nil
		x.RouteStates = nil
		h.Stations = &x
		for k, v := range s.Stations.Catalogs {
			put("station_catalog", k, v)
		}
		for k, v := range s.Stations.Sequences {
			put("station_sequence", k, v)
		}
		for k, v := range s.Stations.RouteStates {
			put("route_state", k, v)
		}
		for k, v := range s.Stations.Jobs {
			j := v.Job
			j.Payload = nil
			putBlob("station_job", k, stationJobRow{j, blobRef{v.Job.PayloadDigest, len(v.Job.Payload)}}, v.Job.Payload)
			r := *v
			r.Job = printstation.Job{}
			r.Attempts = nil
			r.Resolution = nil
			put("station_result", k, r)
			for i, a := range v.Attempts {
				put("station_attempt", fmt.Sprintf("%s/%d", k, i), a)
			}
			if v.Resolution != nil {
				put("station_resolution", k, v.Resolution)
			}
		}
	}
	return &h, rows
}
func rowRoot(hashes map[rowKey]string) string {
	keys := make([]rowKey, 0, len(hashes))
	for k := range hashes {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(i, j int) bool {
		if keys[i].Kind != keys[j].Kind {
			return keys[i].Kind < keys[j].Kind
		}
		return keys[i].Key < keys[j].Key
	})
	var b strings.Builder
	for _, k := range keys {
		fmt.Fprintf(&b, "%s\x00%s\x00%s\n", k.Kind, k.Key, hashes[k])
	}
	return sha([]byte(b.String()))
}

// writeNormalized changes only affected rows and blobs in the same FULL/WAL
// transaction as applied_index. A failed commit cannot expose an accepted receipt.
func (f *durableFSM) writeNormalized(s *projection) ([]byte, error) {
	header, rows := normalized(s)
	hashes := make(map[rowKey]string, len(rows))
	// Conservative portable snapshot budget: normalized metadata plus base64
	// payload length per live reference. No full-state serialization is needed.
	sizes := make(map[rowKey]int, len(rows))
	budget := 4096 + len(printstation.Encode(header))
	blobs := map[string]int{}
	for _, r := range rows {
		if len(r.Payload) == 0 {
			continue
		}
		digest := rowBlobDigest(r)
		if !hash(digest) {
			return nil, ErrStorage
		}
		if n, ok := blobs[digest]; ok {
			if n != len(r.Payload) {
				return nil, ErrStorage
			}
			continue
		}
		blobs[digest] = len(r.Payload)
		budget += ((len(r.Payload)+2)/3)*4 + 80
		if budget > MaxStateBytes {
			return nil, ErrCapacity
		}
	}
	persistStart := time.Now()
	payloadTouched := false
	tx, e := f.db.Begin()
	if e != nil {
		return nil, e
	}
	defer tx.Rollback()
	for k := range f.rows {
		if _, ok := rows[k]; !ok {
			if _, e = tx.Exec("DELETE FROM printcluster_rows WHERE kind=? AND key=?", k.Kind, k.Key); e != nil {
				return nil, e
			}
		}
	}
	for k, r := range rows {
		if old, ok := f.rows[k]; ok && reflect.DeepEqual(old.Value, r.Value) {
			hashes[k] = f.rowHashes[k]
			sizes[k] = f.rowSizes[k]
			budget += sizes[k]
			if budget > MaxStateBytes {
				return nil, ErrCapacity
			}
			continue
		}
		raw, e := json.Marshal(r.Value)
		if e != nil {
			return nil, e
		}
		hashes[k] = sha(raw)
		sizes[k] = len(raw) + 128
		budget += sizes[k]
		if budget > MaxStateBytes {
			return nil, ErrCapacity
		}
		if _, e = tx.Exec(`INSERT INTO printcluster_rows(kind,key,value,sha256) VALUES(?,?,?,?) ON CONFLICT(kind,key) DO UPDATE SET value=excluded.value,sha256=excluded.sha256`, k.Kind, k.Key, raw, hashes[k]); e != nil {
			return nil, e
		}
		if len(r.Payload) > 0 {
			payloadTouched = true
			digest := sha(r.Payload)
			// Existing content is compared, not silently replaced, even when its key is
			// correct. This detects corruption and also refuses a hash collision.
			if _, e = tx.Exec("INSERT INTO printcluster_payloads(digest,length,bytes) VALUES(?,?,?) ON CONFLICT(digest) DO NOTHING", digest, len(r.Payload), r.Payload); e != nil {
				return nil, e
			}
			var matches bool
			if e = tx.QueryRow("SELECT length=? AND bytes=? FROM printcluster_payloads WHERE digest=?", len(r.Payload), r.Payload, digest).Scan(&matches); e != nil || !matches {
				return nil, ErrStorage
			}

			if _, e = tx.Exec(`INSERT INTO printcluster_payload_refs(kind,key,digest) VALUES(?,?,?) ON CONFLICT(kind,key) DO UPDATE SET digest=excluded.digest`, k.Kind, k.Key, digest); e != nil {
				return nil, e
			}
		}
	}
	// Removed staging chunks are no longer live. Referenced job/history payloads
	// remain protected by foreign keys. Raft retains committed chunk commands until
	// its separately bounded snapshot compaction; this is projection garbage only.
	if _, e = tx.Exec("DELETE FROM printcluster_payloads WHERE NOT EXISTS (SELECT 1 FROM printcluster_payload_refs r WHERE r.digest=printcluster_payloads.digest)"); e != nil {
		return nil, e
	}
	raw, e := json.Marshal(storageHeader{2, header, len(rows), rowRoot(hashes)})
	if e != nil {
		return nil, e
	}
	if _, e = tx.Exec(`INSERT INTO printcluster_projection(id,schema_version,cluster_id,pin_sha256,applied_index,state_json) VALUES(1,2,?,?,?,?) ON CONFLICT(id) DO UPDATE SET applied_index=excluded.applied_index,state_json=excluded.state_json`, s.Pin.ClusterID, pinDigest(s.Pin), s.AppliedIndex, raw); e != nil {
		return nil, e
	}
	if f.afterWrite != nil {
		if e = f.afterWrite(); e != nil {
			return nil, e
		}
	}
	if e = tx.Commit(); e != nil {
		return nil, e
	}
	if payloadTouched {
		f.payloadPersistTime += time.Since(persistStart)
		f.payloadPersistCount++
	}
	f.rows = rows
	f.rowHashes = hashes
	f.rowSizes = sizes
	return raw, nil
}

func (f *durableFSM) loadNormalized(raw []byte, pin ClusterConfig, index uint64) error {
	var h storageHeader
	if strict(raw, MaxStateBytes, &h) != nil || h.Version != 2 || h.State == nil || h.State.AppliedIndex != index || pinDigest(h.State.Pin) != pinDigest(pin) {
		return ErrStorage
	}
	s := h.State
	s.Members = map[string]membershipRecord{}
	s.Configs = map[string][]byte{}
	s.CurrentConfigs = map[string]string{}
	s.Requests = map[string]*requestRecord{}
	s.Stages = map[string]*stagedJob{}
	s.Jobs = map[string]*storedJob{}
	s.Effects = map[string]string{}
	s.NextSequence = map[string]uint64{}
	s.Attempts = map[string]Assignment{}
	s.Audit = []auditRecord{}
	if s.Stations != nil {
		x := s.Stations
		x.Catalogs = map[string]printstation.Catalog{}
		x.Jobs = map[string]*printstation.Record{}
		x.Sequences = map[string]uint64{}
		x.RouteStates = map[string]printstation.RouteState{}
	}
	blobs := map[string][]byte{}
	rs, e := f.db.Query("SELECT digest,length,bytes FROM printcluster_payloads")
	if e != nil {
		return e
	}
	total := 0
	for rs.Next() {
		var key string
		var n int
		var b []byte
		if e = rs.Scan(&key, &n, &b); e != nil {
			rs.Close()
			return e
		}
		total += len(b)
		if total > MaxStateBytes || n != len(b) || sha(b) != key {
			rs.Close()
			return ErrStorage
		}
		blobs[key] = b
	}
	e = rs.Err()
	rs.Close()
	if e != nil {
		return e
	}
	getBlob := func(r blobRef) ([]byte, error) {
		b, ok := blobs[r.Digest]
		if !ok || len(b) != r.Length {
			return nil, ErrStorage
		}
		return b, nil
	}
	rs, e = f.db.Query("SELECT kind,key,value,sha256 FROM printcluster_rows ORDER BY kind,key")
	if e != nil {
		return e
	}
	defer rs.Close()
	hashes := map[rowKey]string{}
	// Results/attempts can precede the immutable job lexically; merge explicitly.
	stationRow := func(k string) *printstation.Record {
		r := s.Stations.Jobs[k]
		if r == nil {
			r = &printstation.Record{Attempts: []printstation.Attempt{}}
			s.Stations.Jobs[k] = r
		}
		return r
	}
	for rs.Next() {
		var k rowKey
		var b []byte
		var digest string
		if e = rs.Scan(&k.Kind, &k.Key, &b, &digest); e != nil {
			return e
		}
		total += len(b)
		if total > MaxStateBytes || sha(b) != digest {
			return ErrStorage
		}
		hashes[k] = digest
		decode := func(v any) error { return strict(b, MaxEnvelopeBytes, v) }
		if strings.HasPrefix(k.Kind, "station_") || k.Kind == "route_state" {
			if s.Stations == nil {
				return ErrStorage
			}
		}
		switch k.Kind {
		case "member":
			var v membershipRecord
			e = decode(&v)
			s.Members[k.Key] = v
		case "config":
			var v blobRef
			e = decode(&v)
			if e == nil {
				s.Configs[k.Key], e = getBlob(v)
			}
		case "current_config":
			var v string
			e = decode(&v)
			s.CurrentConfigs[k.Key] = v
		case "receipt":
			var v requestRecord
			e = decode(&v)
			s.Requests[k.Key] = &v
		case "stage":
			if string(b) != "true" {
				return ErrStorage
			}
			if s.Stages[k.Key] == nil {
				s.Stages[k.Key] = &stagedJob{Chunks: map[int][]byte{}}
			}
		case "chunk":
			id, n, err := splitRow(k.Key)
			if err != nil {
				return err
			}
			if s.Stages[id] == nil {
				s.Stages[id] = &stagedJob{Chunks: map[int][]byte{}}
			}
			var v blobRef
			e = decode(&v)
			if e == nil {
				s.Stages[id].Chunks[n], e = getBlob(v)
			}
		case "legacy_job":
			var v legacyJobRow
			e = decode(&v)
			if e == nil {
				v.Record.Raw, e = getBlob(v.Payload)
			}
			s.Jobs[k.Key] = &v.Record
		case "effect":
			var v string
			e = decode(&v)
			s.Effects[k.Key] = v
		case "sequence":
			var v uint64
			e = decode(&v)
			s.NextSequence[k.Key] = v
		case "assignment":
			var v Assignment
			e = decode(&v)
			s.Attempts[k.Key] = v
		case "audit":
			n, err := strconv.Atoi(k.Key)
			if err != nil || n < 0 || n >= 2048 {
				return ErrStorage
			}
			for len(s.Audit) <= n {
				s.Audit = append(s.Audit, auditRecord{})
			}
			e = decode(&s.Audit[n])
		case "station_catalog":
			var v printstation.Catalog
			e = decode(&v)
			s.Stations.Catalogs[k.Key] = v
		case "station_sequence":
			var v uint64
			e = decode(&v)
			s.Stations.Sequences[k.Key] = v
		case "route_state":
			var v printstation.RouteState
			e = decode(&v)
			s.Stations.RouteStates[k.Key] = v
		case "station_job":
			var v stationJobRow
			e = decode(&v)
			if e == nil {
				v.Job.Payload, e = getBlob(v.Payload)
			}
			stationRow(k.Key).Job = v.Job
		case "station_result":
			var v printstation.Record
			e = decode(&v)
			old := stationRow(k.Key)
			v.Job = old.Job
			v.Attempts = old.Attempts
			v.Resolution = old.Resolution
			s.Stations.Jobs[k.Key] = &v
		case "station_attempt":
			id, n, err := splitRow(k.Key)
			if err != nil || n >= 8 {
				return ErrStorage
			}
			r := stationRow(id)
			for len(r.Attempts) <= n {
				r.Attempts = append(r.Attempts, printstation.Attempt{})
			}
			e = decode(&r.Attempts[n])
		case "station_resolution":
			var v printstation.Reprint
			e = decode(&v)
			stationRow(k.Key).Resolution = &v
		default:
			return ErrStorage
		}
		if e != nil {
			return fmt.Errorf("decode normalized row %s/%s: %w", k.Kind, k.Key, e)
		}
	}
	if e = rs.Err(); e != nil {
		return e
	}
	if len(hashes) != h.Rows || rowRoot(hashes) != h.Digest || validateProjection(s, pin) != nil {
		return ErrStorage
	}
	_, rows := normalized(s)
	if len(rows) != len(hashes) {
		return ErrStorage
	}
	// Require canonical rows and their payload-reference identities, not merely a
	// semantically valid reconstruction that could hide extra/missing fields.
	for k, r := range rows {
		b, e := json.Marshal(r.Value)
		if e != nil || sha(b) != hashes[k] {
			return ErrStorage
		}
	}
	rs.Close()
	var refs int
	if e = f.db.QueryRow("SELECT count(*) FROM printcluster_payload_refs").Scan(&refs); e != nil {
		return e
	}
	wanted := 0
	for k, r := range rows {
		if len(r.Payload) == 0 {
			continue
		}
		wanted++
		var digest string
		if e = f.db.QueryRow("SELECT digest FROM printcluster_payload_refs WHERE kind=? AND key=?", k.Kind, k.Key).Scan(&digest); e != nil || digest != sha(r.Payload) {
			return ErrStorage
		}
	}
	if refs != wanted {
		return ErrStorage
	}
	f.state = s
	f.rows = rows
	f.rowHashes = hashes
	f.rowSizes = make(map[rowKey]int, len(rows))
	for k, r := range rows {
		b, _ := json.Marshal(r.Value)
		f.rowSizes[k] = len(b) + 128
	}
	f.encoded = bytes.Clone(raw)
	return nil
}
func splitRow(key string) (string, int, error) {
	p := strings.Split(key, "/")
	if len(p) != 2 || !uuid(p[0]) {
		return "", 0, ErrStorage
	}
	n, e := strconv.Atoi(p[1])
	if e != nil || n < 0 || strconv.Itoa(n) != p[1] {
		return "", 0, ErrStorage
	}
	return p[0], n, nil
}

func rowBlobDigest(r durableRow) string {
	switch v := r.Value.(type) {
	case blobRef:
		return v.Digest
	case legacyJobRow:
		return v.Payload.Digest
	case stationJobRow:
		return v.Payload.Digest
	default:
		return ""
	}
}
