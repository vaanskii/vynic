package server

import (
	"bytes"

	pb "vynic.local/contracts/go/vynic/edge/v1"
	"vynic.local/edge/internal/store"
)

func proofLimits() *pb.ProofLimits {
	return &pb.ProofLimits{
		MaxRequestBytes: store.OperationalMaxRequestBytes, MaxDocumentBytes: store.OperationalMaxDocumentBytes,
		MaxEffectBytes: store.OperationalMaxEffectBytes, MaxApplicationBytes: store.OperationalMaxApplicationBytes,
		MaxResultBytes: store.OperationalMaxResultBytes, MaxSnapshotBytes: store.OperationalMaxSnapshotBytes,
		MaxReplayBytes: store.OperationalMaxReplayBytes, MaxWrites: store.OperationalMaxWrites,
		MaxReads: store.OperationalMaxReads, MaxRequestEffects: store.OperationalMaxRequestEffects,
		MaxReplayEvents: store.OperationalMaxReplayEvents, MaxEntities: store.OperationalMaxEntities,
		MaxRetainedRequests: store.OperationalMaxRequests, MaxRetainedEvents: store.OperationalMaxEvents,
		MaxRetainedEffects: store.OperationalMaxEffects, MaxEventBytes: store.OperationalMaxEventBytes,
		MaxStateBytes: store.OperationalMaxStateBytes, MaxJournalBytes: store.OperationalMaxJournalBytes,
	}
}

func proofKind(kind pb.ProofEntity_Kind) (store.OperationalEntityKind, error) {
	switch kind {
	case pb.ProofEntity_ORDER:
		return store.OperationalOrder, nil
	case pb.ProofEntity_TABLE:
		return store.OperationalTable, nil
	case pb.ProofEntity_RESERVATION:
		return store.OperationalReservation, nil
	case pb.ProofEntity_PACKAGE:
		return store.OperationalPackage, nil
	case pb.ProofEntity_SALE:
		return store.OperationalSale, nil
	case pb.ProofEntity_DAY:
		return store.OperationalDay, nil
	case pb.ProofEntity_OPERATIONAL_CONTROL:
		return store.OperationalControl, nil
	case pb.ProofEntity_AUDIT_REPORT:
		return store.OperationalAuditReport, nil
	case pb.ProofEntity_CLOSURE:
		return store.OperationalClosure, nil
	case pb.ProofEntity_ADVANCE:
		return store.OperationalAdvance, nil
	case pb.ProofEntity_EXPENSE:
		return store.OperationalExpense, nil
	case pb.ProofEntity_STAFF:
		return store.OperationalStaff, nil
	case pb.ProofEntity_OPERATIONAL_POLICY:
		return store.OperationalPolicy, nil
	default:
		return "", store.ErrOperationalIntent
	}
}

func proofCommit(r *pb.ProofCommitRequest, auth store.OperationalAuth) (*store.OperationalCommit, error) {
	if len(r.Reads) > store.OperationalMaxReads || len(r.Writes) > store.OperationalMaxWrites || len(r.Effects) > store.OperationalMaxRequestEffects {
		return nil, store.ErrOperationalIntent
	}
	result := &store.OperationalCommit{Auth: auth, RequestID: r.RequestId, AuthorityEpoch: r.AuthorityEpoch, ApplicationData: bytes.Clone(r.ApplicationData), PrintAdmission: r.PrintAdmission, OriginInstallationID: r.OriginInstallationId,
		Reads: make([]store.OperationalRead, 0, len(r.Reads)), Writes: make([]store.OperationalWrite, 0, len(r.Writes)), Effects: make([]store.OperationalEffect, 0, len(r.Effects))}
	for _, read := range r.Reads {
		if read == nil {
			return nil, store.ErrOperationalIntent
		}
		kind, err := proofKind(read.Kind)
		if err != nil {
			return nil, err
		}
		result.Reads = append(result.Reads, store.OperationalRead{Kind: kind, ID: read.Id, ExpectedRevision: read.ExpectedRevision, ExpectedTombstone: read.ExpectedTombstone})
	}
	for _, write := range r.Writes {
		if write == nil {
			return nil, store.ErrOperationalIntent
		}
		kind, err := proofKind(write.Kind)
		if err != nil {
			return nil, err
		}
		result.Writes = append(result.Writes, store.OperationalWrite{Kind: kind, ID: write.Id, ExpectedRevision: write.ExpectedRevision, Tombstone: write.Tombstone, Document: bytes.Clone(write.Document)})
	}
	for _, effect := range r.Effects {
		if effect == nil {
			return nil, store.ErrOperationalIntent
		}
		var kind store.OperationalEffectKind
		switch effect.Kind {
		case pb.ProofEffect_AUDIT:
			kind = store.OperationalAudit
		case pb.ProofEffect_PRINT:
			kind = store.OperationalPrint
		default:
			return nil, store.ErrOperationalIntent
		}
		result.Effects = append(result.Effects, store.OperationalEffect{ID: effect.Id, Kind: kind, Payload: bytes.Clone(effect.Payload)})
	}
	return result, nil
}

func proofEntity(e store.OperationalEntity) *pb.ProofEntity {
	return &pb.ProofEntity{Kind: pb.ProofEntity_Kind(pb.ProofEntity_Kind_value[string(e.Kind)]), Id: e.ID, Revision: e.Revision, Tombstone: e.Tombstone, Document: bytes.Clone(e.Document)}
}

func proofEffect(e store.OperationalEffect) *pb.ProofEffect {
	return &pb.ProofEffect{Id: e.ID, Kind: pb.ProofEffect_Kind(pb.ProofEffect_Kind_value[string(e.Kind)]), Payload: bytes.Clone(e.Payload)}
}

func proofEvent(event *store.OperationalEvent) *pb.ProofEvent {
	if event == nil {
		return nil
	}
	result := &pb.ProofEvent{Mode: event.Mode, AuthorityEpoch: event.AuthorityEpoch, Sequence: event.Sequence, RequestId: event.RequestID, TerminalId: event.TerminalID, PrintAdmission: event.PrintAdmission, OriginInstallationId: event.OriginInstallationID}
	for _, receipt := range event.PrintReceipts {
		result.PrintReceipts = append(result.PrintReceipts, &pb.ProofPrintReceipt{Version: receipt.Version, JobId: receipt.JobID, EffectId: receipt.EffectID, PhysicalPrinterId: receipt.PhysicalPrinterID, Sequence: receipt.Sequence, AdmissionSha256: receipt.AdmissionSHA256})
	}
	for _, e := range event.Entities {
		result.Entities = append(result.Entities, proofEntity(e))
	}
	for _, e := range event.Effects {
		result.Effects = append(result.Effects, proofEffect(e))
	}
	return result
}

func proofResult(r *store.OperationalCommitResult) *pb.ProofCommitResult {
	result := &pb.ProofCommitResult{Mode: r.Mode, RequestId: r.RequestID, TerminalId: r.TerminalID, Outcome: pb.ProofCommitResult_Outcome(pb.ProofCommitResult_Outcome_value[string(r.Outcome)]), AuthorityEpoch: r.AuthorityEpoch, HeadSequence: r.HeadSequence, Event: proofEvent(r.Event), ApplicationData: bytes.Clone(r.ApplicationData), PrintAdmission: r.PrintAdmission, OriginInstallationId: r.OriginInstallationID}
	for _, e := range r.Current {
		result.Current = append(result.Current, proofEntity(e))
	}
	return result
}
