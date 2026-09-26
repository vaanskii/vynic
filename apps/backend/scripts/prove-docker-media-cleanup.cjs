/** Only creates/removes uniquely named proof files. No DB mutations. */
const assert = require('node:assert/strict');
const { randomUUID: uuid } = require('node:crypto');
const fs = require('node:fs/promises');
const { PrismaClient } = require('@prisma/client');
const { cleanupMedia } = require('./dist/src/local-tools/customer-cleanup');
const {
  requireLocalDocker,
} = require('./dist/src/local-tools/local-docker-guard');
requireLocalDocker();
const db = new PrismaClient(),
  root = '/var/lib/vynic/media',
  dir = root + '/.local-customer-cleanup';
async function main() {
  const key = uuid() + '.webp',
    sentinel = uuid() + '.txt',
    journal = uuid() + '.json',
    failureKey = uuid() + '.webp',
    failureJournal = uuid() + '.json';
  await fs.mkdir(dir, { recursive: true, mode: 0o700 });
  try {
    await fs.writeFile(root + '/' + key, 'proof', { flag: 'wx' });
    await fs.writeFile(root + '/' + sentinel, 'unrelated proof', {
      flag: 'wx',
    });
    await fs.writeFile(
      dir + '/' + journal,
      JSON.stringify({ venueIds: [uuid()], keys: [key] }),
      { flag: 'wx', mode: 0o600 },
    );
    const result = await cleanupMedia(db, journal);
    assert.equal(result.removed, 1);
    assert.deepEqual(result.failures, []);
    await assert.rejects(fs.stat(root + '/' + key));
    await fs.stat(root + '/' + sentinel);
    console.log(
      'PASS manifest cleanup removes exactly its owned proof file and preserves unrelated file',
    );
    await fs.mkdir(root + '/' + failureKey);
    await fs.writeFile(
      dir + '/' + failureJournal,
      JSON.stringify({ venueIds: [uuid()], keys: [failureKey] }),
      { flag: 'wx', mode: 0o600 },
    );
    const failed = await cleanupMedia(db, failureJournal);
    assert.equal(failed.failures.length, 1);
    await fs.stat(dir + '/' + failureJournal);
    await fs.rmdir(root + '/' + failureKey);
    const retry = await cleanupMedia(db, failureJournal);
    assert.deepEqual(retry.failures, []);
    await assert.rejects(fs.stat(dir + '/' + failureJournal));
    console.log(
      'PASS failed file cleanup reports an error, keeps its manifest, and succeeds on retry',
    );
  } finally {
    for (const path of [
      root + '/' + key,
      root + '/' + sentinel,
      dir + '/' + journal,
      dir + '/' + failureJournal,
    ])
      await fs.unlink(path).catch((e) => {
        if (e.code !== 'ENOENT') throw e;
      });
    await fs.rmdir(root + '/' + failureKey).catch((e) => {
      if (e.code !== 'ENOENT') throw e;
    });
  }
}
main()
  .catch((e) => {
    console.error(e);
    process.exitCode = 1;
  })
  .finally(() => db.$disconnect());
