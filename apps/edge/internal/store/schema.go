package store

import (
	"database/sql"
	"errors"
	"strings"
)

const migrationTable = "CREATE TABLE schema_migration(version INTEGER PRIMARY KEY, checksum TEXT NOT NULL)"

type queryer interface {
	Query(string, ...any) (*sql.Rows, error)
}

func schemaShape(db queryer) (string, error) {
	rows, err := db.Query("SELECT type,name,tbl_name,COALESCE(sql,'') FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type,name")
	if err != nil {
		return "", err
	}
	defer rows.Close()
	var shape strings.Builder
	for rows.Next() {
		var kind, name, table, ddl string
		if err = rows.Scan(&kind, &name, &table, &ddl); err != nil {
			return "", err
		}
		for _, v := range []string{kind, name, table, ddl} {
			shape.WriteString(v)
			shape.WriteByte(0)
		}
	}
	return shape.String(), rows.Err()
}

// Compare actual DDL with the embedded schema as well as verifying migration
// checksums: a dropped constraint/added trigger must not hide behind user_version.
func verifySchema(tx *sql.Tx) error {
	expected, err := sql.Open("sqlite", ":memory:")
	if err != nil {
		return err
	}
	defer expected.Close()
	expected.SetMaxOpenConns(1)
	if _, err = expected.Exec(migrationTable); err != nil {
		return err
	}
	files, err := migrations.ReadDir("migrations")
	if err != nil {
		return err
	}
	for _, f := range files {
		b, e := migrations.ReadFile("migrations/" + f.Name())
		if e != nil {
			return e
		}
		if _, e = expected.Exec(string(b)); e != nil {
			return e
		}
	}
	want, err := schemaShape(expected)
	if err != nil {
		return err
	}
	actual, err := schemaShape(tx)
	if err != nil {
		return err
	}
	if want != actual {
		return errors.New("local schema differs from embedded migrations")
	}
	return nil
}
