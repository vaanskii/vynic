package updater

import (
	"context"
	"errors"
	"io"
	"net/http"
	"time"
)

// LaunchCurrent is used by a Windows shortcut/launcher. The daemon resolves
// the durable current release; the shortcut never hardcodes a release path.
func LaunchCurrent(c Config) error {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	r, e := http.NewRequestWithContext(ctx, "POST", "http://"+c.Listen+"/v1/launch", nil)
	if e != nil {
		return e
	}
	r.Header.Set("Authorization", "Bearer "+c.Token)
	resp, e := http.DefaultClient.Do(r)
	if e != nil {
		return e
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		b, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
		return errors.New(string(b))
	}
	return nil
}
