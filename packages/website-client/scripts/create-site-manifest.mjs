import { createHash } from "node:crypto";
import { readFile, readdir, writeFile } from "node:fs/promises";
import { resolve, relative, join } from "node:path";
import { pathToFileURL } from "node:url";

export const MANIFEST_FILENAME = "vynic-site-manifest.json";
const digest = (bytes) => createHash("sha256").update(bytes).digest("hex");

/** Fingerprint only public emitted files; never read git, env or credentials. */
export async function createSiteManifest(distDirectory, identity) {
  if (
    !["CUSTOM", "SAAS"].includes(identity?.renderer) ||
    (identity.renderer === "CUSTOM"
      ? typeof identity.siteKey !== "string" ||
        !/^[a-z0-9][a-z0-9-]{0,62}[a-z0-9]$/.test(identity.siteKey)
      : identity.siteKey !== null)
  )
    throw new Error("Use a CUSTOM app key or SAAS with a null siteKey");
  const root = resolve(distDirectory);
  const files = [];
  async function walk(directory) {
    for (const entry of await readdir(directory, { withFileTypes: true })) {
      const path = join(directory, entry.name);
      if (entry.isSymbolicLink())
        throw new Error("Emitted files cannot be symlinks");
      if (entry.isDirectory()) await walk(path);
      else if (entry.isFile()) {
        const name = relative(root, path).replaceAll("\\", "/");
        if (name !== MANIFEST_FILENAME) files.push(name);
      } else throw new Error("Only regular emitted files are supported");
    }
  }
  await walk(root);
  if (!files.includes("index.html"))
    throw new Error("Build index.html before generating a manifest");
  files.sort();
  const hash = createHash("sha256").update("vynic-site-artifact-v1\0");
  hash.update(
    JSON.stringify({ renderer: identity.renderer, siteKey: identity.siteKey }),
  );
  let htmlDigest;
  for (const name of files) {
    const bytes = await readFile(join(root, name));
    hash.update(JSON.stringify({ name, bytes: bytes.length }) + "\n");
    hash.update(bytes);
    if (name === "index.html") htmlDigest = digest(bytes);
  }
  const manifest = {
    schemaVersion: 1,
    renderer: identity.renderer,
    siteKey: identity.siteKey,
    buildId: hash.digest("hex"),
    htmlDigest,
    files: files.length,
  };
  await writeFile(
    join(root, MANIFEST_FILENAME),
    JSON.stringify(manifest, null, 2) + "\n",
  );
  return manifest;
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(resolve(process.argv[1])).href
) {
  const [dist, config, ...extra] = process.argv.slice(2);
  if (!dist || !config || extra.length)
    throw new Error("Usage: create-site-manifest.mjs <dist> <identity.json>");
  const identity = JSON.parse(await readFile(resolve(config), "utf8"));
  // Whitelist public fields, never hash arbitrary private configuration.
  const manifest = await createSiteManifest(dist, {
    renderer: identity.renderer,
    siteKey: identity.siteKey,
  });
  process.stdout.write(
    `Public ${manifest.renderer} build ${manifest.buildId}\n`,
  );
}
