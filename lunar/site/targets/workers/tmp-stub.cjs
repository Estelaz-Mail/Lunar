// A stand-in for the `tmp` package, for the Workers build.
//
// Fengari's os library pulls `tmp` in for `os.tmpname`, and `tmp` binds Node's
// `fs` functions as it loads — which fails on an edge runtime before any Lua
// has run. A frozen Lunar app never asks for a temporary file, so the import
// is satisfied with this.

const unavailable = () => {
	throw new Error("lunar: os.tmpname is not available in a Worker; there is no filesystem");
};

module.exports = {
	tmpNameSync: unavailable,
	fileSync: unavailable,
	dirSync: unavailable,
	setGracefulCleanup: () => {},
};
