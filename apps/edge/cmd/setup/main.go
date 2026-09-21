// VynicSetup is a first-install/repair/uninstall bootstrapper, not an Edge updater.
package main

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"os"
	"vynic.local/edge/internal/setup"
)

// Build-time public configuration only. Release builds inject this with -X;
// no endpoint/key default or production signing secret exists in source.
var distributionBase64 string
var setupVersion = "development"

func distribution(path string) (setup.Distribution, error) {
	var d setup.Distribution
	var b []byte
	var e error
	if path != "" {
		b, e = os.ReadFile(path)
	} else {
		b, e = base64.StdEncoding.DecodeString(distributionBase64)
	}
	if e != nil {
		return d, e
	}
	if len(b) == 0 {
		return d, errors.New("This setup build has no release configuration. Obtain a configured, signed VynicSetup from your distributor")
	}
	decoder := json.NewDecoder(bytes.NewReader(b))
	decoder.DisallowUnknownFields()
	if e = decoder.Decode(&d); e != nil {
		return d, e
	}
	if decoder.Decode(new(any)) != io.EOF {
		return d, errors.New("trailing distribution JSON")
	}
	return d, d.Validate()
}
func main() { nativeMain() }
