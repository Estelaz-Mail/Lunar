const unavailable = () => {
	throw new Error("lunar: os.tmpname is not available in a Worker; there is no filesystem");
};

module.exports = {
	tmpNameSync: unavailable,
	fileSync: unavailable,
	dirSync: unavailable,
	setGracefulCleanup: () => {},
};
