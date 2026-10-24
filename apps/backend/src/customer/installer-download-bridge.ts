/** A per-grant transport handshake, never a public installer/catalog page.
 * The bearer secret stays in a fragment until POST, then only a scoped HttpOnly
 * cookie. The non-secret selector alone never authorizes artifact bytes. */
export function installerDownloadBridge(id: string, nonce: string) {
  const base = JSON.stringify('/customer/downloads/access/' + id);
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="referrer" content="no-referrer"><meta name="robots" content="noindex,nofollow,noarchive"><title>Vynic secure transfer</title></head><body><main><p id="status" role="status">Checking your temporary link…</p><a id="file" hidden rel="noreferrer">Download Windows package (.zip)</a></main><script nonce="${nonce}">
(() => {
  const base = ${base};
  const token = new URLSearchParams(location.hash.slice(1)).get('token');
  history.replaceState(null, '', location.pathname);
  const status = document.getElementById('status');
  fetch(base + '/session', { method: 'POST', credentials: 'same-origin', headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': 'vynic-download' }, body: JSON.stringify(token ? { token } : {}) })
    .then(async response => {
      if (!response.ok) throw new Error('unavailable');
      const check = await fetch(base + '/file', { method: 'HEAD', credentials: 'same-origin', cache: 'no-store', redirect: 'error' });
      if (!check.ok) throw new Error(check.status >= 500 ? 'storage' : 'unavailable');
      const size = Number(check.headers.get('content-length'));
      if (!Number.isSafeInteger(size) || size < 1 || !check.headers.get('content-type')?.startsWith('application/zip') || !check.headers.get('content-disposition')?.startsWith('attachment;')) throw new Error('storage');
      status.textContent = 'Your temporary file is ready. This link can be used by anyone holding it until it expires or is revoked.';
      const file = document.getElementById('file'); file.href = base + '/file'; file.hidden = false;
    }).catch(error => { status.textContent = error.message === 'storage' ? 'The protected Windows package is temporarily unavailable. Please try again shortly or contact Vynic.' : 'This link is unavailable or expired. Request a new link from your account or administrator.'; });
})();
</script></body></html>`;
}

export function installerDownloadFailure(status: number) {
  const message =
    status >= 500
      ? 'The protected Windows package is temporarily unavailable. Please try again shortly or contact Vynic.'
      : status === 429
        ? 'Too many download attempts. Please try again later.'
        : 'This download link is unavailable, expired or replaced. Request a new link from your account or administrator.';
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,nofollow,noarchive"><title>Vynic download unavailable</title></head><body><main><h1>Download unavailable</h1><p role="alert">${message}</p></main></body></html>`;
}
