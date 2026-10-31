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
import { FunctionObject, SequenceObject, TaskObject, EnumCaseValue, StructValue, HostValue } from './objects.js';

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

// ---- the guards (round 256): one per kind, so a check narrows and no cast follows ----
export const isNil = (v: Value | undefined): v is null | undefined => v == null;
export const isBool = (v: Value | undefined): v is boolean => typeof v === 'boolean';
export const isInt = (v: Value | undefined): v is bigint => typeof v === 'bigint';
export const isDouble = (v: Value | undefined): v is number => typeof v === 'number';
export const isString = (v: Value | undefined): v is string => typeof v === 'string';
export const isArray = (v: Value | undefined): v is SArray => v instanceof SArray;
export const isDictionary = (v: Value | undefined): v is SDictionary => v instanceof SDictionary;
export const isSet = (v: Value | undefined): v is SSet => v instanceof SSet;
export const isByte = (v: Value | undefined): v is Byte => v instanceof Byte;
export const isData = (v: Value | undefined): v is SData => v instanceof SData;
export const isDate = (v: Value | undefined): v is SDate => v instanceof SDate;
export const isRange = (v: Value | undefined): v is SRange => v instanceof SRange;
export const isTuple = (v: Value | undefined): v is TupleValue => v instanceof TupleValue;
export const isFunction = (v: Value | undefined): v is FunctionObject => v instanceof FunctionObject;
export const isSequence = (v: Value | undefined): v is SequenceObject => v instanceof SequenceObject;
export const isTask = (v: Value | undefined): v is TaskObject => v instanceof TaskObject;
export const isEnumCase = (v: Value | undefined): v is EnumCaseValue => v instanceof EnumCaseValue;
export const isStructValue = (v: Value | undefined): v is StructValue => v instanceof StructValue;
export const isHost = (v: Value | undefined): v is HostValue => v instanceof HostValue;
/// A container with a stamp: an Array, a Dictionary, or a Set.
export const isContainer = (v: Value | undefined): v is SArray | SDictionary | SSet => isArray(v) || isDictionary(v) || isSet(v);

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
  if (v instanceof FunctionObject || v instanceof SequenceObject || v instanceof TaskObject || v instanceof EnumCaseValue || v instanceof StructValue || v instanceof HostValue) return v.kind;
  return 'unknown';
}

export function typeName(v: Value): string {
  if (isEnumCase(v) || isStructValue(v)) return v.type.name;
  if (isHost(v)) return v.object.typeName;
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
  if (v === null) return 'n';
  if (isBool(v)) return v ? 'T' : 'F';
  if (isInt(v)) return 'i' + v.toString();
  if (isByte(v)) return 'i' + String(v.v);
  if (isDouble(v)) return 'd' + String(v);                 // -0.0 hashes with 0.0, as Swift
  if (isString(v)) return 's' + v.normalize('NFC');
  if (isArray(v)) return 'a[' + v.items.map(keyOf).join(',') + ']';
  if (isDictionary(v)) return 'D[' + v.entries().map(([k, x]) => keyOf(k) + ':' + keyOf(x)).sort().join(',') + ']';
  if (isSet(v)) return 'S[' + v.values().map(keyOf).sort().join(',') + ']';
  if (isData(v)) return 'b' + Array.from(v.bytes).join(',');
  if (isDate(v)) return 't' + String(v.epoch);
  if (isRange(v)) return 'r' + v.from + (v.closed ? '...' : '..<') + (v.to === null ? '' : v.to);
  if (isTuple(v)) return 'T(' + v.values.map(keyOf).join(',') + ')';   // labels do not take part in == (round 70)
  if (isFunction(v)) return 'f' + v.identityKey();
  if (isEnumCase(v)) return 'e' + v.type.name + '.' + v.caseName + '(' + v.associated.map(keyOf).join(',') + ')';
  if (isStructValue(v)) return 'v' + v.type.name + '(' + v.type.propertyOrder.map((p) => p + '=' + keyOf(v.values.get(p) ?? null)).join(',') + ')';
  if (isHost(v)) return 'h' + v.object.hashKey();
  return 'o' + String(v.id);                               // a Sequence or a Task: identity
}
export function equals(a: Value, b: Value): boolean {
  if (isByte(a) && isInt(b)) return BigInt(a.v) === b;
  if (isInt(a) && isByte(b)) return a === BigInt(b.v);
  if (kindOf(a) !== kindOf(b)) return false;
  if (a === null || isBool(a) || isInt(a)) return a === b;
  if (isDouble(a)) return a === b;                    // NaN != NaN, 0.0 == -0.0, as Swift
  if (isString(a) && isString(b)) return a === b || a.normalize('NFC') === b.normalize('NFC');
  if (isByte(a) && isByte(b)) return a.v === b.v;
  if (isDate(a) && isDate(b)) return a.epoch === b.epoch;
  if (isFunction(a)) return a === b || a.sameAs(b);
  if (isSequence(a) || isTask(a)) return a === b;
  if (isHost(a) && isHost(b)) return a.object.isEqual(b.object);
  return keyOf(a) === keyOf(b);
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
  const rec = (x: Value): string => sourceString(x, debug, custom);
  if (v === null) return 'nil';
  if (isBool(v)) return v ? 'true' : 'false';
  if (isInt(v)) return debug ? (v < 0n ? '-0x' : '+0x') + (v < 0n ? -v : v).toString(16) : v.toString();
  if (isDouble(v)) return debug ? hexFloat(v, true) : formatDouble(v);
  if (isString(v)) return quote(v);
  if (isArray(v)) return '[' + v.items.map(rec).join(', ') + ']';
  if (isFunction(v)) return v.sourceString();
  if (isRange(v)) {
    const lo = rec(v.from);
    if (v.to === null) return lo + '...';
    return lo + (v.closed ? '...' : '..<') + rec(v.to);
  }
  if (isSequence(v)) return 'Sequence { ... }';
  if (isTask(v)) return 'Task { ... }';
  if (isTuple(v)) {
    const body = v.values.map((x, i) => (v.labels[i] !== null ? `${v.labels[i]}: ` : '') + rec(x)).join(', ');
    const lonely = v.count === 1 && v.labels[0] === null;
    return '(' + body + (lonely ? ',)' : ')');
  }
  if (isByte(v)) return 'Byte(' + (debug ? '0x' + v.v.toString(16) : String(v.v)) + ')';
  if (isData(v)) {
    if (debug) return 'Data([' + Array.from(v.bytes, (b) => '0x' + b.toString(16)).join(', ') + '])';
    return `.Data("${base64Encode(v.bytes)}")`;
  }
  if (isDate(v)) return `.Date(${debug ? hexFloat(v.epoch) : formatDouble(v.epoch)})`;
  if (isHost(v)) return v.object.sourceString(debug);
  if (isStructValue(v)) return v.type.name + '(' + v.type.propertyOrder.map((p) => `${p}: ${rec(v.values.get(p) ?? null)}`).join(', ') + ')';
  if (isEnumCase(v)) {
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
  if (isSet(v)) {
    if (v.size === 0) return 'Set()';
    const elements = v.values().map(rec).sort(compareStrings);
    if (v.size === 1 && spreadsInSet(v.values()[0])) return 'Set([' + elements[0] + '])';
    return 'Set(' + elements.join(', ') + ')';
  }
  if (isDictionary(v)) {
    if (v.size === 0) return '[:]';
    return '[' + v.entries().map(([k, x]) => ({ key: rec(k), value: rec(x) }))
      .sort((a, b) => compareStrings(a.key, b.key)).map((e) => `${e.key}: ${e.value}`).join(', ') + ']';
  }
  return '<unknown>';
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

/// A lookup that must succeed — a Map keyed by a name the caller already walked, say; the throw is a bug's.
export function must<T>(x: T | undefined | null, what: string): T {
  if (x === undefined || x === null) throw new Error(`${what} is missing`);
  return x;
}

/// Int64 arithmetic: the result if it fits, else null — overflow is the
/// caller's trap (§3b).
export function fits64(n: bigint): boolean { return n >= INT64_MIN && n <= INT64_MAX; }
export function checkInt(n: bigint, what: string): bigint {
  if (!fits64(n)) throw SwiftalkError.overflow(what);
  return n;
}
export { TypeAnnotation };
