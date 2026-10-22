"use strict";

const state = {
	folders: [],
	activeFile: null,
	settings: {},
	warnings: [],
	information: [],
	status: { text: null, tooltip: null, visible: false },
	commands: new Map(),
	output: [],
	answer: undefined,
};

function reset(fields) {
	state.folders = fields.folders ?? [];
	state.activeFile = fields.activeFile ?? null;
	state.settings = fields.settings ?? {};
	state.warnings = [];
	state.information = [];
	state.status = { text: null, tooltip: null, visible: false };
	state.commands = new Map();
	state.output = [];
	state.answer = undefined;
}

const Uri = { file: (fsPath) => ({ fsPath, toString: () => `file://${fsPath}` }) };

const vscode = {
	__state: state,
	__reset: reset,
	Uri,
	StatusBarAlignment: { Left: 1, Right: 2 },
	ViewColumn: { Beside: 2 },
	ConfigurationTarget: { Global: 1, Workspace: 2 },
	ThemeColor: class ThemeColor {
		constructor(id) {
			this.id = id;
		}
	},
	DiagnosticSeverity: { Error: 0, Warning: 1 },
	Diagnostic: class Diagnostic {
		constructor(range, message, severity) {
			Object.assign(this, { range, message, severity });
		}
	},
	Range: class Range {
		constructor(...args) {
			this.args = args;
		}
	},
	Position: class Position {
		constructor(line, character) {
			Object.assign(this, { line, character });
		}
	},
	Location: class Location {
		constructor(uri, range) {
			Object.assign(this, { uri, range });
		}
	},
	window: {
		get activeTextEditor() {
			if (!state.activeFile) return undefined;
			return { document: { uri: Uri.file(state.activeFile), languageId: "lunar" } };
		},
		createOutputChannel: () => ({
			appendLine: (line) => state.output.push(line),
			show: () => {},
			dispose: () => {},
		}),
		createStatusBarItem: () => ({
			show() {
				state.status.visible = true;
			},
			hide() {
				state.status.visible = false;
			},
			dispose() {},
			set text(value) {
				state.status.text = value;
			},
			get text() {
				return state.status.text;
			},
			set tooltip(value) {
				state.status.tooltip = value;
			},
			get tooltip() {
				return state.status.tooltip;
			},
			set backgroundColor(value) {
				state.status.background = value;
			},
			set command(value) {
				state.status.command = value;
			},
		}),
		showWarningMessage: (message, ...actions) => {
			state.warnings.push({ message, actions });
			return Promise.resolve(state.answer);
		},
		showInformationMessage: (message) => {
			state.information.push(message);
			return Promise.resolve(undefined);
		},
		showErrorMessage: (message) => {
			state.information.push(message);
			return Promise.resolve(undefined);
		},
		showOpenDialog: () => Promise.resolve(state.pick ?? undefined),
		showTextDocument: () => Promise.resolve({}),
		createTerminal: () => ({ show: () => {}, sendText: () => {}, dispose: () => {} }),
		onDidChangeActiveTextEditor: () => ({ dispose: () => {} }),
	},
	workspace: {
		get workspaceFolders() {
			return state.folders.length ? state.folders.map((f) => ({ uri: Uri.file(f) })) : undefined;
		},
		textDocuments: [],
		getConfiguration: () => ({
			get: (key, fallback) => (key in state.settings ? state.settings[key] : fallback),
			update: (key, value) => {
				state.settings[key] = value;
				return Promise.resolve();
			},
		}),
		openTextDocument: () => Promise.resolve({}),
		onDidOpenTextDocument: () => ({ dispose: () => {} }),
		onDidChangeTextDocument: () => ({ dispose: () => {} }),
		onDidSaveTextDocument: () => ({ dispose: () => {} }),
		onDidCloseTextDocument: () => ({ dispose: () => {} }),
		onDidChangeConfiguration: () => ({ dispose: () => {} }),
		onDidChangeWorkspaceFolders: () => ({ dispose: () => {} }),
	},
	languages: {
		createDiagnosticCollection: () => ({
			set: () => {},
			delete: () => {},
			dispose: () => {},
		}),
		registerDefinitionProvider: () => ({ dispose: () => {} }),
	},
	commands: {
		registerCommand: (name, handler) => {
			state.commands.set(name, handler);
			return { dispose: () => {} };
		},
		executeCommand: (name, ...args) => {
			const handler = state.commands.get(name);
			return Promise.resolve(handler ? handler(...args) : undefined);
		},
	},
};

module.exports = vscode;
