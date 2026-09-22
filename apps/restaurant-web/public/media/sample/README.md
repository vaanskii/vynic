# Local development media

Placeholder artwork for the disposable local website fixture. These files exist
so `/media/...` — the deployment-managed media reference used by published
website content — resolves to something during local development without any
object storage being configured.

They are not product assets and no deployment should ship them. Production
serves this same `/media/` prefix from real object storage or a CDN; see
`docs/WEBSITE_PHASE_W3.md`.
