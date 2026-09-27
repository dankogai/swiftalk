// Types as constructor Functions, protocols, the conformance table
// (Builtins.swift), and the math library (Math.swift).
import { SwiftalkError } from './errors.js';
import { TypeAnnotation } from './parser.js';
import { kindOf, typeName, V, SArray, SDictionary, SSet, Byte, SData, SDate, SRange, TupleValue,
  base64Decode, INT64_MAX, INT64_MIN, fits64, sourceString, hexFloat, formatDouble } from './value.js';
import { FunctionObject, EnumType, EnumCaseValue, SequenceObject } from './objects.js';
import { Environment } from './env.js';
import { inferLock, knownElementLock, tryInfer, ann, isSION } from './types.js';
import { collect, isSequenceValue, displayString, spawnTask, userOperator } from './eval.js';
import { SIONFormat } from './formats.js';

export const Builtins = {};
Builtins.emptyEnvironment = new Environment();

const resultType = new EnumType('Result', ['success', 'failure'],
  new Map([['success', [{ label: null, typeName: null }]], ['failure', [{ label: null, typeName: null }]]]));
resultType.constructor_ = new FunctionObject([], [], Builtins.emptyEnvironment,
  () => { throw SwiftalkError.type('construct a Result via Result.success(v) or Result.failure(e)'); }, { k: 'enumType', type: resultType });
Builtins.resultType = resultType;
Builtins.todo = new FunctionObject([], [], Builtins.emptyEnvironment,
  () => { throw SwiftalkError.type('this Function is .todo — assign an implementation before calling it'); }, { k: 'todo' });
export const success = (v) => new EnumCaseValue(resultType, 'success', [v]);
export const failure = (m) => new EnumCaseValue(resultType, 'failure', [typeof m === 'string' ? m : m]);
export const isResult = (v) => v instanceof EnumCaseValue && v.type === resultType;

const type = (name, construct) => new FunctionObject([], [], Builtins.emptyEnvironment, construct, { k: 'type', name });
const protocolObject = (name) => new FunctionObject([], [], Builtins.emptyEnvironment,
  () => { throw SwiftalkError.type(`${name} is a protocol, not a constructor`); }, { k: 'protocol', name });

Builtins.stampedSet = (elements, source) => {
  const set = elements instanceof SSet ? elements : new SSet(elements);
  const inferred = tryInfer(set, 'Set', false);
  if (inferred && inferred.parameters.length) return new SSet(set.values(), inferred);
  if (set.size === 0 && source != null) {
    const known = knownElementLock(source);
    if (known) return new SSet([], ann('Set', false, [known]));
  }
  return set;
};

/// Int-from-String, accepting everything the lexer does.
export function parseIntText(input) {
  let s = input.replace(/_/g, '');
  let negative = false;
  if (s.startsWith('-') || s.startsWith('+')) { negative = s.startsWith('-'); s = s.slice(1); }
  let radix = 10, digits = /^[0-9]+$/;
  if (s.startsWith('0x')) { radix = 16; s = s.slice(2); digits = /^[0-9a-fA-F]+$/; }
  else if (s.startsWith('0o')) { radix = 8; s = s.slice(2); digits = /^[0-7]+$/; }
  else if (s.startsWith('0b')) { radix = 2; s = s.slice(2); digits = /^[01]+$/; }
  if (!s.length || !digits.test(s)) return null;
  const prefix = { 10: '', 16: '0x', 8: '0o', 2: '0b' }[radix];
  const magnitude = BigInt(prefix + s);
  if (negative) {
    if (magnitude > (1n << 63n)) return null;
    return -magnitude;
  }
  if (magnitude > INT64_MAX) return null;
  return magnitude;
}
Builtins.parseInt = parseIntText;

/// Swift's Double(String): decimal, hex floats, inf/nan spellings; nil otherwise.
export function parseDoubleText(s) {
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

const toByte = (n) => (n >= 0n && n <= 255n ? new Byte(Number(n)) : null);

Builtins.types = new Map([
  ['Nil', type('Nil', (args) => {
    if (args.length === 0 || args[0] === null) return null;
    throw SwiftalkError.type(`cannot convert ${typeName(args[0])} to Nil`);
  })],
  ['Bool', type('Bool', (args) => {
    const v = args[0];
    if (args.length === 0) return false;
    switch (kindOf(v)) {
      case 'bool': return v;
      case 'string': return v === 'true' ? true : v === 'false' ? false : null;
      case 'int': return v !== 0n;
      default: throw SwiftalkError.type(`cannot convert ${typeName(v)} to Bool`);
    }
  })],
  ['Byte', type('Byte', (args) => {
    const v = args[0];
    if (args.length === 0) return new Byte(0);
    switch (kindOf(v)) {
      case 'byte': return v;
      case 'int': return toByte(v);
      case 'double': { const t = Math.trunc(v); return Number.isFinite(t) && t >= 0 && t <= 255 && t === v ? new Byte(t) : (Number.isFinite(t) && t >= 0 && t <= 255 ? new Byte(t) : null); }
      case 'string': { const i = parseIntText(v); return i === null ? null : toByte(i); }
      default: throw SwiftalkError.type(`cannot convert ${typeName(v)} to Byte`);
    }
  })],
  ['Int', type('Int', (args) => {
    const v = args[0];
    if (args.length === 0) return 0n;
    switch (kindOf(v)) {
      case 'int': return v;
      case 'byte': return BigInt(v.v);
      case 'double': {
        if (!Number.isFinite(v)) return null;
        const t = Math.trunc(v);
        const b = BigInt(t);
        return fits64(b) ? b : null;
      }
      case 'string': return parseIntText(v);
      default: throw SwiftalkError.type(`cannot convert ${typeName(v)} to Int`);
    }
  })],
  ['Double', type('Double', (args) => {
    const v = args[0];
    if (args.length === 0) return 0;
    switch (kindOf(v)) {
      case 'double': return v;
      case 'int': return Number(v);
      case 'byte': return v.v;
      case 'string': return parseDoubleText(v);
      case 'date': return v.epoch;
      default: throw SwiftalkError.type(`cannot convert ${typeName(v)} to Double`);
    }
  })],
  ['String', type('String', function* (args) {
    if (args.length === 0) return '';
    return yield* displayString(args[0]);
  })],
  ['Optional', type('Optional', (args) => (args.length ? args[0] : null))],
  ['Array', type('Array', function* (args) {
    const v = args[0];
    if (args.length === 0) return new SArray([]);
    switch (kindOf(v)) {
      case 'array': return new SArray(v.items, v.lock);
      case 'set': return new SArray(v.values(), v.lock ? ann('Array', false, v.lock.parameters) : null);
      default: {
        const out = yield* collect(v);
        const inferred = tryInfer(new SArray(out), 'Array', false);
        if (inferred && inferred.parameters.length) return new SArray(out, inferred);
        if (out.length === 0) { const known = knownElementLock(v); if (known) return new SArray(out, ann('Array', false, [known])); }
        return new SArray(out);
      }
    }
  })],
  ['Dictionary', type('Dictionary', function* (args) {
    const v = args[0];
    if (args.length === 0) return new SDictionary([]);
    if (kindOf(v) === 'dictionary') return new SDictionary(v.entries(), v.lock);
    if (isSequenceValue(v)) {
      const d = new SDictionary([]);
      for (const pair of yield* collect(v)) {
        if (!(pair instanceof TupleValue) || pair.count !== 2) throw SwiftalkError.type(`Dictionary(pairs) takes a Sequence of (key, value) tuples, not a ${typeName(pair)}`);
        if (d.has(pair.values[0])) throw SwiftalkError.type(`Dictionary(pairs): duplicate key ${sourceString(pair.values[0])}`);
        d.set(pair.values[0], pair.values[1]);
      }
      const inferred = tryInfer(d, 'Dictionary', false);
      if (inferred && inferred.parameters.length) return new SDictionary(d.entries(), inferred);
      return d;
    }
    throw SwiftalkError.type(`cannot convert ${typeName(v)} to Dictionary`);
  })],
  ['Set', type('Set', function* (args) {
    const v = args[0];
    if (args.length === 0) return new SSet([]);
    if (kindOf(v) === 'set') return new SSet(v.values(), v.lock);
    if (isSequenceValue(v)) return Builtins.stampedSet(new SSet(yield* collect(v)), v);
    return Builtins.stampedSet(new SSet([v]), null);
  })],
  ['Range', type('Range', (args) => {
    const v = args[0];
    if (args.length === 0) throw SwiftalkError.type('construct a Range with its literal: a...b or a..<b');
    if (kindOf(v) === 'range') return new SRange(v.from, v.to, v.closed);
    throw SwiftalkError.type(`cannot convert ${typeName(v)} to Range`);
  })],
  ['Function', type('Function', (args) => {
    const v = args[0];
    if (args.length === 0) throw SwiftalkError.type('there is no default Function');
    if (kindOf(v) === 'function') return v;
    throw SwiftalkError.type(`cannot convert ${typeName(v)} to Function`);
  })],
  ['Data', type('Data', (args) => {
    const v = args[0];
    if (args.length === 0) return new SData([]);
    switch (kindOf(v)) {
      case 'data': return v;
      case 'string': { const b = base64Decode(v); return b === null || (v.replace(/\s/g, '').length % 4) !== 0 ? null : new SData(b); }
      case 'array': {
        const bytes = [];
        for (const x of v.items) {
          if (x instanceof Byte) bytes.push(x.v);
          else if (typeof x === 'bigint' && x >= 0n && x <= 255n) bytes.push(Number(x));
          else return null;
        }
        return new SData(bytes);
      }
      default: throw SwiftalkError.type(`cannot convert ${typeName(v)} to Data`);
    }
  })],
  ['Task', type('Task', function* (args) {
    if (args.length !== 1 || kindOf(args[0]) !== 'function') throw SwiftalkError.type('Task { ... } spawns a Function as a concurrent task');
    const f = args[0];
    if (f.builtin) throw SwiftalkError.type('Task(f): cannot spawn a builtin Function');
    if (f.parameters.length) throw SwiftalkError.type('Task(f): a task body declares no parameters — nothing is passed in');
    return yield* spawnTask(f);
  })],
  ['Tuple', type('Tuple', function* (args) {
    const v = args[0];
    if (args.length === 0) return new TupleValue([]);
    if (v instanceof TupleValue) return v;
    return new TupleValue(yield* collect(v));
  })],
  ['SION', type('SION', (args) => {
    const v = args[0];
    if (args.length === 0) throw SwiftalkError.type('SION(text) reads a SION document; SION(json:) and SION(propertyList:) the other formats');
    if (kindOf(v) === 'string') return SIONFormat.parse(v);
    if (!isSION(v)) throw SwiftalkError.type(`a ${typeName(v)} is not SION`);
    return v;
  })],
  ['Date', type('Date', (args) => {
    const v = args[0];
    if (args.length === 0) return new SDate(Date.now() / 1000);
    switch (kindOf(v)) {
      case 'date': return v;
      case 'double': return new SDate(v);
      case 'int': return new SDate(Number(v));
      default: throw SwiftalkError.type(`cannot convert ${typeName(v)} to Date`);
    }
  })],
]);

Builtins.protocols = new Map([
  ['Sequence', new FunctionObject([], [], Builtins.emptyEnvironment, (args) => {
    if (args.length === 1 && kindOf(args[0]) === 'function') {
      const f = args[0];
      if (f.builtin) throw SwiftalkError.type('Sequence(f): cannot wrap a builtin Function as a coroutine');
      if (f.parameters.length) throw SwiftalkError.type('Sequence(f): a coroutine body declares no parameters — nothing is passed in on resume');
      return new SequenceObject({ kind: 'coroutine', body: f });
    }
    if (args.length !== 2 || kindOf(args[0]) !== 'array' || kindOf(args[1]) !== 'function') {
      throw SwiftalkError.type('Sequence(f) wraps a yielding Function; Sequence(initialState) { next } generates');
    }
    return new SequenceObject({ kind: 'generator', initial: args[0].items, next: args[1] });
  }, { k: 'protocol', name: 'Sequence' })],
  ['Equatable', protocolObject('Equatable')],
  ['Hashable', protocolObject('Hashable')],
  ['Comparable', protocolObject('Comparable')],
]);

const allTypeNames = new Set(['Nil', 'Bool', 'Int', 'Double', 'String', 'Array', 'Dictionary', 'Set', 'Range', 'Function', 'Sequence', 'Data', 'Date', 'Task', 'Tuple', 'Byte']);
Builtins.conformance = new Map([
  ['Sequence', new Set(['String', 'Array', 'Dictionary', 'Set', 'Range', 'Sequence', 'Tuple', 'Data'])],
  ['Equatable', allTypeNames],
  ['Hashable', allTypeNames],
  ['Comparable', new Set(['Int', 'Double', 'String', 'Date', 'Byte'])],
]);

// ---- math ----
const M = Math;
function erf(x) {
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
const erfc = (x) => 1 - erf(x);
function lgamma(x) {
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
function tgamma(x) {
  if (Number.isInteger(x)) { if (x <= 0) return NaN; if (x <= 171) { let r = 1; for (let i = 2; i < x; i++) r *= i; return r; } return Infinity; }
  if (x < 0.5) return Math.PI / (Math.sin(Math.PI * x) * tgamma(1 - x));
  return Math.exp(lgamma(x));
}
// Bessel functions — Numerical Recipes' polynomial approximations. FIXME: ~1e-8 accuracy, not libm's.
/// The power series inside |x| < 8 (exact at 0, ~1e-15), Numerical Recipes' asymptotic form beyond.
function besselSeries(x, order) {
  const h = x / 2;
  let term = order === 0 ? 1 : h, sum = term;
  for (let k = 1; k < 60; k++) { term *= -(h * h) / (k * (k + order)); sum += term; if (Math.abs(term) < 1e-17 * Math.abs(sum)) break; }
  return sum;
}
function j0(x) {
  const ax = Math.abs(x);
  if (ax < 8) return besselSeries(x, 0);
  const z = 8 / ax, y = z * z, xx = ax - 0.785398164;
  return Math.sqrt(0.636619772 / ax) * (Math.cos(xx) * (1 + y * (-0.1098628627e-2 + y * (0.2734510407e-4 + y * (-0.2073370639e-5 + y * 0.2093887211e-6))))
    - z * Math.sin(xx) * (-0.1562499995e-1 + y * (0.1430488765e-3 + y * (-0.6911147651e-5 + y * (0.7621095161e-6 - y * 0.934935152e-7)))));
}
function j1(x) {
  const ax = Math.abs(x);
  if (ax < 8) return besselSeries(x, 1);
  const z = 8 / ax, y = z * z, xx = ax - 2.356194491;
  const ans = Math.sqrt(0.636619772 / ax) * (Math.cos(xx) * (1 + y * (0.183105e-2 + y * (-0.3516396496e-4 + y * (0.2457520174e-5 + y * -0.240337019e-6))))
    - z * Math.sin(xx) * (0.04687499995 + y * (-0.2002690873e-3 + y * (0.8449199096e-5 + y * (-0.88228987e-6 + y * 0.105787412e-6)))));
  return x < 0 ? -ans : ans;
}
function y0(x) {
  if (x < 8) { const y = x * x; return (-2957821389.0 + y * (7062834065.0 + y * (-512359803.6 + y * (10879881.29 + y * (-86327.92757 + y * 228.4622733)))))
    / (40076544269.0 + y * (745249964.8 + y * (7189466.438 + y * (47447.26470 + y * (226.1030244 + y))))) + 0.636619772 * j0(x) * Math.log(x); }
  const z = 8 / x, y = z * z, xx = x - 0.785398164;
  return Math.sqrt(0.636619772 / x) * (Math.sin(xx) * (1 + y * (-0.1098628627e-2 + y * (0.2734510407e-4 + y * (-0.2073370639e-5 + y * 0.2093887211e-6))))
    + z * Math.cos(xx) * (-0.1562499995e-1 + y * (0.1430488765e-3 + y * (-0.6911147651e-5 + y * (0.7621095161e-6 + y * -0.934945152e-7)))));
}
function y1(x) {
  if (x < 8) { const y = x * x; return x * (-0.4900604943e13 + y * (0.1275274390e13 + y * (-0.5153438139e11 + y * (0.7349264551e9 + y * (-0.4237922726e7 + y * 0.8511937935e4)))))
    / (0.2499580570e14 + y * (0.4244419664e12 + y * (0.3733650367e10 + y * (0.2245904002e8 + y * (0.1020426050e6 + y * (0.3549632885e3 + y)))))) + 0.636619772 * (j1(x) * Math.log(x) - 1 / x); }
  const z = 8 / x, y = z * z, xx = x - 2.356194491;
  return Math.sqrt(0.636619772 / x) * (Math.sin(xx) * (1 + y * (0.183105e-2 + y * (-0.3516396496e-4 + y * (0.2457520174e-5 + y * -0.240337019e-6))))
    + z * Math.cos(xx) * (0.04687499995 + y * (-0.2002690873e-3 + y * (0.8449199096e-5 + y * (-0.88228987e-6 + y * 0.105787412e-6)))));
}
function jn(n, x) {
  if (n === 0) return j0(x); if (n === 1) return j1(x);
  if (x === 0) return 0;
  let bjm = j0(x), bj = j1(x);
  for (let k = 1; k < n; k++) { const bjp = k * 2 / x * bj - bjm; bjm = bj; bj = bjp; }
  return bj;
}
function yn(n, x) {
  if (n === 0) return y0(x); if (n === 1) return y1(x);
  let bym = y0(x), by = y1(x);
  for (let k = 1; k < n; k++) { const byp = k * 2 / x * by - bym; bym = by; by = byp; }
  return by;
}
function frexp(x) {
  if (x === 0 || !Number.isFinite(x)) return [x, 0];
  const view = new DataView(new ArrayBuffer(8));
  view.setFloat64(0, x);
  let e = (view.getUint16(0) >> 4) & 0x7ff;
  if (e === 0) { const r = frexp(x * Math.pow(2, 64)); return [r[0], r[1] - 64]; }
  const exponent = e - 1022;
  view.setUint16(0, (view.getUint16(0) & 0x800f) | (1022 << 4));
  return [view.getFloat64(0), exponent];
}
function ilogb(x) {
  if (x === 0) return -2147483648;                 // FP_ILOGB0
  if (Number.isNaN(x)) return 2147483648;          // FP_ILOGBNAN
  if (!Number.isFinite(x)) return 2147483647;
  return frexp(x)[1] - 1;
}
function logb(x) {
  if (x === 0) return -Infinity;
  if (!Number.isFinite(x)) return Math.abs(x);
  return frexp(x)[1] - 1;
}
function scalbn(x, n) { return x * Math.pow(2, n); }
function nextafter(x, y) {
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
function remainder(x, y) {
  if (!Number.isFinite(x) || y === 0 || Number.isNaN(y)) return NaN;
  const n = x / y;
  let q = Math.round(n);
  if (Math.abs(n - Math.trunc(n)) === 0.5) q = 2 * Math.round(n / 2);   // ties to even
  return x - q * y;
}
const cRound = (x) => (x < 0 ? -Math.round(-x) : Math.round(x));   // half away from zero
const roundEven = (x) => { const r = Math.round(x); return Math.abs(x - Math.trunc(x)) === 0.5 ? 2 * Math.round(x / 2) : r; };

export const DoubleMath = {
  constants: new Map(Object.entries({
    pi: Math.PI, tau: 2 * Math.PI, e: Math.E, ln2: Math.LN2, ln10: Math.LN10, log2e: Math.LOG2E, log10e: Math.LOG10E,
    sqrt2: Math.SQRT2, sqrtHalf: Math.SQRT1_2, infinity: Infinity, nan: NaN,
    greatestFiniteMagnitude: Number.MAX_VALUE, leastNormalMagnitude: 2.2250738585072014e-308, leastNonzeroMagnitude: Number.MIN_VALUE,
    ulpOfOne: Number.EPSILON, zero: 0, radix: 2, exponentBitCount: 11, significandBitCount: 52,
  })),
  unary: new Map(Object.entries({
    abs: Math.abs, sqrt: Math.sqrt, cbrt: Math.cbrt, exp: Math.exp, exp2: (x) => Math.pow(2, x), expm1: Math.expm1,
    log: Math.log, log2: Math.log2, log10: Math.log10, log1p: Math.log1p, logb,
    sin: Math.sin, cos: Math.cos, tan: Math.tan, asin: Math.asin, acos: Math.acos, atan: Math.atan,
    sinh: Math.sinh, cosh: Math.cosh, tanh: Math.tanh, asinh: Math.asinh, acosh: Math.acosh, atanh: Math.atanh,
    floor: Math.floor, ceil: Math.ceil, trunc: Math.trunc, round: cRound, rint: roundEven, nearbyint: roundEven,
    sign: (x) => (Number.isNaN(x) ? NaN : x > 0 ? 1 : x < 0 ? -1 : x),
    erf, erfc, tgamma, gamma: tgamma, lgamma, j0, j1, y0, y1, fround: Math.fround,
  })),
  binary: new Map(Object.entries({
    pow: Math.pow, atan2: Math.atan2, fmod: (a, b) => a % b, remainder,
    fdim: (a, b) => (a > b ? a - b : 0), fmax: (a, b) => (Number.isNaN(a) ? b : Number.isNaN(b) ? a : Math.max(a, b)),
    fmin: (a, b) => (Number.isNaN(a) ? b : Number.isNaN(b) ? a : Math.min(a, b)),
    copysign: (a, b) => (Math.sign(b) < 0 || Object.is(b, -0) || (b !== b && Object.is(b, -0)) ? -Math.abs(a) : Math.abs(a)), nextafter,
  })),
  predicates: new Map(Object.entries({
    isNaN: Number.isNaN, isFinite: Number.isFinite, isInfinite: (x) => x === Infinity || x === -Infinity,
    isZero: (x) => x === 0, isNormal: (x) => Number.isFinite(x) && x !== 0 && Math.abs(x) >= 2.2250738585072014e-308,
    isSubnormal: (x) => x !== 0 && Math.abs(x) < 2.2250738585072014e-308,
  })),
};
DoubleMath.functions = new Set([...DoubleMath.unary.keys(), ...DoubleMath.binary.keys(), ...DoubleMath.predicates.keys(),
  'max', 'min', 'hypot', 'random', 'fma', 'ldexp', 'scalbn', 'ilogb', 'jn', 'yn', 'modf', 'frexp', 'remquo']);
function number(v, name) {
  switch (kindOf(v)) {
    case 'double': return v;
    case 'int': return Number(v);
    case 'byte': return v.v;
    default: throw SwiftalkError.type(`Double.${name} takes numbers, not a ${typeName(v)}`);
  }
}
function mathApply(name, args) {
  const arity = (n) => {
    if (args.length !== n) throw SwiftalkError.type(`Double.${name} takes ${n} argument${n === 1 ? '' : 's'}, got ${args.length}`);
    return args.map((a) => number(a, name));
  };
  if (DoubleMath.unary.has(name)) return DoubleMath.unary.get(name)(arity(1)[0]);
  if (DoubleMath.binary.has(name)) { const a = arity(2); return DoubleMath.binary.get(name)(a[0], a[1]); }
  if (DoubleMath.predicates.has(name)) return DoubleMath.predicates.get(name)(arity(1)[0]);
  switch (name) {
    case 'max': case 'min': {
      if (!args.length) throw SwiftalkError.type(`Double.${name} takes at least one number`);
      const xs = args.map((a) => number(a, name));
      return name === 'max' ? xs.reduce((m, x) => Math.max(m, x), -Infinity) : xs.reduce((m, x) => Math.min(m, x), Infinity);
    }
    case 'hypot': return args.map((a) => number(a, name)).reduce((h, x) => Math.hypot(h, x), 0);
    case 'random': return mathRandom(args.map((v) => ({ label: null, value: v })));
    case 'fma': { const a = arity(3); return a[0] * a[1] + a[2]; }   // FIXME: not a fused multiply-add
    case 'ldexp': case 'scalbn': {
      if (args.length !== 2 || kindOf(args[1]) !== 'int') throw SwiftalkError.type(`Double.${name}(x, n) takes a number and an Int`);
      return scalbn(number(args[0], name), Number(args[1]));
    }
    case 'ilogb': return BigInt(ilogb(arity(1)[0]));
    case 'jn': case 'yn': {
      if (args.length !== 2 || kindOf(args[0]) !== 'int') throw SwiftalkError.type(`Double.${name}(n, x) takes an Int order and a number`);
      const x = number(args[1], name);
      return name === 'jn' ? jn(Number(args[0]), x) : yn(Number(args[0]), x);
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
export function parseRandomBounds(args, who) {
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
function mathRandom(args) {
  const [from, to] = parseRandomBounds(args, 'Double');
  const lo = from === null ? 0 : number(from, 'random');
  const hi = to === null ? 1 : number(to, 'random');
  if (!Number.isFinite(lo) || !Number.isFinite(hi) || !(lo < hi)) throw SwiftalkError.type(`Double.random needs finite bounds with from < to, got ${formatDouble(lo)} and ${formatDouble(hi)}`);
  return lo + Math.random() * (hi - lo);
}
/// `Double.name` — nil when not a math member.
DoubleMath.member = (name, args, called) => {
  if (DoubleMath.constants.has(name)) {
    if (called) throw SwiftalkError.type(`Double.${name} is a constant, not a function`);
    return DoubleMath.constants.get(name);
  }
  if (!DoubleMath.functions.has(name)) return undefined;
  if (name === 'random' && called) return mathRandom(args);
  const label = args.map((a) => a.label).find((l) => l !== null);
  if (label !== undefined) throw SwiftalkError.type(`Double.${name} takes no argument label '${label}'`);
  const values = args.map((a) => a.value);
  if (!called) return new FunctionObject([], [], Builtins.emptyEnvironment, (xs) => mathApply(name, xs));
  return mathApply(name, values);
};

/// `base ** exponent` (round 142).
export function* power(base, exponent) {
  const r = yield* userOperator('infix:**', [base, exponent]);
  if (r !== undefined) return r;
  const kb = kindOf(base), ke = kindOf(exponent);
  if (kb === 'int' && ke === 'int') {
    if (exponent < 0n) throw SwiftalkError.type(`'**' with a negative Int exponent has no Int answer — ${base}.Double() ** ${exponent}.Double()`);
    let result = 1n, x = base, n = exponent;
    while (n > 0n) {
      if (n & 1n) { result *= x; if (!fits64(result)) throw SwiftalkError.overflow(`${base} ** ${exponent}`); }
      n >>= 1n;
      if (n > 0n) { x *= x; if (!fits64(x)) throw SwiftalkError.overflow(`${base} ** ${exponent}`); }
    }
    return result;
  }
  if (kb === 'double' && ke === 'double') return Math.pow(base, exponent);
  throw SwiftalkError.type(`'**' is not defined between ${typeName(base)} and ${typeName(exponent)} — two Ints or two Doubles`);
}

export const IntStatics = new Map([
  ['Int', new Map([['min', INT64_MIN], ['max', INT64_MAX], ['bitWidth', 64n], ['zero', 0n], ['isSigned', true]])],
  ['Byte', new Map([['min', new Byte(0)], ['max', new Byte(255)], ['bitWidth', 8n], ['zero', new Byte(0)], ['isSigned', false]])],
]);
export function dataRandom(args) {
  if (args.length !== 1 || kindOf(args[0]) !== 'int' || args[0] < 0n) throw SwiftalkError.type('Data.random(count) takes one non-negative Int');
  const n = Number(args[0]);
  const bytes = new Uint8Array(n);
  for (let i = 0; i < n; i++) bytes[i] = Math.floor(Math.random() * 256);
  return new SData(bytes);
}
export function stringFromCodePoint(args) {
  let out = '';
  for (const v of args) {
    let i;
    if (kindOf(v) === 'int') i = v; else if (v instanceof Byte) i = BigInt(v.v);
    else throw SwiftalkError.type(`String.fromCodePoint takes Ints, not a ${typeName(v)}`);
    if (i < 0n || i > 0x10FFFFn || (i >= 0xD800n && i <= 0xDFFFn)) throw SwiftalkError.type(`${i} is not a Unicode scalar value`);
    out += String.fromCodePoint(Number(i));
  }
  return out;
}
function randomBigInt(lo, hi) {           // inclusive
  const span = hi - lo + 1n;
  const bits = span.toString(2).length;
  for (;;) {
    let r = 0n;
    for (let b = 0; b < bits; b += 30) r = (r << 30n) | BigInt(Math.floor(Math.random() * (1 << 30)));
    r &= (1n << BigInt(bits)) - 1n;
    if (r < span) return lo + r;
  }
}
export function intRandom(args) {
  if (args.length !== 1 || !(args[0].label === null || args[0].label === 'in') || kindOf(args[0].value) !== 'range') {
    throw SwiftalkError.type('Int.random(in:) takes one Range: Int.random(in: 1...6)');
  }
  const r = args[0].value;
  if (r.to === null) throw SwiftalkError.type(`Int.random(in:) needs a bounded Range — ${r.from}... has no upper bound`);
  if (r.closed) return randomBigInt(r.from, r.to);
  if (!(r.from < r.to)) throw SwiftalkError.type(`Int.random(in:) needs a non-empty Range — ${r.from}..<${r.to} is empty`);
  return randomBigInt(r.from, r.to - 1n);
}
