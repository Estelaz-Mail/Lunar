const unavailable = (name) => () => {
	throw new Error(`lunar: ${name} is not available in a Worker; there is no filesystem`);
};

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
