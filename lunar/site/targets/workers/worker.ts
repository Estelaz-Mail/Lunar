import { LuaRuntime, type LuaFunction } from "../../../../runtime/bridge.ts";
import module from "./lua54.wasm";
import source from "./app.lua";

export interface WorkerEnv {
	ASSETS?: { fetch(request: Request): Promise<Response> };
}

export interface WorkerContext {
	waitUntil(promise: Promise<unknown>): void;
}

interface Instance {
	runtime: LuaRuntime;
	fetch: LuaFunction;
}

interface RequestPayload {
	method: string;
	url: string;
	headers: Record<string, string>;
	body: string | null;
	ip: string | null;
}

interface SerializedResponse {
	status: number;
	headers: Record<string, string>;
	body: string;
}

let state: Promise<Instance> | null = null;

async function boot() {
	const runtime = await LuaRuntime.create({ module });
	try {
		const fetch = runtime.evaluateFunction(source, "@app.lua");
		return { runtime, fetch };
	} catch (error) {
		runtime.close();
		throw error;
	}
}

function record(value: unknown): value is Record<string, unknown> {
	return typeof value === "object" && value !== null && !Array.isArray(value);
}

function dispatch(instance: Instance, payload: RequestPayload): SerializedResponse {
	const serialized = instance.fetch(JSON.stringify(payload));
	if (typeof serialized !== "string") throw new TypeError("lunar: expected a serialized response");
	const response: unknown = JSON.parse(serialized);
	if (
		!record(response) ||
		typeof response.status !== "number" ||
		!Number.isInteger(response.status) ||
		response.status < 200 ||
		response.status > 599 ||
		!record(response.headers) ||
		typeof response.body !== "string"
	) {
		throw new TypeError("lunar: malformed response from Lua");
	}
	const headers: Record<string, string> = {};
	for (const [name, value] of Object.entries(response.headers)) {
		if (typeof value !== "string") throw new TypeError(`lunar: invalid response header ${name}`);
		headers[name] = value;
	}
	return { status: response.status, headers, body: response.body };
}

function headersOf(request: Request): Record<string, string> {
	const out: Record<string, string> = {};
	for (const [name, value] of request.headers) out[name.toLowerCase()] = value;
	return out;
}

async function bodyOf(request: Request): Promise<string | null> {
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
	async fetch(request: Request, env: WorkerEnv, _ctx: WorkerContext): Promise<Response> {
		if (env.ASSETS && (request.method === "GET" || request.method === "HEAD")) {
			const asset = await env.ASSETS.fetch(request);
			if (asset.status !== 404) return asset;
		}

		try {
			const pending = (state ??= boot());
			const instance = await pending;
			const body = await bodyOf(request);
			const response = dispatch(instance, {
				method: request.method,
				url: request.url,
				headers: headersOf(request),
				body,
				ip: request.headers.get("cf-connecting-ip"),
			});

			return new Response(response.status === 204 ? null : response.body, {
				status: response.status,
				headers: response.headers,
			});
		} catch (error) {
			const failed = state;
			state = null;
			if (failed)
				failed.then(
					({ runtime }) => runtime.close(),
					() => {},
				);
			console.error("lunar: request failed", error);
			return new Response("500 Internal Server Error\n", {
				status: 500,
				headers: { "Content-Type": "text/plain; charset=utf-8" },
			});
		}
	},
};
