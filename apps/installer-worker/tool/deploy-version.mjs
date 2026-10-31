import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const worker = 'vynic-installer-downloads';
const account = '4347dd6103310d9273ecca7f207a0f4b';
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

export function failureDiagnostic(stage, result) {
  const text = String(result.stdout ?? '') + '\n' + String(result.stderr ?? '');
  const codes = [...text.matchAll(/\[code: ([0-9]{4,6})\]/g)].map(m => Number(m[1]));
  return {
    stage: ['preflight', 'upload', 'compare', 'activate', 'verify', 'dry-run'].includes(stage) ? stage : 'unknown',
    exit: Number.isInteger(result.status) ? result.status : null,
    diagnostic: text.includes('Aborting the upload operation because of conflicts') ? 'strict-config-conflict' :
      text.includes('Unable to fetch bindings, routes, or services metadata') ? 'dashboard-config-read-failed' :
      text.includes('required secrets have not been set') ? 'required-secret-unavailable' :
      codes.length ? 'provider-api-error' : 'provider-command-failed',
    codes: [...new Set(codes)].slice(0, 8),
  };
}

export function validateTarget(config) {
  if (config.name !== worker || config.account_id !== account ||
      config.workers_dev !== false || config.preview_urls !== false ||
      config.observability?.enabled !== true ||
      config.r2_buckets?.length !== 1 ||
      config.r2_buckets[0].binding !== 'INSTALLERS' ||
      config.r2_buckets[0].bucket_name !== 'vynic-installers' ||
      config.env || config.build ||
      JSON.stringify(config.secrets?.required) !== '["DOWNLOAD_GATEWAY_SECRET"]') {
    throw new Error('Unexpected Worker target, binding or public exposure configuration');
  }
}

export function verifyActivation(text, deploymentId, versionId) {
  const rows = JSON.parse(text);
  if (!Array.isArray(rows) || !rows.length || rows.some(row =>
    !Number.isFinite(Date.parse(row.created_on)))) throw new Error('Invalid deployment readback');
  const newest = rows.filter(row => Date.parse(row.created_on) ===
    Math.max(...rows.map(row => Date.parse(row.created_on))));
  if (newest.length !== 1 || newest[0].id !== deploymentId ||
      newest[0].versions?.length !== 1 ||
      newest[0].versions[0].version_id !== versionId ||
      newest[0].versions[0].percentage !== 100) {
    throw new Error('Latest deployment does not confirm this exact version at 100%');
  }
}

async function main() {
  const root = fileURLToPath(new URL('..', import.meta.url));
  const configPath = join(root, 'wrangler.json');
  const config = JSON.parse(readFileSync(configPath, 'utf8'));
  validateTarget(config);
  const args = process.argv.slice(2);
  if (args.length && !(args.length === 1 && args[0] === '--dry-run')) throw new Error('Unsupported arguments');
  const dry = args[0] === '--dry-run';
  const git = (args) => {
    const result = spawnSync('git', args, { cwd: root, encoding: 'utf8', timeout: 30000 });
    if (result.status !== 0) throw new Error('Cannot verify source checkout');
    return result.stdout.trim();
  };
  const sha = git(['rev-parse', 'HEAD']);
  const unchanged = () => git(['rev-parse', 'HEAD']) === sha &&
    git(['status', '--porcelain', '--untracked-files=no']) === '';
  if (!dry && !unchanged()) throw new Error('Commit reviewed source before deployment');
  if (!dry && !process.env.CLOUDFLARE_API_TOKEN) throw new Error('Worker deployment token is unavailable');
  const env = { ...process.env, WRANGLER_SEND_METRICS: 'false' };
  // Wrangler only packages locally. The official code-only API owns remote work.
  // Never give the bundler credentials, including during a real deployment.
  for (const key of Object.keys(env)) {
    if (/^(CLOUDFLARE|CF)_.*(TOKEN|KEY|EMAIL)$/.test(key)) delete env[key];
  }
  if (env.WRANGLER_CI_OVERRIDE_NAME || env.CLOUDFLARE_ENV || env.WRANGLER_ENV) {
    throw new Error('Worker name/environment overrides are not supported');
  }
  const directory = mkdtempSync(join(tmpdir(), 'vynic-worker-version-'));
  const run = (args, stage) => {
    const result = spawnSync(process.execPath,
      [resolve(root, 'node_modules/wrangler/bin/wrangler.js'), ...args, '--config', configPath],
      { cwd: root, encoding: 'utf8', timeout: 300000, maxBuffer: 4 * 1024 * 1024,
        env: { ...env, WRANGLER_OUTPUT_FILE_PATH: join(directory, `${stage}.jsonl`),
          WRANGLER_LOG_PATH: join(directory, 'wrangler.log') } });
    // Provider output can contain configuration. Never echo raw stdout/stderr.
    if (result.status !== 0) {
      console.error(JSON.stringify(failureDiagnostic(stage, result)));
      throw new Error(`${stage} did not confirm completion; inspect the Worker dashboard before retrying`);
    }
    return result.stdout;
  };
  try {
    if (dry) {
      run(['versions', 'upload', '--dry-run', '--strict', '--keep-vars', '--outdir', 'dist-version'], 'dry-run');
      console.log('Version-only package dry run passed; no upload, activation or route change');
    } else {
      run(['versions', 'upload', '--dry-run', '--strict', '--keep-vars', '--outdir', join(directory, 'bundle')], 'dry-run');
      const { deployCodeOnly } = await import('./code-only-api.mjs');
      const code = readFileSync(join(directory, 'bundle', 'index.js'), 'utf8');
      const result = await deployCodeOnly({ sha, config, unchanged, code,
        token: process.env.CLOUDFLARE_API_TOKEN,
        branch: process.env.WORKERS_CI_BRANCH,
        enabled: process.env.VYNIC_WORKER_DEPLOY_ENABLED,
        progress: event => console.log(JSON.stringify(event)) });
      console.log(JSON.stringify(result));
    }
  } finally {
    // This invocation owns only its fresh temporary provider output directory.
    rmSync(directory, { recursive: true, force: true });
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try { await main(); } catch (error) {
    // Only our fixed errors are emitted. Parsing errors never include provider payloads.
    const message = error instanceof SyntaxError ? 'Invalid provider receipt or configuration' :
      error.code ? 'Required deployment input unavailable' : error.message;
    console.error(message);
    process.exitCode = 1;
  }
}
