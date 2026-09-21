CREATE TABLE coordination (
  singleton INTEGER PRIMARY KEY CHECK(singleton=1),
  authority_epoch INTEGER NOT NULL CHECK(authority_epoch>0),
  sequence INTEGER NOT NULL CHECK(sequence>=0)
);
INSERT INTO coordination VALUES(1,1,0);
CREATE TABLE projection (
  kind INTEGER NOT NULL CHECK(kind IN (1,2)),
  id TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK(revision>0),
  tombstone INTEGER NOT NULL CHECK(tombstone IN (0,1)),
  document BLOB NOT NULL,
  PRIMARY KEY(kind,id)
);
CREATE TABLE committed_event (
  sequence INTEGER PRIMARY KEY CHECK(sequence>0),
  event BLOB NOT NULL
);
CREATE TABLE request_result (
  request_id TEXT PRIMARY KEY,
  terminal_id TEXT NOT NULL REFERENCES terminal(id),
  digest BLOB NOT NULL,
  result BLOB NOT NULL
);
