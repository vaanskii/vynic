import { test } from "node:test";
import assert from "node:assert/strict";
import {
  mkdtemp,
  mkdir,
  readFile,
  writeFile,
  rm,
  symlink,
} from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import {
  createSiteManifest,
  MANIFEST_FILENAME,
} from "./create-site-manifest.mjs";

const custom = { renderer: "CUSTOM", siteKey: "custom-a-web" };
async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), "vynic-site-manifest-test-"));
  t.after(() => rm(root, { recursive: true, force: true }));
  await mkdir(join(root, "assets"));
  await writeFile(
    join(root, "index.html"),
    '<html><script src="assets/app.js"></script></html>',
  );
  await writeFile(
    join(root, "assets/app.js"),
    'console.log("synthetic public build")',
  );
  await writeFile(
    join(root, "public-image.jpg"),
    "synthetic public image bytes",
  );
  return root;
}
test("same emitted files produce the same fingerprint, including a repeated manifest write", async (t) => {
  const root = await fixture(t);
  const one = await createSiteManifest(root, custom);
  const two = await createSiteManifest(root, custom);
  assert.deepEqual(two, one);
  assert.match(one.buildId, /^[a-f0-9]{64}$/);
  assert.equal(one.files, 3);
  assert.deepEqual(
    JSON.parse(await readFile(join(root, MANIFEST_FILENAME), "utf8")),
    one,
  );
});
for (const file of ["index.html", "assets/app.js", "public-image.jpg"])
  test(`a changed emitted ${file} changes the artifact fingerprint`, async (t) => {
    const root = await fixture(t),
      before = await createSiteManifest(root, custom);
    await writeFile(join(root, file), "a changed public file");
    const after = await createSiteManifest(root, custom);
    assert.notEqual(after.buildId, before.buildId);
    assert.equal(after.htmlDigest === before.htmlDigest, file !== "index.html");
  });
test("same files with different renderer/key cannot claim the same build", async (t) => {
  const root = await fixture(t),
    one = await createSiteManifest(root, custom);
  const two = await createSiteManifest(root, {
    renderer: "CUSTOM",
    siteKey: "custom-b-web",
  });
  const saas = await createSiteManifest(root, {
    renderer: "SAAS",
    siteKey: null,
  });
  assert.notEqual(one.buildId, two.buildId);
  assert.notEqual(one.buildId, saas.buildId);
  assert.equal(saas.renderer, "SAAS");
});
test("private config and filesystem paths cannot enter public metadata or the fingerprint", async (t) => {
  const root = await fixture(t),
    one = await createSiteManifest(root, custom);
  const two = await createSiteManifest(root, {
    ...custom,
    credential: "synthetic-not-public",
  });
  assert.deepEqual(two, one);
  assert.equal(JSON.stringify(two).includes(root), false);
  assert.equal(JSON.stringify(two).includes("synthetic-not-public"), false);
});
test("invalid identities, missing HTML and symlinks fail rather than creating a plausible manifest", async (t) => {
  const root = await fixture(t);
  for (const identity of [
    { renderer: "CUSTOM", siteKey: "BAD!" },
    { renderer: "CUSTOM", siteKey: 123 },
    { renderer: "SAAS", siteKey: "custom-a-web" },
  ])
    await assert.rejects(createSiteManifest(root, identity));
  await rm(join(root, "index.html"));
  await assert.rejects(createSiteManifest(root, custom), /index.html/);
  await writeFile(join(root, "index.html"), "<html></html>");
  await symlink(join(root, "assets/app.js"), join(root, "linked-file"));
  await assert.rejects(createSiteManifest(root, custom), /symlink/);
});
