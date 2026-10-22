import { lua, lauxlib, lualib, to_luastring } from "fengari";
import source from "./app.lua";

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

function dispatch(L, payload) {
	lua.lua_getglobal(L, to_luastring("LUNAR_FETCH"));
	lua.lua_pushstring(L, to_luastring(JSON.stringify(payload)));
	const status = lua.lua_pcall(L, 1, 1, 0);
	const result = lua.lua_tojsstring(L, -1);
	lua.lua_pop(L, 1);
	if (status !== lua.LUA_OK) throw new Error(`lunar: ${result}`);
	return JSON.parse(result);
}

function headersOf(request) {
	const out = {};
	for (const [name, value] of request.headers) out[name.toLowerCase()] = value;
	return out;
}

async function bodyOf(request) {
	if (request.method === "GET" || request.method === "HEAD") return null;
	const type = request.headers.get("content-type") ?? "";
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
			state = null;
			console.error("lunar: request failed", error);
			return new Response("500 Internal Server Error\n", {
				status: 500,
				headers: { "Content-Type": "text/plain; charset=utf-8" },
			});
		}
	},
};
