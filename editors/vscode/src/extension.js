"use strict";

const vscode = require("vscode");
const cp = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

let diagnostics;
let output;
let status;
let cli = null;
let warned = null;

const timers = new Map();

const CLI_NAMES = process.platform === "win32" ? ["lunar.cmd", "lunar.exe", "lunar"] : ["lunar"];
const SEARCH_DEPTH = 8;

const WITH_LINE = /^lunar:\s+(.*?):(\d+):\s*(.+)$/;
const WITHOUT_LINE = /^lunar:\s+(.*?):\s*(.+)$/;

function activate(context) {
	diagnostics = vscode.languages.createDiagnosticCollection("lunar");
	output = vscode.window.createOutputChannel("Lunar");
	status = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 100);
	status.command = "lunar.status";
	context.subscriptions.push(diagnostics, output, status);

	context.subscriptions.push(
		vscode.workspace.onDidOpenTextDocument((doc) => maybeCheck(doc, false)),
		vscode.workspace.onDidChangeTextDocument((event) => maybeCheck(event.document, true)),
		vscode.workspace.onDidSaveTextDocument((doc) => maybeCheck(doc, false)),
		vscode.workspace.onDidCloseTextDocument((doc) => {
			diagnostics.delete(doc.uri);
			clearTimer(doc.uri.toString());
		}),
	);

	context.subscriptions.push(
		vscode.commands.registerCommand("lunar.check", () => {
			const doc = activeComponent();
			if (doc) check(doc);
		}),
		vscode.commands.registerCommand("lunar.compile", () => showCompiled()),
		vscode.commands.registerCommand("lunar.dev", () => runInTerminal("dev", ["dev", appRoot()])),
		vscode.commands.registerCommand("lunar.build", () =>
			runInTerminal("build", ["build", appRoot()]),
		),
		vscode.commands.registerCommand("lunar.routes", () => showOrbit()),
		vscode.commands.registerCommand("lunar.spec", () => runInTerminal("spec", ["spec"])),
		vscode.commands.registerCommand("lunar.locateCli", () => locateCli()),
		vscode.commands.registerCommand("lunar.status", () => showStatus()),
	);

	context.subscriptions.push(
		vscode.window.onDidChangeActiveTextEditor(() => updateStatus()),
		vscode.workspace.onDidChangeWorkspaceFolders(() => refreshCli()),
		vscode.workspace.onDidChangeConfiguration((event) => {
			if (event.affectsConfiguration("lunar.path") || event.affectsConfiguration("lunar.lua")) {
				warned = null;
				refreshCli();
			}
		}),
	);

	context.subscriptions.push(
		vscode.languages.registerDefinitionProvider(
			{ language: "lunar" },
			{ provideDefinition: resolveImport },
		),
	);

	refreshCli();
	for (const doc of vscode.workspace.textDocuments) maybeCheck(doc, false);
}

function deactivate() {
	for (const timer of timers.values()) clearTimeout(timer);
	timers.clear();
}

function maybeCheck(doc, fromType) {
	if (doc.languageId !== "lunar") return;
	const mode = config().get("diagnostics.run", "onType");
	if (mode === "off") return;
	if (fromType && mode !== "onType") return;
	if (!fromType) {
		check(doc);
		return;
	}

	const key = doc.uri.toString();
	clearTimer(key);
	const delay = config().get("diagnostics.debounce", 300);
	timers.set(
		key,
		setTimeout(() => {
			timers.delete(key);
			check(doc);
		}, delay),
	);
}

function clearTimer(key) {
	const timer = timers.get(key);
	if (timer) {
		clearTimeout(timer);
		timers.delete(key);
	}
}

function check(doc) {
	compile(doc, (error, stdout, stderr) => {
		if (error && (error.code === "ENOENT" || error.code === "EACCES")) {
			refreshCli();
			return;
		}
		if (error && !String(stderr || "").includes("lunar:")) {
			blame(String(stderr || error.message));
			return;
		}
		diagnostics.set(
			doc.uri,
			parseDiagnostics(`${stderr || ""}\n${error ? stdout || "" : ""}`, doc),
		);
	});
}

function compile(doc, done) {
	const found = cliOrWarn();
	if (!found) return;
	let target = doc.uri.fsPath;
	let temporary = null;

	if (doc.isDirty || doc.isUntitled) {
		const key = Buffer.from(doc.uri.toString()).toString("hex").slice(0, 16);
		const directory = path.join(os.tmpdir(), `lunar-check-${key}`);
		try {
			fs.mkdirSync(directory, { recursive: true });
			temporary = path.join(directory, path.basename(doc.uri.fsPath) || "component.lunar");
			fs.writeFileSync(temporary, doc.getText());
			target = temporary;
		} catch (error) {
			output.appendLine(`could not write a temporary file: ${error}`);
			return;
		}
	}

	cp.execFile(
		found.command,
		[...found.args, "compile", target],
		{ timeout: 10000, cwd: workspaceRoot(), env: environment(), maxBuffer: 8 * 1024 * 1024 },
		(error, stdout, stderr) => {
			if (temporary) fs.rm(path.dirname(temporary), { recursive: true, force: true }, () => {});
			done(error, stdout, stderr);
		},
	);
}

function parseDiagnostics(text, doc) {
	const out = [];
	const seen = new Set();

	for (const raw of text.split("\n")) {
		const line = raw.trimEnd();
		if (!line.startsWith("lunar:")) continue;

		let match = WITH_LINE.exec(line);
		let number = 0;
		let message;
		if (match) {
			number = Math.max(0, parseInt(match[2], 10) - 1);
			message = match[3];
		} else {
			match = WITHOUT_LINE.exec(line);
			if (!match) continue;
			message = match[2];
		}

		const key = `${number}:${message}`;
		if (seen.has(key)) continue;
		seen.add(key);

		const diagnostic = new vscode.Diagnostic(
			lineRange(doc, number),
			message,
			vscode.DiagnosticSeverity.Error,
		);
		diagnostic.source = "lunar";
		out.push(diagnostic);
	}
	return out;
}

function lineRange(doc, number) {
	if (number < doc.lineCount) {
		const text = doc.lineAt(number);
		const start = text.firstNonWhitespaceCharacterIndex;
		const end = Math.max(start + 1, text.text.length);
		return new vscode.Range(number, start, number, end);
	}
	return new vscode.Range(0, 0, 0, 1);
}

function activeComponent() {
	const doc = vscode.window.activeTextEditor?.document;
	if (!doc || doc.languageId !== "lunar") {
		vscode.window.showErrorMessage("Lunar: no .lunar file is open.");
		return null;
	}
	return doc;
}

function showCompiled() {
	const doc = activeComponent();
	if (!doc) return;

	compile(doc, async (error, stdout, stderr) => {
		if (error && (error.code === "ENOENT" || error.code === "EACCES")) {
			refreshCli();
			return;
		}
		if (error && !String(stderr || "").includes("lunar:")) {
			blame(String(stderr || error.message));
			return;
		}
		if (error) {
			output.show(true);
			output.appendLine(stderr || stdout || "the compiler failed with no message");
			vscode.window.showErrorMessage(
				"Lunar: this component does not compile. See the Lunar output.",
			);
			return;
		}
		const generated = await vscode.workspace.openTextDocument({
			language: "lua",
			content: stdout,
		});
		await vscode.window.showTextDocument(generated, {
			viewColumn: vscode.ViewColumn.Beside,
			preview: true,
		});
	});
}

function showOrbit() {
	const found = cliOrWarn();
	if (!found) return;
	cp.execFile(
		found.command,
		[...found.args, "map", appRoot()],
		{ timeout: 15000, cwd: workspaceRoot(), env: environment() },
		(error, stdout, stderr) => {
			if (error && (error.code === "ENOENT" || error.code === "EACCES")) {
				refreshCli();
				return;
			}
			if (error && !String(stderr || "").includes("lunar:")) {
				blame(String(stderr || error.message));
				return;
			}
			output.show(true);
			output.appendLine(stdout || stderr || "no routes");
		},
	);
}

function runInTerminal(name, args) {
	const found = cliOrWarn();
	if (!found) return;
	const terminal = vscode.window.createTerminal({
		name: `lunar ${name}`,
		cwd: workspaceRoot(),
	});
	terminal.show();
	terminal.sendText([found.command, ...found.args, ...args].map(quote).join(" "));
}

function resolveImport(doc, position) {
	const line = doc.lineAt(position.line).text;
	const imports = /import\s*\(\s*(["'])([^"']+)\1\s*\)/g;

	let match;
	while ((match = imports.exec(line)) !== null) {
		const start = match.index;
		const end = start + match[0].length;
		if (position.character < start || position.character > end) continue;

		const request = match[2];
		const base = request.startsWith("/")
			? path.join(appRoot() || workspaceRoot() || ".", request)
			: path.join(path.dirname(doc.uri.fsPath), request);
		const target = base.endsWith(".lunar") ? base : `${base}.lunar`;
		if (!fs.existsSync(target)) return null;
		return new vscode.Location(vscode.Uri.file(target), new vscode.Position(0, 0));
	}
	return null;
}

function workspaceRoot() {
	return vscode.workspace.workspaceFolders?.[0]?.uri.fsPath;
}

function appRoot() {
	const configured = config().get("app", "");
	if (configured) return configured;

	const open = vscode.window.activeTextEditor?.document.uri.fsPath;
	const root = workspaceRoot();
	if (open) {
		let directory = path.dirname(open);
		while (true) {
			if (fs.existsSync(path.join(directory, "orbit"))) return directory;
			const parent = path.dirname(directory);
			if (parent === directory || (root && !directory.startsWith(root))) break;
			directory = parent;
		}
	}
	return root ?? ".";
}

function expandHome(value) {
	if (value === "~") return os.homedir();
	if (value.startsWith("~/")) return path.join(os.homedir(), value.slice(2));
	return value;
}

function ancestors(from) {
	const out = [];
	let directory = from;
	while (directory && out.length < SEARCH_DEPTH) {
		out.push(directory);
		const parent = path.dirname(directory);
		if (parent === directory) break;
		directory = parent;
	}
	return out;
}

function searchBases() {
	const bases = [];
	const open = vscode.window.activeTextEditor?.document.uri.fsPath;
	if (open) bases.push(...ancestors(path.dirname(open)));
	for (const folder of vscode.workspace.workspaceFolders ?? []) {
		bases.push(...ancestors(folder.uri.fsPath));
	}
	return [...new Set(bases)];
}

function isExecutable(target) {
	try {
		const info = fs.statSync(target);
		if (!info.isFile()) return false;
		if (process.platform === "win32") return true;
		return (info.mode & 0o111) !== 0;
	} catch {
		return false;
	}
}

function onPath(name) {
	for (const entry of (process.env.PATH ?? "").split(path.delimiter)) {
		if (!entry) continue;
		const candidate = path.join(entry, name);
		if (isExecutable(candidate)) return candidate;
	}
	return null;
}

function candidates() {
	const configured = config().get("path", "").trim();
	if (configured) {
		const expanded = expandHome(configured);
		if (path.isAbsolute(expanded)) {
			return [{ command: expanded, origin: "the lunar.path setting" }];
		}
		if (expanded.includes(path.sep) || expanded.includes("/")) {
			return searchBases().map((base) => ({
				command: path.join(base, expanded),
				origin: `the lunar.path setting, under ${base}`,
			}));
		}
		const found = onPath(expanded);
		return found ? [{ command: found, origin: "the lunar.path setting, on your PATH" }] : [];
	}

	const out = searchBases().map((base) => ({
		command: path.join(base, "bin", "lunar"),
		origin: `bin/lunar in ${base}`,
	}));
	for (const name of CLI_NAMES) {
		const found = onPath(name);
		if (found) out.push({ command: found, origin: "your PATH" });
	}
	return out;
}

function refreshCli() {
	const tried = [];
	let chosen = null;

	for (const candidate of candidates()) {
		tried.push(candidate.command);
		if (!fs.existsSync(candidate.command)) continue;
		chosen = { ...candidate, args: [] };
		if (!isExecutable(candidate.command)) chosen.problem = "not-executable";
		break;
	}

	cli = chosen ?? { command: null, args: [], origin: null, problem: "missing" };
	cli.tried = tried;
	logCli();
	updateStatus();
	if (cli.problem) {
		warn();
		return;
	}
	verifyCli();
}

function verifyCli() {
	const target = cli;
	cp.execFile(
		target.command,
		[...target.args, "help"],
		{ timeout: 10000, cwd: workspaceRoot(), env: environment() },
		(error, stdout, stderr) => {
			if (cli !== target) return;
			if (error) {
				target.problem = error.code === "EACCES" ? "not-executable" : "broken";
				target.detail = firstLine(stderr || error.message);
			} else {
				target.problem = null;
				target.version = (String(stdout).match(/lunar\s+(\S+)/) ?? [])[1] ?? null;
			}
			logCli();
			updateStatus();
			if (target.problem) warn();
		},
	);
}

function cliOrWarn() {
	if (!cli) refreshCli();
	if (!cli || !cli.command) {
		warn();
		return null;
	}
	return cli;
}

function blame(text) {
	if (!cli) return;
	cli.problem = "broken";
	cli.detail = firstLine(text);
	logCli();
	updateStatus();
	warn();
}

function firstLine(text) {
	return String(text || "")
		.trim()
		.split(/\r?\n/)[0];
}

function cliMessage() {
	if (!cli || cli.problem === "missing") {
		const places = cli?.tried?.length ?? 0;
		return (
			"Lunar: no CLI found. The extension looked in " +
			`${places} place${places === 1 ? "" : "s"} — bin/lunar in the folder you have open ` +
			"and its parents, and lunar on your PATH. Point lunar.path at bin/lunar in your checkout."
		);
	}
	if (cli.problem === "not-executable") {
		return `Lunar: ${cli.command} is there but is not executable. Run chmod +x on it.`;
	}
	if (cli.problem === "broken") {
		const detail = cli.detail ? ` It said: ${cli.detail}` : "";
		return (
			`Lunar: ${cli.command} did not run.${detail} ` +
			"The CLI needs Lua 5.4 on your PATH, or lunar.lua pointed at one."
		);
	}
	return `Lunar: using ${cli.command}.`;
}

function warn() {
	if (!cli || !cli.problem) return;
	const key = `${cli.problem}:${cli.command ?? ""}:${cli.detail ?? ""}`;
	if (warned === key) return;
	warned = key;

	const locate = "Locate the CLI…";
	const settings = "Open settings";
	const log = "Show log";
	vscode.window.showWarningMessage(cliMessage(), locate, settings, log).then((choice) => {
		if (choice === locate) vscode.commands.executeCommand("lunar.locateCli");
		if (choice === settings) {
			vscode.commands.executeCommand("workbench.action.openSettings", "lunar.path");
		}
		if (choice === log) output.show(true);
	});
}

function logCli() {
	if (!output) return;
	if (cli?.command && !cli.problem) {
		const version = cli.version ? ` (${cli.version})` : "";
		output.appendLine(`cli: ${cli.command}${version}, found via ${cli.origin}`);
		return;
	}
	output.appendLine(`cli: ${cliMessage()}`);
	for (const candidate of cli?.tried ?? []) output.appendLine(`  tried ${candidate}`);
}

function updateStatus() {
	if (!status) return;
	if (!cli || cli.problem) {
		status.text = "$(warning) Lunar";
		status.tooltip = cliMessage();
		status.backgroundColor = new vscode.ThemeColor("statusBarItem.warningBackground");
		status.show();
		return;
	}
	status.text = "$(check) Lunar";
	status.tooltip = `${cli.command}${cli.version ? ` — ${cli.version}` : ""}\nFound via ${cli.origin}.`;
	status.backgroundColor = undefined;
	if (vscode.window.activeTextEditor?.document.languageId === "lunar") {
		status.show();
	} else {
		status.hide();
	}
}

async function locateCli() {
	const root = workspaceRoot();
	const picked = await vscode.window.showOpenDialog({
		title: "Select the lunar CLI",
		openLabel: "Use this CLI",
		canSelectMany: false,
		defaultUri: root ? vscode.Uri.file(path.join(root, "bin")) : undefined,
	});
	if (!picked || picked.length === 0) return;

	const scope = vscode.workspace.workspaceFolders?.length
		? vscode.ConfigurationTarget.Workspace
		: vscode.ConfigurationTarget.Global;
	await config().update("path", picked[0].fsPath, scope);
	warned = null;
	refreshCli();
}

function showStatus() {
	warned = null;
	refreshCli();
	output.show(true);
	if (cli?.problem) return;
	const version = cli.version ? ` (${cli.version})` : "";
	vscode.window.showInformationMessage(
		`Lunar: using ${cli.command}${version}, found via ${cli.origin}.`,
	);
}

function environment() {
	const lua = config().get("lua", "");
	if (!lua) return process.env;
	return { ...process.env, LUA: lua };
}

function quote(value) {
	return /[^A-Za-z0-9_./-]/.test(value) ? `"${String(value).replace(/"/g, '\\"')}"` : value;
}

function config() {
	return vscode.workspace.getConfiguration("lunar");
}

module.exports = { activate, deactivate };
