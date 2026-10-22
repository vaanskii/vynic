const path = require("node:path");
const [project, npmRoot, scope] = process.argv.slice(2);
if (!project || !npmRoot || !["build", "production"].includes(scope))
  throw Error("Provide project, existing npm root and build/production scope");
const A = require(path.join(npmRoot, "node_modules/@npmcli/arborist"));
const { cyclonedxOutput } = require(
  path.join(npmRoot, "lib/utils/sbom-cyclonedx.js"),
);
const version = require(path.join(npmRoot, "package.json")).version;
(async () => {
  const tree = await new A({ path: project }).loadVirtual();
  const nodes = [...tree.inventory.values()].filter(
    (n) => scope === "build" || n.isRoot || !n.dev,
  );
  const errors = [];
  for (const node of nodes)
    for (const edge of node.edgesOut.values()) {
      if (edge.type === "dev" && scope === "production") continue;
      if (edge.missing && !["optional", "peerOptional"].includes(edge.type))
        errors.push(
          "missing dependency " + edge.name + " required by " + node.pkgid,
        );
      if (edge.invalid)
        errors.push(
          "invalid dependency " + edge.name + " required by " + node.pkgid,
        );
    }
  if (errors.length) throw Error([...new Set(errors)].join("\n"));
  const bom = cyclonedxOutput({
    npm: { version },
    nodes,
    packageType: "application",
    packageLockOnly: true,
  });
  bom.metadata.tools.push({
    vendor: "Vynic",
    name: "locked-node-flag-scope",
    version: "1",
  });
  process.stdout.write(JSON.stringify(bom, null, 2) + "\n");
})();
