import Module from "node:module";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { mkdtempSync, writeFileSync, chmodSync } from "node:fs";
import { tmpdir } from "node:os";

const here = dirname(fileURLToPath(import.meta.url));
const extension = join(here, "..", "src", "extension.js");
const stub = join(here, "vscode-stub.cjs");
const checkout = join(here, "..", "..", "..");

const resolve = Module._resolveFilename;
Module._resolveFilename = function (request, ...rest) {
	if (request === "vscode") return stub;
	return resolve.call(this, request, ...rest);
};

const require = createRequire(import.meta.url);
const vscode = require(stub);

const problems = [];
const check = (condition, what) => {
	if (!condition) problems.push(what);
};

function activate(fields) {
	vscode.__reset(fields);
	delete require.cache[require.resolve(extension)];
	const api = require(extension);
	api.activate({ subscriptions: [] });
	return { api, state: vscode.__state };
}

const settled = () => new Promise((done) => setTimeout(done, 400));

{
	const { state } = activate({ folders: [checkout] });
	await settled();
	check(
		state.output.some((line) => line.startsWith(`cli: ${join(checkout, "bin", "lunar")}`)),
		"the CLI in the workspace root was not found",
	);
	check(state.warnings.length === 0, "finding the CLI still warned");
	check(state.status.text === "$(check) Lunar", `status was ${state.status.text}`);
	check(
		state.output.some((line) => /\(\d+\.\d+\.\d+\)/.test(line)),
		"the CLI version was not read",
	);
}

{
	const subfolder = join(checkout, "editors", "vscode");
	const { state } = activate({
		folders: [subfolder],
		activeFile: join(subfolder, "test", "sample.lunar"),
	});
	await settled();
	check(
		state.output.some((line) => line.startsWith(`cli: ${join(checkout, "bin", "lunar")}`)),
		"opening a subfolder of the checkout did not find the CLI above it",
	);
	check(state.warnings.length === 0, "a subfolder of the checkout warned");
}

{
	const empty = mkdtempSync(join(tmpdir(), "lunar-cli-"));
	const path = process.env.PATH;
	process.env.PATH = empty;
	const { state } = activate({ folders: [empty] });
	await settled();
	process.env.PATH = path;

	check(state.warnings.length === 1, `a missing CLI warned ${state.warnings.length} times`);
	const warning = state.warnings[0] ?? { message: "", actions: [] };
	check(/no CLI found/.test(warning.message), `the message was: ${warning.message}`);
	check(/looked in \d+ places/.test(warning.message), "the message does not say where it looked");
	check(warning.actions.includes("Locate the CLI…"), "there is no way to point at the CLI");
	check(warning.actions.includes("Show log"), "there is no way to see the log");
	check(state.status.text === "$(warning) Lunar", `status was ${state.status.text}`);
	check(
		state.output.filter((line) => line.startsWith("  tried ")).length > 0,
		"the log does not list what was tried",
	);
}

{
	const home = mkdtempSync(join(tmpdir(), "lunar-cli-"));
	const fake = join(home, "lunar");
	writeFileSync(fake, "#!/bin/sh\nexit 0\n");
	chmodSync(fake, 0o644);
	const { state } = activate({ folders: [home], settings: { path: fake } });
	await settled();

	check(state.warnings.length === 1, "a CLI that cannot be run did not warn");
	check(
		/is not executable/.test(state.warnings[0]?.message ?? ""),
		`the message was: ${state.warnings[0]?.message}`,
	);
}

{
	const home = mkdtempSync(join(tmpdir(), "lunar-cli-"));
	const fake = join(home, "lunar");
	writeFileSync(fake, '#!/bin/sh\necho "lua5.4: not found" >&2\nexit 127\n');
	chmodSync(fake, 0o755);
	const { state } = activate({ folders: [home], settings: { path: fake } });
	await settled();

	check(state.warnings.length === 1, "a CLI without Lua did not warn");
	const message = state.warnings[0]?.message ?? "";
	check(/did not run/.test(message), `the message was: ${message}`);
	check(/lua5\.4: not found/.test(message), "the message does not repeat what the CLI said");
	check(/Lua 5\.4/.test(message), "the message does not say what is missing");
}

for (const problem of problems) console.error(`  ${problem}`);
console.log(`5 CLI scenarios, ${problems.length} problems`);
process.exit(problems.length === 0 ? 0 : 1);
