// Lunar editor integration.
//
// There is no language server. The extension shells out to the real compiler
// (`lunar compile <file>`) and turns what it says into editor squiggles, so
// the editor and the command line can never disagree about what is an error.
//
// It is written in plain JavaScript, with no build step and no runtime
// dependency beyond the `vscode` API and Node's standard library. That is not
// laziness: Lunar's own rule is that there is no build step, and an extension
// that needed `tsc` before it could run would be the first exception.

"use strict";

const vscode = require("vscode");
const cp = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

/** @type {vscode.DiagnosticCollection} */
let diagnostics;
/** @type {vscode.OutputChannel} */
let output;

/** Debounce timers, keyed by document URI. */
const timers = new Map();

/**
 * A compiler message looks like one of these:
 *
 *   lunar: orbit/page.lunar:12: {#if} is never closed
 *   lunar: orbit/page.lunar:3: an expression is not a Lua expression: unexpected symbol
 *   lunar: Card.lunar: a component has one <script>, at the top level
 *
 * The line number is optional because a few checks are about the file as a
 * whole. Everything after the last colon-space is the message.
 */
const WITH_LINE = /^lunar:\s+(.*?):(\d+):\s*(.+)$/;
const WITHOUT_LINE = /^lunar:\s+(.*?):\s*(.+)$/;

function activate(context) {
  diagnostics = vscode.languages.createDiagnosticCollection("lunar");
  output = vscode.window.createOutputChannel("Lunar");
  context.subscriptions.push(diagnostics, output);

  context.subscriptions.push(
    vscode.workspace.onDidOpenTextDocument((doc) => maybeCheck(doc, false)),
    vscode.workspace.onDidChangeTextDocument((event) => maybeCheck(event.document, true)),
    vscode.workspace.onDidSaveTextDocument((doc) => maybeCheck(doc, false)),
    vscode.workspace.onDidCloseTextDocument((doc) => {
      diagnostics.delete(doc.uri);
      clearTimer(doc.uri.toString());
    })
  );

  context.subscriptions.push(
    vscode.commands.registerCommand("lunar.check", () => {
      const doc = activeComponent();
      if (doc) check(doc);
    }),
    vscode.commands.registerCommand("lunar.compile", () => showCompiled()),
    vscode.commands.registerCommand("lunar.dev", () => runInTerminal("dev", ["dev", appRoot()])),
    vscode.commands.registerCommand("lunar.build", () => runInTerminal("build", ["build", appRoot()])),
    vscode.commands.registerCommand("lunar.routes", () => showOrbit()),
    vscode.commands.registerCommand("lunar.spec", () => runInTerminal("spec", ["spec"]))
  );

  // `import("./Card.lunar")` is a path, so ctrl-click should open it. The
  // compiler resolves these relative to the importing file, or to the app root
  // for a leading slash; this does the same arithmetic.
  context.subscriptions.push(
    vscode.languages.registerDefinitionProvider(
      { language: "lunar" },
      { provideDefinition: resolveImport }
    )
  );

  for (const doc of vscode.workspace.textDocuments) maybeCheck(doc, false);
}

function deactivate() {
  for (const timer of timers.values()) clearTimeout(timer);
  timers.clear();
}

// Diagnostics ----------------------------------------------------------------

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
    }, delay)
  );
}

function clearTimer(key) {
  const timer = timers.get(key);
  if (timer) {
    clearTimeout(timer);
    timers.delete(key);
  }
}

/**
 * Compiles the document's current text, saved or not, and publishes what the
 * compiler said. An unsaved buffer goes through a temporary file, so the
 * squiggles are live rather than one save behind.
 */
function check(doc) {
  compile(doc, (error, stdout, stderr) => {
    if (error && error.code === "ENOENT") {
      promptMissingCli();
      return;
    }
    diagnostics.set(doc.uri, parseDiagnostics(`${stderr || ""}\n${error ? stdout || "" : ""}`, doc));
  });
}

/**
 * Runs `lunar compile` over a document. The temporary file keeps the real
 * file's name, in a directory of its own, because the compiler puts the file
 * name in its messages and a name like `lunar-check-9f3b.lunar` in a squiggle
 * would be confusing.
 */
function compile(doc, done) {
  const cli = resolveCli();
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
    cli.command,
    [...cli.args, "compile", target],
    { timeout: 10000, cwd: workspaceRoot(), env: environment(), maxBuffer: 8 * 1024 * 1024 },
    (error, stdout, stderr) => {
      if (temporary) fs.rm(path.dirname(temporary), { recursive: true, force: true }, () => {});
      done(error, stdout, stderr);
    }
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
      vscode.DiagnosticSeverity.Error
    );
    diagnostic.source = "lunar";
    out.push(diagnostic);
  }
  return out;
}

/**
 * The compiler reports a line, not a column, so the squiggle covers the line's
 * text rather than a guessed token.
 */
function lineRange(doc, number) {
  if (number < doc.lineCount) {
    const text = doc.lineAt(number);
    const start = text.firstNonWhitespaceCharacterIndex;
    const end = Math.max(start + 1, text.text.length);
    return new vscode.Range(number, start, number, end);
  }
  return new vscode.Range(0, 0, 0, 1);
}

// Commands -------------------------------------------------------------------

function activeComponent() {
  const doc = vscode.window.activeTextEditor?.document;
  if (!doc || doc.languageId !== "lunar") {
    vscode.window.showErrorMessage("Lunar: no .lunar file is open.");
    return null;
  }
  return doc;
}

/**
 * Opens the generated module beside the component.
 *
 * This is the first thing to reach for when a template does not do what it
 * reads like: the output is plain Lua, and the `<script>` keeps its original
 * line numbers inside it.
 */
function showCompiled() {
  const doc = activeComponent();
  if (!doc) return;

  compile(doc, async (error, stdout, stderr) => {
    if (error && error.code === "ENOENT") {
      promptMissingCli();
      return;
    }
    if (error) {
      output.show(true);
      output.appendLine(stderr || stdout || "the compiler failed with no message");
      vscode.window.showErrorMessage("Lunar: this component does not compile. See the Lunar output.");
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

/** The route table, as the framework discovered it. */
function showOrbit() {
  const cli = resolveCli();
  cp.execFile(
    cli.command,
    [...cli.args, "map", appRoot()],
    { timeout: 15000, cwd: workspaceRoot(), env: environment() },
    (error, stdout, stderr) => {
      if (error && error.code === "ENOENT") {
        promptMissingCli();
        return;
      }
      output.show(true);
      output.appendLine(stdout || stderr || "no routes");
    }
  );
}

function runInTerminal(name, args) {
  const cli = resolveCli();
  const terminal = vscode.window.createTerminal({
    name: `lunar ${name}`,
    cwd: workspaceRoot(),
  });
  terminal.show();
  terminal.sendText([cli.command, ...cli.args, ...args].map(quote).join(" "));
}

// Resolution -----------------------------------------------------------------

/**
 * `import("./Card.lunar")` under the cursor, as a location.
 *
 * Mirrors `lunar/compiler/resolve.lua`: relative to the importing file, or to
 * the app root when it starts with a slash, and `.lunar` is added when it is
 * not already there.
 */
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

/** The first workspace folder, which is what the CLI is run from. */
function workspaceRoot() {
  return vscode.workspace.workspaceFolders?.[0]?.uri.fsPath;
}

/**
 * The app directory: the `lunar.app` setting, or the nearest ancestor of the
 * open file that has an `orbit/` in it, or the workspace root.
 */
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

/**
 * How to run the CLI. Resolution order, most to least specific:
 *   1. the `lunar.path` setting;
 *   2. `bin/lunar` in a workspace folder, so a contributor runs the checkout
 *      they are editing;
 *   3. `lunar` on PATH.
 */
function resolveCli() {
  const configured = config().get("path", "");
  if (configured) return { command: configured, args: [] };

  for (const folder of vscode.workspace.workspaceFolders ?? []) {
    for (const relative of ["bin/lunar", "editors/../bin/lunar"]) {
      const candidate = path.join(folder.uri.fsPath, relative);
      if (fs.existsSync(candidate)) return { command: candidate, args: [] };
    }
  }

  return { command: "lunar", args: [] };
}

/** The CLI runs under whichever Lua the user has; `bin/lunar` honours `LUA`. */
function environment() {
  const lua = config().get("lua", "");
  if (!lua) return process.env;
  return { ...process.env, LUA: lua };
}

function promptMissingCli() {
  vscode.window
    .showWarningMessage(
      "Lunar: the CLI was not found. Point `lunar.path` at bin/lunar in your checkout.",
      "Open settings"
    )
    .then((choice) => {
      if (choice === "Open settings") {
        vscode.commands.executeCommand("workbench.action.openSettings", "lunar.path");
      }
    });
}

function quote(value) {
  return /[^A-Za-z0-9_./-]/.test(value) ? `"${String(value).replace(/"/g, '\\"')}"` : value;
}

function config() {
  return vscode.workspace.getConfiguration("lunar");
}

module.exports = { activate, deactivate };
