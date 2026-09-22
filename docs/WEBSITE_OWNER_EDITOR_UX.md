# Customer Portal website editor

## Before → after

| Before | After |
| --- | --- |
| General, hero, about, theme, menu, gallery, links, SEO and publication shared the same navigation priority | მთავარი · ჩვენ შესახებ · მენიუ · ფოტოები · სამუშაო საათები · კონტაქტი · დიზაინი · გამოქვეყნება |
| Technical address/media/map labels | ვებსაიტის მისამართი; plain photo labels; named Instagram, Facebook, TikTok and website fields |
| A map URL was the only way to offer directions | რუკის ჩვენება defaults on; current Venue Profile address supplies directions; optional exact Google Maps link is collapsed |
| SEO and internal revision numbers occupied the primary flow | დამატებითი პარამეტრები contains SEO/footer; Draft/Published and unsaved changes remain visible |
| Website, payments, profile and device onboarding stacked together | Separate Website, Restaurant Profile and Restaurant Setup workspaces; local website edits survive workspace switches |
| Disabled online payments still offered credentials | No payment component or payment API request without ONLINE_PAYMENTS; fetched disabled status also hides the form |
| Generic gallery configuration | ფოტოების დამატება, descriptions, image previews and load-error feedback |

Publishing offers საიტის ნახვა, მონახაზის შენახვა and გამოქვეყნება. Viewing opens the saved private draft. Unsaved edits block preview/publication; revision checks and explicit publication remain unchanged. Working hours retain day checkboxes and native time inputs, including overnight hours. Menu presentation still uses its existing separate save contract; operational menu authority does not change.

## Compatibility and limits

The only backend contract addition is optional-on-write `showMap`, defaulting to true for older content. The flag distinguishes a hidden map from an empty exact-pin field; `mapUrl` remains the optional override. The public SaaS renderer derives directions from the current profile address, never a duplicated draft address. No migration, tenancy change, schema-version bump, payment behavior change or CUSTOM/Vankisi edit is involved. Deploy the compatible backend before the editor that writes the flag.

Gallery and about photo entry remain link-based. Logo and main-photo entry use the file picker described below. Missing link schemes are supplied for website contact links; invalid links return a human-readable error. General photo uploads are not added.

## Verification

- Portal: 52 tests pass, including private preview, explicit publish, unsaved-edit blocking, revision conflict recovery, CUSTOM protection, entitlement gates, named fields, map controls, hours and setup separation.
- Public restaurant website: 19 tests pass, including profile-address fallback, exact pins and hidden-map behavior.
- Backend content: 2 compatibility tests pass for legacy reads/writes and boolean validation.
- Production builds pass for platform-web, restaurant-web and backend. Frontend typechecks pass.
- Full backend test-inclusive typecheck has an unrelated existing error in `edge-foundation.integration.spec.ts:97` (`"bad"` is not a UUID template-literal type).
- Real Chromium checks at 390, 768 and 1440 px: all eight sections, no horizontal overflow, save/publish revision assertions, hidden setup flow and no disabled-payment requests. Screenshots reviewed for mobile contact/hours, tablet publishing and desktop editor/photos.

Reproduce browser checks with a local platform-web Vite server and `node apps/platform-web/scripts/website-editor-qa.mjs`. The script intercepts customer APIs with disposable fixtures; it never saves a real venue. Optional environment variables: `QA_URL`, `QA_OUTPUT`, `PLAYWRIGHT_MODULE` (existing module path), `BROWSER_PATH` (Chromium executable). Default screenshots are written to `/tmp/vynic-website-editor-qa`.


## Logo uploads

Design now offers **ლოგოს ატვირთვა** with a native file picker, preview, replacement,
removal, progress and retry. PNG, JPEG and WebP files up to 5 MB are supported.
The owner endpoint checks ownership and SAAS mode before storing anything;
Sharp decodes files, rejects SVG/unsupported or invalid content and excessive
pixel counts, strips metadata, and emits WebP at at most 1024×1024. Multipart
transport retains the customer bearer token and lets the browser set its boundary.
The resulting reference changes only the local draft until normal revision-checked
save and explicit publication. Removing/replacing a draft logo does not delete an
asset still referenced by a published revision.

Production setup:

- Set `WEBSITE_MEDIA_DIR` to a writable persistent directory, backed up and shared
  by all backend replicas. The production server fails explicitly if this setting
  is absent. Development defaults to ignored `.data/website-media` under backend cwd.
- Reverse-proxy `/media/website-logos/` to the backend from the portal, public SaaS
  and preview origins. Both Vite configs include that proxy for local development;
  existing sample media continue to be served by the frontends.
- Assets are public raster logos with random immutable filenames, safe MIME headers
  and one-year caching. No directory listing or original filename is exposed.
  Host-based website content resolution, private draft APIs and CUSTOM behavior
  are unchanged. Do not upload private documents as branding assets.
- Storage retains replaced/abandoned uploads; automatic pruning and storage quotas
  are not implemented. Any future cleanup must account for both draft and published
  references. No database migration or content-schema change is required.

Logo validation: 55 portal tests and 7 backend logo tests pass, including real
multipart upload/download, image decoding, ownership/CUSTOM rejection, size/type
limits, retries and old-logo retention. Browser QA exercises file selection,
multipart requests, preview and draft publication at 390, 768 and 1440 px.


### Main photo

The მთავარი section now offers მთავარი ფოტოს ატვირთვა using the shared
`WebsiteImageUpload` component. The ownership-checked `POST website/hero` endpoint
uses the same 5 MB raster validation, storage and existing media proxy path.
Main photos are resized proportionally to at most 2400×2400, while logos retain
the 1024×1024 limit. Both keep their existing draft content fields and explicit
save/publication. The legacy `/media/website-logos/` asset prefix remains in use
so this addition needs no new storage or proxy configuration.
