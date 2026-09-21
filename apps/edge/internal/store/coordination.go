package store

import (
	"bytes"
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"
	"google.golang.org/protobuf/proto"
	pb "vynic.local/contracts/go/vynic/edge/v1"
)

var ErrEpoch = errors.New("stale shadow authority epoch")
var ErrIntent = errors.New("invalid Order/Table intent")
var ErrRequestReuse = errors.New("request ID reused with different intent or terminal")
var ErrProjectionLimit = errors.New("shadow projection limit reached")

func canonicalUUID(s string) bool {
	id, e := uuid.Parse(s)
	return e == nil && id != uuid.Nil && id.String() == s
}
func entityKey(e *pb.ProjectionEntity) string { return fmt.Sprintf("%d/%s", e.Kind, e.Id) }

// Transport/schema validation only. Pricing, permissions and restaurant rules
// remain Flutter-owned. SHADOW data cannot authorize restaurant operations.
func validateIntent(r *pb.CommitIntent) error {
	if r == nil || r.Auth == nil || !canonicalUUID(r.Auth.TerminalId) || !canonicalUUID(r.RequestId) || len(r.Changes) == 0 || len(r.Changes) > 100 || r.AuthorityEpoch > math.MaxInt64 {
		return ErrIntent
	}
	seen := map[string]bool{}
	for _, c := range r.Changes {
		if c == nil || c.Entity == nil || c.ExpectedRevision >= math.MaxInt64 {
			return ErrIntent
		}
		e := c.Entity
		if e.Revision != 0 || len(e.Id) == 0 || len(e.Id) > 160 || len(e.Document) > 8192 || !utf8.Valid(e.Document) || (e.Kind != pb.ProjectionEntity_ORDER && e.Kind != pb.ProjectionEntity_TABLE) || seen[entityKey(e)] {
			return ErrIntent
		}
		seen[entityKey(e)] = true
		if !canonicalUUID(e.Id) {
			return ErrIntent
		}
		if e.Tombstone {
			if len(e.Document) != 0 {
				return ErrIntent
			}
			continue
		}
		var d map[string]json.RawMessage
		if json.Unmarshal(e.Document, &d) != nil || d == nil {
			return ErrIntent
		}
		if e.Kind == pb.ProjectionEntity_ORDER {
			var shape struct {
				Floor     *string  `json:"floor"`
				CreatedAt *string  `json:"createdAt"`
				CreatedBy *string  `json:"createdBy"`
				OrderID   *int64   `json:"orderId"`
				Total     *float64 `json:"totalAmount"`
				Fee       *bool    `json:"includeServiceFee"`
				Items     []struct {
					Key       *string  `json:"itemKey"`
					Name      *string  `json:"itemName"`
					Price     *float64 `json:"unitPrice"`
					Quantity  *int64   `json:"quantity"`
					Total     *float64 `json:"total"`
					Comment   *string  `json:"comment"`
					MenuID    *string  `json:"menuItemId"`
					VariantID *string  `json:"variantId"`
				} `json:"items"`
			}
			if json.Unmarshal(e.Document, &shape) != nil || shape.Floor == nil || shape.CreatedAt == nil || shape.CreatedBy == nil || shape.OrderID == nil || shape.Total == nil || shape.Fee == nil || shape.Items == nil {
				return ErrIntent
			}
			if _, err := time.Parse(time.RFC3339Nano, *shape.CreatedAt); err != nil {
				if _, err = time.Parse("2006-01-02T15:04:05.999999999", *shape.CreatedAt); err != nil {
					return ErrIntent
				}
			}
			for _, line := range shape.Items {
				if line.Key == nil || line.Name == nil || line.Price == nil || line.Quantity == nil || line.Total == nil {
					return ErrIntent
				}
			}
			var id, status string
			if json.Unmarshal(d["orderUuid"], &id) != nil || id != e.Id || json.Unmarshal(d["status"], &status) != nil || (status != "pending" && status != "confirmed") {
				return ErrIntent
			}
			var lines []struct {
				LineUUID string `json:"lineUuid"`
			}
			if json.Unmarshal(d["items"], &lines) != nil {
				return ErrIntent
			}
			var lineDocuments []map[string]json.RawMessage
			if json.Unmarshal(d["items"], &lineDocuments) != nil {
				return ErrIntent
			}
			for _, line := range lineDocuments {
				for key := range line {
					switch key {
					case "lineUuid", "itemKey", "itemName", "unitPrice", "quantity", "total", "comment", "menuItemId", "variantId":
					default:
						return ErrIntent
					}
				}
			}
			ids := map[string]bool{}
			for _, line := range lines {
				if !canonicalUUID(line.LineUUID) || ids[line.LineUUID] {
					return ErrIntent
				}
				ids[line.LineUUID] = true
			}
			// Phase 2A snapshots carry ordinary open Orders only. Money/closure fields
			// are not admitted to this projection's schema at all.
			allowed := map[string]bool{"orderUuid": true, "orderId": true, "floor": true, "tableIds": true, "items": true, "status": true, "totalAmount": true, "includeServiceFee": true, "createdAt": true, "createdBy": true}
			for key := range d {
				if !allowed[key] {
					return ErrIntent
				}
			}
		} else {
			if _, ok := d["activeOrderUuid"]; !ok {
				return ErrIntent
			}
			var shape struct {
				Floor  *string `json:"floor"`
				Number *string `json:"tableNumber"`
				Active *string `json:"activeOrderUuid"`
			}
			if json.Unmarshal(e.Document, &shape) != nil || shape.Floor == nil || shape.Number == nil || *shape.Floor == "" || *shape.Number == "" {
				return ErrIntent
			}
			if shape.Active != nil && !canonicalUUID(*shape.Active) {
				return ErrIntent
			}
			var id string
			if json.Unmarshal(d["tableId"], &id) != nil || id != e.Id {
				return ErrIntent
			}
			for key := range d {
				if key != "tableId" && key != "activeOrderUuid" && key != "floor" && key != "tableNumber" {
					return ErrIntent
				}
			}
		}
	}
	return nil
}

func state(tx *sql.Tx) (epoch, sequence uint64, err error) {
	err = tx.QueryRow("SELECT authority_epoch,sequence FROM coordination WHERE singleton=1").Scan(&epoch, &sequence)
	return
}
func readEntity(tx *sql.Tx, kind pb.ProjectionEntity_Kind, id string) (*pb.ProjectionEntity, error) {
	e := &pb.ProjectionEntity{Kind: kind, Id: id}
	err := tx.QueryRow("SELECT revision,tombstone,document FROM projection WHERE kind=? AND id=?", kind, id).Scan(&e.Revision, &e.Tombstone, &e.Document)
	if errors.Is(err, sql.ErrNoRows) {
		return e, nil
	}
	return e, err
}
func projection(tx *sql.Tx) ([]*pb.ProjectionEntity, error) {
	rows, err := tx.Query("SELECT kind,id,revision,tombstone,document FROM projection ORDER BY kind,id")
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var result []*pb.ProjectionEntity
	for rows.Next() {
		e := &pb.ProjectionEntity{}
		if err = rows.Scan(&e.Kind, &e.Id, &e.Revision, &e.Tombstone, &e.Document); err != nil {
			return nil, err
		}
		result = append(result, e)
	}
	return result, rows.Err()
}

// Referential consistency is transport-level: a change set cannot occupy a
// table without its Order, or remove an Order while leaving a dangling table.
func validateLinks(entities []*pb.ProjectionEntity) error {
	orders := map[string][]string{}
	tables := map[string]string{}
	lineOwners := map[string]string{}
	for _, e := range entities {
		if e.Tombstone {
			continue
		}
		if e.Kind == pb.ProjectionEntity_ORDER {
			var d struct {
				TableIDs []string `json:"tableIds"`
				Items    []struct {
					ID string `json:"lineUuid"`
				} `json:"items"`
			}
			if json.Unmarshal(e.Document, &d) != nil || d.TableIDs == nil {
				return ErrIntent
			}
			seen := map[string]bool{}
			for _, ref := range d.TableIDs {
				if seen[ref] {
					return ErrIntent
				}
				seen[ref] = true
			}
			for _, line := range d.Items {
				if owner, ok := lineOwners[line.ID]; ok && owner != e.Id {
					return ErrIntent
				}
				lineOwners[line.ID] = e.Id
			}
			orders[e.Id] = d.TableIDs
		} else {
			var d struct {
				Active string `json:"activeOrderUuid"`
			}
			if json.Unmarshal(e.Document, &d) != nil {
				return ErrIntent
			}
			tables[e.Id] = d.Active
		}
	}
	for id, refs := range orders {
		for _, ref := range refs {
			if active, ok := tables[ref]; !ok || active != id {
				return ErrIntent
			}
		}
	}
	for ref, id := range tables {
		if id == "" {
			continue
		}
		refs, ok := orders[id]
		if !ok {
			return ErrIntent
		}
		found := false
		for _, v := range refs {
			if v == ref {
				found = true
			}
		}
		if !found {
			return ErrIntent
		}
	}
	return nil
}

func (s *Store) CommitIntent(ctx context.Context, r *pb.CommitIntent) (*pb.CommitResult, error) {
	if err := validateIntent(r); err != nil {
		return nil, err
	}
	// Credentials never enter durable business events or request digests.
	clean := proto.Clone(r).(*pb.CommitIntent)
	clean.Auth = nil
	raw, err := (proto.MarshalOptions{Deterministic: true}).Marshal(clean)
	if err != nil {
		return nil, err
	}
	digest := sha256.Sum256(raw)
	tx, err := s.DB.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()
	epoch, head, err := state(tx)
	if err != nil {
		return nil, err
	}
	if epoch != r.AuthorityEpoch {
		return nil, ErrEpoch
	}
	var terminal string
	var priorDigest, priorResult []byte
	err = tx.QueryRow("SELECT terminal_id,digest,result FROM request_result WHERE request_id=?", r.RequestId).Scan(&terminal, &priorDigest, &priorResult)
	if err == nil {
		if terminal != r.Auth.TerminalId || !bytes.Equal(priorDigest, digest[:]) {
			return nil, ErrRequestReuse
		}
		result := &pb.CommitResult{}
		err = proto.Unmarshal(priorResult, result)
		return result, err
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return nil, err
	}
	result := &pb.CommitResult{Outcome: pb.CommitResult_COMMITTED, AuthorityEpoch: epoch, HeadSequence: head}
	for _, c := range r.Changes {
		current, e := readEntity(tx, c.Entity.Kind, c.Entity.Id)
		if e != nil {
			return nil, e
		}
		result.Current = append(result.Current, current)
		if current.Revision != c.ExpectedRevision || current.Tombstone {
			result.Outcome = pb.CommitResult_CONFLICT
		}
	}
	if result.Outcome == pb.CommitResult_COMMITTED {
		if head >= math.MaxInt64 {
			return nil, ErrProjectionLimit
		}
		event := &pb.CommittedEvent{Sequence: head + 1, AuthorityEpoch: epoch, RequestId: r.RequestId, TerminalId: r.Auth.TerminalId}
		for _, c := range r.Changes {
			e := proto.Clone(c.Entity).(*pb.ProjectionEntity)
			e.Revision = c.ExpectedRevision + 1
			if e.Document == nil {
				e.Document = []byte{}
			}
			if _, err = tx.Exec("INSERT INTO projection(kind,id,revision,tombstone,document) VALUES(?,?,?,?,?) ON CONFLICT(kind,id) DO UPDATE SET revision=excluded.revision,tombstone=excluded.tombstone,document=excluded.document", e.Kind, e.Id, e.Revision, e.Tombstone, e.Document); err != nil {
				return nil, err
			}
			event.Entities = append(event.Entities, e)
		}
		all, e := projection(tx)
		if e != nil {
			return nil, e
		}
		if len(all) > 256 {
			return nil, ErrProjectionLimit
		}
		if e = validateLinks(all); e != nil {
			return nil, e
		}
		eventBytes, e := proto.Marshal(event)
		if e != nil {
			return nil, e
		}
		if _, err = tx.Exec("INSERT INTO committed_event(sequence,event) VALUES(?,?)", event.Sequence, eventBytes); err != nil {
			return nil, err
		}
		if _, err = tx.Exec("UPDATE coordination SET sequence=? WHERE singleton=1", event.Sequence); err != nil {
			return nil, err
		}
		result.Event = event
		result.HeadSequence = event.Sequence
		result.Current = nil
	}
	resultBytes, err := proto.Marshal(result)
	if err != nil {
		return nil, err
	}
	if _, err = tx.Exec("INSERT INTO request_result(request_id,terminal_id,digest,result) VALUES(?,?,?,?)", r.RequestId, r.Auth.TerminalId, digest[:], resultBytes); err != nil {
		return nil, err
	}
	if err = tx.Commit(); err != nil {
		return nil, err
	}
	return result, nil
}
func (s *Store) ProjectionSnapshot(ctx context.Context, epoch uint64) (*pb.ProjectionSnapshot, error) {
	tx, err := s.DB.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()
	current, head, err := state(tx)
	if err != nil {
		return nil, err
	}
	if current != epoch {
		return nil, ErrEpoch
	}
	entities, err := projection(tx)
	if err != nil {
		return nil, err
	}
	return &pb.ProjectionSnapshot{Entities: entities, Sequence: head, AuthorityEpoch: current, Mode: "SHADOW"}, nil
}
func (s *Store) Replay(ctx context.Context, epoch, after uint64, limit uint32) (*pb.ReplayPage, error) {
	if limit == 0 {
		limit = 100
	}
	if limit > 100 {
		return nil, ErrIntent
	}
	tx, err := s.DB.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()
	current, head, err := state(tx)
	if err != nil {
		return nil, err
	}
	if current != epoch {
		return nil, ErrEpoch
	}
	if after > head {
		return nil, ErrIntent
	}
	rows, err := tx.Query("SELECT event FROM committed_event WHERE sequence>? ORDER BY sequence LIMIT ?", after, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	result := &pb.ReplayPage{HeadSequence: head, AuthorityEpoch: current}
	size := 0
	for rows.Next() {
		var raw []byte
		if err = rows.Scan(&raw); err != nil {
			return nil, err
		}
		if size+len(raw) > 2<<20 && len(result.Events) > 0 {
			break
		}
		size += len(raw)
		e := &pb.CommittedEvent{}
		if err = proto.Unmarshal(raw, e); err != nil {
			return nil, err
		}
		result.Events = append(result.Events, e)
	}
	return result, rows.Err()
}
