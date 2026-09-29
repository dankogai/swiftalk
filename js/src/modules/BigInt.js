// `BigInt` — arbitrary-precision integers (round 201), a module: the type
// `BigInt` behind the literal `123n` — JS's spelling, the `n` mandatory,
// whose grammar is the core's — and its arithmetic. The engine here is
// JavaScript's own BigInt (the Swift module vendors swift-bignum). Strict,
// as swiftalk's numbers are: a BigInt meets a BigInt, not an Int or a
// Double — convert first. Division truncates and `%` follows the
// dividend's sign, as Int's do.
import { SwiftalkError } from '../errors.js';
import { Module } from '../modules.js';
import { kindOf, typeName, sourceString, Byte, INT64_MAX, INT64_MIN } from '../value.js';
import { HostValue } from '../objects.js';

/// What the literal and `BigInt(s)` accept: a sign, a radix prefix, `_`, a trailing `n`.
function parseLiteral(text) {
  let s = text.replace(/_/g, '');
  if (s.endsWith('n')) s = s.slice(0, -1);
  let negative = false;
  if (s.startsWith('-')) { negative = true; s = s.slice(1); } else if (s.startsWith('+')) s = s.slice(1);
  if (!/^(0[xX][0-9a-fA-F]+|0[oO][0-7]+|0[bB][01]+|[0-9]+)$/.test(s)) return null;
  const v = BigInt(s.replace(/^0[oObB]/, (p) => p.toLowerCase()).replace(/^0X/, '0x'));
  return negative ? -v : v;
}
function parseRadix(text, radix) {
  let s = text.replace(/_/g, '');
  let negative = false;
  if (s.startsWith('-')) { negative = true; s = s.slice(1); }
  if (!s.length) return null;
  let v = 0n;
  for (const c of s.toLowerCase()) {
    const d = parseInt(c, 36);
    if (Number.isNaN(d) || d >= radix) return null;
    v = v * BigInt(radix) + BigInt(d);
  }
  return negative ? -v : v;
}
const toRadix = (n, radix) => (n < 0n ? '-' : '') + (n < 0n ? -n : n).toString(radix);
const magnitude = (n) => (n < 0n ? -n : n);
/// Swift's smart shift: any count, arithmetic to the right.
const shift = (a, b, left) => (left ? (b >= 0n ? a << b : a >> -b) : (b >= 0n ? a >> b : a << -b));

const operators = new Set(['infix:+', 'infix:-', 'infix:*', 'infix:/', 'infix:%', 'infix:**', 'infix:<',
  'infix:+&', 'infix:+|', 'infix:+^', 'infix:+<', 'infix:+>', 'prefix:-', 'prefix:+', 'prefix:+^']);

export class BigIntValue {
  constructor(n, type) { this.n = n; this.type = type; this.typeName = 'BigInt'; }
  get bigInt() { return this.n; }                    // what the BigRat module sees (round 203)
  make(v) { return new HostValue(new BigIntValue(v, this.type), this.type); }
  other(v, what) {
    if (kindOf(v) === 'host' && v.object instanceof BigIntValue) return v.object.n;
    throw SwiftalkError.type(`${what} takes a BigInt, not ${typeName(v)} — BigInt(x) converts`);
  }
  prefixed(radix) {
    const prefix = { 16: '0x', 8: '0o', 2: '0b' }[radix];
    return (this.n < 0n ? '-' : '') + prefix + magnitude(this.n).toString(radix) + 'n';
  }
  member(name, args, called) {
    const n = this.n;
    switch (`${name}${called ? '()' : ''}`) {
      case 'BigInt()': return new HostValue(this, this.type);
      case 'Int()':
        if (n > INT64_MAX || n < INT64_MIN) throw SwiftalkError.overflow(`${n}n does not fit in an Int`);
        return n;
      case 'Double()': return Number(n);
      case 'String()': {
        if (!args.length) return this.sourceString(false);
        if (args.length !== 1) throw SwiftalkError.type('BigInt.String() takes at most one format');
        const format = args[0];
        if (format === 'hex') return this.prefixed(16);
        if (format === 'oct') return this.prefixed(8);
        if (format === 'bin') return this.prefixed(2);
        if (format === 'sign') return (n < 0n ? '' : '+') + n.toString(10);
        if (typeof format === 'bigint' && format >= 2n && format <= 36n) return toRadix(n, Number(format));
        throw SwiftalkError.type(`BigInt.String() takes .hex, .oct, .bin, .sign, or a radix 2...36, not ${sourceString(format)}`);
      }
      case 'magnitude': return this.make(magnitude(n));
      case 'signum': return n < 0n ? -1n : n > 0n ? 1n : 0n;
      case 'isZero': return n === 0n;
      case 'bitWidth': return BigInt(n < 0n ? (-n - 1n).toString(2).length + 1 : n.toString(2).length + 1);   // two's complement, sign bit included
      case 'trailingZeroBitCount': { if (n === 0n) return 0n; let c = 0n, x = n; while ((x & 1n) === 0n) { x >>= 1n; c++; } return c; }
      case 'power()': {
        if (!(args.length === 1 || args.length === 2)) throw SwiftalkError.type('BigInt.power(exponent) or .power(exponent, modulus)');
        let e;
        if (typeof args[0] === 'bigint') e = args[0];
        else if (kindOf(args[0]) === 'host' && args[0].object instanceof BigIntValue) e = args[0].object.n;
        else throw SwiftalkError.type(`BigInt.power takes an Int or BigInt exponent, not ${typeName(args[0])}`);
        if (e < 0n) throw SwiftalkError.type('BigInt.power: a negative exponent has no integer answer');
        if (args.length === 2) {
          const m = this.other(args[1], 'BigInt.power(exponent, modulus)');
          if (m === 0n) throw SwiftalkError.zeroDivision();
          let result = 1n % m, base = ((n % m) + m) % m, k = e;
          while (k > 0n) { if (k & 1n) result = (result * base) % m; base = (base * base) % m; k >>= 1n; }
          return this.make(result);
        }
        return this.make(n ** e);
      }
      case 'squareRoot()': {
        if (args.length) throw SwiftalkError.type('BigInt.squareRoot() takes no arguments');
        if (n < 0n) throw SwiftalkError.type(`BigInt.squareRoot() of a negative: ${n}n`);
        if (n < 2n) return this.make(n);
        let x = BigInt(Math.floor(Math.sqrt(Number(n)))) + 1n;           // Newton from a Double guess
        for (;;) { const y = (x + n / x) >> 1n; if (y >= x) break; x = y; }
        while (x * x > n) x--;
        while ((x + 1n) * (x + 1n) <= n) x++;
        return this.make(x);
      }
      case 'gcd()': {
        if (args.length !== 1) throw SwiftalkError.type('BigInt.gcd(other) takes one BigInt');
        let a = magnitude(n), b = magnitude(this.other(args[0], 'BigInt.gcd'));
        while (b !== 0n) [a, b] = [b, a % b];
        return this.make(a);
      }
      default: return undefined;
    }
  }
  hasOperator(key) { return operators.has(key); }
  operate(key, operands) {
    if (!operators.has(key)) return undefined;
    const [fix, op] = [key.slice(0, key.indexOf(':')), key.slice(key.indexOf(':') + 1)];
    if (fix === 'prefix') return this.make(op === '-' ? -this.n : op === '+' ? this.n : ~this.n);
    if (operands.length !== 2) return undefined;
    const sides = operands.map((v) => {
      if (kindOf(v) === 'host' && v.object instanceof BigIntValue) return v.object.n;
      const k = kindOf(v);
      if (k === 'host' && Array.isArray(v.object.bigRat)) throw SwiftalkError.type(`'${op}' between BigInt and BigRat: convert first — BigRat(b), or r.BigInt()`);
      if (k === 'int' || k === 'double' || k === 'byte') throw SwiftalkError.type(`'${op}' between BigInt and ${typeName(v)}: convert first — BigInt(x), or b.Int()`);
      throw SwiftalkError.type(`'${op}' is not defined between ${typeName(operands[0])} and ${typeName(operands[1])}`);
    });
    const [a, b] = sides;
    switch (op) {
      case '+': return this.make(a + b);
      case '-': return this.make(a - b);
      case '*': return this.make(a * b);
      case '/': case '%': if (b === 0n) throw SwiftalkError.zeroDivision(); return this.make(op === '/' ? a / b : a % b);
      case '**': if (b < 0n) throw SwiftalkError.type("'**' with a negative BigInt exponent has no integer answer"); return this.make(a ** b);
      case '<': return a < b;
      case '+&': return this.make(a & b);
      case '+|': return this.make(a | b);
      case '+^': return this.make(a ^ b);
      case '+<': return this.make(shift(a, b, true));
      case '+>': return this.make(shift(a, b, false));
      default: return undefined;
    }
  }
  isEqual(other) { return other instanceof BigIntValue && other.n === this.n; }
  hashKey() { return `BigInt:${this.n}`; }
  /// `123n`: re-enters (§3d); the debug form is hex, as Int's is (round 37)
  sourceString(debug) { return debug ? (this.n < 0n ? '-0x' : '+0x') + magnitude(this.n).toString(16) + 'n' : this.n.toString(10) + 'n'; }
  /// `case 42n:` — equality; a non-BigInt subject is no match (and, binding, an error)
  patternMatch(subject, binding) {
    if (!(kindOf(subject) === 'host' && subject.object instanceof BigIntValue)) {
      if (binding) throw SwiftalkError.type(`a BigInt case needs a BigInt subject, not ${typeName(subject)}`);
      return null;
    }
    return subject.object.n === this.n ? subject : null;
  }
}

export function BigIntModule() {
  const m = new Module('BigInt');
  let typeValue = null;
  const make = (v) => new HostValue(new BigIntValue(v, typeValue), typeValue);
  typeValue = m.type('BigInt', (args) => {
    switch (args.length) {
      case 0: return make(0n);
      case 1: {
        const v = args[0];
        switch (kindOf(v)) {
          case 'int': return make(v);
          case 'byte': return make(BigInt(v.v));
          case 'double':
            if (!Number.isFinite(v) || Math.trunc(v) !== v) throw SwiftalkError.type(`BigInt(${sourceString(v)}): not an integer — round it first`);
            return make(BigInt(v));
          case 'string': { const p = parseLiteral(v); if (p === null) throw SwiftalkError.type(`BigInt("${v}"): not an integer literal`); return make(p); }
          case 'host':
            if (v.object instanceof BigIntValue) return v;
            if (Array.isArray(v.object.bigRat)) { const [n, d] = v.object.bigRat; return make(n / d); }   // truncation toward zero, as BigInt's / is (round 203)
            break;
          default: break;
        }
        throw SwiftalkError.type(`cannot convert ${typeName(v)} to BigInt`);
      }
      case 2: {
        if (typeof args[0] !== 'string' || typeof args[1] !== 'bigint' || args[1] < 2n || args[1] > 36n) throw SwiftalkError.type('BigInt(digits, radix) takes a String and a radix 2...36');
        const p = parseRadix(args[0], Number(args[1]));
        if (p === null) throw SwiftalkError.type(`BigInt("${args[0]}", ${args[1]}): not a radix-${args[1]} integer`);
        return make(p);
      }
      default: throw SwiftalkError.type('BigInt(x) or BigInt(digits, radix)');
    }
  }).value('BigInt');
  return m;
}
