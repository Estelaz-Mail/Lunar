import { cpSync, existsSync, rmSync, readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const extension = join(here, "..");
const checkout = join(extension, "..", "..");
const source = join(checkout, "lunar");
const target = join(extension, "runtime");

if (!existsSync(join(source, "cli.lua"))) {
	console.error(`  ${source} is not a Lunar checkout`);
	process.exit(1);
}

rmSync(target, { recursive: true, force: true });
mkdirSync(target, { recursive: true });
cpSync(source, join(target, "lunar"), { recursive: true });

const version = (readFileSync(join(source, "init.lua"), "utf8").match(/VERSION\s*=\s*"([^"]+)"/) ??
	[])[1];
writeFileSync(join(target, "VERSION"), `${version ?? "unknown"}\n`);

const manifest = JSON.parse(readFileSync(join(extension, "package.json"), "utf8"));
if (version && version !== manifest.version) {
	console.error(`  the framework is ${version} and the extension is ${manifest.version}`);
	process.exit(1);
}

console.log(`runtime: lunar ${version}, staged into ${target}`);
