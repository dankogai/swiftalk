// Types as constructor Functions, protocols, the conformance table
// (Builtins.swift), and the math library (Math.swift).
import { SwiftalkError } from './errors.js';
import { TypeAnnotation } from './parser.js';
import { kindOf, typeName, V, SArray, SDictionary, SSet, Byte, SData, SDate, SRange, TupleValue,
  base64Decode, INT64_MAX, INT64_MIN, fits64, sourceString, hexFloat, formatDouble,
  isBool, isInt, isDouble, isString, isByte, isArray, isDictionary, isSet, isData, isDate, isRange, isFunction, isTuple } from './value.js';
import { FunctionObject, EnumType, EnumCaseValue, SequenceObject } from './objects.js';
import type { Builtin, G } from './objects.js';
import { Environment } from './env.js';
import { inferLock, knownElementLock, tryInfer, ann, isSION } from './types.js';
import { collect, isSequenceValue, displayString, spawnTask, userOperator } from './eval.js';
import { SIONFormat, CivilDate } from './formats.js';
import type { Value, LabeledArg } from './value.js';

/// The table the evaluator and the modules share: the type constructors, the protocols, conformance, and a few helpers.
export interface BuiltinsTable {
  emptyEnvironment: Environment;
  resultType: EnumType;
  todo: FunctionObject;
  stampedSet: (elements: SSet | Value[], source: Value | null) => SSet;
  parseInt: (text: string) => bigint | null;
  types: Map<string, FunctionObject>;
  protocols: Map<string, FunctionObject>;
  conformance: Map<string, Set<string>>;
}
/// The scope builtin Functions close over: empty, below every program's.
const builtinScope = new Environment();

const resultType = new EnumType('Result', ['success', 'failure'],
  new Map([['success', [{ label: null, typeName: null }]], ['failure', [{ label: null, typeName: null }]]]));
resultType.constructor_ = new FunctionObject([], [], builtinScope,
  () => { throw SwiftalkError.type('construct a Result via Result.success(v) or Result.failure(e)'); }, { k: 'enumType', type: resultType });
const todoFunction = new FunctionObject([], [], builtinScope,
  () => { throw SwiftalkError.type('this Function is .todo — assign an implementation before calling it'); }, { k: 'todo' });
export const success = (v: Value): EnumCaseValue => new EnumCaseValue(resultType, 'success', [v]);
export const failure = (m: Value): EnumCaseValue => new EnumCaseValue(resultType, 'failure', [m]);
export const isResult = (v: Value): v is EnumCaseValue => v instanceof EnumCaseValue && v.type === resultType;

const type = (name: string, construct: Builtin): FunctionObject => new FunctionObject([], [], builtinScope, construct, { k: 'type', name });
const protocolObject = (name: string): FunctionObject => new FunctionObject([], [], builtinScope,
  () => { throw SwiftalkError.type(`${name} is a protocol, not a constructor`); }, { k: 'protocol', name });

const stampedSetOf = (elements: SSet | Value[], source: Value | null): SSet => {
  const set = elements instanceof SSet ? elements : new SSet(elements);
  const inferred = tryInfer(set, 'Set', false);
  if (inferred && inferred.parameters.length) return new SSet(set.values(), inferred);
  if (set.size === 0 && source != null) {
    const known = knownElementLock(source);
    if (known) return new SSet([], ann('Set', false, [known]));
  }
  return set;
};

const radixPrefixes: Record<number, string> = { 10: '', 16: '0x', 8: '0o', 2: '0b' };
/// Int-from-String, accepting everything the lexer does.
export function parseIntText(input: string): bigint | null {
  let s = input.replace(/_/g, '');
  let negative = false;
  if (s.startsWith('-') || s.startsWith('+')) { negative = s.startsWith('-'); s = s.slice(1); }
  let radix = 10, digits = /^[0-9]+$/;
  if (s.startsWith('0x')) { radix = 16; s = s.slice(2); digits = /^[0-9a-fA-F]+$/; }
  else if (s.startsWith('0o')) { radix = 8; s = s.slice(2); digits = /^[0-7]+$/; }
  else if (s.startsWith('0b')) { radix = 2; s = s.slice(2); digits = /^[01]+$/; }
  if (!s.length || !digits.test(s)) return null;
  const prefix = radixPrefixes[radix];
  const magnitude = BigInt(prefix + s);
  if (negative) {
    if (magnitude > (1n << 63n)) return null;
    return -magnitude;
  }
  if (magnitude > INT64_MAX) return null;
  return magnitude;
}

/// Swift's Double(String): decimal, hex floats, inf/nan spellings; nil otherwise.
export function parseDoubleText(s: string): number | null {
  const t = s.trim();
  if (t !== s || t === '') return null;
  if (/^[-+]?(inf|infinity)$/i.test(t)) return t.startsWith('-') ? -Infinity : Infinity;
  if (/^[-+]?nan$/i.test(t)) return NaN;
  if (/^[-+]?0x[0-9a-fA-F]+(\.[0-9a-fA-F]*)?(p[-+]?\d+)?$/i.test(t)) {
    const neg = t.startsWith('-');
    const body = t.replace(/^[-+]/, '').slice(2);
    const [mant, exp = '0'] = body.split(/p/i);
    const [whole, frac = ''] = mant.split('.');
    let v = 0;
    for (const c of whole) v = v * 16 + parseInt(c, 16);
    let scale = 1 / 16;
    for (const c of frac) { v += parseInt(c, 16) * scale; scale /= 16; }
    v *= Math.pow(2, parseInt(exp, 10));
    return neg ? -v : v;
  }
  if (!/^[-+]?(\d+\.?\d*([eE][-+]?\d+)?|\.\d+([eE][-+]?\d+)?)$/.test(t)) return null;
  const d = Number(t);
  return Number.isNaN(d) ? null : d;
}

const toByte = (n: bigint): Byte | null => (n >= 0n && n <= 255n ? new Byte(Number(n)) : null);

const builtinTypes = new Map<string, FunctionObject>([
  // Round 237: a Context is made where it is called — the evaluator builds it from the call's scope
  ['Context', type('Context', (): Value => { throw SwiftalkError.type('Context() is made where it is called, with no arguments — it copies the top level there'); })],
  ['Nil', type('Nil', (args: Value[]) => {
    if (args.length === 0 || args[0] === null) return null;
    throw SwiftalkError.type(`cannot convert ${typeName(args[0])} to Nil`);
  })],
  ['Bool', type('Bool', (args: Value[]) => {
    if (args.length === 0) return false;
    const v = args[0];
    if (isBool(v)) return v;
    if (isString(v)) return v === 'true' ? true : v === 'false' ? false : null;
    // Bool(i) as `i != 0` was round 105's; removed in round 204 — `i != 0` says it
    throw SwiftalkError.type(`cannot convert ${typeName(v)} to Bool` + (isInt(v) ? ' — write i != 0' : ''));
  })],
  ['Byte', type('Byte', (args: Value[]) => {
    if (args.length === 0) return new Byte(0);
    const v = args[0];
    if (isByte(v)) return v;
    if (isInt(v)) return toByte(v);
    if (isDouble(v)) { const t = Math.trunc(v); return Number.isFinite(t) && t >= 0 && t <= 255 ? new Byte(t) : null; }
    if (isString(v)) { const i = parseIntText(v); return i === null ? null : toByte(i); }
    throw SwiftalkError.type(`cannot convert ${typeName(v)} to Byte`);
  })],
  ['Int', type('Int', (args: Value[]) => {
    if (args.length === 0) return 0n;
    const v = args[0];
    if (isInt(v)) return v;
    if (isByte(v)) return BigInt(v.v);
    if (isDouble(v)) {
      if (!Number.isFinite(v)) return null;
      const b = BigInt(Math.trunc(v));
      return fits64(b) ? b : null;
    }
    if (isString(v)) return parseIntText(v);
    throw SwiftalkError.type(`cannot convert ${typeName(v)} to Int`);
  })],
  ['Double', type('Double', (args: Value[]) => {
    if (args.length === 0) return 0;
    const v = args[0];
    if (isDouble(v)) return v;
    if (isInt(v)) return Number(v);
    if (isByte(v)) return v.v;
    if (isString(v)) return parseDoubleText(v);
    if (isDate(v)) return v.epoch;
    throw SwiftalkError.type(`cannot convert ${typeName(v)} to Double`);
  })],
  ['String', type('String', function* (args: Value[]) {
    if (args.length === 0) return '';
    return yield* displayString(args[0]);
  })],
  ['Optional', type('Optional', (args: Value[]) => (args.length ? args[0] : null))],
  ['Array', type('Array', function* (args: Value[]): G<Value> {
    if (args.length === 0) return new SArray([]);
    const v = args[0];
    if (isArray(v)) return new SArray(v.items, v.lock);
    if (isSet(v)) return new SArray(v.values(), v.lock ? ann('Array', false, v.lock.parameters) : null);
    const out = yield* collect(v);
    const inferred = tryInfer(new SArray(out), 'Array', false);
    if (inferred && inferred.parameters.length) return new SArray(out, inferred);
    if (out.length === 0) { const known = knownElementLock(v); if (known) return new SArray(out, ann('Array', false, [known])); }
    return new SArray(out);
  })],
  ['Dictionary', type('Dictionary', function* (args: Value[]): G<Value> {
    if (args.length === 0) return new SDictionary([]);
    const v = args[0];
    if (isDictionary(v)) return new SDictionary(v.entries(), v.lock);
    if (isSequenceValue(v)) {
      const d = new SDictionary([]);
      for (const pair of yield* collect(v)) {
        if (!isTuple(pair) || pair.count !== 2) throw SwiftalkError.type(`Dictionary(pairs) takes a Sequence of (key, value) tuples, not a ${typeName(pair)}`);
        if (d.has(pair.values[0])) throw SwiftalkError.type(`Dictionary(pairs): duplicate key ${sourceString(pair.values[0])}`);
        d.set(pair.values[0], pair.values[1]);
      }
      const inferred = tryInfer(d, 'Dictionary', false);
      if (inferred && inferred.parameters.length) return new SDictionary(d.entries(), inferred);
      return d;
    }
    throw SwiftalkError.type(`cannot convert ${typeName(v)} to Dictionary`);
  })],
  ['Set', type('Set', function* (args: Value[]): G<Value> {
    if (args.length === 0) return new SSet([]);
    const v = args[0];
    if (isSet(v)) return new SSet(v.values(), v.lock);
    if (isSequenceValue(v)) return stampedSetOf(new SSet(yield* collect(v)), v);
    return stampedSetOf(new SSet([v]), null);
  })],
  ['Range', type('Range', (args: Value[]) => {
    if (args.length === 0) throw SwiftalkError.type('construct a Range with its literal: a...b or a..<b');
    const v = args[0];
    if (isRange(v)) return new SRange(v.from, v.to, v.closed);
    throw SwiftalkError.type(`cannot convert ${typeName(v)} to Range`);
  })],
  ['Function', type('Function', (args: Value[]) => {
    if (args.length === 0) throw SwiftalkError.type('there is no default Function');
    const v = args[0];
    if (isFunction(v)) return v;
    throw SwiftalkError.type(`cannot convert ${typeName(v)} to Function`);
  })],
  ['Data', type('Data', (args: Value[]) => {
    if (args.length === 0) return new SData([]);
    const v = args[0];
    if (isData(v)) return v;
    if (isString(v)) { const b = base64Decode(v); return b === null || (v.replace(/\s/g, '').length % 4) !== 0 ? null : new SData(b); }
    if (isArray(v)) {
      const bytes: number[] = [];
      for (const x of v.items) {
        if (isByte(x)) bytes.push(x.v);
        else if (isInt(x) && x >= 0n && x <= 255n) bytes.push(Number(x));
        else return null;
      }
      return new SData(bytes);
    }
    throw SwiftalkError.type(`cannot convert ${typeName(v)} to Data`);
  })],
  ['Task', type('Task', function* (args: Value[]): G<Value> {
    const f = args[0];
    if (args.length !== 1 || !isFunction(f)) throw SwiftalkError.type('Task { ... } spawns a Function as a concurrent task');
    if (f.builtin) throw SwiftalkError.type('Task(f): cannot spawn a builtin Function');
    if (f.parameters.length) throw SwiftalkError.type('Task(f): a task body declares no parameters — nothing is passed in');
    return yield* spawnTask(f);
  })],
  ['Tuple', type('Tuple', function* (args: Value[]): G<Value> {
    if (args.length === 0) return new TupleValue([]);
    const v = args[0];
    if (isTuple(v)) return v;
    return new TupleValue(yield* collect(v));
  })],
  ['SION', type('SION', (args: Value[]) => {
    if (args.length === 0) throw SwiftalkError.type('SION(text) reads a SION document; SION(json:) and SION(propertyList:) the other formats');
    const v = args[0];
    if (isString(v)) return SIONFormat.parse(v);
    if (!isSION(v)) throw SwiftalkError.type(`a ${typeName(v)} is not SION`);
    return v;
  })],
  ['Date', type('Date', (args: Value[]) => {
    if (args.length === 0) return new SDate(Date.now() / 1000);
    const v = args[0];
    if (isDate(v)) return v;
    if (isDouble(v)) return new SDate(v);
    if (isInt(v)) return new SDate(Number(v));
    if (isString(v)) { const e = CivilDate.epochFromISO8601(v); return e === null ? null : new SDate(e); }   // the parse (round 209)
    throw SwiftalkError.type(`cannot convert ${typeName(v)} to Date`);
  })],
]);

const builtinProtocols = new Map<string, FunctionObject>([
  ['Sequence', new FunctionObject([], [], builtinScope, (args: Value[]) => {
    const f = args[0];
    if (args.length === 1 && isFunction(f)) {
      if (f.builtin) throw SwiftalkError.type('Sequence(f): cannot wrap a builtin Function as a coroutine');
      if (f.parameters.length) throw SwiftalkError.type('Sequence(f): a coroutine body declares no parameters — nothing is passed in on resume');
      return new SequenceObject({ kind: 'coroutine', body: f });
    }
    const [initial, next] = args;
    if (args.length !== 2 || !isArray(initial) || !isFunction(next)) {
      throw SwiftalkError.type('Sequence(f) wraps a yielding Function; Sequence(initialState) { next } generates');
    }
    return new SequenceObject({ kind: 'generator', initial: initial.items, next });
  }, { k: 'protocol', name: 'Sequence' })],
  ['Equatable', protocolObject('Equatable')],
  ['Hashable', protocolObject('Hashable')],
  ['Comparable', protocolObject('Comparable')],
]);

const allTypeNames = new Set(['Nil', 'Bool', 'Int', 'Double', 'String', 'Array', 'Dictionary', 'Set', 'Range', 'Function', 'Sequence', 'Data', 'Date', 'Task', 'Tuple', 'Byte']);
const builtinConformance = new Map<string, Set<string>>([
  ['Sequence', new Set(['String', 'Array', 'Dictionary', 'Set', 'Range', 'Sequence', 'Tuple', 'Data'])],
  ['Equatable', allTypeNames],
  ['Hashable', allTypeNames],
  ['Comparable', new Set(['Int', 'Double', 'String', 'Date', 'Byte'])],
]);

export const Builtins: BuiltinsTable = { emptyEnvironment: builtinScope, resultType, todo: todoFunction, stampedSet: stampedSetOf, parseInt: parseIntText, types: builtinTypes, protocols: builtinProtocols, conformance: builtinConformance };

// ---- math ----
const M = Math;
function erf(x: number): number {
  // Abramowitz–Stegun 7.1.26 refined with a series near 0 — FIXME: not libm-exact in the last digits
  const sign = x < 0 ? -1 : 1;
  x = Math.abs(x);
  if (x < 2.5) {
    let sum = x, term = x, n = 0;
    while (Math.abs(term) > 1e-17 * Math.abs(sum) && n < 200) { n++; term *= -x * x / n; sum += term / (2 * n + 1); }
    return sign * 2 / Math.sqrt(Math.PI) * sum;
  }
  // continued fraction for erfc
  let a = 0;
  for (let k = 60; k >= 1; k--) a = k / 2 / (x + a);
  const erfc = Math.exp(-x * x) / Math.sqrt(Math.PI) / (x + a);
  return sign * (1 - erfc);
}
const erfc = (x: number): number => 1 - erf(x);
function lgamma(x: number): number {
  if (x <= 0 && Number.isInteger(x)) return Infinity;
  if (x < 0.5) return Math.log(Math.PI / Math.abs(Math.sin(Math.PI * x))) - lgamma(1 - x);
  x -= 1;
  const g = 7;
  const c = [0.99999999999980993, 676.5203681218851, -1259.1392167224028, 771.32342877765313, -176.61502916214059,
    12.507343278686905, -0.13857109526572012, 9.9843695780195716e-6, 1.5056327351493116e-7];
  let a = c[0];
  const t = x + g + 0.5;
  for (let i = 1; i < g + 2; i++) a += c[i] / (x + i);
  return 0.5 * Math.log(2 * Math.PI) + (x + 0.5) * Math.log(t) - t + Math.log(a);
}
function tgamma(x: number): number {
  if (Number.isInteger(x)) { if (x <= 0) return NaN; if (x <= 171) { let r = 1; for (let i = 2; i < x; i++) r *= i; return r; } return Infinity; }
  if (x < 0.5) return Math.PI / (Math.sin(Math.PI * x) * tgamma(1 - x));
  return Math.exp(lgamma(x));
}
// Bessel functions — Numerical Recipes' polynomial approximations. FIXME: ~1e-8 accuracy, not libm's.
/// The power series inside |x| < 8 (exact at 0, ~1e-15), Numerical Recipes' asymptotic form beyond.
function besselSeries(x: number, order: number): number {
  const h = x / 2;
  let term = order === 0 ? 1 : h, sum = term;
  for (let k = 1; k < 60; k++) { term *= -(h * h) / (k * (k + order)); sum += term; if (Math.abs(term) < 1e-17 * Math.abs(sum)) break; }
  return sum;
}
function j0(x: number): number {
  const ax = Math.abs(x);
  if (ax < 8) return besselSeries(x, 0);
  const z = 8 / ax, y = z * z, xx = ax - 0.785398164;
  return Math.sqrt(0.636619772 / ax) * (Math.cos(xx) * (1 + y * (-0.1098628627e-2 + y * (0.2734510407e-4 + y * (-0.2073370639e-5 + y * 0.2093887211e-6))))
    - z * Math.sin(xx) * (-0.1562499995e-1 + y * (0.1430488765e-3 + y * (-0.6911147651e-5 + y * (0.7621095161e-6 - y * 0.934935152e-7)))));
}
function j1(x: number): number {
  const ax = Math.abs(x);
  if (ax < 8) return besselSeries(x, 1);
  const z = 8 / ax, y = z * z, xx = ax - 2.356194491;
  const ans = Math.sqrt(0.636619772 / ax) * (Math.cos(xx) * (1 + y * (0.183105e-2 + y * (-0.3516396496e-4 + y * (0.2457520174e-5 + y * -0.240337019e-6))))
    - z * Math.sin(xx) * (0.04687499995 + y * (-0.2002690873e-3 + y * (0.8449199096e-5 + y * (-0.88228987e-6 + y * 0.105787412e-6)))));
  return x < 0 ? -ans : ans;
}
function y0(x: number): number {
  if (x < 8) { const y = x * x; return (-2957821389.0 + y * (7062834065.0 + y * (-512359803.6 + y * (10879881.29 + y * (-86327.92757 + y * 228.4622733)))))
    / (40076544269.0 + y * (745249964.8 + y * (7189466.438 + y * (47447.26470 + y * (226.1030244 + y))))) + 0.636619772 * j0(x) * Math.log(x); }
  const z = 8 / x, y = z * z, xx = x - 0.785398164;
  return Math.sqrt(0.636619772 / x) * (Math.sin(xx) * (1 + y * (-0.1098628627e-2 + y * (0.2734510407e-4 + y * (-0.2073370639e-5 + y * 0.2093887211e-6))))
    + z * Math.cos(xx) * (-0.1562499995e-1 + y * (0.1430488765e-3 + y * (-0.6911147651e-5 + y * (0.7621095161e-6 + y * -0.934945152e-7)))));
}
function y1(x: number): number {
  if (x < 8) { const y = x * x; return x * (-0.4900604943e13 + y * (0.1275274390e13 + y * (-0.5153438139e11 + y * (0.7349264551e9 + y * (-0.4237922726e7 + y * 0.8511937935e4)))))
    / (0.2499580570e14 + y * (0.4244419664e12 + y * (0.3733650367e10 + y * (0.2245904002e8 + y * (0.1020426050e6 + y * (0.3549632885e3 + y)))))) + 0.636619772 * (j1(x) * Math.log(x) - 1 / x); }
  const z = 8 / x, y = z * z, xx = x - 2.356194491;
  return Math.sqrt(0.636619772 / x) * (Math.sin(xx) * (1 + y * (0.183105e-2 + y * (-0.3516396496e-4 + y * (0.2457520174e-5 + y * -0.240337019e-6))))
    + z * Math.cos(xx) * (0.04687499995 + y * (-0.2002690873e-3 + y * (0.8449199096e-5 + y * (-0.88228987e-6 + y * 0.105787412e-6)))));
}
function jn(n: number, x: number): number {
  if (n === 0) return j0(x); if (n === 1) return j1(x);
  if (x === 0) return 0;
  let bjm = j0(x), bj = j1(x);
  for (let k = 1; k < n; k++) { const bjp = k * 2 / x * bj - bjm; bjm = bj; bj = bjp; }
  return bj;
}
function yn(n: number, x: number): number {
  if (n === 0) return y0(x); if (n === 1) return y1(x);
  let bym = y0(x), by = y1(x);
  for (let k = 1; k < n; k++) { const byp = k * 2 / x * by - bym; bym = by; by = byp; }
  return by;
}
function frexp(x: number): [number, number] {
  if (x === 0 || !Number.isFinite(x)) return [x, 0];
  const view = new DataView(new ArrayBuffer(8));
  view.setFloat64(0, x);
  let e = (view.getUint16(0) >> 4) & 0x7ff;
  if (e === 0) { const r = frexp(x * Math.pow(2, 64)); return [r[0], r[1] - 64]; }
  const exponent = e - 1022;
  view.setUint16(0, (view.getUint16(0) & 0x800f) | (1022 << 4));
  return [view.getFloat64(0), exponent];
}
function ilogb(x: number): number {
  if (x === 0) return -2147483648;                 // FP_ILOGB0
  if (Number.isNaN(x)) return 2147483648;          // FP_ILOGBNAN
  if (!Number.isFinite(x)) return 2147483647;
  return frexp(x)[1] - 1;
}
function logb(x: number): number {
  if (x === 0) return -Infinity;
  if (!Number.isFinite(x)) return Math.abs(x);
  return frexp(x)[1] - 1;
}
function scalbn(x: number, n: number): number { return x * Math.pow(2, n); }
function nextafter(x: number, y: number): number {
  if (Number.isNaN(x) || Number.isNaN(y)) return NaN;
  if (x === y) return y;
  if (x === 0) return y > 0 ? Number.MIN_VALUE : -Number.MIN_VALUE;
  const view = new DataView(new ArrayBuffer(8));
  view.setFloat64(0, x);
  let bits = view.getBigInt64(0);
  bits += (y > x) === (x > 0) ? 1n : -1n;
  view.setBigInt64(0, bits);
  return view.getFloat64(0);
}
function remainder(x: number, y: number): number {
  if (!Number.isFinite(x) || y === 0 || Number.isNaN(y)) return NaN;
  const n = x / y;
  let q = Math.round(n);
  if (Math.abs(n - Math.trunc(n)) === 0.5) q = 2 * Math.round(n / 2);   // ties to even
  return x - q * y;
}
const cRound = (x: number): number => (x < 0 ? -Math.round(-x) : Math.round(x));   // half away from zero
const roundEven = (x: number): number => { const r = Math.round(x); return Math.abs(x - Math.trunc(x)) === 0.5 ? 2 * Math.round(x / 2) : r; };

type Unary = (x: number) => number;
type Binary = (a: number, b: number) => number;
type Predicate = (x: number) => boolean;
export interface DoubleMathTable {
  constants: Map<string, number>;
  unary: Map<string, Unary>;
  binary: Map<string, Binary>;
  predicates: Map<string, Predicate>;
  functions: Set<string>;
  member: (name: string, args: LabeledArg[], called: boolean) => Value | undefined;
}
const mathConstants = new Map<string, number>(Object.entries({
    pi: Math.PI, tau: 2 * Math.PI, e: Math.E, ln2: Math.LN2, ln10: Math.LN10, log2e: Math.LOG2E, log10e: Math.LOG10E,
    sqrt2: Math.SQRT2, sqrtHalf: Math.SQRT1_2, infinity: Infinity, nan: NaN,
    greatestFiniteMagnitude: Number.MAX_VALUE, leastNormalMagnitude: 2.2250738585072014e-308, leastNonzeroMagnitude: Number.MIN_VALUE,
    ulpOfOne: Number.EPSILON, zero: 0, radix: 2, exponentBitCount: 11, significandBitCount: 52,
}));
const mathUnary = new Map<string, Unary>(Object.entries({
    abs: Math.abs, sqrt: Math.sqrt, cbrt: Math.cbrt, exp: Math.exp, exp2: (x: number) => Math.pow(2, x), expm1: Math.expm1,
    log: Math.log, log2: Math.log2, log10: Math.log10, log1p: Math.log1p, logb,
    sin: Math.sin, cos: Math.cos, tan: Math.tan, asin: Math.asin, acos: Math.acos, atan: Math.atan,
    sinh: Math.sinh, cosh: Math.cosh, tanh: Math.tanh, asinh: Math.asinh, acosh: Math.acosh, atanh: Math.atanh,
    floor: Math.floor, ceil: Math.ceil, trunc: Math.trunc, round: cRound, rint: roundEven, nearbyint: roundEven,
    sign: (x: number) => (Number.isNaN(x) ? NaN : x > 0 ? 1 : x < 0 ? -1 : x),
    erf, erfc, tgamma, gamma: tgamma, lgamma, j0, j1, y0, y1, fround: Math.fround,
}));
const mathBinary = new Map<string, Binary>(Object.entries({
    pow: Math.pow, atan2: Math.atan2, fmod: (a: number, b: number) => a % b, remainder,
    fdim: (a: number, b: number) => (a > b ? a - b : 0), fmax: (a: number, b: number) => (Number.isNaN(a) ? b : Number.isNaN(b) ? a : Math.max(a, b)),
    fmin: (a: number, b: number) => (Number.isNaN(a) ? b : Number.isNaN(b) ? a : Math.min(a, b)),
    copysign: (a: number, b: number) => (Math.sign(b) < 0 || Object.is(b, -0) || (b !== b && Object.is(b, -0)) ? -Math.abs(a) : Math.abs(a)), nextafter,
}));
const mathPredicates = new Map<string, Predicate>(Object.entries({
    isNaN: Number.isNaN, isFinite: Number.isFinite, isInfinite: (x: number) => x === Infinity || x === -Infinity,
    isZero: (x: number) => x === 0, isNormal: (x: number) => Number.isFinite(x) && x !== 0 && Math.abs(x) >= 2.2250738585072014e-308,
    isSubnormal: (x: number) => x !== 0 && Math.abs(x) < 2.2250738585072014e-308,
}));
const mathFunctions = new Set<string>([...mathUnary.keys(), ...mathBinary.keys(), ...mathPredicates.keys(),
  'max', 'min', 'hypot', 'random', 'fma', 'ldexp', 'scalbn', 'ilogb', 'jn', 'yn', 'modf', 'frexp', 'remquo']);
function number(v: Value, name: string): number {
  if (isDouble(v)) return v;
  if (isInt(v)) return Number(v);
  if (isByte(v)) return v.v;
  throw SwiftalkError.type(`Double.${name} takes numbers, not a ${typeName(v)}`);
}
function mathApply(name: string, args: Value[]): Value {
  const arity = (n: number): number[] => {
    if (args.length !== n) throw SwiftalkError.type(`Double.${name} takes ${n} argument${n === 1 ? '' : 's'}, got ${args.length}`);
    return args.map((a) => number(a, name));
  };
  const u = mathUnary.get(name); if (u) return u(arity(1)[0]);
  const b = mathBinary.get(name); if (b) { const a = arity(2); return b(a[0], a[1]); }
  const p = mathPredicates.get(name); if (p) return p(arity(1)[0]);
  switch (name) {
    case 'max': case 'min': {
      if (!args.length) throw SwiftalkError.type(`Double.${name} takes at least one number`);
      const xs = args.map((a) => number(a, name));
      return name === 'max' ? xs.reduce((m, x) => Math.max(m, x), -Infinity) : xs.reduce((m, x) => Math.min(m, x), Infinity);
    }
    case 'hypot': return args.map((a) => number(a, name)).reduce((h, x) => Math.hypot(h, x), 0);
    case 'random': return mathRandom(args.map((v): LabeledArg => ({ label: null, value: v })));
    case 'fma': { const a = arity(3); return a[0] * a[1] + a[2]; }   // FIXME: not a fused multiply-add
    case 'ldexp': case 'scalbn': {
      const [x, n] = args;
      if (args.length !== 2 || !isInt(n)) throw SwiftalkError.type(`Double.${name}(x, n) takes a number and an Int`);
      return scalbn(number(x, name), Number(n));
    }
    case 'ilogb': return BigInt(ilogb(arity(1)[0]));
    case 'jn': case 'yn': {
      const [order, arg] = args;
      if (args.length !== 2 || !isInt(order)) throw SwiftalkError.type(`Double.${name}(n, x) takes an Int order and a number`);
      const x = number(arg, name);
      return name === 'jn' ? jn(Number(order), x) : yn(Number(order), x);
    }
    case 'modf': { const x = arity(1)[0]; const whole = Math.trunc(x); return new TupleValue([whole, x - whole], ['integer', 'fraction']); }
    case 'frexp': {
      const x = arity(1)[0];
      if (x === 0 || !Number.isFinite(x)) return new TupleValue([x, 0n], ['fraction', 'exponent']);
      const [f, e] = frexp(x);
      return new TupleValue([f, BigInt(e)], ['fraction', 'exponent']);
    }
    case 'remquo': {
      const a = arity(2);
      const rem = remainder(a[0], a[1]);
      const quo = Math.round((a[0] - rem) / a[1]);
      return new TupleValue([rem, BigInt(quo)], ['remainder', 'quotient']);
    }
    default: throw SwiftalkError.unknownMember(`Double.${name}`);
  }
}
export function parseRandomBounds(args: LabeledArg[], who: string): [Value | null, Value | null] {
  const usage = SwiftalkError.type(`${who}.random(), .random(to:), or .random(from:to:)`);
  switch (args.length) {
    case 0: return [null, null];
    case 1: if (!(args[0].label === null || args[0].label === 'to')) throw usage; return [null, args[0].value];
    case 2:
      if (!(args[0].label === null || args[0].label === 'from') || !(args[1].label === null || args[1].label === 'to')) throw usage;
      return [args[0].value, args[1].value];
    default: throw usage;
  }
}
function mathRandom(args: LabeledArg[]): number {
  const [from, to] = parseRandomBounds(args, 'Double');
  const lo = from === null ? 0 : number(from, 'random');
  const hi = to === null ? 1 : number(to, 'random');
  if (!Number.isFinite(lo) || !Number.isFinite(hi) || !(lo < hi)) throw SwiftalkError.type(`Double.random needs finite bounds with from < to, got ${formatDouble(lo)} and ${formatDouble(hi)}`);
  return lo + Math.random() * (hi - lo);
}
/// `Double.name` — undefined when not a math member.
function mathMember(name: string, args: LabeledArg[], called: boolean): Value | undefined {
  const constant = mathConstants.get(name);
  if (constant !== undefined) {
    if (called) throw SwiftalkError.type(`Double.${name} is a constant, not a function`);
    return constant;
  }
  if (!mathFunctions.has(name)) return undefined;
  if (name === 'random' && called) return mathRandom(args);
  const label = args.map((a) => a.label).find((l) => l !== null);
  if (label !== undefined) throw SwiftalkError.type(`Double.${name} takes no argument label '${label}'`);
  const values = args.map((a) => a.value);
  if (!called) return new FunctionObject([], [], builtinScope, (xs: Value[]) => mathApply(name, xs));
  return mathApply(name, values);
}
export const DoubleMath: DoubleMathTable = { constants: mathConstants, unary: mathUnary, binary: mathBinary, predicates: mathPredicates, functions: mathFunctions, member: mathMember };

/// `base ** exponent` (round 142).
export function* power(base: Value, exponent: Value): G<Value> {
  const r = yield* userOperator('infix:**', [base, exponent]);
  if (r !== undefined) return r;
  if (isInt(base) && isInt(exponent)) {
    const b = base, e = exponent;
    if (e < 0n) throw SwiftalkError.type(`'**' with a negative Int exponent has no Int answer — Double(${base}) ** Double(${exponent})`);
    let result = 1n, x = b, n = e;
    while (n > 0n) {
      if (n & 1n) { result *= x; if (!fits64(result)) throw SwiftalkError.overflow(`${base} ** ${exponent}`); }
      n >>= 1n;
      if (n > 0n) { x *= x; if (!fits64(x)) throw SwiftalkError.overflow(`${base} ** ${exponent}`); }
    }
    return result;
  }
  if (isDouble(base) && isDouble(exponent)) return Math.pow(base, exponent);
  throw SwiftalkError.type(`'**' is not defined between ${typeName(base)} and ${typeName(exponent)} — two Ints or two Doubles`);
}

export const IntStatics = new Map<string, Map<string, Value>>([
  ['Int', new Map<string, Value>([['min', INT64_MIN], ['max', INT64_MAX], ['bitWidth', 64n], ['zero', 0n], ['isSigned', true]])],
  ['Byte', new Map<string, Value>([['min', new Byte(0)], ['max', new Byte(255)], ['bitWidth', 8n], ['zero', new Byte(0)], ['isSigned', false]])],
]);
export function dataRandom(args: Value[]): SData {
  const count = args[0];
  if (args.length !== 1 || !isInt(count) || count < 0n) throw SwiftalkError.type('Data.random(count) takes one non-negative Int');
  const n = Number(count);
  const bytes = new Uint8Array(n);
  for (let i = 0; i < n; i++) bytes[i] = Math.floor(Math.random() * 256);
  return new SData(bytes);
}
export function stringFromCodePoint(args: Value[]): string {
  let out = '';
  for (const v of args) {
    let i: bigint;
    if (isInt(v)) i = v; else if (isByte(v)) i = BigInt(v.v);
    else throw SwiftalkError.type(`String.fromCodePoint takes Ints, not a ${typeName(v)}`);
    if (i < 0n || i > 0x10FFFFn || (i >= 0xD800n && i <= 0xDFFFn)) throw SwiftalkError.type(`${i} is not a Unicode scalar value`);
    out += String.fromCodePoint(Number(i));
  }
  return out;
}
function randomBigInt(lo: bigint, hi: bigint): bigint {           // inclusive
  const span = hi - lo + 1n;
  const bits = span.toString(2).length;
  for (;;) {
    let r = 0n;
    for (let b = 0; b < bits; b += 30) r = (r << 30n) | BigInt(Math.floor(Math.random() * (1 << 30)));
    r &= (1n << BigInt(bits)) - 1n;
    if (r < span) return lo + r;
  }
}
export function intRandom(args: LabeledArg[]): bigint {
  const r = args[0]?.value;
  if (args.length !== 1 || !(args[0].label === null || args[0].label === 'in') || !isRange(r)) {
    throw SwiftalkError.type('Int.random(in:) takes one Range: Int.random(in: 1...6)');
  }
  if (r.to === null) throw SwiftalkError.type(`Int.random(in:) needs a bounded Range — ${r.from}... has no upper bound`);
  if (r.closed) return randomBigInt(r.from, r.to);
  if (!(r.from < r.to)) throw SwiftalkError.type(`Int.random(in:) needs a non-empty Range — ${r.from}..<${r.to} is empty`);
  return randomBigInt(r.from, r.to - 1n);
}
