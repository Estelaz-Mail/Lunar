import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "bun:test";

const launcher = fileURLToPath(new URL("../bin/lunar", import.meta.url));

function run(cwd: string, args: string[], input?: string) {
	const result = Bun.spawnSync([launcher, "fmt", ...args], {
		cwd,
		stdin: input === undefined ? "ignore" : new TextEncoder().encode(input),
		stdout: "pipe",
		stderr: "pipe",
	});
	return {
		code: result.exitCode,
		out: new TextDecoder().decode(result.stdout),
		err: new TextDecoder().decode(result.stderr),
	};
}

test("fmt checks without writing, formats recursively, then checks cleanly", () => {
	const directory = mkdtempSync(join(tmpdir(), "lunar-fmt-"));
	try {
		const source = "<main><h1>Hello</h1><p>World</p></main>";
		const path = join(directory, "page.lunar");
		writeFileSync(path, source);
		for (const name of [".lunar", "node_modules", "output"]) {
			mkdirSync(join(directory, name));
			writeFileSync(join(directory, name, "invalid.lunar"), "<broken>");
		}
		const check = run(directory, ["--check"]);
		assert.equal(check.code, 1, check.err);
		assert.equal(readFileSync(path, "utf8"), source);
		const write = run(directory, [".", "page.lunar"]);
		assert.equal(write.code, 0, write.err);
		assert.match(write.out, /1 checked, 1 formatted/);
		assert.equal(readFileSync(path, "utf8"), "<main>\n  <h1>Hello</h1>\n  <p>World</p>\n</main>\n");
		assert.equal(run(directory, ["--check"]).code, 0);
	} finally {
		rmSync(directory, { recursive: true, force: true });
	}
});

test("fmt validates every component before writing any component", () => {
	const directory = mkdtempSync(join(tmpdir(), "lunar-fmt-invalid-"));
	try {
		const source = "<main><p>valid</p></main>";
		const path = join(directory, "a.lunar");
		writeFileSync(path, source);
		writeFileSync(join(directory, "b.lunar"), "<p>unclosed");
		const result = run(directory, ["."]);
		assert.equal(result.code, 2);
		assert.match(result.err, /b\.lunar/);
		assert.equal(readFileSync(path, "utf8"), source);
	} finally {
		rmSync(directory, { recursive: true, force: true });
	}
});

test("fmt stdin emits only source and rejects invalid options and missing paths", () => {
	const result = run(
		tmpdir(),
		["--stdin", "example.lunar", "--indent", "4"],
		"<div><p>Hello</p></div>",
	);
	assert.equal(result.code, 0, result.err);
	assert.equal(result.out, "<div>\n    <p>Hello</p>\n</div>\n");
	for (const args of [
		["--stdin", "--check"],
		["--stdin", "--indent", "0"],
		["--width", "bad"],
		["--unknown"],
		["missing-component-938573.lunar"],
	]) {
		assert.equal(run(tmpdir(), args, "<p>Hello</p>").code, 2, args.join(" "));
	}
});
