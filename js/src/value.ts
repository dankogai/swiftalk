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
import type { FunctionObject, SequenceObject, TaskObject, EnumCaseValue, StructValue, HostValue } from './objects.js';

/// A swiftalk value — Value.swift's enum, as the JS representations above.
export type Value =
  | null | boolean | bigint | number | string
  | SArray | SDictionary | SSet | Byte | SData | SDate | SRange | TupleValue
  | FunctionObject | SequenceObject | TaskObject | EnumCaseValue | StructValue | HostValue;
/// The kind tag `kindOf` answers: the Swift enum case's name.
export type Kind = 'nil' | 'bool' | 'int' | 'double' | 'string' | 'array' | 'dictionary' | 'set' | 'byte' | 'data' | 'date'
  | 'range' | 'tuple' | 'function' | 'sequence' | 'task' | 'enumCase' | 'structValue' | 'host' | 'unknown';
/// A call argument as the evaluator passes it: the label and the value.
export type LabeledArg = { label: string | null; value: Value };
/// A container's stamp (round 165): the parameterized annotation it was built or bound under.
export type Lock = TypeAnnotation | null;

export const INT64_MAX = (1n << 63n) - 1n;
export const INT64_MIN = -(1n << 63n);

export class SArray {
  items: Value[];
  lock: Lock;
  constructor(items: Value[], lock: Lock = null) { this.items = items; this.lock = lock; }
}
export class SDictionary {
  map: Map<string, [Value, Value]>;
  lock: Lock;
  constructor(entries: Iterable<[Value, Value]> = [], lock: Lock = null) { this.map = new Map(); this.lock = lock; for (const [k, v] of entries) this.set(k, v); }
  set(k: Value, v: Value): void { this.map.set(keyOf(k), [k, v]); }
  get(k: Value): Value | undefined { const e = this.map.get(keyOf(k)); return e === undefined ? undefined : e[1]; }
  has(k: Value): boolean { return this.map.has(keyOf(k)); }
  delete(k: Value): boolean { return this.map.delete(keyOf(k)); }
  get size(): number { return this.map.size; }
  entries(): [Value, Value][] { return [...this.map.values()]; }
  keys(): Value[] { return this.entries().map((e) => e[0]); }
  values(): Value[] { return this.entries().map((e) => e[1]); }
  clone(lock: Lock = this.lock): SDictionary { const d = new SDictionary([], lock); for (const [key, [k, v]] of this.map) d.map.set(key, [k, v]); return d; }
}
export class SSet {
  map: Map<string, Value>;
  lock: Lock;
  constructor(items: Iterable<Value> = [], lock: Lock = null) { this.map = new Map(); this.lock = lock; for (const v of items) this.add(v); }
  add(v: Value): void { this.map.set(keyOf(v), v); }
  has(v: Value): boolean { return this.map.has(keyOf(v)); }
  delete(v: Value): boolean { return this.map.delete(keyOf(v)); }
  get size(): number { return this.map.size; }
  values(): Value[] { return [...this.map.values()]; }
  clone(lock: Lock = this.lock): SSet { const s = new SSet([], lock); for (const [key, v] of this.map) s.map.set(key, v); return s; }
}
export class Byte { v: number; constructor(v: number) { this.v = v; } }
export class SData { bytes: Uint8Array; constructor(bytes: Uint8Array | ArrayLike<number> | Iterable<number>) { this.bytes = bytes instanceof Uint8Array ? bytes : Uint8Array.from(bytes as ArrayLike<number>); } }
export class SDate { epoch: number; constructor(epoch: number) { this.epoch = epoch; } }
/// `from...to`, `from..<to`; `to` is null for the unbounded `from...` (round 88).
export class SRange { from: bigint; to: bigint | null; closed: boolean; constructor(from: bigint, to: bigint | null, closed: boolean) { this.from = from; this.to = to; this.closed = closed; } }
export class TupleValue {
  values: Value[];
  labels: (string | null)[];
  constructor(values: Value[], labels: (string | null)[] | null = null) { this.values = values; this.labels = labels ?? values.map(() => null); }
  get count(): number { return this.values.length; }
  indexOfLabel(label: string): number | null { const i = this.labels.indexOf(label); return i < 0 ? null : i; }
}

export const V = {
  nil: null as null,
  bool: (b: boolean): boolean => b,
  int: (i: number | bigint | string): bigint => BigInt(i),
  double: (d: number): number => d,
  string: (s: string): string => s,
  array: (items: Value[], lock: Lock = null): SArray => new SArray(items, lock),
  dictionary: (entries: Iterable<[Value, Value]>, lock: Lock = null): SDictionary => new SDictionary(entries, lock),
  set: (items: Iterable<Value>, lock: Lock = null): SSet => new SSet(items, lock),
  byte: (v: number): Byte => new Byte(v),
  data: (bytes: Uint8Array | ArrayLike<number>): SData => new SData(bytes),
  date: (epoch: number): SDate => new SDate(epoch),
  range: (from: bigint, to: bigint | null, closed: boolean): SRange => new SRange(from, to, closed),
  tuple: (values: Value[], labels?: (string | null)[] | null): TupleValue => new TupleValue(values, labels),
};

/// The kind tag a value answers: the Swift enum case's name.
export function kindOf(v: Value | undefined): Kind {
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
  return ((v as { kind?: Kind }).kind) ?? 'unknown';       // function, sequence, task, enumCase, structValue, host
}

export function typeName(v: Value): string {
  const x = v as any;
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
    case 'enumCase': return x.type.name;
    case 'structValue': return x.type.name;
    case 'host': return x.object.typeName;
    default: return 'Unknown';
  }
}

// ---- graphemes ----
const segmenter = new Intl.Segmenter(undefined, { granularity: 'grapheme' });
const graphemeCache = new Map<string, string[]>();
/// The graphemes of a String — Swift's Characters (§11).
export function graphemes(s: string): string[] {
  if (s.length < 2) return s.length ? [s] : [];
  let g = graphemeCache.get(s);
  if (g) return g;
  g = Array.from(segmenter.segment(s), (x) => x.segment);
  if (graphemeCache.size > 4096) graphemeCache.clear();
  graphemeCache.set(s, g);
  return g;
}
export const graphemeCount = (s: string): number => graphemes(s).length;

// ---- equality and hashing ----
/// The canonical key of a value — what Dictionary and Set hash by. Strings
/// compare by canonical equivalence (Swift's ==), so NFC; Byte and Int
/// equal by value across the two (round 116).
export function keyOf(v: Value): string {
  const x = v as any;
  switch (kindOf(v)) {
    case 'nil': return 'n';
    case 'bool': return x ? 'T' : 'F';
    case 'int': return 'i' + x.toString();
    case 'byte': return 'i' + String(x.v);
    case 'double': return 'd' + String(x);                 // -0.0 hashes with 0.0, as Swift
    case 'string': return 's' + x.normalize('NFC');
    case 'array': return 'a[' + x.items.map(keyOf).join(',') + ']';
    case 'dictionary': return 'D[' + x.entries().map(([k, x]) => keyOf(k) + ':' + keyOf(x)).sort().join(',') + ']';
    case 'set': return 'S[' + x.values().map(keyOf).sort().join(',') + ']';
    case 'data': return 'b' + Array.from(x.bytes).join(',');
    case 'date': return 't' + String(x.epoch);
    case 'range': return 'r' + x.from + (x.closed ? '...' : '..<') + (x.to === null ? '' : x.to);
    case 'tuple': return 'T(' + x.values.map(keyOf).join(',') + ')';   // labels do not take part in == (round 70)
    case 'function': return 'f' + (x.identityKey ? x.identityKey() : String(x.id));
    case 'enumCase': return 'e' + x.type.name + '.' + x.caseName + '(' + x.associated.map(keyOf).join(',') + ')';
    case 'structValue': return 'v' + x.type.name + '(' + x.type.propertyOrder.map((p) => p + '=' + keyOf(x.values.get(p) ?? null)).join(',') + ')';
    case 'host': return 'h' + x.object.hashKey();
    default: return 'o' + String(x.id ?? 0);
  }
}
export function equals(a: Value, b: Value): boolean {
  const ka = kindOf(a), kb = kindOf(b);
  const x = a as any, y = b as any;
  if (ka === 'byte' && kb === 'int') return BigInt(x.v) === b;
  if (ka === 'int' && kb === 'byte') return a === BigInt(y.v);
  if (ka !== kb) return false;
  switch (ka) {
    case 'nil': return true;
    case 'bool': case 'int': return a === b;
    case 'double': return a === b;                    // NaN != NaN, 0.0 == -0.0, as Swift
    case 'string': return a === b || x.normalize('NFC') === y.normalize('NFC');
    case 'byte': return x.v === y.v;
    case 'date': return x.epoch === y.epoch;
    case 'function': return a === b || (x.sameAs ? x.sameAs(b) : false);
    case 'sequence': case 'task': return a === b;
    case 'host': return x.object.isEqual(y.object);
    default: return keyOf(a) === keyOf(b);
  }
}

// ---- printing ----
export function formatDouble(d: number): string {
  if (Number.isNaN(d)) return 'nan';
  if (d === Infinity) return 'inf';
  if (d === -Infinity) return '-inf';
  if (d === 0) return Object.is(d, -0) ? '-0.0' : '0.0';
  // shortest round-trip digits, Swift's layout: positional for exponents
  // -4 ..< 16, scientific with a two-digit signed exponent outside
  const exp = d.toExponential();              // "1.2345e+17" — as many digits as needed
  const m = /^(-?)(\d)(?:\.(\d+))?e([+-]\d+)$/.exec(exp)!;
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
export function hexFloat(d: number, signed = false): string {
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
export function quote(s: string): string {
  let out = '"';
  for (const ch of s) {
    const cp = ch.codePointAt(0)!;
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
export function base64Encode(bytes: Uint8Array | number[]): string {
  let out = '';
  for (let i = 0; i < bytes.length; i += 3) {
    const a = bytes[i], b = bytes[i + 1], c = bytes[i + 2];
    const n = (a! << 16) | ((b ?? 0) << 8) | (c ?? 0);
    out += B64[(n >> 18) & 63] + B64[(n >> 12) & 63] + (b === undefined ? '=' : B64[(n >> 6) & 63]) + (c === undefined ? '=' : B64[n & 63]);
  }
  return out;
}
export function base64Decode(text: string): Uint8Array | null {
  const clean = text.replace(/[\s=]/g, '');
  if (!/^[A-Za-z0-9+/]*$/.test(clean)) return null;
  const out: number[] = [];
  let buffer = 0, bits = 0;
  for (const ch of clean) {
    buffer = (buffer << 6) | B64.indexOf(ch);
    bits += 6;
    if (bits >= 8) { bits -= 8; out.push((buffer >> bits) & 0xff); }
  }
  return Uint8Array.from(out);
}
export const spreadsInSet = (x: Value): boolean => ['array', 'string', 'dictionary', 'set', 'range', 'sequence', 'tuple', 'data'].includes(kindOf(x));

/// The source form — `eval(x.String()) == x` (§3d); `debug` is the
/// debugDescription. `custom` may answer for a struct or enum with its
/// own `String` member (round 152); the evaluator supplies it.
export type CustomText = ((v: Value) => string | null | undefined) | null;
export function sourceString(v: Value, debug = false, custom: CustomText = null): string {
  if (custom) { const own = custom(v); if (own != null) return own; }
  const rec = (x: Value) => sourceString(x, debug, custom);
  const o = v as any;
  switch (kindOf(v)) {
    case 'nil': return 'nil';
    case 'bool': return o ? 'true' : 'false';
    case 'int': return debug ? (o < 0n ? '-0x' : '+0x') + (o < 0n ? -o : o).toString(16) : o.toString();
    case 'double': return debug ? hexFloat(o, true) : formatDouble(o);
    case 'string': return quote(o);
    case 'array': return '[' + o.items.map(rec).join(', ') + ']';
    case 'function': return o.sourceString ? o.sourceString() : '{ ... }';
    case 'range': {
      const lo = sourceString(o.from, debug, custom);
      if (o.to === null) return lo + '...';
      return lo + (o.closed ? '...' : '..<') + sourceString(o.to, debug, custom);
    }
    case 'sequence': return 'Sequence { ... }';
    case 'task': return 'Task { ... }';
    case 'tuple': {
      const body = o.values.map((x: Value, i: number) => (o.labels[i] !== null ? `${o.labels[i]}: ` : '') + rec(x)).join(', ');
      const lonely = o.count === 1 && o.labels[0] === null;
      return '(' + body + (lonely ? ',)' : ')');
    }
    case 'byte': return 'Byte(' + (debug ? '0x' + o.v.toString(16) : String(o.v)) + ')';
    case 'data':
      if (debug) return 'Data([' + Array.from(o.bytes as Uint8Array, (b: number) => '0x' + b.toString(16)).join(', ') + '])';
      return `.Data("${base64Encode(o.bytes)}")`;
    case 'date': return `.Date(${debug ? hexFloat(o.epoch) : formatDouble(o.epoch)})`;
    case 'host': return o.object.sourceString(debug);
    case 'structValue':
      return o.type.name + '(' + o.type.propertyOrder.map((p: string) => `${p}: ${rec(o.values.get(p) ?? null)}`).join(', ') + ')';
    case 'enumCase': {
      let out = `${o.type.name}.${o.caseName}`;
      if (o.associated.length) {
        const params = o.type.cases.get(o.caseName) ?? [];
        out += '(' + o.associated.map((x: Value, i: number) => {
          const s = rec(x);
          const label = params[i]?.label;
          return label ? `${label}: ${s}` : s;
        }).join(', ') + ')';
      }
      return out;
    }
    case 'set': {
      if (o.size === 0) return 'Set()';
      const elements: string[] = o.values().map(rec).sort(compareStrings);
      if (o.size === 1 && spreadsInSet(o.values()[0])) return 'Set([' + elements[0] + '])';
      return 'Set(' + elements.join(', ') + ')';
    }
    case 'dictionary': {
      if (o.size === 0) return '[:]';
      return '[' + o.entries().map(([k, x]: [Value, Value]) => ({ key: rec(k), value: rec(x) }))
        .sort((a: { key: string }, b: { key: string }) => compareStrings(a.key, b.key)).map((e: { key: string; value: string }) => `${e.key}: ${e.value}`).join(', ') + ']';
    }
    default: return '<unknown>';
  }
}
/// Swift's String `<`: Unicode scalar order (not UTF-16 code units).
export function compareStrings(a: string, b: string): number {
  if (a === b) return 0;
  const ai = a[Symbol.iterator](), bi = b[Symbol.iterator]();
  for (;;) {
    const x = ai.next(), y = bi.next();
    if (x.done) return y.done ? 0 : -1;
    if (y.done) return 1;
    const cx = x.value.codePointAt(0)!, cy = y.value.codePointAt(0)!;
    if (cx !== cy) return cx < cy ? -1 : 1;
  }
}

/// Int64 arithmetic: the result if it fits, else null — overflow is the
/// caller's trap (§3b).
export function fits64(n: bigint): boolean { return n >= INT64_MIN && n <= INT64_MAX; }
export function checkInt(n: bigint, what: string): bigint {
  if (!fits64(n)) throw SwiftalkError.overflow(what);
  return n;
}
export { TypeAnnotation };
