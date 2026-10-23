import { readFileSync, writeFileSync } from "node:fs";
import { Transpiler } from "bun";

const transpiler = new Transpiler({ loader: "ts", target: "browser" });

for (const name of ["boot.ts", "bridge.ts"]) {
	const source = readFileSync(new URL(name, import.meta.url), "utf8");
	const executable = transpiler.transformSync(source);
	writeFileSync(
		new URL(`../static/runtime/${name.replace(/\.ts$/, ".json")}`, import.meta.url),
		JSON.stringify({ source: executable }, null, "\t") + "\n",
	);
}
