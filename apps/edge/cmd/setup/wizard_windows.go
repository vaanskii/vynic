//go:build windows

package main

import (
	"fmt"
	"path/filepath"

	"vynic.local/edge/internal/setup"
)

func installWizard(l setup.Layout) (setup.Layout, bool, error) {
	destination := l.Root
	page := 0
	for {
		var choice int
		var err error
		switch page {
		case 0:
			choice, err = nativePage("Welcome to Vynic POS", "This wizard will install Vynic POS for your Windows account.\n\nYou will choose a destination, review the installation, and connect your restaurant after setup.", nil, []button{{"Next >", 1}, {"Cancel", 0}}, nil)
		case 1:
			choice, err = nativePage("Choose installation folder", fmt.Sprintf("Select a dedicated folder under your Local AppData directory.\n\nDefault: %s\n\nAdministrator access is not required.", l.Root), &destination, []button{{"< Back", 2}, {"Next >", 1}, {"Cancel", 0}}, nil)
		case 2:
			choice, err = nativePage("Ready to install", fmt.Sprintf("Vynic POS will be installed in:\n%s\n\nSetup will verify the signed release and create shortcuts. Restaurant data is retained during updates and repair.", destination), nil, []button{{"< Back", 2}, {"Install", 1}, {"Cancel", 0}}, nil)
		}
		if err != nil {
			return l, false, err
		}
		if choice == 0 {
			return l, false, nil
		}
		if choice == 2 {
			page--
			continue
		}
		if page < 2 {
			page++
			continue
		}
		selected, err := setup.SelectInstallRoot(l, filepath.Clean(destination))
		if err != nil {
			showError(err)
			page = 1
			continue
		}
		return selected, true, nil
	}
}

func maintenanceWizard(l setup.Layout) (int, error) {
	for {
		action, e := nativePage("Vynic POS is installed", "Update POS downloads the latest signed version.\nYou confirm installation in POS after its safety check.\n\nRepair restores the installed version; it does not upgrade it.\nRestaurant data stays in place.", nil, []button{{"Update POS", 5}, {"More options", 6}, {"Cancel", 0}}, nil)
		if e != nil || action != 6 {
			return action, e
		}
		action, e = nativePage("Manage Vynic POS", "Installation folder:\n"+l.Root+"\n\nRepair keeps the installed version and restaurant data.\nUninstall removes applications and retains restaurant data.", nil, []button{{"< Back", 6}, {"Open POS", 4}, {"Repair", 2}, {"Uninstall", 3}}, nil)
		if e != nil || action != 6 {
			return action, e
		}
	}
}
