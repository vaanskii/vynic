/** A per-grant transport handshake, never a public installer/catalog page.
 * The bearer secret stays in a fragment until POST, then only a scoped HttpOnly
 * cookie. The non-secret selector alone never authorizes artifact bytes. */
export function installerDownloadBridge(id: string, nonce: string) {
  const base = JSON.stringify('/customer/downloads/access/' + id);
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="referrer" content="no-referrer"><meta name="robots" content="noindex,nofollow,noarchive"><title>Vynic secure transfer</title></head><body><main><p id="status" role="status">Checking your temporary link…</p><a id="file" hidden rel="noreferrer" download>Download file</a></main><script nonce="${nonce}">
(() => {
  const base = ${base};
  const token = new URLSearchParams(location.hash.slice(1)).get('token');
  history.replaceState(null, '', location.pathname);
  const status = document.getElementById('status');
  fetch(base + '/session', { method: 'POST', credentials: 'same-origin', headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': 'vynic-download' }, body: JSON.stringify(token ? { token } : {}) })
    .then(async response => {
      if (!response.ok) throw new Error('unavailable');
      status.textContent = 'Your temporary file is ready. This link can be used by anyone holding it until it expires or is revoked.';
      const file = document.getElementById('file'); file.href = base + '/file'; file.hidden = false;
    }).catch(() => { status.textContent = 'This link is unavailable or expired. Request a new link from your account or administrator.'; });
})();
</script></body></html>`;
}
