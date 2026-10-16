package printcluster

import (
	"maps"
	"slices"

	"vynic.local/edge/internal/printstation"
)

// transitionCopy copies mutable records only. Payloads, serialized legacy jobs
// and catalog snapshots are immutable inside the FSM and are never copied for
// a state transition. Public reads still return independent owned values.
func transitionCopy(p *projection) *projection {
	s := *p
	s.Members = maps.Clone(p.Members)
	s.Configs = maps.Clone(p.Configs)
	s.CurrentConfigs = maps.Clone(p.CurrentConfigs)
	s.Effects = maps.Clone(p.Effects)
	s.NextSequence = maps.Clone(p.NextSequence)
	s.Attempts = maps.Clone(p.Attempts)
	s.Audit = slices.Clone(p.Audit)
	s.Requests = make(map[string]*requestRecord, len(p.Requests))
	for k, r := range p.Requests {
		v := *r
		v.ChunkHashes = maps.Clone(r.ChunkHashes)
		if r.Receipt != nil {
			x := *r.Receipt
			v.Receipt = &x
		}
		s.Requests[k] = &v
	}
	s.Stages = make(map[string]*stagedJob, len(p.Stages))
	for k, r := range p.Stages {
		s.Stages[k] = &stagedJob{Chunks: maps.Clone(r.Chunks)}
	}
	s.Jobs = make(map[string]*storedJob, len(p.Jobs))
	for k, r := range p.Jobs {
		v := *r
		if r.Assignment != nil {
			x := *r.Assignment
			v.Assignment = &x
		}
		s.Jobs[k] = &v
	}
	if p.Stations != nil {
		v := *p.Stations
		v.Catalogs = maps.Clone(p.Stations.Catalogs)
		v.Sequences = maps.Clone(p.Stations.Sequences)
		v.RouteStates = maps.Clone(p.Stations.RouteStates)
		v.Jobs = make(map[string]*printstation.Record, len(p.Stations.Jobs))
		for k, r := range p.Stations.Jobs {
			x := *r
			x.Attempts = slices.Clone(r.Attempts)
			v.Jobs[k] = &x
		}
		s.Stations = &v
	}
	return &s
}
