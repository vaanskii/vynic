package printerprovisioning

import (
	"bytes"
	"encoding/json"
	"io"
	"reflect"
	"strings"
	"unicode/utf8"
)

func uniqueJSON(d *json.Decoder, depth int) error {
	if depth > 32 {
		return ErrInvalid
	}
	token, err := d.Token()
	if err != nil {
		return ErrInvalid
	}
	delim, compound := token.(json.Delim)
	if !compound {
		return nil
	}
	switch delim {
	case '{':
		seen := map[string]bool{}
		for d.More() {
			key, err := d.Token()
			name, ok := key.(string)
			if err != nil || !ok || seen[name] {
				return ErrInvalid
			}
			seen[name] = true
			if err := uniqueJSON(d, depth+1); err != nil {
				return err
			}
		}
	case '[':
		for d.More() {
			if err := uniqueJSON(d, depth+1); err != nil {
				return err
			}
		}
	default:
		return ErrInvalid
	}
	_, err = d.Token()
	if err != nil {
		return ErrInvalid
	}
	return nil
}

func exactObject(raw []byte, target any) error {
	var fields map[string]json.RawMessage
	if json.Unmarshal(raw, &fields) != nil || fields == nil {
		return ErrInvalid
	}
	typ := reflect.TypeOf(target)
	if typ.Kind() == reflect.Pointer {
		typ = typ.Elem()
	}
	if len(fields) != typ.NumField() {
		return ErrInvalid
	}
	for i := 0; i < typ.NumField(); i++ {
		key := strings.Split(typ.Field(i).Tag.Get("json"), ",")[0]
		value, ok := fields[key]
		if !ok || bytes.Equal(bytes.TrimSpace(value), []byte("null")) {
			return ErrInvalid
		}
	}
	return nil
}

func strict(raw []byte, limit int, target any) error {
	if len(raw) == 0 || len(raw) > limit || !utf8.Valid(raw) {
		return ErrInvalid
	}
	check := json.NewDecoder(bytes.NewReader(raw))
	check.UseNumber()
	if uniqueJSON(check, 0) != nil {
		return ErrInvalid
	}
	if _, err := check.Token(); err != io.EOF {
		return ErrInvalid
	}
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.DisallowUnknownFields()
	if decoder.Decode(target) != nil {
		return ErrInvalid
	}
	return exactObject(raw, target)
}

func nestedObject(raw []byte, key string, target any) error {
	var fields map[string]json.RawMessage
	if json.Unmarshal(raw, &fields) != nil {
		return ErrInvalid
	}
	return exactObject(fields[key], target)
}
