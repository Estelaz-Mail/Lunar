import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { Transpiler } from "bun";
import { test } from "bun:test";
import { LuaRuntime, fetchVerified, type LuaRuntimeOptions } from "../runtime/bridge.ts";

const module = await WebAssembly.compile(
	readFileSync(new URL("../static/runtime/lua54.wasm", import.meta.url)),
);

test("distributed TypeScript assets match their typed sources", () => {
	for (const name of ["boot.ts", "bridge.ts"]) {
		const source = readFileSync(new URL(`../runtime/${name}`, import.meta.url), "utf8");
		const artifact: unknown = JSON.parse(
			readFileSync(
				new URL(`../static/runtime/${name.replace(/\.ts$/, ".json")}`, import.meta.url),
				"utf8",
			),
		);
		assert.ok(record(artifact) && typeof artifact.source === "string");
		const executable = artifact.source;
		assert.equal(
			executable,
			new Transpiler({ loader: "ts", target: "browser" }).transformSync(source),
			name,
		);
	}
});

test("SHA-256 rejects altered runtime, application, index and Wasm bytes", async () => {
	let content = new TextEncoder().encode("trusted resource");
	const server = Bun.serve({
		port: 0,
		hostname: "127.0.0.1",
		fetch: (_request: Request): Response => new Response(content),
	});
	try {
		const trusted = content.slice();
		const hash =
			"sha256-" +
			btoa(String.fromCharCode(...new Uint8Array(await crypto.subtle.digest("SHA-256", trusted))));
		for (const path of [
			"runtime/boot",
			"runtime/bridge",
			"runtime/lua54.wasm",
			"moonlight.lua",
			"wasm/index.json",
			"wasm/geometry.wasm",
		]) {
			content = trusted.slice();
			const url = new URL(path, server.url);
			assert.deepEqual(new Uint8Array(await fetchVerified(url, hash)), trusted);
			content[0] = (content[0] ?? 0) ^ 1;
			await assert.rejects(fetchVerified(url, hash), /integrity mismatch/);
		}
		await assert.rejects(fetchVerified(server.url, ""), /invalid SHA-256/);
		await assert.rejects(fetchVerified(server.url, "md5-invalid"), /invalid SHA-256/);
		await assert.rejects(
			LuaRuntime.create({ url: server.url, integrity: hash }),
			/integrity mismatch/,
		);
	} finally {
		await server.stop(true);
	}
});

function record(value: unknown): value is Record<string, unknown> {
	return typeof value === "object" && value !== null;
}

async function withRuntime(
	fn: (runtime: LuaRuntime) => unknown | Promise<unknown>,
	options: LuaRuntimeOptions = {},
) {
	const runtime = await LuaRuntime.create({ module, ...options });
	try {
		await fn(runtime);
	} finally {
		runtime.close();
	}
}

test("Lua 5.4 language, standard libraries, integers and bytecode", () =>
	withRuntime((runtime) => {
		assert.equal(
			runtime.evaluate(`
assert(_VERSION == "Lua 5.4")
assert(math.maxinteger == 9223372036854775807)
assert((1 << 60) | 3 == 1152921504606846979)
assert(utf8.len("Lua 🌙") == 5)
local copy = assert(load(string.dump(function(x) return x + 1 end)))
assert(copy(41) == 42)
assert(table.concat(table.pack("a", "b")) == "ab")
assert(type(debug.getinfo(copy)) == "table")
local object = setmetatable({}, {__index = function(_, key) return key end})
assert(object.answer == "answer")
return 9223372036854775807
`),
			9223372036854775807n,
		);
	}));

test("to-be-closed variables, errors and yielding coroutines", () =>
	withRuntime((runtime) => {
		assert.equal(
			runtime.evaluate(`
local closed = 0
local function work()
  local resource <close> = setmetatable({}, {__close=function(_, error) closed=closed+1 end})
  error("expected")
end
assert(not pcall(work))
assert(closed == 1)
local thread = coroutine.create(function()
  local resource <close> = setmetatable({}, {__close=function() closed=closed+1 end})
  coroutine.yield(21)
  return 42
end)
local ok, first = coroutine.resume(thread)
assert(ok and first == 21)
assert(coroutine.close(thread))
assert(closed == 2)
collectgarbage("collect")
return closed
`),
			2,
		);
		assert.throws(() => runtime.evaluate('error("recoverable")'), /recoverable/);
		assert.equal(runtime.evaluate("return 42"), 42);
	}));

test("JavaScript identity, Unicode, null, properties, receivers and callbacks", () =>
	withRuntime((runtime) => {
		const add = runtime.evaluateFunction(`
local js = require("js")
assert(js.global.Object == js.global.Object)
local object = js.new(js.global.Object)
object.answer = "Lua 🌙\\0!"
assert(object.answer == "Lua 🌙\\0!")
object.answer = nil
assert(object.answer == nil)
local array = js.new(js.global.Array)
array:push(21)
array:push(42)
assert(array.length == 2 and array[1] == 42)
local missing = js.global.JSON:parse("null")
assert(missing == js.null and missing ~= nil)
local ok = pcall(function() js.global.JSON:parse("{") end)
assert(not ok)
return function(value) return value + 1 end
`);
		assert.equal(add(41), 42);
	}));

test("promises call Lua after evaluation and preserve listener identity", () =>
	withRuntime(async (runtime) => {
		runtime.evaluate(`
local js = require("js")
result = 0
local callback = function(value) result = value end
local object = js.new(js.global.Object)
object.first = callback
object.second = callback
assert(object.first == object.second)
js.global.Promise:resolve(42)["then"](js.global.Promise:resolve(42), callback)
`);
		await new Promise((resolve) => setTimeout(resolve, 0));
		assert.equal(runtime.evaluate("return result"), 42);
	}));

test("closing releases the VM and prevents stale callbacks", async () => {
	const runtime = await LuaRuntime.create({ module });
	const callback = runtime.evaluateFunction("return function() return 42 end");
	runtime.close();
	runtime.close();
	assert.throws(() => callback(), /closed/);
});

test("reactive updates reach every subscriber in Lua 5.4 Wasm", () =>
	withRuntime((runtime) => {
		const source = readFileSync(new URL("../lunar/runtime/signal.lua", import.meta.url), "utf8");
		assert.equal(
			runtime.evaluate(`
local signal = assert(load([====[${source}]====]))()
local state = signal.new(0)
local seen, dispose = {}, {}
for i = 1, 32 do
  dispose[i] = signal.effect(function() seen[i] = signal.get(state) end)
end
for value = 1, 10 do
  signal.set(state, value)
  signal.invalidate(state)
  for i = 1, 32 do assert(seen[i] == value, "subscriber was skipped") end
end
for _, fn in ipairs(dispose) do fn() end
assert(next(state.subscribers) == nil)
return true
`),
			true,
		);
	}));

test("the frozen application renders identically in native Lua and Wasm", () =>
	withRuntime((runtime) => {
		const script = `
local lunar = require("lunar")
local bundle = require("lunar.site.bundle")
local json = require("lunar.core.json")
local request = require("lunar.http.request")
local app = lunar.app({root="examples/tranquility", dev=false, version="spec"})
local source = assert(bundle.server(app))
local responses = {}
for _, path in ipairs({"/", "/about", "/blog", "/blog/why-lua", "/missing"}) do
  local response = app:handler()(request.new({method="GET", target=path, headers={host="example.test"}}, {}))
  responses[path] = {status=response.status, body=response.body, headers=response.headers}
end
io.write(json.encode({source=source, responses=responses}))
`;
		const native = spawnSync(process.env.LUA ?? "lua5.4", ["-e", script], {
			cwd: new URL("../", import.meta.url),
			encoding: "utf8",
			maxBuffer: 4 * 1024 * 1024,
		});
		assert.equal(native.error, undefined);
		assert.equal(native.status, 0, native.stderr);
		const fixture: unknown = JSON.parse(native.stdout);
		assert.ok(record(fixture));
		assert.ok(typeof fixture.source === "string");
		assert.ok(record(fixture.responses));
		const fetch = runtime.evaluateFunction(fixture.source, "@app.lua");
		for (const [path, expected] of Object.entries(fixture.responses)) {
			const serialized = fetch(
				JSON.stringify({ method: "GET", url: `https://example.test${path}`, headers: {} }),
			);
			assert.ok(typeof serialized === "string");
			const actual: unknown = JSON.parse(serialized);
			assert.ok(record(actual) && record(actual.headers));
			assert.ok(record(expected) && record(expected.headers));
			assert.equal(actual.status, expected.status, path);
			assert.equal(actual.body, expected.body, path);
			assert.equal(
				actual.headers["Content-Security-Policy"],
				expected.headers["Content-Security-Policy"],
			);
		}
	}));

test("the real browser bootstrap passes verified chunk URLs and applies navigation", async () => {
	const listeners = new Map<string, unknown>();
	const requested: unknown[] = [];
	const target = {};
	const location = {
		pathname: "/",
		search: "",
		hash: "",
		href: "https://lunar.test/",
		origin: "https://lunar.test",
	};
	const global = {
		Object,
		URL,
		location,
		console: { warn() {} },
		document: {
			getElementById(id: string): object | null {
				if (id === "lunar") return target;
				if (id === "lunar-data") return { textContent: '{"route":"/","data":[]}' };
				return null;
			},
			addEventListener(name: string, listener: unknown) {
				listeners.set(name, listener);
			},
		},
		addEventListener() {},
		history: { pushState() {} },
		scrollTo() {},
		async fetch() {
			return new Response(
				JSON.stringify({ route: "/next", data: [], chunk: "/_lunar/chunk/next.lua" }),
			);
		},
		async lunarFetchVerified(url: unknown) {
			requested.push(url);
			if (typeof url !== "string") throw new TypeError("missing chunk URL");
			return new Response("chunk_evaluated = true");
		},
	};
	await withRuntime(
		async (runtime) => {
			for (const name of ["lunar/core/json.lua", "lunar/site/chunks.lua", "lunar/site/boot.lua"]) {
				const source = readFileSync(new URL(`../${name}`, import.meta.url), "utf8");
				runtime.evaluate(
					`package.preload[${JSON.stringify(name.replace(/\.lua$/, "").replaceAll("/", "."))}] = function()\n${source}\nend`,
				);
			}
			runtime.evaluate(`
package.preload["lunar.runtime.dom"] = function() return { browser = function() return {} end } end
package.preload["lunar.runtime.wasm"] = function() return {} end
package.preload["lunar.site.moonlight"] = function()
  return { start = function()
    return {
      begin_navigation = function() return 1 end,
      is_current = function() return true end,
      apply = function(_, _, payload) applied_route = payload.route; return true end,
    }
  end }
end
require("lunar.site.boot").start({})
`);
			const click = listeners.get("click");
			assert.equal(typeof click, "function");
			if (typeof click !== "function") throw new TypeError("missing click listener");
			click({
				button: 0,
				target: {
					tagName: "A",
					href: "https://lunar.test/next",
					getAttribute(name: string) {
						return name === "href" ? "/next" : null;
					},
					hasAttribute() {
						return false;
					},
				},
				preventDefault() {},
			});
			await new Promise((resolve) => setTimeout(resolve, 0));
			assert.deepEqual(requested, ["/_lunar/chunk/next.lua"]);
			assert.equal(runtime.evaluate("return chunk_evaluated"), true);
			assert.equal(runtime.evaluate("return applied_route"), "/next");
		},
		{ global },
	);
});
