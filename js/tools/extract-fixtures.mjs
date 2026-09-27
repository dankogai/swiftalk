#!/usr/bin/env node
// Turns the Swift test corpus into JSON the JS runtime can be checked
// against: every `#expect(try eval("...") == .value)` and every
// `#expect(throws: SwiftalkError.self) { try eval("...") }` in
// Tests/SwiftalkTests/*.swift. Expected values are the Swift Value
// literals, parsed into JSON: {nil} {bool} {int:"n"} {double} {string}
// {array:[…]} {set:[…]} {dictionary:[[k,v]…]} {byte} {data:[…]} {date}
// {tuple:[…], labels:[…]}. Anything the extractor cannot read is counted
// and skipped — the corpus is an aid, not the law.
import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const testsDir = join(here, '..', '..', 'Tests', 'SwiftalkTests');
const out = join(here, '..', 'test', 'fixtures.json');

/// A Swift string literal starting at s[i] (the opening quote); returns
/// [decoded, indexAfter] or null when it interpolates (\( ) or is odd.
function swiftString(s, i) {
  if (s.startsWith('"""', i)) {
    const end = s.indexOf('"""', i + 3);
    if (end < 0) return null;
    let body = s.slice(i + 3, end);
    // Swift's multi-line rule: drop the first newline, strip the closing indentation
    const lines = body.split('\n');
    if (lines[0].trim() === '') lines.shift();
    const last = lines[lines.length - 1];
    const indent = last.trim() === '' ? last.length : 0;
    if (last.trim() === '') lines.pop();
    const text = lines.map((l) => l.slice(indent)).join('\n');
    if (/(^|[^\\])\\\(/.test(text)) return null;
    return [unescape(text), end + 3];
  }
  let j = i + 1;
  let raw = '';
  while (j < s.length) {
    const c = s[j];
    if (c === '\\') {
      if (s[j + 1] === '(') return null;              // Swift interpolation: not a fixture
      raw += c + s[j + 1]; j += 2; continue;
    }
    if (c === '"') return [unescape(raw), j + 1];
    raw += c; j++;
  }
  return null;
}
function unescape(raw) {
  let out = '';
  for (let i = 0; i < raw.length; i++) {
    const c = raw[i];
    if (c !== '\\') { out += c; continue; }
    const e = raw[++i];
    switch (e) {
      case 'n': out += '\n'; break;
      case 't': out += '\t'; break;
      case 'r': out += '\r'; break;
      case '0': out += '\0'; break;
      case '"': out += '"'; break;
      case '\\': out += '\\'; break;
      case 'u': {
        const close = raw.indexOf('}', i);
        out += String.fromCodePoint(parseInt(raw.slice(i + 2, close), 16));
        i = close;
        break;
      }
      default: out += '\\' + e;
    }
  }
  return out;
}

/// Parses a Swift Value literal (`.int(4)`, `.array([...])`, …) at s[i];
/// returns [json, indexAfter] or null.
function swiftValue(s, i) {
  const ws = () => { while (i < s.length && /\s/.test(s[i])) i++; };
  ws();
  const m = /^\.([a-zA-Z]+)/.exec(s.slice(i));
  if (!m) return null;
  const name = m[1];
  i += m[0].length;
  const expectParen = () => { ws(); if (s[i] !== '(') return false; i++; ws(); return true; };
  const closeParen = () => { ws(); if (s[i] !== ')') return false; i++; return true; };
  const number = () => { const n = /^[-+]?(?:0x[0-9a-fA-F_]+|\d[\d_]*(?:\.\d+)?(?:e[-+]?\d+)?|\.inf|\.nan)/.exec(s.slice(i)); if (!n) return null; i += n[0].length; return n[0].replace(/_/g, ''); };
  const list = (close) => {
    const items = [];
    ws();
    if (s[i] === close) { i++; return items; }
    for (;;) {
      const v = swiftValue(s, i);
      if (!v) return null;
      items.push(v[0]); i = v[1];
      ws();
      if (s[i] === ',') { i++; ws(); continue; }
      if (s[i] === close) { i++; return items; }
      return null;
    }
  };
  switch (name) {
    case 'nil': return [{ nil: true }, i];
    case 'bool': { if (!expectParen()) return null; const b = /^(true|false)/.exec(s.slice(i)); if (!b) return null; i += b[0].length; if (!closeParen()) return null; return [{ bool: b[0] === 'true' }, i]; }
    case 'int': { if (!expectParen()) return null; const n = number(); if (n === null) return null; if (!closeParen()) return null; return [{ int: n }, i]; }
    case 'byte': { if (!expectParen()) return null; const n = number(); if (n === null) return null; if (!closeParen()) return null; return [{ byte: Number(n) }, i]; }
    case 'double': {
      if (!expectParen()) return null;
      let n = number();
      if (n === null) { const sp = /^(-?)Double\.(infinity|nan|pi)/.exec(s.slice(i)); if (!sp) return null; i += sp[0].length; n = sp[1] + (sp[2] === 'infinity' ? 'Infinity' : sp[2] === 'nan' ? 'NaN' : 'pi'); }
      if (!closeParen()) return null;
      return [{ double: n }, i];
    }
    case 'date': { if (!expectParen()) return null; const n = number(); if (n === null) return null; if (!closeParen()) return null; return [{ date: n }, i]; }
    case 'string': { if (!expectParen()) return null; const str = swiftString(s, i); if (!str) return null; i = str[1]; if (!closeParen()) return null; return [{ string: str[0] }, i]; }
    case 'array': case 'set': {
      if (!expectParen()) return null;
      if (s[i] !== '[') return null; i++;
      const items = list(']'); if (!items) return null;
      ws();
      if (s[i] === ',') return null;                 // a lock argument: skip such fixtures
      if (!closeParen()) return null;
      return [{ [name]: items }, i];
    }
    case 'data': {
      if (!expectParen()) return null;
      if (s[i] !== '[') return null; i++;
      const bytes = [];
      ws();
      while (s[i] !== ']') { const n = number(); if (n === null) return null; bytes.push(Number(n)); ws(); if (s[i] === ',') { i++; ws(); } }
      i++;
      if (!closeParen()) return null;
      return [{ data: bytes }, i];
    }
    case 'tuple': {
      if (!expectParen()) return null;
      if (s[i] !== '[') return null; i++;
      const items = list(']'); if (!items) return null;
      ws();
      let labels = items.map(() => null);
      if (s[i] === ',') {
        i++; ws();
        const lm = /^labels:\s*\[/.exec(s.slice(i)); if (!lm) return null; i += lm[0].length;
        labels = [];
        ws();
        while (s[i] !== ']') {
          if (s.startsWith('nil', i)) { labels.push(null); i += 3; }
          else { const str = swiftString(s, i); if (!str) return null; labels.push(str[0]); i = str[1]; }
          ws(); if (s[i] === ',') { i++; ws(); }
        }
        i++;
      }
      if (!closeParen()) return null;
      return [{ tuple: items, labels }, i];
    }
    case 'dictionary': {
      if (!expectParen()) return null;
      if (s[i] !== '[') return null; i++;
      const pairs = [];
      ws();
      if (s[i] === ':') { i++; ws(); if (s[i] !== ']') return null; }
      while (s[i] !== ']') {
        const k = swiftValue(s, i); if (!k) return null; i = k[1]; ws();
        if (s[i] !== ':') return null; i++;
        const v = swiftValue(s, i); if (!v) return null; i = v[1]; ws();
        pairs.push([k[0], v[0]]);
        if (s[i] === ',') { i++; ws(); }
      }
      i++;
      if (!closeParen()) return null;
      return [{ dictionary: pairs }, i];
    }
    default: return null;
  }
}

const fixtures = [];
let skipped = 0;
/// Drops the tests Swift itself skips: a `@Suite(..., .disabled(...))`
/// empties the file, a `@Test(..., .disabled(...))` its body — the
/// shelved `class`/`actor` surface (round 62) lives there.
function enabledOnly(text) {
  if (/@Suite\([^\n]*\.disabled\(/.test(text)) return '';
  const parts = text.split(/(?=@Test\()/);
  return parts.filter((part) => !/^@Test\([^\n]*\.disabled\(/.test(part)).join('');
}

for (const file of readdirSync(testsDir).filter((f) => f.endsWith('.swift')).sort()) {
  const text = enabledOnly(readFileSync(join(testsDir, file), 'utf8'));
  // values: #expect(try eval("...") == <value>)
  const re = /#expect\(try eval\(/g;
  let m;
  while ((m = re.exec(text))) {
    const str = swiftString(text, m.index + m[0].length);
    if (!str) { skipped++; continue; }
    let i = str[1];
    while (/\s/.test(text[i])) i++;
    if (text[i] !== ')') { skipped++; continue; }
    i++;
    const cmp = /^\s*==\s*/.exec(text.slice(i));
    if (!cmp) { skipped++; continue; }
    i += cmp[0].length;
    const value = swiftValue(text, i);
    if (!value) { skipped++; continue; }
    let j = value[1];
    while (/\s/.test(text[j])) j++;
    if (text[j] !== ')') { skipped++; continue; }
    fixtures.push({ file, source: str[0], expect: value[0] });
  }
  // throws: #expect(throws: SwiftalkError.self) { try eval("...") }
  const rt = /#expect\(throws: SwiftalkError\.self\) \{ try eval\(/g;
  while ((m = rt.exec(text))) {
    const str = swiftString(text, m.index + m[0].length);
    if (!str) { skipped++; continue; }
    let i = str[1];
    while (/\s/.test(text[i])) i++;
    if (text[i] !== ')') { skipped++; continue; }
    fixtures.push({ file, source: str[0], throws: true });
  }
}
writeFileSync(out, JSON.stringify(fixtures, null, 1));
const values = fixtures.filter((f) => !f.throws).length;
console.log(`${fixtures.length} fixtures (${values} values, ${fixtures.length - values} throws) from ${new Set(fixtures.map((f) => f.file)).size} files; ${skipped} expectations skipped`);
