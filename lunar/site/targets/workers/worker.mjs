// The Cloudflare Workers entry point.
//
// The whole app — the framework, every component, every probe and the route
// table — is one Lua file, `app.lua`, imported here as text. Fengari is
// a Lua virtual machine written in JavaScript, so the Worker runs that file
// directly: no WebAssembly, no toolchain, and the same code that runs behind
// the HTTP server in `lunar/http/`.
//
// This file is copied verbatim by `lunar workers`. It is yours to edit
// afterwards — put a binding, a cache or an auth check in `fetch` below — but
// regenerating overwrites it, so keep anything you add somewhere else or pass
// `--no-entry`.

import { lua, lauxlib, lualib, to_luastring } from "fengari";
import source from "./app.lua";

/**
 * One Lua state per isolate, built on the first request and reused.
 *
 * It holds no request state: the app's caches are the route table and the
 * compiled components, which are the same for every request. What is per
 * request lives on the request object inside Lua and is gone when the call
 * returns. Building it costs a few milliseconds, which is why it is not built
 * per request.
 */
let state = null;

function boot() {
	const L = lauxlib.luaL_newstate();
	lualib.luaL_openlibs(L);

	if (
		lauxlib.luaL_loadbuffer(L, to_luastring(source), null, to_luastring("@app.lua")) !==
		lua.LUA_OK
	) {
		throw new Error(`lunar: the app did not load: ${lua.lua_tojsstring(L, -1)}`);
	}
	if (lua.lua_pcall(L, 0, 1, 0) !== lua.LUA_OK) {
		throw new Error(`lunar: the app did not start: ${lua.lua_tojsstring(L, -1)}`);
	}
	lua.lua_setglobal(L, to_luastring("LUNAR_FETCH"));
	return L;
}

/**
 * Calls into Lua with a request and gets a response back, both as JSON.
 *
 * The call is synchronous and the isolate is single-threaded, so one state is
 * safe: nothing can interleave between the push and the pop.
 */
function dispatch(L, payload) {
	lua.lua_getglobal(L, to_luastring("LUNAR_FETCH"));
	lua.lua_pushstring(L, to_luastring(JSON.stringify(payload)));
	const status = lua.lua_pcall(L, 1, 1, 0);
	const result = lua.lua_tojsstring(L, -1);
	lua.lua_pop(L, 1);
	if (status !== lua.LUA_OK) throw new Error(`lunar: ${result}`);
	return JSON.parse(result);
}

/** The headers Lunar needs to see, lowercased, as a plain object. */
function headersOf(request) {
	const out = {};
	for (const [name, value] of request.headers) out[name.toLowerCase()] = value;
	return out;
}

/** A body, for the methods that have one. */
async function bodyOf(request) {
	if (request.method === "GET" || request.method === "HEAD") return null;
	const type = request.headers.get("content-type") ?? "";
	// Lunar's endpoints read forms and JSON; anything else is handed over as
	// text and a handler that wants bytes should not be a Lunar route.
	if (
		type.includes("application/json") ||
		type.includes("application/x-www-form-urlencoded") ||
		type.startsWith("text/")
	) {
		return await request.text();
	}
	return null;
}

export default {
	async fetch(request, env, ctx) {
		// Static files are served by the platform, not by the app: the assets
		// binding answers for everything under public/, which is where the
		// stylesheet, the client bundle and Fengari were published.
		//
		// Only for GET and HEAD. There is no asset to find for a POST, and
		// handing the request to the binding consumes its body — which the
		// app then cannot read.
		if (env.ASSETS && (request.method === "GET" || request.method === "HEAD")) {
			const asset = await env.ASSETS.fetch(request);
			if (asset.status !== 404) return asset;
		}

		try {
			state = state ?? boot();
			const response = dispatch(state, {
				method: request.method,
				url: request.url,
				headers: headersOf(request),
				body: await bodyOf(request),
				ip: request.headers.get("cf-connecting-ip"),
			});

			return new Response(response.status === 204 ? null : response.body, {
				status: response.status,
				headers: response.headers,
			});
		} catch (error) {
			// A throw here means the Lua state is suspect — a failed boot, or a
			// panic in the middle of a call — so the next request builds a new
			// one rather than inheriting whatever this one left on the stack.
			state = null;
			console.error("lunar: request failed", error);
			return new Response("500 Internal Server Error\n", {
				status: 500,
				headers: { "Content-Type": "text/plain; charset=utf-8" },
			});
		}
	},
};
