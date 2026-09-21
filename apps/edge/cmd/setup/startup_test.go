package main

import (
	"testing"
)

func TestStartupModes(t *testing.T) {
	for _, tc := range []struct {
		args []string
		want string
	}{
		{nil, "installer"}, {[]string{"--launch"}, "launch"}, {[]string{"--host"}, "host"},
		{[]string{"--host=false"}, "installer"}, {[]string{"--repair"}, "repair"},
		{[]string{"--uninstall"}, "uninstall"}, {[]string{"--distribution", `C:\Test Folder\distribution.json`}, "installer"},
	} {
		t.Run(tc.want, func(t *testing.T) {
			o, e := parseStartup(tc.args)
			if e != nil || o.mode != tc.want {
				t.Fatalf("%+v %v", o, e)
			}
		})
	}
	for _, args := range [][]string{{"--host", "--launch"}, {"--host", "--repair"}, {"--bogus"}, {"host"}} {
		if _, e := parseStartup(args); e == nil {
			t.Fatalf("accepted invalid arguments %v", args)
		}
	}
}
