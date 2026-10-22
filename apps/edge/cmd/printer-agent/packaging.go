package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"io"

	"vynic.local/edge/internal/printerdaemon"
)

func runPackaging(mode string, args []string, out, diagnostic io.Writer) error {
	flags := flag.NewFlagSet("printer-agent "+mode, flag.ContinueOnError)
	flags.SetOutput(diagnostic)
	encoder := json.NewEncoder(out)
	if mode == "apply" {
		planPath := flags.String("plan", "", "exact reviewed plan file")
		apply := flags.Bool("apply", false, "explicit later registration only; default PlanOnly")
		reviewed := flags.String("reviewed-plan-sha256", "", "required exact reviewed hash for later Apply")
		if err := flags.Parse(args); err != nil {
			return err
		}
		if flags.NArg() != 0 || *planPath == "" {
			return errors.New("apply requires --plan; defaults to PlanOnly")
		}
		document, err := printerdaemon.LoadPlan(*planPath)
		if err != nil {
			return err
		}
		if err = printerdaemon.ApplyInstallerPlan(context.Background(), document, *reviewed, *apply, printerdaemon.WindowsInstallerBackend{}); err != nil {
			return err
		}
		return encoder.Encode(map[string]any{"mode": map[bool]string{false: printerdaemon.PlanOnly, true: "ExplicitApplyCreateStopped"}[*apply], "planSha256": document.PlanSHA256, "physicalEligible": false})
	}
	configPath := flags.String("config", "", "explicit provisioned profile")
	if mode == "bundle" {
		directory := flags.String("out", "", "new bundle output directory")
		if err := flags.Parse(args); err != nil {
			return err
		}
		if flags.NArg() != 0 || *configPath == "" || *directory == "" {
			return errors.New("bundle requires --config and a new --out directory")
		}
		config, err := printerdaemon.LoadConfig(*configPath)
		if err != nil {
			return err
		}
		manifest, err := printerdaemon.BuildBundle(config, *directory)
		if err != nil {
			return err
		}
		return encoder.Encode(manifest)
	}
	bundlePath := flags.String("bundle-manifest", "", "exact artifact bundle manifest")
	clientPath := flags.String("client-profile", "", "explicit read-only client profile")
	if err := flags.Parse(args); err != nil {
		return err
	}
	if flags.NArg() != 0 || *configPath == "" || *bundlePath == "" || *clientPath == "" {
		return errors.New("plan requires --config, --bundle-manifest and --client-profile")
	}
	bundle, err := printerdaemon.ReferenceFile(*bundlePath)
	if err != nil {
		return err
	}
	client, err := printerdaemon.ReferenceFile(*clientPath)
	if err != nil {
		return err
	}
	document, err := printerdaemon.CreateInstallerPlan(*configPath, bundle, client)
	if err != nil {
		return err
	}
	return encoder.Encode(document)
}
