package printcluster

// snapshotProjection places each immutable blob in the snapshot once. Rows keep
// their stable content identities. Version 2 is refused by version 1 readers.
func snapshotProjection(p *projection) *projection {
	s := transitionCopy(p)
	s.SnapshotBlobs = map[string][]byte{}
	for k, b := range s.Configs {
		s.SnapshotBlobs[k] = b
		s.Configs[k] = nil
	}
	for _, j := range s.Jobs {
		s.SnapshotBlobs[j.Receipt.InputSHA256] = j.Raw
		j.Raw = nil
	}
	for id, st := range s.Stages {
		for i, b := range st.Chunks {
			s.SnapshotBlobs[s.Requests[id].ChunkHashes[i]] = b
			st.Chunks[i] = nil
		}
	}
	if s.Stations != nil {
		for _, r := range s.Stations.Jobs {
			s.SnapshotBlobs[r.Job.PayloadDigest] = r.Job.Payload
			r.Job.Payload = nil
		}
	}
	return s
}
func hydrateSnapshot(s *projection) error {
	// Empty initial snapshots may omit an empty map, but embedded version-1-style
	// blobs are never accepted as an implicit downgrade of this format.
	used := map[string]bool{}
	get := func(digest string, b []byte) ([]byte, error) {
		if b != nil {
			return nil, ErrInvalid
		}
		value, ok := s.SnapshotBlobs[digest]
		if !ok || len(value) == 0 || sha(value) != digest {
			return nil, ErrInvalid
		}
		used[digest] = true
		return value, nil
	}
	var e error
	for k, b := range s.Configs {
		if s.Configs[k], e = get(k, b); e != nil {
			return e
		}
	}
	for _, j := range s.Jobs {
		if j == nil {
			return ErrInvalid
		}
		if j.Raw, e = get(j.Receipt.InputSHA256, j.Raw); e != nil {
			return e
		}
	}
	for id, st := range s.Stages {
		if st == nil || s.Requests[id] == nil {
			return ErrInvalid
		}
		for i, b := range st.Chunks {
			if st.Chunks[i], e = get(s.Requests[id].ChunkHashes[i], b); e != nil {
				return e
			}
		}
	}
	if s.Stations != nil {
		for _, r := range s.Stations.Jobs {
			if r == nil {
				return ErrInvalid
			}
			if r.Job.Payload, e = get(r.Job.PayloadDigest, r.Job.Payload); e != nil {
				return e
			}
		}
	}
	if len(used) != len(s.SnapshotBlobs) {
		return ErrInvalid
	}
	s.SnapshotBlobs = nil
	return nil
}
