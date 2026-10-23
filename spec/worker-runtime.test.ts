import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "bun:test";

type FetchWorker = (
	request: Request,
	env: Record<string, unknown>,
	context: { waitUntil(promise: Promise<unknown>): void },
) => Promise<Response>;

function record(value: unknown): value is Record<string, unknown> {
	return typeof value === "object" && value !== null && !Array.isArray(value);
}

test("the actual Worker preserves bodyless statuses and HEAD responses", async () => {
	const template = readFileSync(
		new URL("../lunar/site/targets/workers/worker.ts", import.meta.url),
		"utf8",
	);
	const wasm = fileURLToPath(new URL("../static/runtime/lua54.wasm", import.meta.url));
	const directory = mkdtempSync(join(tmpdir(), "lunar-worker-audit-"));
	try {
		const bridge = new URL("../runtime/bridge.ts", import.meta.url).href;
		for (const [method, status] of [
			["GET", 200],
			["GET", 204],
			["GET", 205],
			["GET", 304],
			["HEAD", 200],
		] as const) {
			const response = JSON.stringify({ status, headers: {}, body: "response body" });
			const lua = `return function(_) return [=[${response}]=] end`;
			const source = template
				.replace('"../../../../runtime/bridge.ts"', JSON.stringify(bridge))
				.replace(
					'import module from "./lua54.wasm";',
					`import { readFileSync } from "node:fs"; const module = await WebAssembly.compile(readFileSync(${JSON.stringify(wasm)}));`,
				)
				.replace('import source from "./app.lua";', `const source = ${JSON.stringify(lua)};`);
			const path = join(directory, `worker-${method}-${status}.ts`);
			writeFileSync(path, source);
			const generated: unknown = await import(path);
			assert.ok(record(generated) && record(generated.default));
			assert.equal(typeof generated.default.fetch, "function");
			const fetch = generated.default.fetch as FetchWorker;
			const answer = await fetch(
				new Request("https://lunar.test/", { method }),
				{},
				{
					waitUntil() {},
				},
			);
			assert.equal(answer.status, status, `${method} ${status}`);
			if (method === "HEAD" || [204, 205, 304].includes(status)) {
				assert.equal(answer.body, null, `${method} ${status}`);
			} else {
				assert.equal(await answer.text(), "response body");
			}
		}
	} finally {
		rmSync(directory, { recursive: true, force: true });
	}
});
