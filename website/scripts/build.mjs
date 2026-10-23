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

// Fengari's interop uses Function for two static helpers. Equivalent closures
// let this site hydrate under Lunar's CSP without enabling unsafe-eval.
const { readFileSync, writeFileSync } = await import("node:fs");
const browserRuntime = new URL("../.lunar/workers/public/_lunar/fengari.js", import.meta.url);
let runtime = readFileSync(browserRuntime, "utf8");
for (const [before, after] of [
	['Function("t","k","delete t[k]")', "(function(t,k){return delete t[k]})"],
	['Function("return ()=>void 0;")', "(()=>()=>void 0)"],
]) {
	if (runtime.split(before).length !== 2)
		throw new Error("Fengari CSP patch no longer matches the pinned runtime");
	runtime = runtime.replace(before, after);
}
writeFileSync(browserRuntime, runtime);

// The pinned runtime mutates the subscriber table while iterating it. Snapshot
// before running effects so an update reaches every dependent view.
const subscriberLoop = "for effect in pairs(self.subscribers) do schedule(effect) end";
const stableLoop = `local subscribers = {}
  for effect in pairs(self.subscribers) do subscribers[#subscribers + 1] = effect end
  for _, effect in ipairs(subscribers) do schedule(effect) end`;
for (const relative of ["src/app.lua", "public/_lunar/moonlight.lua"]) {
	const path = new URL(`../.lunar/workers/${relative}`, import.meta.url);
	const source = readFileSync(path, "utf8");
	if (source.split(subscriberLoop).length !== 3)
		throw new Error("Lunar signal patch no longer matches the pinned runtime");
	writeFileSync(path, source.replaceAll(subscriberLoop, stableLoop));
}
