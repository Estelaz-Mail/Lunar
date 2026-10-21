// A module that does not exist, for the ones a Worker cannot have.
//
// Fengari's debug library pulls in `readline-sync` for `debug.debug()`, and
// its os library pulls in `child_process` for `os.execute`. Both read from the
// Node runtime as they load — `process.binding` in one case — and fail on an
// edge runtime before any Lua has run.
//
// A frozen Lunar app uses neither: there is no terminal to read a line from
// and no process to start. So they resolve to this, a Proxy that accepts being
// looked at and configured, and throws the moment anything is really called.
// A module that only binds or configures as it loads still loads; a program
// that genuinely tries to use one gets a message saying why it cannot.

const message = "lunar: this is not available in a Worker; there is no process and no terminal";

const absent = new Proxy(function absent() {}, {
	get(target, name) {
		// A bundler and a module loader both probe for these; answering with the
		// Proxy would make this look like a promise or an ES module.
		if (name === "then" || name === "__esModule" || name === Symbol.toStringTag) {
			return undefined;
		}
		if (name === "name") return "absent";
		// Anything that looks like configuration is accepted and ignored, because
		// it is called as the importing module loads.
		if (typeof name === "string" && /^set[A-Z]/.test(name)) return () => {};
		return absent;
	},
	apply() {
		throw new Error(message);
	},
	construct() {
		throw new Error(message);
	},
});

module.exports = absent;
