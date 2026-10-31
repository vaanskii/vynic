// Official Versions/Deployments APIs. No zone, route, domain, secret-write or R2
// management calls. This deliberately does not use Wrangler's dashboard import.
import { validateTarget, verifyActivation } from './deploy-version.mjs';

const account = '4347dd6103310d9273ecca7f207a0f4b';
const worker = 'vynic-installer-downloads';
const base = `https://api.cloudflare.com/client/v4/accounts/${account}/workers`;
const script = `/scripts/${worker}`;
const environment = `/services/${worker}/environments/production`;
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const fail = message => { throw new Error(message); };

export function bindingShape(bindings) {
  if (!Array.isArray(bindings) || bindings.length !== 2) fail('Unexpected Worker bindings; no activation');
  const r2 = bindings.find(b => b.name === 'INSTALLERS');
  const secret = bindings.find(b => b.name === 'DOWNLOAD_GATEWAY_SECRET');
  if (r2?.type !== 'r2_bucket' || r2.bucket_name !== 'vynic-installers' ||
      (r2.jurisdiction && r2.jurisdiction !== 'default') ||
      secret?.type !== 'secret_text') fail('Unexpected Worker bindings; no activation');
  // Only a projection of expected non-secret metadata is compared or emitted.
  return [{ name: 'INSTALLERS', type: 'r2_bucket', bucket_name: 'vynic-installers' },
    { name: 'DOWNLOAD_GATEWAY_SECRET', type: 'secret_text' }];
}

export function deployments(result) {
  const rows = Array.isArray(result) ? result : result?.deployments;
  if (!Array.isArray(rows) || !rows.length || rows.some(d => !uuid.test(d?.id ?? '') ||
      !Number.isFinite(Date.parse(d.created_on)) || !Array.isArray(d.versions) ||
      !d.versions.length || d.versions.some(v => !uuid.test(v?.version_id ?? '') ||
      !Number.isFinite(v.percentage) || v.percentage <= 0 || v.percentage > 100))) {
    fail('Invalid deployment metadata; no activation');
  }
  return rows.map(d => ({ id: d.id, created_on: d.created_on, versions: d.versions.map(v =>
    ({ version_id: v.version_id, percentage: v.percentage })).sort((a,b) => a.version_id.localeCompare(b.version_id)) }))
    .sort((a,b) => Date.parse(b.created_on) - Date.parse(a.created_on));
}

function singleActive(rows) {
  const current = rows[0];
  verifyActivation(JSON.stringify(rows), current.id, current.versions[0].version_id);
  return current.versions[0].version_id;
}

function latestVersion(result) {
  const rows = Array.isArray(result) ? result : result?.items;
  // Cloudflare lists versions newest first. Refuse an unknown/empty contract.
  if (!Array.isArray(rows) || !rows.length || rows.some(v => !uuid.test(v?.id ?? ''))) {
    fail('Invalid version metadata; no activation');
  }
  return rows[0].id;
}

function privateSettings(result) {
  if (result?.enabled !== false || result?.previews_enabled !== false) {
    fail('Worker preview exposure does not match the approved private configuration');
  }
  return { enabled: false, previews_enabled: false };
}

function runtimeSettings(result, config) {
  const s = result?.script;
  const flags = s?.compatibility_flags ?? [];
  if (s?.compatibility_date !== config.compatibility_date || !Array.isArray(flags) || flags.length ||
      s?.observability?.enabled !== true ||
      (s?.limits && Object.keys(s.limits).length) || s?.tail_consumers?.length ||
      s?.placement?.mode || s?.assets) fail('Worker runtime configuration requires separate review');
  // Logs are non-versioned settings: preserve them by never PATCHing settings.
  return { compatibility_date: s.compatibility_date, compatibility_flags: [],
    observability: s.observability, limits: s.limits ?? null,
    tail_consumers: s.tail_consumers ?? [] };
}

export async function deployCodeOnly({ config, sha, branch, enabled, token, code,
  unchanged, fetcher = fetch, progress = () => {} }) {
  validateTarget(config);
  const configKeys = ['$schema', 'name', 'account_id', 'main', 'compatibility_date',
    'workers_dev', 'preview_urls', 'observability', 'secrets', 'r2_buckets', 'routes'];
  if (Object.keys(config).some(k => !configKeys.includes(k)) ||
      config.main !== 'src/index.mjs' || config.compatibility_date !== '2026-06-16') {
    fail('New Worker configuration requires code-only deployment review');
  }
  if (!/^[a-f0-9]{40}$/.test(sha) || branch !== 'main' || enabled !== 'true' ||
      typeof token !== 'string' || !token || typeof code !== 'string' || !code.trim() ||
      Buffer.byteLength(code) > 1024 * 1024 || !unchanged()) fail('Invalid code-only deployment inputs');

  async function request(path, stage, body) {
    const allowedGet = [environment, `${environment}/bindings`, `${environment}/subdomain`,
      `${script}/versions`, `${script}/deployments`].includes(path) ||
      (path.startsWith(`${script}/versions/`) && uuid.test(path.slice(`${script}/versions/`.length)));
    const allowedPost = [`${script}/versions?bindings_inherit=strict`, `${script}/deployments`].includes(path);
    if ((body === undefined && !allowedGet) || (body !== undefined && !allowedPost)) fail('API path is outside code-only deployment scope');
    let response, payload;
    try {
      response = await fetcher(base + path, { method: body === undefined ? 'GET' : 'POST',
        headers: { Authorization: `Bearer ${token}`, ...(body && !(body instanceof FormData) ?
          { 'Content-Type': 'application/json' } : {}) },
        body: body === undefined ? undefined : body instanceof FormData ? body : JSON.stringify(body),
        redirect: 'error', signal: AbortSignal.timeout(60000) });
      let size = 0; const chunks = [];
      for await (const chunk of response.body) {
        size += chunk.length;
        if (size > 1024 * 1024) throw new Error('Bounded response exceeded');
        chunks.push(chunk);
      }
      payload = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    } catch {
      // No automatic retry after a possible write. Never expose fetch errors or bodies.
      fail(`${stage}: response uncertain; inspect current versions/deployments before retrying`);
    }
    if (!response.ok || payload?.success !== true) {
      const codes = (Array.isArray(payload?.errors) ? payload.errors : []).map(e => e?.code)
        .filter(c => Number.isInteger(c) && c >= 0 && c <= 999999).slice(0,8);
      fail(`${stage}: API HTTP ${response.status}; codes ${codes.join(',') || 'unavailable'}; no automatic retry`);
    }
    return payload.result;
  }

  async function configuration() {
    const bindings = bindingShape(await request(`${environment}/bindings`, 'bindings'));
    const exposure = privateSettings(await request(`${environment}/subdomain`, 'private-settings'));
    const runtime = runtimeSettings(await request(environment, 'runtime-settings'), config);
    return JSON.stringify({ bindings, exposure, runtime });
  }
  const before = deployments(await request(`${script}/deployments`, 'preflight'));
  const active = singleActive(before);
  const settings = await configuration();
  // Inherit is relative to the latest upload, not the active version. A previously
  // failed/unreviewed upload therefore requires explicit reconciliation first.
  if (latestVersion(await request(`${script}/versions`, 'latest-before-upload')) !== active) {
    fail('An inactive version exists; reconcile it before another upload');
  }
  if (!unchanged()) fail('Source changed before upload');
  const metadata = { main_module: 'index.js', compatibility_date: config.compatibility_date,
    compatibility_flags: [], bindings: [
      { name: 'INSTALLERS', type: 'inherit' }, { name: 'DOWNLOAD_GATEWAY_SECRET', type: 'inherit' }],
    annotations: { 'workers/tag': sha, 'workers/commit_sha': sha, 'workers/message': `Reviewed source ${sha}` } };
  const form = new FormData();
  form.set('metadata', new Blob([JSON.stringify(metadata)], { type: 'application/json' }));
  form.set('index.js', new Blob([code], { type: 'application/javascript+module' }), 'index.js');
  const upload = await request(`${script}/versions?bindings_inherit=strict`, 'upload', form);
  const versionId = upload?.id;
  if (!uuid.test(versionId ?? '') || versionId === active) fail('Invalid upload receipt; inspect versions before retrying');
  progress({ stage: 'uploaded-not-active', source: sha, versionId });
  const uploaded = await request(`${script}/versions/${versionId}`, 'uploaded-version-readback');
  if (uploaded?.id !== versionId || uploaded.annotations?.['workers/tag'] !== sha ||
      ![config.compatibility_date, `${config.compatibility_date}T00:00:00Z`]
        .includes(uploaded.resources?.script_runtime?.compatibility_date) ||
      (uploaded.resources?.script_runtime?.compatibility_flags ?? []).length) {
    fail('Uploaded version does not match approved source/runtime; no activation');
  }
  bindingShape(uploaded.resources?.bindings);
  if (latestVersion(await request(`${script}/versions`, 'latest-after-upload')) !== versionId ||
      JSON.stringify(deployments(await request(`${script}/deployments`, 'compare'))) !== JSON.stringify(before) ||
      await configuration() !== settings || !unchanged()) {
    fail('Source, settings or deployment changed during upload; no activation');
  }
  const activated = await request(`${script}/deployments`, 'activate', {
    strategy: 'percentage', versions: [{ version_id: versionId, percentage: 100 }],
    annotations: { 'workers/message': `Reviewed source ${sha}` },
  });
  const deploymentId = activated?.id;
  if (!uuid.test(deploymentId ?? '')) fail('Activation receipt uncertain; inspect deployments before retrying');
  progress({ stage: 'activation-received-verification-pending', source: sha, versionId, deploymentId });
  verifyActivation(JSON.stringify(deployments(await request(`${script}/deployments`, 'verify'))), deploymentId, versionId);
  if (await configuration() !== settings) fail('Post-deployment settings changed; inspect before further operations');
  return { worker, source: sha, versionId, deploymentId, traffic: 100 };
}
