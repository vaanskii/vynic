//go:build !windows

package printerdaemon

func platformReparse(string) error { return nil }

func platformLocalPath(string) error { return nil }
