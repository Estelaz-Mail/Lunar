// Checks the grammar without opening an editor.
//
// There is no way to assert on colours from a script, but the two ways a
// TextMate grammar actually breaks are checkable: a regular expression that
// does not compile, and an `include` that points at a rule which is not there.
// Both make the grammar fail silently in VS Code — the file simply stops being
// highlighted — so they are worth a script.
//
//   node scripts/check-grammar.mjs

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const path = join(here, "..", "syntaxes", "lunar.tmLanguage.json");
const grammar = JSON.parse(readFileSync(path, "utf8"));

const problems = [];
let patterns = 0;
let includes = 0;

// Oniguruma accepts a few things JavaScript does not. These are the ones this
// grammar uses on purpose; anything else that fails to compile is a mistake.
const ONIGURUMA_ONLY = [/\(\?<[=!]/, /\\h/, /\(\?i:/, /\\p\{/];

const checkRegex = (source, where) => {
  patterns++;
  try {
    new RegExp(source);
  } catch (error) {
    if (ONIGURUMA_ONLY.some((pattern) => pattern.test(source))) return;
    problems.push(`${where}: ${error.message}`);
  }
};

const names = new Set(Object.keys(grammar.repository ?? {}));

const walk = (node, where) => {
  if (Array.isArray(node)) {
    node.forEach((item, index) => walk(item, `${where}[${index}]`));
    return;
  }
  if (!node || typeof node !== "object") return;

  for (const key of ["match", "begin", "end", "while"]) {
    if (typeof node[key] === "string") checkRegex(node[key], `${where}.${key}`);
  }

  if (typeof node.include === "string") {
    includes++;
    const target = node.include;
    if (target.startsWith("#")) {
      if (!names.has(target.slice(1))) {
        problems.push(`${where}.include: no rule named ${target}`);
      }
    } else if (target !== "$self" && target !== "$base") {
      // An external scope (source.lua, source.css). It cannot be verified
      // from here, but it can be spelled wrong in a recognisable way.
      if (!/^[a-z]+(\.[a-z0-9-]+)+$/.test(target)) {
        problems.push(`${where}.include: ${target} is not a scope name`);
      }
    }
  }

  if (typeof node.name === "string" && where !== "" && !node.name.includes(".")) {
    problems.push(`${where}.name: "${node.name}" is not a dotted scope name`);
  }

  for (const [key, value] of Object.entries(node)) {
    if (key === "comment") continue;
    walk(value, `${where}.${key}`);
  }
};

walk(grammar, "");

if (grammar.scopeName !== "source.lunar") {
  problems.push(`scopeName is ${grammar.scopeName}, not source.lunar`);
}

// Every rule in the repository should be reachable, or it is dead weight that
// looks like it is doing something.
const serialized = JSON.stringify(grammar);
for (const name of names) {
  if (!serialized.includes(`"#${name}"`)) {
    problems.push(`repository.${name} is never included`);
  }
}

for (const problem of problems) console.error(`  ${problem}`);
console.log(
  `${patterns} patterns, ${includes} includes, ${names.size} rules, ${problems.length} problems`
);
process.exit(problems.length === 0 ? 0 : 1);
