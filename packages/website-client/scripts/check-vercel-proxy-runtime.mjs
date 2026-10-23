import { execFileSync } from "node:child_process";
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

// Execute emitted ESM with Node, without Vite's extension-resolution fallback.
const root = fileURLToPath(new URL("../../../", import.meta.url));
const scratch = mkdtempSync(join(tmpdir(), "vynic-proxy-runtime-"));
try {
  for (const [app, route] of [
    ["platform-web", "/platform/auth/me"],
    ["restaurant-web", "/api/website/bootstrap"],
    ["vankisi-custom-web", "/api/auth/csrf"],
  ]) {
    const directory = join(root, "apps", app);
    const require = createRequire(join(directory, "package.json"));
    const compilerConfig = join(scratch, `${app}.json`);
    writeFileSync(
      compilerConfig,
      JSON.stringify({
        compilerOptions: {
          rootDir: root,
          outDir: scratch,
          module: "NodeNext",
          moduleResolution: "NodeNext",
          target: "ES2023",
          strict: true,
          skipLibCheck: true,
          esModuleInterop: true,
          noEmitOnError: true,
          types: ["node"],
          typeRoots: [join(directory, "node_modules/@types")],
        },
        files: [join(directory, "proxy.ts")],
      }),
    );
    execFileSync(
      process.execPath,
      [require.resolve("typescript/bin/tsc"), "--project", compilerConfig],
      { cwd: directory, stdio: "inherit" },
    );
    for (const relative of [
      "package.json",
      "packages/website-client/package.json",
      `apps/${app}/package.json`,
    ]) {
      if (!existsSync(join(root, relative))) continue;
      const target = join(scratch, relative);
      mkdirSync(join(target, ".."), { recursive: true });
      writeFileSync(target, readFileSync(join(root, relative)));
    }
    symlinkSync(
      join(directory, "node_modules"),
      join(scratch, "apps", app, "node_modules"),
      "dir",
    );
    const entrypoint = pathToFileURL(
      join(scratch, "apps", app, "proxy.js"),
    ).href;
    const program = `
      const { default: proxy } = await import(${JSON.stringify(entrypoint)});
      const request = new Request(${JSON.stringify(`https://runtime.example.invalid${route}?cursor=a%2Fb`)}, { headers: { host: 'runtime.example.invalid', 'x-vercel-forwarded-for': '203.0.113.21' } });
      const result = await proxy(request);
      if (result.headers.get('x-middleware-rewrite') !== ${JSON.stringify(`https://api.vynic.ge${route}?cursor=a%2Fb`)}) throw new Error('Runtime rewrite failed');
      if (result.headers.get('x-middleware-request-x-vynic-web-proxy-host') !== 'runtime.example.invalid') throw new Error('Runtime host failed');
    `;
    execFileSync(process.execPath, ["--input-type=module", "--eval", program], {
      cwd: scratch,
      env: {
        ...process.env,
        VYNIC_WEB_PROXY_SECRET:
          "synthetic-runtime-test-secret-without-live-access",
      },
      stdio: "inherit",
    });
    console.log(`${app}: emitted Node ESM proxy passed`);
  }
} finally {
  rmSync(scratch, { recursive: true, force: true });
}
