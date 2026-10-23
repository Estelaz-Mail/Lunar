export interface LuaRuntimeOptions {
	module?: WebAssembly.Module;
	url?: string | URL;
	integrity?: string;
	global?: object;
	print?: (line: string) => void;
	printError?: (line: string) => void;
}

type LuaAPI = {
	memory: WebAssembly.Memory;
	_initialize(): void;
	lunar_open(): number;
	lunar_close(state: number): void;
	lunar_alloc(size: number): number;
	lunar_free(pointer: number): void;
	lunar_top(state: number): number;
	lunar_settop(state: number, index: number): void;
	lunar_type(state: number, index: number): number;
	lunar_isinteger(state: number, index: number): number;
	lunar_integer(state: number, index: number): bigint;
	lunar_number(state: number, index: number): number;
	lunar_boolean(state: number, index: number): number;
	lunar_string(state: number, index: number): number;
	lunar_length(state: number, index: number): number;
	lunar_identity(state: number, index: number): number;
	lunar_handle(state: number, index: number): number;
	lunar_pushhandle(state: number, handle: number): void;
	lunar_pushnil(state: number): void;
	lunar_pushboolean(state: number, value: number): void;
	lunar_pushnumber(state: number, value: number): void;
	lunar_pushinteger(state: number, value: bigint): void;
	lunar_pushstring(state: number, pointer: number, size: number): void;
	lunar_ref(state: number, index: number): number;
	lunar_unref(state: number, reference: number): void;
	lunar_eval(state: number, source: number, size: number, name: number): number;
	lunar_call(state: number, reference: number, count: number): number;
	lunar_index(state: number, reference: number): number;
	lunar_assign(state: number, reference: number): number;
};

type ProxyKind = "function" | "arrow_function" | "object";
type Reference = { identity: string; reference: number };
export type LuaFunction = (...args: unknown[]) => unknown;

const encoder = new TextEncoder();
const decoder = new TextDecoder();

export async function fetchVerified(url: string | URL, expected: string): Promise<ArrayBuffer> {
	if (!/^sha256-[A-Za-z0-9+/]{43}=$/.test(expected))
		throw new Error("lunar: missing or invalid SHA-256 integrity");
	const response = await fetch(url, { redirect: "error", credentials: "same-origin" });
	if (!response.ok) throw new Error(`lunar: resource returned HTTP ${response.status}`);
	const bytes = await response.arrayBuffer();
	const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
	const actual = "sha256-" + btoa(String.fromCharCode(...digest));
	if (actual !== expected) throw new Error(`lunar: integrity mismatch for ${String(url)}`);
	return bytes;
}

export interface BrowserRuntimeFactory {
	create(options: LuaRuntimeOptions): Promise<LuaRuntime>;
	fetchVerified: typeof fetchVerified;
}

export class LuaRuntime {
	api!: LuaAPI;
	state = 0;
	output: (line: string) => void;
	errorOutput: (line: string) => void;
	handles: Map<number, unknown>;
	identities: WeakMap<object, number>;
	nextHandle: number;
	references: Map<string, { weak: WeakRef<object>; reference: number }>;
	luaProxies: WeakMap<object, { reference: number; callable: boolean }>;
	finalizers: FinalizationRegistry<Reference>;

	static async create(options: LuaRuntimeOptions = {}) {
		const runtime = new LuaRuntime(options);
		let module = options.module;
		if (!module) {
			const bytes = await fetchVerified(
				options.url ?? new URL("lua54.wasm", import.meta.url),
				options.integrity ?? "",
			);
			module = await WebAssembly.compile(bytes);
		}
		const instance = await WebAssembly.instantiate(module, runtime.imports());
		runtime.api = instance.exports as unknown as LuaAPI;
		runtime.api._initialize();
		runtime.state = runtime.api.lunar_open();
		if (!runtime.state) throw new Error("lunar: could not allocate a Lua state");
		return runtime;
	}

	constructor(options: LuaRuntimeOptions) {
		this.output = options.print ?? console.log;
		this.errorOutput = options.printError ?? console.error;
		const hostGlobal = options.global ?? globalThis;
		this.handles = new Map<number, unknown>([
			[0, null],
			[1, hostGlobal],
		]);
		this.identities = new WeakMap();
		this.identities.set(hostGlobal, 1);
		this.nextHandle = 2;
		this.references = new Map();
		this.luaProxies = new WeakMap();
		this.finalizers = new FinalizationRegistry(({ identity, reference }) => {
			if (!this.state) return;
			this.api.lunar_unref(this.state, reference);
			if (this.references.get(identity)?.reference === reference) this.references.delete(identity);
		});
	}

	imports(): WebAssembly.Imports {
		return {
			env: {
				emscripten_notify_memory_growth() {},
				__syscall_dup3: () => -52,
				__syscall_unlinkat: () => -52,
				__syscall_rmdir: () => -52,
				__syscall_renameat: () => -52,
				__syscall_readlinkat: () => -52,
				_emscripten_system: () => -52,
			},
			lunar: {
				host: (state: number, operation: number, handle: number) =>
					this.host(state, operation, handle),
			},
			wasi_snapshot_preview1: {
				proc_exit: (code: number) => {
					throw new Error(`lunar: Lua exited with status ${code}`);
				},
				fd_close: () => 8,
				fd_seek: () => 8,
				fd_read: (_fd: number, _vectors: number, _count: number, read: number) => {
					new DataView(this.api.memory.buffer).setUint32(read, 0, true);
					return 0;
				},
				fd_write: (fd: number, vectors: number, count: number, written: number) => {
					const view = new DataView(this.api.memory.buffer);
					let size = 0;
					const parts = [];
					for (let i = 0; i < count; i++) {
						const pointer = view.getUint32(vectors + i * 8, true);
						const length = view.getUint32(vectors + i * 8 + 4, true);
						parts.push(this.bytes.slice(pointer, pointer + length));
						size += length;
					}
					const data = new Uint8Array(size);
					let offset = 0;
					for (const part of parts) {
						data.set(part, offset);
						offset += part.length;
					}
					(fd === 2 ? this.errorOutput : this.output)(decoder.decode(data).replace(/\n$/, ""));
					view.setUint32(written, size, true);
					return 0;
				},
				environ_sizes_get: (count: number, size: number) => {
					const view = new DataView(this.api.memory.buffer);
					view.setUint32(count, 0, true);
					view.setUint32(size, 0, true);
					return 0;
				},
				environ_get: () => 0,
				clock_time_get: (_clock: number, _precision: bigint, pointer: number) => {
					new DataView(this.api.memory.buffer).setBigUint64(
						pointer,
						BigInt(Date.now()) * 1000000n,
						true,
					);
					return 0;
				},
			},
		};
	}

	get bytes() {
		return new Uint8Array(this.api.memory.buffer);
	}

	allocate(value: string) {
		const bytes = encoder.encode(value);
		const pointer = this.api.lunar_alloc(bytes.length + 1);
		if (!pointer) throw new Error("lunar: Lua memory exhausted");
		this.bytes.set(bytes, pointer);
		this.bytes[pointer + bytes.length] = 0;
		return { pointer, size: bytes.length };
	}

	string(state: number, index: number) {
		const pointer = this.api.lunar_string(state, index);
		return decoder.decode(
			this.bytes.subarray(pointer, pointer + this.api.lunar_length(state, index)),
		);
	}

	push(state: number, value: unknown) {
		const api = this.api;
		if (value === undefined) api.lunar_pushnil(state);
		else if (typeof value === "boolean") api.lunar_pushboolean(state, Number(value));
		else if (typeof value === "number") {
			if (Number.isSafeInteger(value)) api.lunar_pushinteger(state, BigInt(value));
			else api.lunar_pushnumber(state, value);
		} else if (typeof value === "bigint") {
			if (value < -(1n << 63n) || value >= 1n << 63n)
				throw new RangeError("lunar: integer exceeds Lua's 64-bit range");
			api.lunar_pushinteger(state, value);
		} else if (typeof value === "string") {
			const { pointer, size } = this.allocate(value);
			try {
				api.lunar_pushstring(state, pointer, size);
			} finally {
				api.lunar_free(pointer);
			}
		} else {
			if (value !== null && typeof value !== "object" && typeof value !== "function") {
				throw new TypeError("lunar: unsupported JavaScript value");
			}
			let handle = value === null ? 0 : this.identities.get(value);
			if (handle === undefined) {
				handle = this.nextHandle++;
				this.handles.set(handle, value);
				if (value !== null) this.identities.set(value, handle);
			}
			api.lunar_pushhandle(state, handle);
		}
	}

	value(state: number, index: number, kind?: ProxyKind): unknown {
		const api = this.api;
		switch (api.lunar_type(state, index)) {
			case 0:
				return undefined;
			case 1:
				return Boolean(api.lunar_boolean(state, index));
			case 3: {
				if (!api.lunar_isinteger(state, index)) return api.lunar_number(state, index);
				const value = api.lunar_integer(state, index);
				return value <= BigInt(Number.MAX_SAFE_INTEGER) && value >= BigInt(Number.MIN_SAFE_INTEGER)
					? Number(value)
					: value;
			}
			case 4:
				return this.string(state, index);
			case 7: {
				const handle = api.lunar_handle(state, index);
				if (handle < 0) throw new TypeError("lunar: unsupported Lua userdata");
				return this.handles.get(handle);
			}
			case 5:
			case 6:
				return this.proxy(state, index, kind);
			default:
				throw new TypeError("lunar: this Lua value cannot cross into JavaScript");
		}
	}

	proxy(state: number, index: number, kind?: ProxyKind): object {
		const api = this.api;
		const identity = `${api.lunar_identity(state, index)}:${kind ?? "default"}`;
		const cached = this.references.get(identity)?.weak.deref();
		if (cached) return cached;
		const reference = api.lunar_ref(state, index);
		const callable = kind ? kind !== "object" : api.lunar_type(state, index) === 6;
		const target = callable ? (...args: unknown[]) => this.call(reference, args) : {};
		const result = new Proxy(target, {
			get: (_target, key) => {
				if (typeof key === "symbol") return Reflect.get(target, key);
				return this.withStack((L) => {
					this.push(L, key);
					this.check(api.lunar_index(L, reference), L);
					return this.value(L, -1);
				});
			},
			set: (_target, key, value: unknown) =>
				this.withStack((L) => {
					this.push(L, key);
					this.push(L, value);
					this.check(api.lunar_assign(L, reference), L);
					return true;
				}),
		});
		this.references.set(identity, { weak: new WeakRef(result), reference });
		this.luaProxies.set(result, { reference, callable });
		this.finalizers.register(result, { identity, reference });
		return result;
	}

	check(status: number, state: number) {
		if (status) {
			const type = this.api.lunar_type(state, -1);
			const message =
				type === 4 || type === 3
					? this.string(state, -1)
					: `Lua raised an error value of type ${type}`;
			throw new Error(`lunar: ${message}`);
		}
	}

	withStack<T>(fn: (state: number) => T): T {
		if (!this.state) throw new Error("lunar: Lua runtime is closed");
		const state = this.state;
		const top = this.api.lunar_top(state);
		try {
			return fn(state);
		} finally {
			this.api.lunar_settop(state, top);
		}
	}

	evaluate(source: string, name = "@lunar"): unknown {
		return this.withStack((state) => {
			const input = this.allocate(source);
			const filename = this.allocate(name);
			try {
				const base = this.api.lunar_top(state);
				this.check(this.api.lunar_eval(state, input.pointer, input.size, filename.pointer), state);
				return this.api.lunar_top(state) > base ? this.value(state, base + 1) : undefined;
			} finally {
				this.api.lunar_free(input.pointer);
				this.api.lunar_free(filename.pointer);
			}
		});
	}

	evaluateFunction(source: string, name = "@lunar"): LuaFunction {
		const value = this.evaluate(source, name);
		if (typeof value !== "function")
			throw new TypeError("lunar: expected Lua to return a function");
		return value as LuaFunction;
	}

	call(reference: number, args: unknown[]): unknown {
		return this.withStack((state) => {
			const base = this.api.lunar_top(state);
			for (const arg of args) this.push(state, arg);
			this.check(this.api.lunar_call(state, reference, args.length), state);
			return this.api.lunar_top(state) > base ? this.value(state, base + 1) : undefined;
		});
	}

	host(state: number, operation: number, handle: number) {
		try {
			if (operation === 5) {
				if (handle > 1) {
					const value = this.handles.get(handle);
					this.handles.delete(handle);
					if ((typeof value === "object" && value !== null) || typeof value === "function") {
						this.identities.delete(value);
					}
				}
				return 0;
			}
			const count = this.api.lunar_top(state);
			const object = this.value(state, 1);
			let result: unknown;
			if (operation === 0)
				result = Reflect.get(this.object(object), this.key(this.value(state, 2)));
			else if (operation === 1) {
				const key = this.key(this.value(state, 2));
				const value = this.value(state, 3);
				if (value === undefined) Reflect.deleteProperty(this.object(object), key);
				else if (!Reflect.set(this.object(object), key, value))
					throw new TypeError(`Cannot assign ${String(key)}`);
				return 0;
			} else if (operation === 2 || operation === 3) {
				const args: unknown[] = [];
				const proxy = this.luaProxies.get(this.object(object));
				for (let i = operation === 2 && !proxy ? 3 : 2; i <= count; i++)
					args.push(this.value(state, i));
				if (proxy && operation === 2) result = this.call(proxy.reference, args);
				else {
					if (typeof object !== "function")
						throw new TypeError("lunar: JavaScript value is not callable");
					result =
						operation === 2
							? Reflect.apply(object, count >= 2 ? this.value(state, 2) : undefined, args)
							: Reflect.construct(object, args);
				}
			} else if (operation === 4) result = String(object);
			else if (operation === 6) {
				const kind = count >= 2 ? this.value(state, 2) : undefined;
				if (
					kind !== undefined &&
					kind !== "function" &&
					kind !== "arrow_function" &&
					kind !== "object"
				) {
					throw new TypeError("lunar: invalid proxy kind");
				}
				result = this.proxy(state, 1, kind);
			}
			this.push(state, result);
			return 1;
		} catch (error) {
			this.push(state, error instanceof Error ? error.message : String(error));
			return -1;
		}
	}

	private object(value: unknown): object {
		if ((typeof value === "object" && value !== null) || typeof value === "function") return value;
		throw new TypeError("lunar: expected a JavaScript object");
	}

	private key(value: unknown): string | symbol {
		return typeof value === "symbol" ? value : String(value);
	}

	close() {
		if (!this.state) return;
		this.api.lunar_close(this.state);
		this.state = 0;
		this.handles.clear();
		this.references.clear();
	}
}

if (typeof document !== "undefined") {
	document.dispatchEvent(
		new CustomEvent<BrowserRuntimeFactory>("lunar:runtime", {
			detail: { create: (options) => LuaRuntime.create(options), fetchVerified },
		}),
	);
}
