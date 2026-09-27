#!/usr/bin/env node
// A bundler with no dependencies: concatenates src/ into one ES module,
// dist/swiftalk.js, and inlines it into dist/notebook.html so the
// notebook opens from a file. The modules are plain ESM with relative
// imports and no top-level name collisions (checked here), so the bundle
// is the files in dependency order, `import` lines dropped and `export`
// keywords stripped, ending in one export list — the live bindings the
// cyclic imports rely on are simply the same scope.
import { readFileSync, writeFileSync, mkdirSync, readdirSync, statSync } from 'node:fs';
import { dirname, resolve, relative, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const src = join(root, 'src');
const entry = join(src, 'index.js');

const files = new Map();       // path → source
const order = [];
const importRe = /^import\s+(?:([\w$]+|\{[^}]*\}|\*\s+as\s+[\w$]+)\s+from\s+)?['"](\.[^'"]+)['"];?\s*$/gm;
const exportFromRe = /^export\s+(\{[^}]*\}|\*)\s+from\s+['"](\.[^'"]+)['"];?\s*$/gm;
function visit(path, stack = []) {
  if (files.has(path)) return;
  const text = readFileSync(path, 'utf8');
  files.set(path, text);
  const deps = [];
  for (const m of text.matchAll(importRe)) deps.push(resolve(dirname(path), m[2]));
  for (const m of text.matchAll(exportFromRe)) deps.push(resolve(dirname(path), m[2]));
  for (const d of deps) visit(d, [...stack, path]);
  order.push(path);
}
visit(entry);

// the top-level names, checked for collisions
const declRe = /^(?:export\s+)?(?:async\s+)?(?:function\*?|const|let|var|class)\s+([\w$]+)/gm;
const seen = new Map();
for (const path of order) {
  for (const m of files.get(path).matchAll(declRe)) {
    const name = m[1];
    if (seen.has(name) && seen.get(name) !== path) throw new Error(`top-level name '${name}' is declared in both ${relative(root, seen.get(name))} and ${relative(root, path)} — the bundle is one scope`);
    seen.set(name, path);
  }
}
// what index.js exports, by name
const exported = new Set();
const exportsOf = (path) => {
  const out = new Set();
  const text = files.get(path);
  for (const m of text.matchAll(/^export\s+(?:async\s+)?(?:function\*?|const|let|var|class)\s+([\w$]+)/gm)) out.add(m[1]);
  for (const m of text.matchAll(/^export\s+\{([^}]*)\}\s*;?\s*$/gm)) for (const n of m[1].split(',')) { const t = n.trim(); if (t) out.add(t.split(/\s+as\s+/).pop()); }
  return out;
};
const indexText = files.get(entry);
for (const m of indexText.matchAll(exportFromRe)) {
  const dep = resolve(dirname(entry), m[2]);
  if (m[1] === '*') for (const n of exportsOf(dep)) exported.add(n);
  else for (const n of m[1].slice(1, -1).split(',')) { const t = n.trim(); if (t) exported.add(t.split(/\s+as\s+/).pop()); }
}
for (const n of exportsOf(entry)) exported.add(n);

let bundle = `// swiftalk in JavaScript — one file, bundled from js/src by tools/bundle.mjs. Do not edit; edit src/.\n`;
for (const path of order) {
  let text = files.get(path);
  text = text.replace(importRe, '').replace(exportFromRe, '');
  text = text.replace(/^export\s+\{[^}]*\}\s*;?\s*$/gm, '');
  text = text.replace(/^export\s+(?=(?:async\s+)?(?:function|const|let|var|class)\b)/gm, '');
  bundle += `\n// ---- ${relative(root, path)} ----\n${text.trim()}\n`;
}
bundle += `\nexport { ${[...exported].sort().join(', ')} };\n`;

mkdirSync(join(root, 'dist'), { recursive: true });
writeFileSync(join(root, 'dist', 'swiftalk.js'), bundle);

// the notebook, single-file: the bundle inlined where the page imports it
const page = readFileSync(join(root, 'notebook.html'), 'utf8');
const marker = /<script type="module" src="\.\/src\/index\.js" id="swiftalk"><\/script>\s*<script type="module" id="notebook">/;
if (!marker.test(page)) throw new Error('notebook.html: the two module scripts were not found where expected');
const inlined = page.replace(marker, () => `<script type="module" id="notebook">\n${bundle.replace(/^export \{[^}]*\};\s*$/m, '').replace(/<\/script/g, '<\\/script')}\n`)
  .replace(/^import \{([^}]*)\} from '\.\/src\/index\.js';\s*$/m, '');
writeFileSync(join(root, 'dist', 'notebook.html'), inlined);
// ...and the same page as a fragment — no doctype, html, head, or body of its
// own — for hosts that wrap pages in their own skeleton (claude.ai's Artifacts)
const fragment = inlined.replace(/^<!doctype html>\s*<html[^>]*>\s*<head>\s*/i, '').replace(/<meta charset="utf-8">\s*<meta name="viewport"[^>]*>\s*/i, '')
  .replace(/<\/head>\s*<body>/i, '').replace(/<\/body>\s*<\/html>\s*$/i, '');
writeFileSync(join(root, 'dist', 'notebook.fragment.html'), fragment);
console.log(`dist/swiftalk.js: ${(bundle.length / 1024).toFixed(0)} KB from ${order.length} modules; dist/notebook.html: ${(inlined.length / 1024).toFixed(0)} KB`);
