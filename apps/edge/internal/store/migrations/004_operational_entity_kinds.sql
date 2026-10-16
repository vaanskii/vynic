-- ISOLATED_PROOF only. Expands opaque postimage kinds without creating authority.
-- A rebuild must not silently repair altered v3 constraints/triggers or discard
-- an attached index/trigger before Store's final exact-schema verification.
CREATE TEMP TABLE op_entity_v4_guard (
 valid INTEGER NOT NULL CONSTRAINT unmodified_operational_entity_v3 CHECK(valid=1)
);
INSERT INTO op_entity_v4_guard(valid)
SELECT CASE WHEN
 (SELECT count(*) FROM main.sqlite_master WHERE tbl_name='op_entity')=4
 AND EXISTS(SELECT 1 FROM main.sqlite_master
  WHERE type='table' AND name='op_entity' AND tbl_name='op_entity'
  AND sql='CREATE TABLE op_entity (
 kind TEXT NOT NULL CHECK(kind IN (''ORDER'',''TABLE'',''RESERVATION'',''PACKAGE'',''SALE'',''DAY'')),
 id TEXT NOT NULL,
 revision INTEGER NOT NULL CHECK(typeof(revision)=''integer'' AND revision>0),
 tombstone INTEGER NOT NULL CHECK(tombstone IN (0,1)),
 document BLOB NOT NULL CHECK(length(document)<=1048576 AND ((tombstone=1 AND length(document)=0) OR (tombstone=0 AND length(document)>0))),
 PRIMARY KEY(kind,id)
)')
 AND EXISTS(SELECT 1 FROM main.sqlite_master
  WHERE type='index' AND name='sqlite_autoindex_op_entity_1'
  AND tbl_name='op_entity' AND sql IS NULL)
 AND EXISTS(SELECT 1 FROM main.sqlite_master
  WHERE type='trigger' AND name='op_entity_update' AND tbl_name='op_entity'
  AND sql='CREATE TRIGGER op_entity_update BEFORE UPDATE ON op_entity
WHEN OLD.tombstone=1 OR NEW.kind IS NOT OLD.kind OR NEW.id IS NOT OLD.id OR NEW.revision!=OLD.revision+1
BEGIN SELECT RAISE(ABORT,''invalid entity revision or retained tombstone''); END')
 AND EXISTS(SELECT 1 FROM main.sqlite_master
  WHERE type='trigger' AND name='op_entity_delete' AND tbl_name='op_entity'
  AND sql='CREATE TRIGGER op_entity_delete BEFORE DELETE ON op_entity
BEGIN SELECT RAISE(ABORT,''entity identity must be retained''); END')
 THEN 1 ELSE 0 END;
DROP TABLE temp.op_entity_v4_guard;

-- No table references op_entity. Identical column affinities and INSERT SELECT
-- preserve document bytes, revisions and retained tombstones without replanning.
CREATE TABLE op_entity_v4 (
 kind TEXT NOT NULL CHECK(kind IN ('ORDER','TABLE','RESERVATION','PACKAGE','SALE','DAY','OPERATIONAL_CONTROL','AUDIT_REPORT','CLOSURE','ADVANCE','EXPENSE','STAFF','OPERATIONAL_POLICY')),
 id TEXT NOT NULL,
 revision INTEGER NOT NULL CHECK(typeof(revision)='integer' AND revision>0),
 tombstone INTEGER NOT NULL CHECK(tombstone IN (0,1)),
 document BLOB NOT NULL CHECK(length(document)<=1048576 AND ((tombstone=1 AND length(document)=0) OR (tombstone=0 AND length(document)>0))),
 PRIMARY KEY(kind,id)
);
INSERT INTO op_entity_v4(kind,id,revision,tombstone,document)
 SELECT kind,id,revision,tombstone,document FROM op_entity;
DROP TRIGGER op_entity_update;
DROP TRIGGER op_entity_delete;
DROP TABLE op_entity;
ALTER TABLE op_entity_v4 RENAME TO op_entity;

-- Restore the exact v3 guards. Other authority/request/event/effect triggers and
-- every frozen record remain untouched. There is no schema downgrade operation.
CREATE TRIGGER op_entity_update BEFORE UPDATE ON op_entity
WHEN OLD.tombstone=1 OR NEW.kind IS NOT OLD.kind OR NEW.id IS NOT OLD.id OR NEW.revision!=OLD.revision+1
BEGIN SELECT RAISE(ABORT,'invalid entity revision or retained tombstone'); END;
CREATE TRIGGER op_entity_delete BEFORE DELETE ON op_entity
BEGIN SELECT RAISE(ABORT,'entity identity must be retained'); END;
