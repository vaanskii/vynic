package main

import (
	"flag"
	"fmt"
	"io"
)

type startupOptions struct{ mode, distribution string }

func parseStartup(args []string) (startupOptions, error) {
	o := startupOptions{mode: "installer"}
	f := flag.NewFlagSet("VynicSetup", flag.ContinueOnError)
	f.SetOutput(io.Discard)
	f.StringVar(&o.distribution, "distribution", "", "public distribution config")
	modes := []string{"launch", "host", "repair", "uninstall"}
	selected := make([]bool, len(modes))
	for i, mode := range modes {
		f.BoolVar(&selected[i], mode, false, mode)
	}
	if err := f.Parse(args); err != nil {
		return o, err
	}
	count := 0
	for i, yes := range selected {
		if yes {
			o.mode = modes[i]
			count++
		}
	}
	if count > 1 || f.NArg() != 0 {
		return o, fmt.Errorf("choose only one of --launch, --host, --repair or --uninstall")
	}
	return o, nil
}
