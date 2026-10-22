const message = "lunar: this is not available in a Worker; there is no process and no terminal";

const absent = new Proxy(function absent() {}, {
	get(target, name) {
		if (name === "then" || name === "__esModule" || name === Symbol.toStringTag) {
			return undefined;
		}
		if (name === "name") return "absent";
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
