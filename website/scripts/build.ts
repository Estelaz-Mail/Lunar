import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
const root = fileURLToPath(new URL("../", import.meta.url));
const embed = spawnSync("lua5.4", ["scripts/embed-docs.lua"], {
	cwd: root,
	stdio: "inherit",
});
if (embed.error) throw embed.error;
if (embed.status !== 0) process.exit(embed.status ?? 1);
const result = spawnSync("sh", ["scripts/lunar.sh", "package"], {
	cwd: root,
	stdio: "inherit",
});
if (result.error) throw result.error;
if (result.status !== 0) process.exit(result.status ?? 1);
