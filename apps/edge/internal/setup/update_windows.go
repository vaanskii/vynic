//go:build windows

package setup

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"time"
	"vynic.local/edge/internal/updater"
)

// OfferPOSUpdate never invents readiness or calls /v1/install. A verified
// download can remain staged while POS is closed; consent is supplied in POS.
func OfferPOSUpdate(ctx context.Context, l Layout, report func(UpdateProgress)) (UpdateOfferResult, error) {
	r, e := Load(l)
	if e != nil {
		return UpdateOfferResult{}, e
	}
	ctx, cancel := context.WithTimeout(ctx, 30*time.Minute)
	defer cancel()
	return offerPOSUpdate(ctx, updateOfferOps{
		startHost: func(ctx context.Context) error { return EnsureHost(ctx, l, false) },
		snapshot:  func(ctx context.Context) (st updater.State, e error) { return status(ctx, r.Config) },
		check: func(ctx context.Context) error {
			req, e := http.NewRequestWithContext(ctx, "POST", "http://"+r.Config.Listen+"/v1/check", nil)
			if e != nil {
				return e
			}
			req.Header.Set("Authorization", "Bearer "+r.Config.Token)
			client := &http.Client{Timeout: 5 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return errors.New("IPC redirect refused") }}
			res, e := client.Do(req)
			if e != nil {
				return e
			}
			defer res.Body.Close()
			_, e = io.Copy(io.Discard, io.LimitReader(res.Body, 16<<10))
			if e != nil {
				return e
			}
			if res.StatusCode != 200 {
				return fmt.Errorf("update check failed: HTTP %d", res.StatusCode)
			}
			return nil
		},
		launch:   func(ctx context.Context, report func(UpdateProgress)) error { return ensureHost(ctx, l, true, report) },
		interval: 500 * time.Millisecond,
	}, report)
}
