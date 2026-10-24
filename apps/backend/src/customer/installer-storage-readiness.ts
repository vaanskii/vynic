/** Read-only storage diagnostics. Never return or log provider bodies, URLs or credentials. */
const numberHeader = (response: Response, name: string) => {
  const raw = response.headers.get(name);
  const value = raw === null ? NaN : Number(raw);
  return Number.isSafeInteger(value) && value >= 0 ? value : null;
};

export async function classifyInstallerStorage(
  response: Response,
  host: string,
) {
  let classification =
    response.status === 401
      ? 'credential_rejected'
      : response.status === 404
        ? 'asset_hidden_or_missing'
        : response.status === 403
          ? 'provider_forbidden'
          : 'storage_response_rejected';
  if (response.headers.get('content-type')?.includes('json') && response.body) {
    const reader = response.body.getReader();
    let text = '',
      size = 0;
    try {
      const decoder = new TextDecoder();
      for (;;) {
        const next = await reader.read();
        if (next.done) break;
        size += next.value.byteLength;
        if (size > 8192) {
          await reader.cancel();
          classification = 'provider_error_body_oversize';
          break;
        }
        text += decoder.decode(next.value, { stream: true });
      }
      if (size <= 8192) {
        const parsed = JSON.parse(text);
        const message =
          typeof parsed.message === 'string'
            ? parsed.message.toLowerCase()
            : '';
        if (message.includes('rate limit'))
          classification = 'provider_rate_limited';
        else if (message.includes('resource not accessible'))
          classification = 'credential_scope_denied';
        else if (message.includes('bad credentials'))
          classification = 'credential_rejected';
        else if (message.includes('saml') || message.includes('single sign-on'))
          classification = 'provider_sso_required';
        else if (response.status === 200)
          classification = 'metadata_instead_of_artifact';
      }
    } catch {
      classification = 'provider_error_body_unreadable';
    } finally {
      reader.releaseLock();
    }
  }
  const expiry = Date.parse(
    response.headers.get('github-authentication-token-expiration') ?? '',
  );
  return {
    classification,
    credentialExpiresAt: Number.isFinite(expiry)
      ? new Date(expiry).toISOString()
      : null,
    host,
    status: response.status,
    rateLimitRemaining: numberHeader(response, 'x-ratelimit-remaining'),
    rateLimitReset: numberHeader(response, 'x-ratelimit-reset'),
    retryAfter: numberHeader(response, 'retry-after'),
    acceptedContentsRead:
      response.headers
        .get('x-accepted-github-permissions')
        ?.includes('contents=read') ?? null,
  };
}

export async function checkInstallerStorage(config: {
  token: string;
  assetId: string;
  bytes: number;
}) {
  let url = `https://api.github.com/repos/vaanskii/vynic-releases/releases/assets/${config.assetId}`;
  let host = 'github_api';
  try {
    for (let hop = 0; hop < 4; hop++) {
      const api = new URL(url).hostname === 'api.github.com';
      host = api ? 'github_api' : 'artifact_host';
      const response = await fetch(url, {
        method: api ? 'GET' : 'HEAD',
        redirect: 'manual',
        signal: AbortSignal.timeout(15000),
        headers: {
          Accept: 'application/octet-stream',
          'User-Agent': 'Vynic-protected-download',
          ...(api
            ? {
                Authorization: `Bearer ${config.token}`,
                'X-GitHub-Api-Version': '2022-11-28',
              }
            : {}),
        },
      });
      if ([301, 302, 303, 307, 308].includes(response.status)) {
        const location = response.headers.get('location');
        await response.body?.cancel();
        if (!location)
          return {
            available: false,
            classification: 'redirect_missing',
            host,
            status: response.status,
          };
        const next = new URL(location, url);
        if (
          next.protocol !== 'https:' ||
          next.hostname !== 'release-assets.githubusercontent.com' ||
          next.username ||
          next.password
        )
          return {
            available: false,
            classification: 'redirect_refused',
            host,
            status: response.status,
          };
        url = next.href;
        continue;
      }
      if (
        response.status === 200 &&
        !response.headers.get('content-type')?.includes('json') &&
        Number(response.headers.get('content-length')) === config.bytes
      ) {
        await response.body?.cancel();
        return {
          available: true,
          classification: 'verified_headers',
          host,
          status: response.status,
        };
      }
      const reason = await classifyInstallerStorage(response, host);
      await response.body?.cancel();
      return { available: false, ...reason };
    }
    return { available: false, classification: 'redirect_limit', host };
  } catch {
    return { available: false, classification: 'transport_failure', host };
  }
}
