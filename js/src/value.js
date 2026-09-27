// The value model — Core/Sources/Swiftalk/Value.swift in JavaScript.
//
// Representation: JS primitives where they fit, tagged objects elsewhere.
//   nil      → null                 Bool → boolean
//   Int      → BigInt (64-bit, checked at every operation)
//   Double   → number               String → string (graphemes via Intl.Segmenter)
//   Array    → SArray {items, lock} Dictionary → SDictionary (a Map keyed by keyOf)
//   Set      → SSet                 Byte → Byte {v}          Data → SData {bytes: Uint8Array}
//   Date     → SDate {epoch}        Range → SRange {from, to, closed}
//   Tuple    → TupleValue {values, labels}
//   Function, Sequence, Task, enum cases, struct values, host values: classes in eval.js / their modules.
// Every kind answers `kind` through kindOf(); containers are treated as
// immutable — a write builds a new container (Swift's COW value semantics,
// done by hand).
import { SwiftalkError } from './errors.js';
import { TypeAnnotation } from './parser.js';

export const INT64_MAX = (1n << 63n) - 1n;
export const INT64_MIN = -(1n << 63n);

export class SArray { constructor(items, lock = null) { this.items = items; this.lock = lock; } }
export class SDictionary {
  constructor(entries = [], lock = null) { this.map = new Map(); this.lock = lock; for (const [k, v] of entries) this.set(k, v); }
  set(k, v) { this.map.set(keyOf(k), [k, v]); }
  get(k) { const e = this.map.get(keyOf(k)); return e === undefined ? undefined : e[1]; }
  has(k) { return this.map.has(keyOf(k)); }
  delete(k) { return this.map.delete(keyOf(k)); }
  get size() { return this.map.size; }
  entries() { return [...this.map.values()]; }
  keys() { return this.entries().map((e) => e[0]); }
  values() { return this.entries().map((e) => e[1]); }
  clone(lock = this.lock) { const d = new SDictionary([], lock); for (const [key, [k, v]] of this.map) d.map.set(key, [k, v]); return d; }
}
export class SSet {
  constructor(items = [], lock = null) { this.map = new Map(); this.lock = lock; for (const v of items) this.add(v); }
  add(v) { this.map.set(keyOf(v), v); }
  has(v) { return this.map.has(keyOf(v)); }
  delete(v) { return this.map.delete(keyOf(v)); }
  get size() { return this.map.size; }
  values() { return [...this.map.values()]; }
  clone(lock = this.lock) { const s = new SSet([], lock); for (const [key, v] of this.map) s.map.set(key, v); return s; }
}
export class Byte { constructor(v) { this.v = v; } }
export class SData { constructor(bytes) { this.bytes = bytes instanceof Uint8Array ? bytes : Uint8Array.from(bytes); } }
export class SDate { constructor(epoch) { this.epoch = epoch; } }
export class SRange { constructor(from, to, closed) { this.from = from; this.to = to; this.closed = closed; } }
export class TupleValue {
  constructor(values, labels = null) { this.values = values; this.labels = labels ?? values.map(() => null); }
  get count() { return this.values.length; }
  indexOfLabel(label) { const i = this.labels.indexOf(label); return i < 0 ? null : i; }
}

export const V = {
  nil: null,
  bool: (b) => b,
  int: (i) => BigInt(i),
  double: (d) => d,
  string: (s) => s,
  array: (items, lock = null) => new SArray(items, lock),
  dictionary: (entries, lock = null) => new SDictionary(entries, lock),
  set: (items, lock = null) => new SSet(items, lock),
  byte: (v) => new Byte(v),
  data: (bytes) => new SData(bytes),
  date: (epoch) => new SDate(epoch),
  range: (from, to, closed) => new SRange(from, to, closed),
  tuple: (values, labels) => new TupleValue(values, labels),
};

/// The kind tag a value answers: the Swift enum case's name.
export function kindOf(v) {
  if (v === null || v === undefined) return 'nil';
  switch (typeof v) {
    case 'boolean': return 'bool';
    case 'bigint': return 'int';
    case 'number': return 'double';
    case 'string': return 'string';
    default: break;
  }
  if (v instanceof SArray) return 'array';
  if (v instanceof SDictionary) return 'dictionary';
  if (v instanceof SSet) return 'set';
  if (v instanceof Byte) return 'byte';
  if (v instanceof SData) return 'data';
  if (v instanceof SDate) return 'date';
  if (v instanceof SRange) return 'range';
  if (v instanceof TupleValue) return 'tuple';
  return v.kind ?? 'unknown';       // function, sequence, task, enumCase, structValue, host
}

export function typeName(v) {
  switch (kindOf(v)) {
    case 'nil': return 'Nil';
    case 'bool': return 'Bool';
    case 'int': return 'Int';
    case 'double': return 'Double';
    case 'string': return 'String';
    case 'array': return 'Array';
    case 'dictionary': return 'Dictionary';
    case 'set': return 'Set';
    case 'byte': return 'Byte';
    case 'data': return 'Data';
    case 'date': return 'Date';
    case 'range': return 'Range';
    case 'tuple': return 'Tuple';
    case 'function': return 'Function';
    case 'sequence': return 'Sequence';
    case 'task': return 'Task';
    case 'enumCase': return v.type.name;
    case 'structValue': return v.type.name;
    case 'host': return v.object.typeName;
    default: return 'Unknown';
  }
}

// ---- graphemes ----
const segmenter = new Intl.Segmenter(undefined, { granularity: 'grapheme' });
const graphemeCache = new Map();
/// The graphemes of a String — Swift's Characters (§11).
export function graphemes(s) {
  if (s.length < 2) return s.length ? [s] : [];
  let g = graphemeCache.get(s);
  if (g) return g;
  g = Array.from(segmenter.segment(s), (x) => x.segment);
  if (graphemeCache.size > 4096) graphemeCache.clear();
  graphemeCache.set(s, g);
  return g;
}
export const graphemeCount = (s) => graphemes(s).length;

// ---- equality and hashing ----
/// The canonical key of a value — what Dictionary and Set hash by. Strings
/// compare by canonical equivalence (Swift's ==), so NFC; Byte and Int
/// equal by value across the two (round 116).
export function keyOf(v) {
  switch (kindOf(v)) {
    case 'nil': return 'n';
    case 'bool': return v ? 'T' : 'F';
    case 'int': return 'i' + v.toString();
    case 'byte': return 'i' + String(v.v);
    case 'double': return 'd' + (Object.is(v, -0) ? '-0' : String(v));
    case 'string': return 's' + v.normalize('NFC');
    case 'array': return 'a[' + v.items.map(keyOf).join(',') + ']';
    case 'dictionary': return 'D[' + v.entries().map(([k, x]) => keyOf(k) + ':' + keyOf(x)).sort().join(',') + ']';
    case 'set': return 'S[' + v.values().map(keyOf).sort().join(',') + ']';
    case 'data': return 'b' + Array.from(v.bytes).join(',');
    case 'date': return 't' + String(v.epoch);
    case 'range': return 'r' + v.from + (v.closed ? '...' : '..<') + (v.to === null ? '' : v.to);
    case 'tuple': return 'T(' + v.values.map((x, i) => (v.labels[i] ?? '') + '=' + keyOf(x)).join(',') + ')';
    case 'function': return 'f' + (v.identityKey ? v.identityKey() : String(v.id));
    case 'enumCase': return 'e' + v.type.name + '.' + v.caseName + '(' + v.associated.map(keyOf).join(',') + ')';
    case 'structValue': return 'v' + v.type.name + '(' + v.type.propertyOrder.map((p) => p + '=' + keyOf(v.values.get(p) ?? null)).join(',') + ')';
    case 'host': return 'h' + v.object.hashKey();
    default: return 'o' + String(v.id ?? 0);
  }
}
export function equals(a, b) {
  const ka = kindOf(a), kb = kindOf(b);
  if (ka === 'byte' && kb === 'int') return BigInt(a.v) === b;
  if (ka === 'int' && kb === 'byte') return a === BigInt(b.v);
  if (ka !== kb) return false;
  switch (ka) {
    case 'nil': return true;
    case 'bool': case 'int': return a === b;
    case 'double': return a === b;                    // NaN != NaN, 0.0 == -0.0, as Swift
    case 'string': return a === b || a.normalize('NFC') === b.normalize('NFC');
    case 'byte': return a.v === b.v;
    case 'date': return a.epoch === b.epoch;
    case 'function': return a === b || (a.sameAs ? a.sameAs(b) : false);
    case 'sequence': case 'task': return a === b;
    case 'host': return a.object.isEqual(b.object);
    default: return keyOf(a) === keyOf(b);
  }
}

// ---- printing ----
export function formatDouble(d) {
  if (Number.isNaN(d)) return 'nan';
  if (d === Infinity) return 'inf';
  if (d === -Infinity) return '-inf';
  if (d === 0) return Object.is(d, -0) ? '-0.0' : '0.0';
  // shortest round-trip digits, Swift's layout: positional for exponents
  // -4 ..< 16, scientific with a two-digit signed exponent outside
  const exp = d.toExponential();              // "1.2345e+17" — as many digits as needed
  const m = /^(-?)(\d)(?:\.(\d+))?e([+-]\d+)$/.exec(exp);
  const sign = m[1], lead = m[2], frac = m[3] ?? '', e = parseInt(m[4], 10);
  if (e >= 16 || e < -4) {
    const mantissa = frac.length ? `${lead}.${frac}` : lead;
    const ee = Math.abs(e);
    return `${sign}${mantissa}e${e < 0 ? '-' : '+'}${ee < 10 ? '0' + ee : ee}`;
  }
  const digits = lead + frac;
  if (e >= 0) {
    const intPart = digits.slice(0, e + 1).padEnd(e + 1, '0');
    const fracPart = digits.slice(e + 1);
    return `${sign}${intPart}.${fracPart.length ? fracPart : '0'}`;
  }
  return `${sign}0.${'0'.repeat(-e - 1)}${digits}`;
}
export function hexFloat(d, signed = false) {
  if (signed && !Number.isNaN(d) && !(d < 0 || Object.is(d, -0))) return '+' + hexFloat(d);
  if (Number.isNaN(d)) return 'nan';
  if (d === Infinity) return 'inf';
  if (d === -Infinity) return '-inf';
  if (d === 0) return Object.is(d, -0) ? '-0x0p0' : '0x0p0';
  const m = Math.abs(d);
  const view = new DataView(new ArrayBuffer(8));
  view.setFloat64(0, m);
  const bits = view.getBigUint64(0);
  const exponent = Number((bits >> 52n) & 0x7ffn);
  if (exponent === 0) return formatDouble(d);           // subnormal: decimal fallback, as the core
  let hex = (bits & ((1n << 52n) - 1n)).toString(16).padStart(13, '0');
  hex = hex.replace(/0+$/, '');
  return `${d < 0 ? '-' : ''}0x1${hex.length ? '.' + hex : ''}p${exponent - 1023}`;
}
export function quote(s) {
  let out = '"';
  for (const ch of s) {
    const cp = ch.codePointAt(0);
    switch (ch) {
      case '"': out += '\\"'; break;
      case '\\': out += '\\\\'; break;
      case '\n': out += '\\n'; break;
      case '\r': out += '\\r'; break;
      case '\t': out += '\\t'; break;
      case '\0': out += '\\0'; break;
      default: out += cp < 0x20 ? `\\u{${cp.toString(16)}}` : ch;
    }
  }
  return out + '"';
}
const B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
export function base64Encode(bytes) {
  let out = '';
  for (let i = 0; i < bytes.length; i += 3) {
    const a = bytes[i], b = bytes[i + 1], c = bytes[i + 2];
    const n = (a << 16) | ((b ?? 0) << 8) | (c ?? 0);
    out += B64[(n >> 18) & 63] + B64[(n >> 12) & 63] + (b === undefined ? '=' : B64[(n >> 6) & 63]) + (c === undefined ? '=' : B64[n & 63]);
  }
  return out;
}
export function base64Decode(text) {
  const clean = text.replace(/[\s=]/g, '');
  if (!/^[A-Za-z0-9+/]*$/.test(clean)) return null;
  const out = [];
  let buffer = 0, bits = 0;
  for (const ch of clean) {
    buffer = (buffer << 6) | B64.indexOf(ch);
    bits += 6;
    if (bits >= 8) { bits -= 8; out.push((buffer >> bits) & 0xff); }
  }
  return Uint8Array.from(out);
}
export const spreadsInSet = (x) => ['array', 'string', 'dictionary', 'set', 'range', 'sequence', 'tuple', 'data'].includes(kindOf(x));

/// The source form — `eval(x.String()) == x` (§3d); `debug` is the
/// debugDescription. `custom` may answer for a struct or enum with its
/// own `String` member (round 152); the evaluator supplies it.
export function sourceString(v, debug = false, custom = null) {
  if (custom) { const own = custom(v); if (own != null) return own; }
  const rec = (x) => sourceString(x, debug, custom);
  switch (kindOf(v)) {
    case 'nil': return 'nil';
    case 'bool': return v ? 'true' : 'false';
    case 'int': return debug ? (v < 0n ? '-0x' : '+0x') + (v < 0n ? -v : v).toString(16) : v.toString();
    case 'double': return debug ? hexFloat(v, true) : formatDouble(v);
    case 'string': return quote(v);
    case 'array': return '[' + v.items.map(rec).join(', ') + ']';
    case 'function': return v.sourceString ? v.sourceString() : '{ ... }';
    case 'range': {
      const lo = sourceString(v.from, debug, custom);
      if (v.to === null) return lo + '...';
      return lo + (v.closed ? '...' : '..<') + sourceString(v.to, debug, custom);
    }
    case 'sequence': return 'Sequence { ... }';
    case 'task': return 'Task { ... }';
    case 'tuple': {
      const body = v.values.map((x, i) => (v.labels[i] !== null ? `${v.labels[i]}: ` : '') + rec(x)).join(', ');
      const lonely = v.count === 1 && v.labels[0] === null;
      return '(' + body + (lonely ? ',)' : ')');
    }
    case 'byte': return 'Byte(' + (debug ? '0x' + v.v.toString(16) : String(v.v)) + ')';
    case 'data':
      if (debug) return 'Data([' + Array.from(v.bytes, (b) => '0x' + b.toString(16)).join(', ') + '])';
      return `.Data("${base64Encode(v.bytes)}")`;
    case 'date': return `.Date(${debug ? hexFloat(v.epoch) : formatDouble(v.epoch)})`;
    case 'host': return v.object.sourceString(debug);
    case 'structValue':
      return v.type.name + '(' + v.type.propertyOrder.map((p) => `${p}: ${rec(v.values.get(p) ?? null)}`).join(', ') + ')';
    case 'enumCase': {
      let out = `${v.type.name}.${v.caseName}`;
      if (v.associated.length) {
        const params = v.type.cases.get(v.caseName) ?? [];
        out += '(' + v.associated.map((x, i) => {
          const s = rec(x);
          const label = params[i]?.label;
          return label ? `${label}: ${s}` : s;
        }).join(', ') + ')';
      }
      return out;
    }
    case 'set': {
      if (v.size === 0) return 'Set()';
      const elements = v.values().map(rec).sort(compareStrings);
      if (v.size === 1 && spreadsInSet(v.values()[0])) return 'Set([' + elements[0] + '])';
      return 'Set(' + elements.join(', ') + ')';
    }
    case 'dictionary': {
      if (v.size === 0) return '[:]';
      return '[' + v.entries().map(([k, x]) => ({ key: rec(k), value: rec(x) }))
        .sort((a, b) => compareStrings(a.key, b.key)).map((e) => `${e.key}: ${e.value}`).join(', ') + ']';
    }
    default: return '<unknown>';
  }
}
/// Swift's String `<`: Unicode scalar order (not UTF-16 code units).
export function compareStrings(a, b) {
  if (a === b) return 0;
  const ai = a[Symbol.iterator](), bi = b[Symbol.iterator]();
  for (;;) {
    const x = ai.next(), y = bi.next();
    if (x.done) return y.done ? 0 : -1;
    if (y.done) return 1;
    const cx = x.value.codePointAt(0), cy = y.value.codePointAt(0);
    if (cx !== cy) return cx < cy ? -1 : 1;
  }
}

/// Int64 arithmetic: the result if it fits, else null — overflow is the
/// caller's trap (§3b).
export function fits64(n) { return n >= INT64_MIN && n <= INT64_MAX; }
export function checkInt(n, what) {
  if (!fits64(n)) throw SwiftalkError.overflow(what);
  return n;
}
export { TypeAnnotation };
