// `BigRat` — exact rationals (roundRat 203), a module beside BigInt: a BigInt
// over a BigInt, reduced on construction, the sign in the numerator.
// Strict, like the rest of swiftalk's numbers: a BigRat meets a BigRat.
// Over the platform's BigInt here; swift-bignum's BigRat in Swift.
import { SwiftalkError } from '../errors.js';
import { Module } from '../modules.js';
import { kindOf, typeName, sourceString, INT64_MAX, INT64_MIN } from '../value.js';
import { HostValue } from '../objects.js';
import { callBuiltin } from '../types.js';
import { scheduler } from '../eval.js';

const absRat = (n) => (n < 0n ? -n : n);
const gcdRat = (a, b) => { a = absRat(a); b = absRat(b); while (b !== 0n) [a, b] = [b, a % b]; return a; };
const bitLength = (n) => absRat(n).toString(2).length;
/// Floor division and the rounding roundingRules, on the fraction n/d (d > 0).
const floorDiv = (n, d) => { const q = n / d; return n % d !== 0n && n < 0n ? q - 1n : q; };
function roundRat(n, d, rule) {
  const f = floorDiv(n, d), r = n - f * d;          // 0 <= r < d
  switch (rule) {
    case 'down': return f;
    case 'up': return r === 0n ? f : f + 1n;
    case 'towardZero': return n < 0n && r !== 0n ? f + 1n : f;
    case 'awayFromZero': return r === 0n ? f : n < 0n ? f : f + 1n;
    case 'toNearestOrEven': { const twice = 2n * r; if (twice < d) return f; if (twice > d) return f + 1n; return f % 2n === 0n ? f : f + 1n; }
    default: { const twice = 2n * r; if (twice < d) return f; if (twice > d) return f + 1n; return n < 0n ? f : f + 1n; }   // toNearestOrAwayFromZero
  }
}
const roundingRules = new Set(['toNearestOrAwayFromZero', 'toNearestOrEven', 'up', 'down', 'towardZero', 'awayFromZero']);

function integerText(text) {
  let s = text, negative = false;
  if (s.startsWith('-')) { negative = true; s = s.slice(1); } else if (s.startsWith('+')) s = s.slice(1);
  if (s.endsWith('n')) s = s.slice(0, -1);
  if (!/^(0[xX][0-9a-fA-F]+|0[oO][0-7]+|0[bB][01]+|[0-9]+)$/.test(s)) return null;
  const v = BigInt(s.replace(/^0[XOB]/, (p) => p.toLowerCase()));
  return negative ? -v : v;
}
/// "n/d", an integer, or a decimal with an optional exponent.
function parseRational(text) {
  const s = text.replace(/[_ ]/g, '');
  const slash = s.indexOf('/');
  if (slash >= 0) {
    const n = integerText(s.slice(0, slash)), d = integerText(s.slice(slash + 1));
    return n === null || d === null || d === 0n ? null : [n, d];
  }
  const i = integerText(s);
  if (i !== null) return [i, 1n];
  const m = /^([+-])?(\d*)(?:\.(\d*))?(?:[eE]([+-]?\d+))?$/.exec(s);
  if (!m || (m[2] === '' && (m[3] ?? '') === '')) return null;
  const digits = m[2] + (m[3] ?? ''), scale = (m[3] ?? '').length, exponent = Number(m[4] ?? 0);
  let n = BigInt(digits), d = 1n;
  const k = exponent - scale;
  if (k >= 0) n *= 10n ** BigInt(k); else d = 10n ** BigInt(-k);
  return [m[1] === '-' ? -n : n, d];
}
/// The Double, exactly: halve until the fraction is gone.
function fromDouble(x) {
  let d = 1n;
  while (!Number.isInteger(x)) { x *= 2; d *= 2n; }
  return [BigInt(x), d];
}
const ratOperators = new Set(['infix:+', 'infix:-', 'infix:*', 'infix:/', 'infix:**', 'infix:<', 'prefix:-', 'prefix:+']);

export class BigRatValue {
  constructor(n, d, type) {
    if (d < 0n) { n = -n; d = -d; }
    const g = n === 0n ? 1n : gcdRat(n, d);
    this.n = n / g; this.d = n === 0n ? 1n : d / g;
    this.type = type;
    this.typeName = 'BigRat';
  }
  get bigRat() { return [this.n, this.d]; }          // what the BigInt module sees
  make(n, d) { return new HostValue(new BigRatValue(n, d, this.type), this.type); }
  isZero() { return this.n === 0n; }
  toDouble() {
    const { n, d } = this;
    if (absRat(n) < 2n ** 53n && d < 2n ** 53n) return Number(n) / Number(d);
    const shift = Math.max(0, bitLength(d) - bitLength(n) + 64);
    return Number((n << BigInt(shift)) / d) * 2 ** -shift;
  }
  *bigInt(n, what) {
    const i = scheduler.current;
    const t = i ? i.environment.tryLookup('BigInt') : undefined;
    if (!t || kindOf(t) !== 'function' || !t.builtin) throw SwiftalkError.type(`${what} is a BigInt — import from "BigInt" (the CLI preimports it)`);
    return yield* callBuiltin(t.builtin, [n.toString()]);
  }
  exponent(v, what) {
    if (typeof v === 'bigint') return v;
    if (kindOf(v) === 'host' && typeof v.object.bigInt === 'bigint') return v.object.bigInt;
    throw SwiftalkError.type(`${what} takes an Int or BigInt exponent, not ${typeName(v)}`);
  }
  raised(e) {
    if (e < 0n) { if (this.isZero()) throw SwiftalkError.zeroDivision(); return this.make(this.d ** -e, this.n ** -e); }
    return this.make(this.n ** e, this.d ** e);
  }
  *member(name, args, called) {
    const { n, d } = this;
    switch (`${name}${called ? '()' : ''}`) {
      case 'BigRat()': return new HostValue(this, this.type);
      case 'Double()': return this.toDouble();
      case 'BigInt()': return yield* this.bigInt(roundRat(n, d, 'towardZero'), 'r.BigInt()');
      case 'Int()': {
        const t = roundRat(n, d, 'towardZero');
        if (t > INT64_MAX || t < INT64_MIN) throw SwiftalkError.overflow(`${this.sourceString(false)} does not fit in an Int`);
        return t;
      }
      case 'String()': {
        if (!args.length) return this.sourceString(false);
        if (args.length !== 1 || typeof args[0] !== 'string') throw SwiftalkError.type('BigRat.String() takes at most one format: .fraction or .mixed');
        if (args[0] === 'fraction') return `${n}/${d}`;
        if (args[0] === 'mixed') {
          const whole = roundRat(n, d, 'towardZero'), part = absRat(n - whole * d);
          if (part === 0n) return `${whole}`;
          const frac = `${part}/${d}`;
          return whole === 0n ? (n < 0n ? '-' : '') + frac : `${whole} ${frac}`;
        }
        throw SwiftalkError.type(`BigRat.String() takes .fraction or .mixed, not .${args[0]}`);
      }
      case 'numerator': return yield* this.bigInt(n, 'r.numerator');
      case 'denominator': return yield* this.bigInt(d, 'r.denominator');
      case 'isInteger': return d === 1n;
      case 'isZero': return n === 0n;
      case 'magnitude': return this.make(absRat(n), d);
      case 'signum': return n < 0n ? -1n : n > 0n ? 1n : 0n;
      case 'reciprocal': if (n === 0n) throw SwiftalkError.zeroDivision(); return this.make(d, n);
      case 'rounded()': {
        if (args.length > 1) throw SwiftalkError.type('BigRat.rounded() or .rounded(rule)');
        let rule = 'toNearestOrAwayFromZero';
        if (args.length) {
          if (typeof args[0] !== 'string') throw SwiftalkError.type('BigRat.rounded takes a rule: .toNearestOrAwayFromZero, .toNearestOrEven, .up, .down, .towardZero, .awayFromZero');
          if (!roundingRules.has(args[0])) throw SwiftalkError.type(`BigRat.rounded: unknown rule .${args[0]}`);
          rule = args[0];
        }
        return this.make(roundRat(n, d, rule), 1n);
      }
      case 'power()':
        if (args.length !== 1) throw SwiftalkError.type('BigRat.power(exponent) takes one Int or BigInt');
        return this.raised(this.exponent(args[0], 'BigRat.power'));
      default: return undefined;
    }
  }
  hasOperator(key) { return ratOperators.has(key); }
  operate(key, operands) {
    if (!ratOperators.has(key)) return undefined;
    const op = key.slice(key.indexOf(':') + 1);
    if (key.startsWith('prefix')) return this.make(op === '-' ? -this.n : this.n, this.d);
    if (operands.length !== 2) return undefined;
    if (op === '**') {
      const base = operands[0];
      if (!(kindOf(base) === 'host' && base.object instanceof BigRatValue)) throw SwiftalkError.type("'**' takes a BigRat base and an Int or BigInt exponent");
      return base.object.raised(this.exponent(operands[1], "'**'"));
    }
    const sides = operands.map((v) => {
      if (kindOf(v) === 'host') {
        if (v.object instanceof BigRatValue) return v.object;
        if (typeof v.object.bigInt === 'bigint') throw SwiftalkError.type(`'${op}' between BigRat and BigInt: convert first — BigRat(b), or r.BigInt()`);
      }
      const k = kindOf(v);
      if (k === 'int' || k === 'double' || k === 'byte') throw SwiftalkError.type(`'${op}' between BigRat and ${typeName(v)}: convert first — BigRat(x)`);
      throw SwiftalkError.type(`'${op}' is not defined between ${typeName(operands[0])} and ${typeName(operands[1])}`);
    });
    const [a, b] = sides;
    switch (op) {
      case '+': return this.make(a.n * b.d + b.n * a.d, a.d * b.d);
      case '-': return this.make(a.n * b.d - b.n * a.d, a.d * b.d);
      case '*': return this.make(a.n * b.n, a.d * b.d);
      case '/': if (b.n === 0n) throw SwiftalkError.zeroDivision(); return this.make(a.n * b.d, a.d * b.n);
      case '<': return a.n * b.d < b.n * a.d;
      default: return undefined;
    }
  }
  isEqual(other) { return other instanceof BigRatValue && other.n === this.n && other.d === this.d; }
  hashKey() { return `BigRat:${this.n}/${this.d}`; }
  sourceString(debug) {
    const hex = (x) => (x < 0n ? '-0x' : '+0x') + absRat(x).toString(16) + 'n';
    return debug ? `BigRat(${hex(this.n)}, ${hex(this.d)})` : `BigRat(${this.n}, ${this.d})`;
  }
  patternMatch(subject, binding) {
    if (!(kindOf(subject) === 'host' && subject.object instanceof BigRatValue)) {
      if (binding) throw SwiftalkError.type(`a BigRat case needs a BigRat subject, not ${typeName(subject)}`);
      return null;
    }
    return this.isEqual(subject.object) ? subject : null;
  }
}

export function BigRatModule() {
  const m = new Module('BigRat');
  let typeValue = null;
  const make = (n, d) => new HostValue(new BigRatValue(n, d, typeValue), typeValue);
  const integer = (v, what) => {
    if (typeof v === 'bigint') return v;
    if (kindOf(v) === 'byte') return BigInt(v.v);
    if (kindOf(v) === 'host' && typeof v.object.bigInt === 'bigint') return v.object.bigInt;
    throw SwiftalkError.type(`${what} takes Ints or BigInts, not ${typeName(v)}`);
  };
  typeValue = m.type('BigRat', (args) => {
    switch (args.length) {
      case 0: return make(0n, 1n);
      case 1: {
        const v = args[0];
        switch (kindOf(v)) {
          case 'int': case 'byte': return make(integer(v, 'BigRat'), 1n);
          case 'double':
            if (!Number.isFinite(v)) throw SwiftalkError.type(`BigRat(${sourceString(v)}): not a number a rational can hold`);
            return make(...fromDouble(v));
          case 'string': { const p = parseRational(v); if (!p) throw SwiftalkError.type(`BigRat("${v}"): not a rational — "n/d", an integer, or a decimal`); return make(p[0], p[1]); }
          case 'host':
            if (v.object instanceof BigRatValue) return v;
            if (typeof v.object.bigInt === 'bigint') return make(v.object.bigInt, 1n);
            break;
          default: break;
        }
        throw SwiftalkError.type(`cannot convert ${typeName(v)} to BigRat`);
      }
      case 2: {
        const n = integer(args[0], 'BigRat(n, d)'), d = integer(args[1], 'BigRat(n, d)');
        if (d === 0n) throw SwiftalkError.zeroDivision();
        return make(n, d);
      }
      default: throw SwiftalkError.type('BigRat(x) or BigRat(numerator, denominator)');
    }
  }).value('BigRat');
  return m;
}
