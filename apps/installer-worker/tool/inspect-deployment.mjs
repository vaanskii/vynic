/** Read-only diagnosis of the exact API reads used by pinned Wrangler 4.156.0.
 * Only fixed labels, booleans, numeric status/error codes and validated version
 * IDs are emitted. Never return provider messages, binding values or bodies.
 */
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { validateTarget } from './deploy-version.mjs';

const prefix = '/accounts/4347dd6103310d9273ecca7f207a0f4b/workers';
const worker = 'vynic-installer-downloads';
const service = `${prefix}/services/${worker}`;
const environment = `${service}/environments/production`;
const script = `${prefix}/scripts/${worker}`;
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
export const reads = Object.freeze([
  ['service', service],
  ['bindings', `${environment}/bindings`],
  ['routes', `${environment}/routes?show_zonename=true`],
  ['domains', `${prefix}/domains/records?page=0&per_page=5&service=${worker}&environment=production`],
  ['subdomain', `${environment}/subdomain`],
  ['environment', environment],
  ['schedules', `${script}/schedules`],
  ['versions', `${script}/versions`],
  ['deployments', `${script}/deployments`],
]);

export function summarize(label, status, body) {
  const result = { read: label, status, success: body?.success === true,
    codes: (Array.isArray(body?.errors) ? body.errors : [])
      .map(e => e?.code).filter(c => Number.isInteger(c) && c >= 0 && c <= 999999).slice(0, 8) };
  if (!result.success || status !== 200) return result;
  const value = body.result;
  if (label === 'service') {
    const current = value?.default_environment;
    result.production = current?.environment === 'production';
    result.lastSource = ['dash', 'api', 'wrangler'].includes(current?.script?.last_deployed_from)
      ? current.script.last_deployed_from : 'other';
  } else if (label === 'bindings' && Array.isArray(value)) {
    result.count = value.length;
    result.expectedR2 = value.some(b => b.name === 'INSTALLERS' && b.type === 'r2_bucket' && b.bucket_name === 'vynic-installers');
    result.expectedSecret = value.some(b => b.name === 'DOWNLOAD_GATEWAY_SECRET' && b.type === 'secret_text');
    result.otherBindings = value.filter(b => !['INSTALLERS', 'DOWNLOAD_GATEWAY_SECRET'].includes(b.name)).length;
  } else if (label === 'environment') {
    const s = value?.script;
    result.compatibilityDateMatches = s?.compatibility_date === '2026-06-16';
    result.compatibilityFlagsEmpty = Array.isArray(s?.compatibility_flags) && s.compatibility_flags.length === 0;
    result.observabilityEnabled = s?.observability?.enabled === true;
    result.logsEnabled = s?.observability?.logs?.enabled === true;
    result.invocationLogs = s?.observability?.logs?.invocation_logs === true;
    result.persistLogs = s?.observability?.logs?.persist === true;
    result.tracesEnabled = s?.observability?.traces?.enabled === true;
    result.hasLimits = !!s?.limits && Object.keys(s.limits).length > 0;
    result.hasTailConsumers = Array.isArray(s?.tail_consumers) && s.tail_consumers.length > 0;
  } else if (label === 'subdomain') {
    result.workersDevEnabled = value?.enabled === true;
    result.previewsEnabled = value?.previews_enabled === true;
  } else if (label === 'routes' && Array.isArray(value)) {
    result.count = value.length;
    result.expectedRoutePresent = value.some(r => r.pattern === 'releases.vynic.ge/windows/access/*');
  } else if (label === 'domains') {
    result.count = Array.isArray(value) ? value.length : null;
  } else if (label === 'schedules') {
    result.count = Array.isArray(value?.schedules) ? value.schedules.length : null;
  } else if (label === 'versions') {
    const items = Array.isArray(value) ? value : value?.items;
    result.versions = Array.isArray(items) ? items.slice(0, 20).map(v => ({
      id: uuid.test(v.id ?? '') ? v.id : null,
      failedRunSource: v.annotations?.['workers/tag'] === '352749a44a61c87c334b2489681f72dcf2ed3115',
    })) : null;
  } else if (label === 'deployments') {
    const items = Array.isArray(value) ? value : value?.deployments;
    result.deployments = (Array.isArray(items) ? items : []).slice(0, 10).map(d => ({
      id: uuid.test(d.id ?? '') ? d.id : null,
      versions: Array.isArray(d.versions) ? d.versions.map(v => ({
        id: uuid.test(v.version_id ?? '') ? v.version_id : null,
        percentage: typeof v.percentage === 'number' && v.percentage >= 0 && v.percentage <= 100 ? v.percentage : null,
      })) : null,
    }));
  }
  return result;
}

export async function inspectDeployment({ token, fetcher = fetch }) {
  if (typeof token !== 'string' || !token) throw new Error('Worker token unavailable');
  const reports = [];
  for (const [label, path] of reads) {
    try {
      const response = await fetcher(`https://api.cloudflare.com/client/v4${path}`, {
        method: 'GET', headers: { Authorization: `Bearer ${token}` },
        redirect: 'error', signal: AbortSignal.timeout(15000),
      });
      // Provider bodies can include sensitive config. Bound memory, never log.
      let size = 0; const chunks = [];
      for await (const chunk of response.body) {
        size += chunk.length;
        if (size > 256 * 1024) throw new Error('Response limit');
        chunks.push(chunk);
      }
      const body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
      reports.push(summarize(label, response.status, body));
    } catch {
      reports.push({ read: label, status: null, success: false, diagnostic: 'Read unavailable; raw response withheld' });
    }
  }
  return reports;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    if (process.argv.length !== 2) throw new Error('Unsupported arguments');
    validateTarget(JSON.parse(readFileSync(new URL('../wrangler.json', import.meta.url))));
    const reports = await inspectDeployment({ token: process.env.CLOUDFLARE_API_TOKEN });
    console.log(JSON.stringify({ mode: 'read-only-no-upload-no-activation', reports }, null, 2));
    if (reports.some(r => !r.success)) process.exitCode = 1;
  } catch {
    console.error('Read-only inspection unavailable; no upload or activation attempted');
    process.exitCode = 1;
  }
}
