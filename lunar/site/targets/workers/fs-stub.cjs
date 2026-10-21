// A stand-in for Node's `fs`, for the Workers build.
//
// Fengari imports `fs` at the top of its io library so that a Lua program can
// open a file. A Worker has no filesystem, and a frozen Lunar app never opens
// one — everything it needs is in `app.lua` — so the import is satisfied with
// this instead of pulling a polyfill into the bundle.
//
// Every function throws rather than returning nothing, so a Lua program that
// does reach for a file gets an error that says why instead of a wrong answer.
//
// CommonJS, because that is how Fengari asks for it: `const fs =
// require('fs')`. An ES module would arrive as a namespace object, and the
// shapes would not line up.

const unavailable = (name) => () => {
	throw new Error(`lunar: ${name} is not available in a Worker; there is no filesystem`);
};

// The list is what Fengari's io library and the packages it pulls in reach
// for as they load. A missing name here is not a missing feature — it is an
// `undefined.bind` at module scope, before any Lua has run.
module.exports = {
	openSync: unavailable("fs.openSync"),
	readSync: unavailable("fs.readSync"),
	writeSync: unavailable("fs.writeSync"),
	closeSync: unavailable("fs.closeSync"),
	fstatSync: unavailable("fs.fstatSync"),
	readFileSync: unavailable("fs.readFileSync"),
	writeFileSync: unavailable("fs.writeFileSync"),
	unlinkSync: unavailable("fs.unlinkSync"),
	renameSync: unavailable("fs.renameSync"),
	statSync: unavailable("fs.statSync"),
	mkdirSync: unavailable("fs.mkdirSync"),
	rmdirSync: unavailable("fs.rmdirSync"),
	rmSync: unavailable("fs.rmSync"),
	readdirSync: unavailable("fs.readdirSync"),
	unlink: unavailable("fs.unlink"),
	rmdir: unavailable("fs.rmdir"),

	existsSync: () => false,
	constants: {},
};
