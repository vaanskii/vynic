//go:build !windows

package main

import (
	"fmt"
	"os"
)

func nativeMain() {
	fmt.Fprintln(os.Stderr, "VynicSetup installs Windows POS only. Run Go fixture tests on this platform.")
	os.Exit(1)
}
