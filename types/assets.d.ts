declare module "*.wasm" {
	const module: WebAssembly.Module;
	export default module;
}

declare module "*.lua" {
	const source: string;
	export default source;
}

interface CacheStorage {
	readonly default: import("../website/worker/install.ts").InstallerCache;
}
