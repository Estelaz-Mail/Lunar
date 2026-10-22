import { existsSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..");
const manifest = JSON.parse(readFileSync(join(root, "package.json"), "utf8"));
const source = readFileSync(join(root, manifest.main.replace(/^\.\//, "")), "utf8");

const problems = [];
const file = (relative) => join(root, String(relative).replace(/^\.\//, ""));

const mustExist = (relative, what) => {
	if (!existsSync(file(relative))) problems.push(`${what}: ${relative} is not there`);
};

mustExist(manifest.main, "main");
mustExist(manifest.icon, "icon");

for (const language of manifest.contributes.languages ?? []) {
	mustExist(language.configuration, `language ${language.id}`);
	for (const theme of ["light", "dark"]) {
		if (language.icon?.[theme]) mustExist(language.icon[theme], `${language.id} ${theme} icon`);
	}
}

for (const grammar of manifest.contributes.grammars ?? []) {
	mustExist(grammar.path, `grammar ${grammar.scopeName}`);
}

for (const snippets of manifest.contributes.snippets ?? []) {
	mustExist(snippets.path, `snippets for ${snippets.language}`);
	try {
		JSON.parse(readFileSync(file(snippets.path), "utf8"));
	} catch (error) {
		problems.push(`snippets ${snippets.path}: ${error.message}`);
	}
}

const contributed = new Set((manifest.contributes.commands ?? []).map((c) => c.command));
const registered = new Set([...source.matchAll(/registerCommand\(\s*"([^"]+)"/g)].map((m) => m[1]));
for (const command of contributed) {
	if (!registered.has(command)) problems.push(`command ${command} is never registered`);
}
for (const command of registered) {
	if (!contributed.has(command)) problems.push(`command ${command} is not in the manifest`);
}

for (const item of manifest.contributes.menus?.["editor/context"] ?? []) {
	if (!contributed.has(item.command)) {
		problems.push(`menu item ${item.command} is not a contributed command`);
	}
}

const prefix = `${manifest.contributes.configuration.title.toLowerCase()}.`;
for (const key of Object.keys(manifest.contributes.configuration.properties ?? {})) {
	const name = key.startsWith(prefix) ? key.slice(prefix.length) : key;
	if (!source.includes(`"${name}"`)) problems.push(`setting ${key} is never read`);
}

for (const problem of problems) console.error(`  ${problem}`);
console.log(
	`${contributed.size} commands, ${Object.keys(manifest.contributes.configuration.properties).length} settings, ${problems.length} problems`,
);
process.exit(problems.length === 0 ? 0 : 1);
