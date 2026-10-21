// Tokenizes a sample component with the real TextMate engine and asserts on
// the scopes that come out.
//
// This is the part of the grammar worth testing: where one language stops and
// another starts. A `{` that does not open a Lua expression, or a `<script>`
// whose contents are not Lua, is a file that looks wrong in the editor and
// right in every other test.
//
// The embedded grammars (source.lua, source.css) ship with VS Code, not with
// this package, so they are stubbed with grammars that scope everything they
// see. That is enough: what is being checked is the boundary, not Lua's own
// highlighting.
//
//   npm install && node scripts/check-tokens.mjs

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { createRequire } from "node:module";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..");
const require = createRequire(import.meta.url);

let vsctm, oniguruma;
try {
  vsctm = require("vscode-textmate");
  oniguruma = require("vscode-oniguruma");
} catch {
  console.log("skipped: run `npm install` to check tokens");
  process.exit(0);
}

const wasm = readFileSync(
  join(root, "node_modules/vscode-oniguruma/release/onig.wasm")
);
await oniguruma.loadWASM(wasm.buffer);

/** A grammar that scopes everything it is given, for the embedded languages.
 *  Word by word, so a token in the sample can be pointed at. */
const stub = (scopeName) => ({
  scopeName,
  patterns: [{ match: "\\w+|[^\\w\\s]|\\s+", name: `${scopeName}.stub` }],
});

const registry = new vsctm.Registry({
  onigLib: Promise.resolve({
    createOnigScanner: (sources) => new oniguruma.OnigScanner(sources),
    createOnigString: (text) => new oniguruma.OnigString(text),
  }),
  loadGrammar: async (scopeName) => {
    if (scopeName === "source.lunar") {
      return vsctm.parseRawGrammar(
        readFileSync(join(root, "syntaxes/lunar.tmLanguage.json"), "utf8"),
        "lunar.tmLanguage.json"
      );
    }
    if (scopeName === "source.lua" || scopeName === "source.css") {
      return stub(scopeName);
    }
    return null;
  },
});

const grammar = await registry.loadGrammar("source.lunar");
const source = readFileSync(join(root, "test/sample.lunar"), "utf8");
const lines = source.split("\n");

// Tokenize the whole file, keeping the rule stack across lines the way an
// editor does, and remember where each token starts in the file.
const tokens = [];
let stack = vsctm.INITIAL;
let offset = 0;
lines.forEach((line, index) => {
  const result = grammar.tokenizeLine(line, stack);
  stack = result.ruleStack;
  for (const token of result.tokens) {
    tokens.push({
      line: index + 1,
      start: offset + token.startIndex,
      stop: offset + token.endIndex,
      text: line.slice(token.startIndex, token.endIndex),
      scopes: token.scopes,
    });
  }
  offset += line.length + 1;
});

const problems = [];

/** The token covering the nth occurrence of a piece of the sample. */
const at = (needle, nth = 1) => {
  let index = -1;
  for (let seen = 0; seen < nth; seen++) {
    index = source.indexOf(needle, index + 1);
    if (index < 0) return null;
  }
  return tokens.find((token) => token.start <= index && index < token.stop) ?? null;
};

const expect = (what, needle, scope, nth = 1) => {
  const token = at(needle, nth);
  if (!token) {
    problems.push(`${what}: "${needle}" is not in the sample`);
    return;
  }
  if (!token.scopes.some((candidate) => candidate.includes(scope))) {
    problems.push(
      `${what}: "${needle}" on line ${token.line} is [${token.scopes.join(", ")}], wanted ${scope}`
    );
  }
};

// The two embedded blocks.
expect("the script is Lua", "props", "source.lua");
expect("the script is Lua", "import", "source.lua");
expect("the style is CSS", "color: red", "source.css");

// Expressions in the template are Lua, wherever they appear.
expect("an interpolation", "{title}", "punctuation.section.embedded");
expect("an attribute expression", '"t-"', "source.lua");
expect("a handler", "function()", "source.lua");
expect("an {#if} test", "count > 1", "source.lua");
expect("an {#each} list", "items", "source.lua");

// The block keywords are keywords, not expressions.
expect("{#if}", "if", "keyword.control");
expect("{#each}", "each", "keyword.control");
expect("as", "as item", "keyword.operator");
expect("{@html}", "html", "keyword.other.unsafe");

// Tags, components and directives.
expect("an element", "h1", "entity.name.tag");
expect("a component", "Card title", "support.class.component");
expect("<slot />", "slot", "keyword.control.special");
expect("a directive", "on:click", "keyword.control.directive");
expect("a modifier", "|prevent", "support.function.modifier");
expect("a class directive", "class:hot", "keyword.control.directive");
expect("a binding", "bind:value", "keyword.control.directive");
expect("a spread", "...", "keyword.operator.spread");

// The rest of the template.
expect("a static attribute", "id", "entity.other.attribute-name");
expect("an escaped brace", "\\{", "constant.character.escape");
expect("an entity", "&amp;", "constant.character.entity");
expect("a comment", "a comment", "comment.block");

// A Lua table inside an expression must not end it early: the brace that
// closes the mustache is the last one, not the first.
const closing = at('class:hot={count > 2}>', 1);
if (closing && !closing.scopes.some((scope) => scope.includes("meta.tag"))) {
  problems.push("a nested brace swallowed the rest of the tag");
}

for (const problem of problems) console.error(`  ${problem}`);
console.log(`${tokens.length} tokens, ${problems.length} problems`);
process.exit(problems.length === 0 ? 0 : 1);
