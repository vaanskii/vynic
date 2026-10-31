import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

export function uploadedVersion(text) {
  const rows = text.split(/\r?\n/).filter(Boolean).map(line => JSON.parse(line));
  const receipts = rows.filter(row => row.type === 'version-upload');
  if (receipts.length !== 1) throw new Error('Expected exactly one Worker upload receipt');
  const receipt = receipts[0];
  if (receipt.version !== 1 || receipt.worker_name !== 'vynic-installer-downloads' ||
      receipt.worker_name_overridden !== false ||
      (receipt.wrangler_environment !== undefined && receipt.wrangler_environment !== '') ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(receipt.version_id ?? '')) {
    throw new Error('Unexpected Worker upload identity');
  }
  return receipt.version_id;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    if (process.argv.length !== 3) throw new Error();
    process.stdout.write(uploadedVersion(readFileSync(process.argv[2], 'utf8')) + '\n');
  } catch {
    // Never echo raw provider output, file contents or argument values.
    process.stderr.write('Invalid Worker upload receipt; activation stopped\n');
    process.exitCode = 1;
  }
}
