import { test } from "bun:test";
import assert from "node:assert/strict";
import { proxyInstaller, type InstallerCache, type FetchUpstream } from "./install.ts";

function fixture(fetchUpstream: FetchUpstream) {
	const stored = new Map<string, { bytes: ArrayBuffer; headers: Headers }>();
	const pending: Promise<unknown>[] = [];
	const keys: string[] = [];
	const cache: InstallerCache = {
		async match(request) {
			keys.push(request.url);
			const cached = stored.get(request.url);
			return cached ? new Response(cached.bytes, { headers: cached.headers }) : undefined;
		},
		async put(request, response) {
			const bytes = await response.arrayBuffer();
			stored.set(request.url, {
				bytes,
				headers: new Headers(response.headers),
			});
		},
	};
	return {
		stored,
		keys,
		async request(method = "GET", query = "") {
			const response = await proxyInstaller(
				new Request(`https://lunar.estelaz.com/install.sh${query}`, { method }),
				{
					waitUntil(promise: Promise<unknown>) {
						pending.push(promise);
					},
				},
				cache,
				fetchUpstream,
			);
			const body = await response.text();
			await Promise.all(pending.splice(0));
			return { response, body };
		},
	};
}

test("streams unchanged bytes, caches success and shares query-string variants", async () => {
	let calls = 0;
	const script = "#!/bin/sh\nset -eu\nprintf 'Lua 🌙\\n'\n";
	const app = fixture(async (url, options) => {
		calls++;
		assert.equal(
			url,
			"https://raw.githubusercontent.com/Estelaz-Mail/Lunar/refs/heads/main/install.sh",
		);
		assert.ok(options);
		assert.equal(options.method, "GET");
		assert.equal(options.headers, undefined);
		assert.equal(options.redirect, "manual");
		assert.ok(options.signal instanceof AbortSignal);
		return new Response(script, {
			headers: { ETag: '"revision"', "Set-Cookie": "private=1" },
		});
	});
	const first = await app.request("GET", "?v=one");
	assert.equal(first.body, script);
	assert.equal(first.response.headers.get("X-Cache"), "MISS");
	assert.equal(first.response.headers.get("Cache-Control"), "public, max-age=300");
	assert.equal(first.response.headers.get("Content-Type"), "text/plain; charset=utf-8");
	assert.equal(first.response.headers.get("ETag"), '"revision"');
	assert.equal(first.response.headers.get("Set-Cookie"), null);
	const second = await app.request("GET", "?v=two");
	assert.equal(second.body, script);
	assert.equal(second.response.headers.get("X-Cache"), "HIT");
	assert.equal(calls, 1);
	assert.equal(app.stored.size, 1);
	assert.ok(app.keys.every((key) => key === "https://lunar.estelaz.com/install.sh"));
});

test("HEAD warms the same cache and returns no body", async () => {
	let calls = 0;
	const app = fixture(async () => {
		calls++;
		return new Response("#!/bin/sh\n");
	});
	const first = await app.request("HEAD");
	assert.equal(first.body, "");
	assert.equal(first.response.headers.get("X-Cache"), "MISS");
	assert.equal((await app.request()).body, "#!/bin/sh\n");
	const cachedHead = await app.request("HEAD");
	assert.equal(cachedHead.body, "");
	assert.equal(cachedHead.response.headers.get("X-Cache"), "HIT");
	assert.equal(calls, 1);
});

test("upstream errors are not cached and the next request retries", async () => {
	let calls = 0;
	const app = fixture(async () =>
		++calls === 1 ? new Response("Not found", { status: 404 }) : new Response("#!/bin/sh\n"),
	);
	const failed = await app.request();
	assert.equal(failed.response.status, 502);
	assert.equal(failed.response.headers.get("Cache-Control"), "no-store");
	assert.equal(app.stored.size, 0);
	assert.equal((await app.request()).response.status, 200);
	assert.equal(calls, 2);
});

test("network failures return an uncached 502, also for HEAD", async () => {
	const app = fixture(async () => {
		throw new Error("upstream timeout");
	});
	for (const method of ["GET", "HEAD"]) {
		const result = await app.request(method);
		assert.equal(result.response.status, 502);
		assert.equal(result.response.headers.get("Cache-Control"), "no-store");
		if (method === "HEAD") assert.equal(result.body, "");
	}
	assert.equal(app.stored.size, 0);
});

test("unsupported methods do not fetch or cache", async () => {
	const app = fixture(async () => {
		throw new Error("must not fetch");
	});
	const result = await app.request("POST");
	assert.equal(result.response.status, 405);
	assert.equal(result.response.headers.get("Allow"), "GET, HEAD");
	assert.equal(app.keys.length, 0);
});

test("cache failure still delivers the upstream script", async () => {
	const pending: Promise<unknown>[] = [];
	const response = await proxyInstaller(
		new Request("https://lunar.estelaz.com/install.sh"),
		{
			waitUntil(promise: Promise<unknown>) {
				pending.push(promise);
			},
		},
		{
			async match() {
				throw new Error("cache unavailable");
			},
			async put() {
				throw new Error("cache unavailable");
			},
		},
		async () => new Response("#!/bin/sh\n"),
	);
	assert.equal(response.status, 200);
	assert.equal(await response.text(), "#!/bin/sh\n");
	await Promise.all(pending);
});
