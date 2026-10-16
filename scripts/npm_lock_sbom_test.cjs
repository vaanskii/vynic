const test = require("node:test"),
  assert = require("node:assert/strict"),
  fs = require("node:fs"),
  os = require("node:os"),
  path = require("node:path"),
  { spawnSync } = require("node:child_process");
const helper = path.join(__dirname, "npm_lock_sbom.cjs");
const npmCli =
  process.env.NPM_CLI ||
  process.env.npm_execpath ||
  (process.env.PATH || "")
    .split(path.delimiter)
    .map((dir) => path.join(dir, "npm"))
    .find((file) => fs.existsSync(file));
if (!npmCli)
  throw new Error("An existing npm CLI is required; set NPM_CLI or PATH");
const npmRoot = path.dirname(path.dirname(fs.realpathSync(npmCli)));
function fixture(extra = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "sbom-scope-"));
  const pkg = {
    name: "private-test-root",
    version: "1.0.0",
    dependencies: { runtime: "1.0.0" },
    devDependencies: { tool: "1.0.0" },
  };
  const lock = {
    name: pkg.name,
    version: pkg.version,
    lockfileVersion: 3,
    packages: {
      "": pkg,
      "node_modules/runtime": {
        version: "1.0.0",
        dependencies: { shared: "1.0.0" },
        ...extra,
      },
      "node_modules/tool": {
        version: "1.0.0",
        dev: true,
        dependencies: { shared: "1.0.0" },
      },
      "node_modules/shared": { version: "1.0.0" },
    },
  };
  fs.writeFileSync(root + "/package.json", JSON.stringify(pkg));
  fs.writeFileSync(root + "/package-lock.json", JSON.stringify(lock));
  return root;
}
test("production retains a dependency shared with development tools", () => {
  const root = fixture();
  try {
    const r = spawnSync(
      process.execPath,
      [helper, root, npmRoot, "production"],
      { encoding: "utf8" },
    );
    assert.equal(r.status, 0, r.stderr);
    const b = JSON.parse(r.stdout),
      names = b.components.map((x) => x.name);
    assert(names.includes("runtime"));
    assert(names.includes("shared"));
    assert(!names.includes("tool"));
  } finally {
    fs.rmSync(root, { recursive: true });
  }
});
test("build includes both root scopes with exact locked versions", () => {
  const root = fixture();
  try {
    const r = spawnSync(process.execPath, [helper, root, npmRoot, "build"], {
      encoding: "utf8",
    });
    assert.equal(r.status, 0, r.stderr);
    const b = JSON.parse(r.stdout);
    for (const name of ["runtime", "shared", "tool"])
      assert(
        b.components.some((x) => x.name === name && x.version === "1.0.0"),
      );
  } finally {
    fs.rmSync(root, { recursive: true });
  }
});
test("required children of an optional package are not silently omitted", () => {
  const root = fixture({ optional: true, dependencies: { missing: "1.0.0" } });
  try {
    const before = fs.readFileSync(root + "/package-lock.json");
    const r = spawnSync(process.execPath, [helper, root, npmRoot, "build"], {
      encoding: "utf8",
    });
    assert.notEqual(r.status, 0);
    assert.match(r.stderr, /missing dependency missing/);
    assert.deepEqual(fs.readFileSync(root + "/package-lock.json"), before);
  } finally {
    fs.rmSync(root, { recursive: true });
  }
});

test("build refuses a missing declared development dependency", () => {
  const root = fixture();
  try {
    const lockPath = path.join(root, "package-lock.json");
    const lock = JSON.parse(fs.readFileSync(lockPath, "utf8"));
    delete lock.packages["node_modules/tool"];
    fs.writeFileSync(lockPath, JSON.stringify(lock));
    const result = spawnSync(
      process.execPath,
      [helper, root, npmRoot, "build"],
      { encoding: "utf8" },
    );
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /missing dependency tool/);
    const runtime = spawnSync(
      process.execPath,
      [helper, root, npmRoot, "production"],
      { encoding: "utf8" },
    );
    assert.equal(runtime.status, 0, runtime.stderr);
  } finally {
    fs.rmSync(root, { recursive: true });
  }
});
