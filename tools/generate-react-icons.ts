import { readFile, writeFile, mkdir } from "node:fs/promises";
import { join, resolve } from "node:path";

type IconNode = {
  tag: string;
  attr?: Record<string, string | number | boolean>;
  child?: IconNode[];
};

type IconDefinition = {
  tag: string;
  attr: { viewBox: string };
  child: IconNode[];
};

const root = resolve(process.argv[2] || process.cwd());
const platform = resolve(process.argv[3] || join(root, "../platform"));
const reactIcons = join(platform, "node_modules/react-icons");
const sources = [join(reactIcons, "fa/index.mjs"), join(reactIcons, "fi/index.mjs")];

function luaQuote(value: string): string {
  return `"${value.replaceAll("\\", "\\\\").replaceAll("\"", "\\\"").replaceAll("\n", "\\n").replaceAll("\r", "\\r")}"`;
}

function markup(node: IconNode): string {
  const attributes = Object.entries(node.attr || {})
    .map(([key, value]) => {
      const name = key === "className" ? "class" : key;
      return ` ${name}="${String(value).replaceAll("&", "&amp;").replaceAll("\"", "&quot;")}"`;
    })
    .join("");
  const children = (node.child || []).map(markup).join("");
  return children ? `<${node.tag}${attributes}>${children}</${node.tag}>` : `<${node.tag}${attributes} />`;
}

function definition(source: string, name: string): IconDefinition | null {
  const expression = new RegExp(`export function ${name} \\(props\\) \\{\\s*return GenIcon\\((\\{.*?\\})\\)\\(props\\);`, "s");
  const match = source.match(expression);
  if (!match) return null;
  return JSON.parse(match[1]) as IconDefinition;
}

const used = new Set<string>();
for (const name of ["FaMinus", "FaBars"]) used.add(name);
for (const pattern of ["src/**/*.ts", "src/**/*.tsx"]) {
  const platformFiles = new Bun.Glob(pattern).scan({ cwd: platform, absolute: true });
  for await (const file of platformFiles) {
    const source = await readFile(file, "utf8");
    for (const match of source.matchAll(/\b(?:Fa|Fi)[A-Z][A-Za-z0-9]+\b/g)) used.add(match[0]);
  }
}

const icons = new Map<string, IconDefinition>();
for (const sourcePath of sources) {
  const source = await readFile(sourcePath, "utf8");
  for (const name of used) {
    if (!name.startsWith(sourcePath.endsWith("/fa/index.mjs") ? "Fa" : "Fi")) continue;
    const icon = definition(source, name);
    if (icon) icons.set(name, icon);
  }
}

const entries = [...icons.entries()].sort(([left], [right]) => left.localeCompare(right));
const output = [
  "<script>",
  '  props { name = "FaQuestionCircle", size = "1.25rem", label = "" }',
  "  icons = {",
  ...entries.map(([name, icon]) => `    [${luaQuote(name)}] = { viewBox = ${luaQuote(icon.attr.viewBox)}, body = ${luaQuote(icon.child.map(markup).join(""))} },`),
  "  }",
  '  icon = icons[name] or icons["FaQuestionCircle"]',
  '  decorative = label == ""',
  "</script>",
  "",
  '<svg class="lunar-icon lunar-icon-{name}" width={size} height={size} viewBox={icon.viewBox} fill="currentColor" aria-hidden={decorative} aria-label={decorative and nil or label}>{@html icon.body}</svg>',
  "",
  "<style>",
  "  .lunar-icon { display: inline-block; flex: 0 0 auto; vertical-align: middle; }",
  "</style>",
  "",
].join("\n");

await mkdir(join(root, "lunar/ui"), { recursive: true });
await writeFile(join(root, "lunar/ui/ReactIcon.lunar"), output);
console.log(`generated ${entries.length} icons in lunar/ui/ReactIcon.lunar`);
