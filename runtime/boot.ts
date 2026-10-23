import type { BrowserRuntimeFactory } from "./bridge.ts";

function record(value: unknown): value is Record<string, unknown> {
	return typeof value === "object" && value !== null && !Array.isArray(value);
}

function loadFactory(url: URL, integrity: string): Promise<BrowserRuntimeFactory> {
	return new Promise((resolve, reject) => {
		let factory: BrowserRuntimeFactory | undefined;
		const script = document.createElement("script");
		const ready = (event: Event) => {
			if (!(event instanceof CustomEvent)) return;
			const value: unknown = event.detail;
			if (
				record(value) &&
				typeof value.create === "function" &&
				typeof value.fetchVerified === "function"
			) {
				factory = value as unknown as BrowserRuntimeFactory;
			}
		};
		const cleanup = () => document.removeEventListener("lunar:runtime", ready);
		document.addEventListener("lunar:runtime", ready);
		script.type = "module";
		script.integrity = integrity;
		script.crossOrigin = "anonymous";
		script.src = url.href;
		script.onload = () => {
			cleanup();
			if (factory) resolve(factory);
			else reject(new Error("lunar: verified runtime did not register its factory"));
		};
		script.onerror = () => {
			cleanup();
			reject(new Error("lunar: runtime failed integrity verification or loading"));
		};
		document.head.appendChild(script);
	});
}

try {
	const root = new URL(import.meta.url);
	const raw: unknown = JSON.parse(
		document.getElementById("lunar-integrity")?.textContent ?? "null",
	);
	if (!record(raw) || raw.version !== 1 || !record(raw.assets))
		throw new Error("lunar: missing integrity manifest");
	const assets: Record<string, string> = {};
	for (const [path, digest] of Object.entries(raw.assets)) {
		if (
			!path.startsWith("/_lunar/") ||
			typeof digest !== "string" ||
			!/^sha256-[A-Za-z0-9+/]{43}=$/.test(digest)
		) {
			throw new Error("lunar: invalid integrity manifest");
		}
		assets[path] = digest;
	}
	Object.freeze(assets);
	const hash = (path: string): string => {
		const expected = assets[path];
		if (!expected) throw new Error(`lunar: no trusted hash for ${path}`);
		return expected;
	};
	const factory = await loadFactory(
		new URL(`bridge${root.search}`, root),
		hash("/_lunar/runtime/bridge"),
	);
	const fetchResource = async (url: string): Promise<Response> => {
		const target = new URL(url, root);
		if (target.origin !== root.origin)
			throw new Error("lunar: cross-origin runtime resource refused");
		return new Response(await factory.fetchVerified(target, hash(target.pathname)));
	};
	Object.defineProperty(globalThis, "lunarFetchVerified", {
		value: fetchResource,
		writable: false,
		configurable: false,
	});
	const page: unknown = JSON.parse(document.getElementById("lunar-data")?.textContent ?? "null");
	const chunk = record(page) && typeof page.chunk === "string" ? page.chunk : null;
	const text = (url: string): Promise<string> =>
		fetchResource(new URL(url, root).href).then((response) => response.text());

	const [runtime, source, piece] = await Promise.all([
		factory.create({
			url: new URL(`lua54.wasm${root.search}`, root),
			integrity: hash("/_lunar/runtime/lua54.wasm"),
		}),
		text(`../moonlight.lua${root.search}`),
		chunk ? text(chunk) : Promise.resolve(null),
	]);
	if (piece !== null && chunk !== null) runtime.evaluate(piece, `@${chunk}`);
	runtime.evaluate(source, "@moonlight.lua");
} catch (error) {
	console.error("lunar: the client half did not start", error);
}
