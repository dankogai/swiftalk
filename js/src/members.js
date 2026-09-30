// Member dispatch — Eval.swift's method(on:), convert, stringFormat,
// staticMember, and Value.prettyString. Generators, like eval.js: a
// member may run swiftalk code (a closure argument, a user type's own
// String member), so everything here is `function*` called with `yield*`.
import { SwiftalkError } from './errors.js';
import { TypeAnnotation } from './parser.js';
import { kindOf, typeName, equals, keyOf, sourceString, graphemes, spreadsInSet, hexFloat, compareStrings,
  SArray, SDictionary, SSet, Byte, SData, SDate, SRange, TupleValue, INT64_MAX } from './value.js';
import { FunctionObject, EnumType, EnumCaseValue, StructType, StructValue, SequenceObject } from './objects.js';
import { Builtins, isResult, DoubleMath, IntStatics, stringFromCodePoint, dataRandom, intRandom } from './builtins.js';
import { ann, inferLock, tryInfer, knownElementLock, stampedArray, typeValue, typeValueForParameter, callBuiltin } from './types.js';
import { JSONFormat, PlistXML, PlistBinary, StringEscapes } from './formats.js';
import { apply, boundMethod, iteratorOf, collect, lazyBase, restamp, reshape, holds, requireFinite, rangeCount,
  compare, hasUserOperator, containsSubstring, constructEnumCase, caseAccessor, computedProperty, readComputed,
  lookupExtension, mergeDictionaries, setElements, resolveStatic, scheduler } from './eval.js';

// ---- the law's hooks ----
/// `.String(.canonical)` (round 153): the builtin source form, no type's String member asked.
export function asksCanonical(name, args) {
  return name === 'String' && args.some((a) => a.label === null && a.value === 'canonical');
}
/// A user type's own conversion member (round 151): `let Double = { ... }` in a struct or enum body.
export function userConversion(value, tn) {
  if (value instanceof StructValue) return value.type.methods.get(tn) ?? null;
  if (value instanceof EnumCaseValue) return value.type.methods.get(tn) ?? null;
  return null;
}
/// Rejects labeled arguments where a member takes none, yielding the bare values.
export function plainValues(args, member) {
  const label = args.map((a) => a.label).find((l) => l !== null);
  if (label !== undefined) throw SwiftalkError.type(`${member} takes no argument label '${label}'`);
  return args.map((a) => a.value);
}

// ---- pretty printing (round 117) ----
/// `.pretty`'s callback (round 151): a type declaring `let String = { }` owns its
/// pretty text at every depth — precomputed here, since calling it runs swiftalk.
function* userPrettyMap(value) {
  const owned = new Map();
  const walk = function* (v) {
    const m = userConversion(v, 'String');
    if (m) {
      const [bound] = boundMethod(m, v);
      const text = yield* apply(bound, [{ label: null, value: 'pretty' }]);
      if (typeof text !== 'string') throw SwiftalkError.type(`${typeName(v)}.String(.pretty) must return a String`);
      owned.set(v, text);
      return;
    }
    switch (kindOf(v)) {
      case 'array': for (const x of v.items) yield* walk(x); break;
      case 'set': for (const x of v.values()) yield* walk(x); break;
      case 'dictionary': for (const [k, x] of v.entries()) { yield* walk(k); yield* walk(x); } break;
      case 'tuple': for (const x of v.values) yield* walk(x); break;
      case 'structValue': for (const x of v.values.values()) yield* walk(x); break;
      case 'enumCase': for (const x of v.associated) yield* walk(x); break;
      default: break;
    }
  };
  yield* walk(value);
  return owned;
}
export function prettyString(value, owned = null, depth = 0) {
  const custom = (v) => (owned && owned.has(v) ? owned.get(v) : null);
  const own = custom(value);
  if (own !== null) return own;
  const pad = '  '.repeat(depth + 1), close = '  '.repeat(depth);
  const inner = (v) => prettyString(v, owned, depth + 1);
  const bySource = (a, b) => (a.key < b.key ? -1 : a.key > b.key ? 1 : 0);
  switch (kindOf(value)) {
    case 'array': {
      if (value.items.length === 0) return '[]';
      return '[\n' + value.items.map((x) => pad + inner(x)).join(',\n') + '\n' + close + ']';
    }
    case 'set': {
      const xs = value.values();
      if (xs.length === 0) return 'Set()';
      const body = xs.map((x) => ({ key: custom(x) ?? sourceString(x), text: inner(x) })).sort(bySource).map((e) => pad + e.text).join(',\n');
      const [open, shut] = xs.length === 1 && spreadsInSet(xs[0]) ? ['Set([\n', '])'] : ['Set(\n', ')'];
      return open + body + '\n' + close + shut;
    }
    case 'dictionary': {
      if (value.size === 0) return '[:]';
      const body = value.entries().map(([k, v]) => ({ key: custom(k) ?? sourceString(k), value: inner(v) })).sort(bySource)
        .map((e) => `${pad}${e.key}: ${e.value}`).join(',\n');
      return '[\n' + body + '\n' + close + ']';
    }
    case 'tuple': {
      if (value.count === 0) return '()';
      const lonely = value.count === 1 && value.labels[0] === null;
      const body = value.values.map((v, i) => pad + (value.labels[i] !== null ? `${value.labels[i]}: ` : '') + inner(v)).join(',\n');
      return '(\n' + body + (lonely ? ',\n' : '\n') + close + ')';
    }
    case 'structValue': {
      const sv = value;
      if (sv.type.propertyOrder.length === 0) return sourceString(value);
      const body = sv.type.propertyOrder.map((p) => `${pad}${p}: ${inner(sv.values.get(p) ?? null)}`).join(',\n');
      return sv.type.name + '(\n' + body + '\n' + close + ')';
    }
    case 'enumCase': {
      const ev = value;
      if (ev.associated.length === 0) return sourceString(value);
      const params = ev.type.cases.get(ev.caseName) ?? [];
      const body = ev.associated.map((v, i) => { const t = inner(v); const label = params[i]?.label ?? null; return pad + (label !== null ? `${label}: ${t}` : t); }).join(',\n');
      return `${ev.type.name}.${ev.caseName}(\n` + body + '\n' + close + ')';
    }
    default: return sourceString(value);
  }
}
export function* prettyText(value) { return prettyString(value, yield* userPrettyMap(value)); }

// ---- conversion: x.T(...) is T(x, ...) (round 47) ----
export function* convert(tn, subject, extra) {
  if (subject !== undefined && !asksCanonical(tn, extra)) {
    const m = userConversion(subject, tn);
    if (m) { const [bound] = boundMethod(m, subject); return yield* apply(bound, extra); }
  }
  // ...and a module's value (round 201): `Int(b)` is `b.Int()`, the host's member, labels dropped
  if (subject !== undefined && kindOf(subject) === 'host') {
    const v = yield* callBuiltin((xs) => subject.object.member(tn, xs, true), extra.map((a) => a.value));
    if (v !== undefined) return v;
  }
  const object = Builtins.types.get(tn) ?? Builtins.protocols.get(tn);
  if (extra.length === 0) return yield* callBuiltin(object.builtin, subject === undefined ? [] : [subject]);
  switch (tn) {
    case 'String':
      if (subject === undefined) throw SwiftalkError.type('String formats need a value to format');
      return yield* stringFormat(subject, extra);
    case 'SION': {
      if (subject !== undefined || extra.length !== 1 || extra[0].label === null) throw SwiftalkError.type('SION(json: text) or SION(propertyList: text or data)');
      const { label, value } = extra[0];
      if (label === 'json' && typeof value === 'string') return JSONFormat.parse(value);
      if (label === 'propertyList' && typeof value === 'string') return PlistXML.parse(value);
      if (label === 'propertyList' && value instanceof SData) return PlistBinary.parse(value.bytes);
      throw SwiftalkError.type(`SION(${label}:) takes a String${label === 'propertyList' ? ' or a Data' : ''}, not a ${typeName(value)}`);
    }
    case 'Data': {
      if (subject === undefined || extra.length !== 1 || extra[0].label !== null || typeof extra[0].value !== 'string') throw SwiftalkError.type('.Data() takes one format: .utf8 or .propertyList');
      switch (extra[0].value) {
        case 'utf8':
          if (typeof subject !== 'string') throw SwiftalkError.type('.Data(.utf8) encodes a String');
          return new SData(new TextEncoder().encode(subject));
        case 'propertyList': return PlistBinary.emit(subject);
        default: throw SwiftalkError.type(`unknown .Data() format .${extra[0].value}`);
      }
    }
    case 'Int': {
      if (subject !== undefined || extra.length !== 1 || extra[0].label !== 'bits' || kindOf(extra[0].value) !== 'array') throw SwiftalkError.type('Int(bits: [Bool]) — the bits, bit 0 first');
      const bits = extra[0].value.items;
      if (bits.length > 64) throw SwiftalkError.overflow(`Int(bits:) takes at most 64 bits, got ${bits.length}`);
      let word = 0n;
      bits.forEach((bit, i) => {
        if (typeof bit !== 'boolean') throw SwiftalkError.type(`Int(bits:) takes Bools, not a ${typeName(bit)} at ${i}`);
        if (bit) word |= 1n << BigInt(i);
      });
      return BigInt.asIntN(64, word);
    }
    case 'Set':
      if (subject === undefined || !extra.every((a) => a.label === null)) throw SwiftalkError.type('Set(a, b, ...) takes unlabeled elements');
      return Builtins.stampedSet([subject, ...extra.map((a) => a.value)], null);
    case 'Sequence':
      if (subject === undefined || extra.length !== 1 || extra[0].label !== null) throw SwiftalkError.type('Sequence(initialState) { next } — an Array state and a Function');
      return yield* callBuiltin(object.builtin, [subject, extra[0].value]);
    default: throw SwiftalkError.type(`${tn}() takes no format arguments`);
  }
}

const radixText = (i, radix) => (i < 0n ? -i : i).toString(radix);
/// String's format vocabulary (rounds 20–21, 42, 117, 125, 153).
function* stringFormat(subject, formatsIn) {
  let formats = formatsIn.slice();
  let pretty = false, sign = false, canonical = false;
  const take = (word) => { const i = formats.findIndex((a) => a.label === null && a.value === word); if (i >= 0) { formats.splice(i, 1); return true; } return false; };
  pretty = take('pretty'); sign = take('sign'); canonical = take('canonical');
  if (formats.length > 1) throw SwiftalkError.type('.String() takes at most one format argument, plus .pretty or .sign');
  if (pretty && sign) throw SwiftalkError.type('.pretty lays out text and .sign marks a number — not both');
  if (canonical) {
    if (formats.length || sign) throw SwiftalkError.type('.canonical is the source form itself — alone or with .pretty, not with another format');
    return pretty ? prettyString(subject) : sourceString(subject);
  }
  const plus = (negative) => (negative ? '-' : sign ? '+' : '');
  if (formats.length === 0) {
    if (pretty) return yield* prettyText(subject);
    switch (kindOf(subject)) {
      case 'int': return plus(subject < 0n) + radixText(subject, 10);
      case 'byte': return plus(false) + String(subject.v);
      case 'double': return Number.isNaN(subject) ? 'nan' : plus(subject < 0 || Object.is(subject, -0)) + sourceString(Math.abs(subject));
      default: throw SwiftalkError.type(`.sign is a number's modifier, not a ${typeName(subject)}'s`);
    }
  }
  const { label, value: format } = formats[0];
  if (pretty && !['quoted', 'sion', 'json', 'propertyList'].includes(format)) throw SwiftalkError.type(`.pretty lays out .sion (the default), .json, or .propertyList — not ${sourceString(format)}`);
  if (sign && label !== 'radix' && !['hex', 'oct', 'bin'].includes(format)) throw SwiftalkError.type(`.sign goes with a number's format — .hex, .oct, .bin, radix:, or none — not ${sourceString(format)}`);
  if (label === 'radix') {
    if (typeof format !== 'bigint' || format < 2n || format > 36n) throw SwiftalkError.type('.String(radix:) takes an Int in 2...36');
    if (typeof subject !== 'bigint') throw SwiftalkError.type(".String(radix:) is an Int's format");
    return plus(subject < 0n) + radixText(subject, Number(format));
  }
  if (label !== null) throw SwiftalkError.type(`unknown .String() format label '${label}'`);
  switch (format) {
    case 'quoted': case 'sion': return pretty ? yield* prettyText(subject) : sourceString(subject);
    case 'json': return JSONFormat.emit(subject, pretty);
    case 'propertyList': return PlistXML.emit(subject);
    case 'utf8': {
      if (!(subject instanceof SData)) throw SwiftalkError.type('.String(.utf8) decodes Data');
      try { return new TextDecoder('utf-8', { fatal: true }).decode(subject.bytes); } catch (e) { return null; }
    }
    case 'hex':
      if (typeof subject === 'bigint') return plus(subject < 0n) + '0x' + radixText(subject, 16);
      if (typeof subject === 'number') return hexFloat(subject, sign);
      throw SwiftalkError.type(".String(.hex) is a number's format");
    case 'oct': case 'bin': {
      if (typeof subject !== 'bigint') throw SwiftalkError.type(".String(.oct)/.String(.bin) are an Int's formats");
      const [prefix, radix] = format === 'oct' ? ['0o', 8] : ['0b', 2];
      return plus(subject < 0n) + prefix + radixText(subject, radix);
    }
    default: throw SwiftalkError.type(`unknown .String() format ${sourceString(format)}`);
  }
}

// ---- statics ----
function parameterMember(f, name, env) {
  if (f.role.k !== 'type') return null;
  const base = f.role.name;
  let wanted;
  if ((base === 'Array' || base === 'Set') && name === 'Element') wanted = 0;
  else if (base === 'Dictionary' && name === 'Key') wanted = 0;
  else if (base === 'Dictionary' && name === 'Value') wanted = 1;
  else return null;
  if (!f.annotation || f.annotation.parameters.length <= wanted) {
    throw SwiftalkError.type(`${base} is the erased type and has no ${name} — a parameterized one does: ${base === 'Dictionary' ? '[Int: String]' : base === 'Set' ? 'Set([1]).Type' : '[Int]'}.${name}`);
  }
  return typeValueForParameter(f.annotation.parameters[wanted], env);
}
function* staticMember(f, name, args, called, env) {
  const p = parameterMember(f, name, env);
  if (p !== null) {
    if (!called || kindOf(p) !== 'function') return p;
    return yield* apply(p, args);
  }
  let stored, getter = null, tn;
  switch (f.role.k) {
    case 'structType': case 'enumType': {
      const t = f.role.type;
      tn = t.name;
      stored = yield* resolveStatic(name, t);
      getter = t.staticGetters.get(name) ?? null;
      break;
    }
    case 'type': case 'protocol': {
      const n = f.role.name;
      tn = n;
      const v = env.tryLookup(`@ext:${n}:static:${name}`);
      if (v !== undefined) stored = v;
      else if (scheduler.modules && scheduler.modules.nativeStatics.get(n)?.has(name)) stored = scheduler.modules.nativeStatics.get(n).get(name);
      else { const g = env.tryLookup(`@ext:${n}:static:get:${name}`); if (g !== undefined && kindOf(g) === 'function') getter = g; }
      break;
    }
    default: return undefined;
  }
  if (getter) {
    if (called) throw SwiftalkError.type(`${tn}.${name} is a static var — read it, do not call it`);
    return yield* apply(getter, []);
  }
  if (stored === undefined) return undefined;
  if (!called) return stored;
  if (kindOf(stored) !== 'function') throw SwiftalkError.type(`cannot call ${tn}.${name}, a ${typeName(stored)}`);
  return yield* apply(stored, args);
}

// ---- sorting with a suspending comparator: a merge sort over yield* ----
function* sortedBy(elements, less) {
  if (elements.length <= 1) return elements.slice();
  const mid = elements.length >> 1;
  const a = yield* sortedBy(elements.slice(0, mid), less);
  const b = yield* sortedBy(elements.slice(mid), less);
  const out = [];
  let i = 0, j = 0;
  while (i < a.length && j < b.length) {
    if (yield* less(b[j], a[i])) out.push(b[j++]); else out.push(a[i++]);   // stable
  }
  while (i < a.length) out.push(a[i++]);
  while (j < b.length) out.push(b[j++]);
  return out;
}
const lessBuiltin = function* (a, b) { const r = yield* compare('<', a, b); return typeof r === 'boolean' ? r : false; };
const lessBy = (fn, who) => function* (a, b) {
  const r = yield* apply(fn, [{ label: null, value: a }, { label: null, value: b }]);
  if (typeof r !== 'boolean') throw SwiftalkError.type(`the .${who} Function must return a Bool`);
  return r;
};

const swiftLabels = (name) => {
  switch (name) {
    case 'sorted': case 'min': case 'max': case 'shifted': return ['by'];
    case 'contains': return ['where'];
    case 'joined': return ['separator'];
    case 'firstMatch': case 'wholeMatch': case 'matches': case 'isSubset': case 'isSuperset': case 'isStrictSubset': case 'isStrictSuperset': return ['of'];
    case 'replacing': case 'isDisjoint': case 'normalized': case 'isNormalized': return ['with'];
    case 'split': return ['separator', 'whereSeparator'];
    case 'prefix': case 'dropFirst': return ['while'];
    case 'merging': return ['uniquingKeysWith'];
    default: return [];
  }
};
const isWhite = (g) => /^[\s\p{White_Space}]+$/u.test(g);   // a grapheme, so "\r\n" is one
const stringType = ann('String');

// ---- the member switch ----
/// `.Bool()`, `.Int()`, `.Double()`, `.Byte()` are a String's parses and nothing
/// else's (rounds 205–207): the constructors convert; a type's own member of
/// the name (round 151) or an extension's stands.
function parseOnly(tn, receiver, called, env) {
  if (!called || !(tn === 'Bool' || tn === 'Int' || tn === 'Double' || tn === 'Byte') || typeof receiver === 'string') return;
  if (userConversion(receiver, tn) || lookupExtension(env, typeName(receiver), tn)) return;
  const hint = tn === 'Bool' ? 'a Bool is a Bool already, and an Int is not one (i != 0)' : `${tn}(x) converts`;
  throw SwiftalkError.unknownMember(`${typeName(receiver)}.${tn}() — .${tn}() is a String's parse; ${hint}`);
}

export function* method(receiver, name, labeledArgs, called, env) {
  const rk = kindOf(receiver);
  const fnLike = rk === 'function' ? receiver : null;
  parseOnly(name, receiver, called, env);
  // A module's extension of a core type (round 186) answers first
  if (scheduler.modules) {
    const ext = scheduler.modules.nativeExtensions.get(typeName(receiver))?.get(name);
    if (ext) {
      const r = ext(receiver, labeledArgs.map((a) => a.value), called);
      const answer = (r && typeof r.next === 'function' && typeof r[Symbol.iterator] === 'function') ? yield* r : r;
      if (answer !== undefined) return answer;                 // undefined declines; null is nil
    }
  }
  if (rk === 'host') {
    const answer = yield* callBuiltin((xs) => receiver.object.member(name, xs, called), labeledArgs.map((a) => a.value));
    if (answer !== undefined) return answer;
  }
  if (name === 'conforms' && called) {
    if (!fnLike) throw SwiftalkError.type("'.conforms(to:)' is a question asked of a type");
    if (labeledArgs.length !== 1 || !(labeledArgs[0].label === null || labeledArgs[0].label === 'to')) throw SwiftalkError.type('.conforms(to:) takes exactly one argument');
    const p = labeledArgs[0].value;
    if (kindOf(p) !== 'function' || p.role.k !== 'protocol') throw SwiftalkError.type('the argument to .conforms(to:) must be a protocol');
    const protoName = p.role.name;
    switch (fnLike.role.k) {
      case 'type': case 'protocol': return Builtins.conformance.get(protoName)?.has(fnLike.role.name) ?? false;
      case 'structType': case 'enumType':
        return protoName === 'Equatable' || protoName === 'Hashable' || (protoName === 'Comparable' && fnLike.role.type.operators.has('infix:<'));
      default: throw SwiftalkError.type("'.conforms(to:)' is a question asked of a type");
    }
  }
  if (fnLike && fnLike.role.k === 'type') {
    const tn = fnLike.role.name;
    if (tn === 'Double') { const v = DoubleMath.member(name, labeledArgs, called); if (v !== undefined) return v; }
    if (tn === 'String' && name === 'fromCodePoint') {
      const label = labeledArgs.map((a) => a.label).find((l) => l !== null);
      if (label !== undefined) throw SwiftalkError.type(`String.fromCodePoint takes no argument label '${label}'`);
      if (!called) return new FunctionObject([], [], Builtins.emptyEnvironment, (xs) => stringFromCodePoint(xs));
      return stringFromCodePoint(labeledArgs.map((a) => a.value));
    }
    const table = IntStatics.get(tn);
    if (table && table.has(name)) {
      if (called) throw SwiftalkError.type(`${tn}.${name} is a constant, not a function`);
      return table.get(name);
    }
    if (tn === 'Data' && name === 'random') {
      if (!called) return new FunctionObject([], [], Builtins.emptyEnvironment, (xs) => dataRandom(xs));
      const label = labeledArgs.map((a) => a.label).find((l) => l !== null);
      if (label !== undefined) throw SwiftalkError.type(`Data.random takes no argument label '${label}'`);
      return dataRandom(labeledArgs.map((a) => a.value));
    }
    if (tn === 'Int' && name === 'random') {
      if (called) return intRandom(labeledArgs);
      return new FunctionObject([], [], Builtins.emptyEnvironment, (xs) => intRandom(xs.map((v) => ({ label: null, value: v }))));
    }
  }
  if (fnLike && fnLike.role.k === 'enumType' && fnLike.role.type.cases.has(name)) return constructEnumCase(fnLike.role.type, name, labeledArgs, called);
  if (fnLike) { const v = yield* staticMember(fnLike, name, labeledArgs, called, env); if (v !== undefined) return v; }
  if (receiver instanceof EnumCaseValue && !called && receiver.type.cases.has(name)) return caseAccessor(receiver, name, receiver);
  if (receiver instanceof TupleValue) {
    const index = /^\d+$/.test(name) ? Number(name) : receiver.indexOfLabel(name);
    if (index !== null) {
      if (!(index >= 0 && index < receiver.count)) throw SwiftalkError.type(`tuple index ${index} out of range (count ${receiver.count})`);
      const value = receiver.values[index];
      if (!called) return value;
      if (kindOf(value) !== 'function') throw SwiftalkError.type(`cannot call Tuple.${name}, a ${typeName(value)}`);
      return yield* apply(value, labeledArgs);
    }
  }
  const c = computedProperty(receiver, name);
  if (c) {
    const value = yield* readComputed(c, receiver);
    if (!called) return value;
    if (kindOf(value) !== 'function') throw SwiftalkError.type(`cannot call ${typeName(receiver)}.${name}, a ${typeName(value)}`);
    return yield* apply(value, labeledArgs);
  }
  if (receiver instanceof StructValue && receiver.values.has(name)) {
    const value = receiver.values.get(name);
    if (!called) return value;
    if (kindOf(value) !== 'function') throw SwiftalkError.type(`cannot call ${receiver.type.name}.${name}, a ${typeName(value)}`);
    return yield* apply(value, labeledArgs);
  }
  if ((receiver instanceof StructValue || receiver instanceof EnumCaseValue) && receiver.type.methods.has(name) && !asksCanonical(name, labeledArgs)) {
    const [bound] = boundMethod(receiver.type.methods.get(name), receiver, true);
    return called ? yield* apply(bound, labeledArgs) : bound;
  }
  {
    const m = lookupExtension(env, typeName(receiver), name);
    if (m) { const [bound] = boundMethod(m, receiver, true); return called ? yield* apply(bound, labeledArgs) : bound; }
    const g = lookupExtension(env, typeName(receiver), `get:${name}`);
    if (g) {
      const [bound] = boundMethod(g, receiver);
      const value = yield* apply(bound, []);
      if (!called) return value;
      if (kindOf(value) !== 'function') throw SwiftalkError.type(`cannot call ${typeName(receiver)}.${name}, a ${typeName(value)}`);
      return yield* apply(value, labeledArgs);
    }
  }
  if (called && (Builtins.types.has(name) || Builtins.protocols.has(name))) return yield* convert(name, receiver, labeledArgs);
  if (called && !Builtins.types.has(name)) {
    const f = env.tryLookup(name);
    if (f !== undefined && kindOf(f) === 'function' && f.role.k === 'type') {
      const tn = f.role.name;
      if (Builtins.types.has(tn) || Builtins.protocols.has(tn)) { parseOnly(tn, receiver, true, env); return yield* convert(tn, receiver, labeledArgs); }   // the alias path (round 111)
      if (f.builtin) return yield* callBuiltin(f.builtin, [receiver, ...labeledArgs.map((a) => a.value)]);
    }
  }
  const dropped = called ? swiftLabels(name) : [];
  const args = plainValues(dropped.length ? labeledArgs.map((a) => (a.label !== null && dropped.includes(a.label) ? { label: null, value: a.value } : a)) : labeledArgs, `.${name}`);
  const unknown = () => SwiftalkError.unknownMember(`${typeName(receiver)}.${name}${called ? '()' : ''}`);
  const isFn = (v) => kindOf(v) === 'function';
  const key = `${name}${called ? '()' : ''}`;
  switch (key) {
    case 'Type': {
      if (receiver instanceof EnumCaseValue) return receiver.type.constructor_;
      if (receiver instanceof StructValue) return receiver.type.constructor_;
      if (rk === 'host') return receiver.type;
      if (rk === 'array' || rk === 'dictionary' || rk === 'set') {
        const inferred = tryInfer(receiver, '', true);
        if (inferred) { const t = typeValue(inferred); if (t) return t; }
      }
      return Builtins.types.get(typeName(receiver)) ?? Builtins.protocols.get(typeName(receiver));
    }
    case 'name': {
      if (!fnLike) throw SwiftalkError.unknownMember(`${typeName(receiver)}.name`);
      switch (fnLike.role.k) {
        case 'type': case 'protocol': return fnLike.role.name;
        case 'enumType': case 'structType': return fnLike.role.type.name;
        case 'operator': return `(${fnLike.role.op})`;
        default: return null;
      }
    }
    case 'count':
      switch (rk) {
        case 'array': return BigInt(receiver.items.length);
        case 'string': return BigInt(graphemes(receiver).length);
        case 'dictionary': case 'set': return BigInt(receiver.size);
        case 'range':
          if (receiver.to === null) throw SwiftalkError.type('an unbounded Range is infinite — .prefix(n) or .prefix { } it deliberately');
          return rangeCount(receiver.from, receiver.to, receiver.closed);
        case 'data': return BigInt(receiver.bytes.length);
        case 'tuple': return BigInt(receiver.count);
        case 'sequence': throw SwiftalkError.type('a Sequence may be infinite — take .prefix(n) or .Array() it deliberately');
        default: throw SwiftalkError.unknownMember(`${typeName(receiver)}.count`);
      }
    case 'enumerated()': {
      if (args.length) throw SwiftalkError.type('.enumerated() takes no arguments');
      const base = lazyBase(receiver);
      if (base) return new SequenceObject({ kind: 'enumerated', base });
      if (rk === 'dictionary') return receiver;
      const out = [];
      const it = yield* iteratorOf(receiver);
      for (;;) { const e = yield* it.next(); if (e === undefined) break; out.push(new TupleValue([BigInt(out.length), e], ['key', 'value'])); }
      return new SArray(out, ann('Array', false, [ann('Tuple')]));
    }
    case 'prefix()': {
      if (args.length === 1 && isFn(args[0])) {
        const base = lazyBase(receiver);
        if (base) return new SequenceObject({ kind: 'takenWhile', base, fn: args[0] });
        const kept = [];
        const it = yield* iteratorOf(receiver);
        for (;;) { const e = yield* it.next(); if (e === undefined || !(yield* holds(args[0], e, 'prefix'))) break; kept.push(e); }
        return restamp(reshape(kept, receiver), receiver);
      }
      if (args.length !== 1 || typeof args[0] !== 'bigint' || args[0] < 0n) throw SwiftalkError.type('.prefix takes a non-negative Int, or a Function x -> Bool');
      const out = [];
      const it = yield* iteratorOf(receiver);
      while (BigInt(out.length) < args[0]) { const e = yield* it.next(); if (e === undefined) break; out.push(e); }
      return restamp(reshape(out, receiver), receiver);
    }
    case 'suffix()': case 'dropFirst()': case 'dropLast()': {
      if (name === 'dropFirst' && args.length === 1 && isFn(args[0])) {
        const base = lazyBase(receiver);
        if (base) return new SequenceObject({ kind: 'droppedWhile', base, fn: args[0] });
        const kept = [];
        let dropping = true;
        const it = yield* iteratorOf(receiver);
        for (;;) {
          const e = yield* it.next(); if (e === undefined) break;
          if (dropping) { if (yield* holds(args[0], e, 'dropFirst')) continue; dropping = false; }
          kept.push(e);
        }
        return restamp(reshape(kept, receiver), receiver);
      }
      let n;
      if (args.length === 0 && name !== 'suffix') n = 1n;
      else if (args.length === 1) {
        if (typeof args[0] !== 'bigint' || args[0] < 0n) throw SwiftalkError.type(`.${name}(n) takes one non-negative Int`);
        n = args[0];
      } else {
        throw SwiftalkError.type(name === 'suffix' ? '.suffix(n) takes one non-negative Int'
          : name === 'dropFirst' ? '.dropFirst takes a non-negative Int (default 1), or a Function x -> Bool' : '.dropLast(n) takes one non-negative Int (default 1)');
      }
      if (name === 'dropFirst') { const base = lazyBase(receiver); if (base) return new SequenceObject({ kind: 'dropped', base, n: Number(n > 1n << 40n ? 1n << 40n : n) }); }
      requireFinite(receiver, name);
      const all = yield* collect(receiver);
      const count = Math.min(Number(n), all.length);
      const kept = name === 'suffix' ? all.slice(all.length - count) : name === 'dropFirst' ? all.slice(count) : all.slice(0, all.length - count);
      return restamp(reshape(kept, receiver), receiver);
    }
    case 'catch()': {
      if (!isResult(receiver)) throw SwiftalkError.type(".catch is a Result's — for nil, `??` is the form");
      if (args.length !== 1 || !isFn(args[0])) throw SwiftalkError.type('.catch takes a single Function: r.catch { err in ... }');
      return receiver.caseName === 'success' ? receiver.associated[0] : yield* apply(args[0], [{ label: null, value: receiver.associated[0] }]);
    }
    case 'then()': {
      if (!isResult(receiver)) throw SwiftalkError.type(".then is a Result's");
      if (args.length !== 1 || !isFn(args[0])) throw SwiftalkError.type('.then takes a single Function: r.then { v in ... }');
      if (receiver.caseName !== 'success') return receiver;
      const out = yield* apply(args[0], [{ label: null, value: receiver.associated[0] }]);
      if (isResult(out)) return out;
      return constructEnumCase(Builtins.resultType, 'success', [{ label: null, value: out }], true);
    }
    case 'description': return typeof receiver === 'string' ? receiver : sourceString(receiver);
    case 'debugDescription': return sourceString(receiver, true);
    case 'map()': {
      if (args.length !== 1 || !isFn(args[0])) throw SwiftalkError.type('.map takes a single Function');
      const base = lazyBase(receiver);
      if (base) return new SequenceObject({ kind: 'mapped', base, fn: args[0] });
      const out = [];
      const it = yield* iteratorOf(receiver);
      for (;;) { const e = yield* it.next(); if (e === undefined) break; out.push(yield* apply(args[0], [{ label: null, value: e }])); }
      const inferred = tryInfer(new SArray(out), 'map', false);
      return inferred && inferred.parameters.length ? new SArray(out, inferred) : new SArray(out);
    }
    case 'forEach()': {
      if (args.length !== 1 || !isFn(args[0])) throw SwiftalkError.type('.forEach takes a single Function');
      const it = yield* iteratorOf(receiver);
      for (;;) { const e = yield* it.next(); if (e === undefined) break; yield* apply(args[0], [{ label: null, value: e }]); }
      return null;
    }
    case 'filter()': {
      if (args.length !== 1 || !isFn(args[0])) throw SwiftalkError.type('.filter takes a single Function');
      const base = lazyBase(receiver);
      if (base) return new SequenceObject({ kind: 'filtered', base, fn: args[0] });
      const kept = [];
      const it = yield* iteratorOf(receiver);
      for (;;) {
        const e = yield* it.next(); if (e === undefined) break;
        const keep = yield* apply(args[0], [{ label: null, value: e }]);
        if (typeof keep !== 'boolean') throw SwiftalkError.type('the .filter Function must return a Bool');
        if (keep) kept.push(e);
      }
      switch (rk) {
        case 'data': case 'set': case 'string': case 'dictionary': return restamp(reshape(kept, receiver), receiver);
        default: return restamp(new SArray(kept), receiver);
      }
    }
    case 'reduce()': {
      if (args.length !== 2 || !isFn(args[1])) throw SwiftalkError.type('.reduce takes an initial value and a Function');
      requireFinite(receiver, 'reduce');
      let acc = args[0];
      const it = yield* iteratorOf(receiver);
      for (;;) { const e = yield* it.next(); if (e === undefined) break; acc = yield* apply(args[1], [{ label: null, value: acc }, { label: null, value: e }]); }
      return acc;
    }
    case 'first': { const e = yield* (yield* iteratorOf(receiver)).next(); return e === undefined ? null : e; }
    case 'min()': case 'max()': {
      const elements = yield* collect(receiver);
      let less;
      if (args.length === 0) {
        const odd = elements.find((e) => !Builtins.conformance.get('Comparable').has(typeName(e)) && !hasUserOperator(e, 'infix:<'));
        if (odd !== undefined) throw SwiftalkError.type(`.${name}() needs Comparable elements — a ${typeName(odd)} is not; give it a Function (a, b) -> Bool`);
        less = lessBuiltin;
      } else if (args.length === 1 && isFn(args[0])) less = lessBy(args[0], name);
      else throw SwiftalkError.type(`.${name} takes no argument, or one Function (a, b) -> Bool`);
      if (!elements.length) return null;
      let best = elements[0];
      for (const candidate of elements.slice(1)) {
        const l = yield* less(candidate, best);
        if (name === 'min' ? l : !l) best = candidate;
      }
      return best;
    }
    case 'sorted()': {
      const elements = yield* collect(receiver);
      if (args.length === 0) return stampedArray(yield* sortedBy(elements, lessBuiltin), receiver);
      if (args.length === 1 && isFn(args[0])) return stampedArray(yield* sortedBy(elements, lessBy(args[0], 'sorted')), receiver);
      throw SwiftalkError.type('.sorted takes no argument, or one Function (a, b) -> Bool');
    }
    case 'contains()': {
      if (args.length !== 1) throw SwiftalkError.type('.contains takes one argument: a value, or a Function x -> Bool');
      if (isFn(args[0])) {
        const it = yield* iteratorOf(receiver);
        for (;;) {
          const e = yield* it.next(); if (e === undefined) return false;
          const hit = yield* apply(args[0], [{ label: null, value: e }]);
          if (typeof hit !== 'boolean') throw SwiftalkError.type('the .contains Function must return a Bool');
          if (hit) return true;
        }
      }
      if (rk === 'string') {
        if (typeof args[0] !== 'string') throw SwiftalkError.type(`String.contains looks for a String or a Regex, not a ${typeName(args[0])}`);
        return containsSubstring(receiver, args[0]);
      }
      const it = yield* iteratorOf(receiver);
      for (;;) { const e = yield* it.next(); if (e === undefined) return false; if (equals(e, args[0])) return true; }
    }
    case 'reversed()':
      if (args.length) throw SwiftalkError.type('.reversed() takes no arguments');
      return stampedArray((yield* collect(receiver)).reverse(), receiver);
    case 'joined()': {
      if (args.length > 1) throw SwiftalkError.type('.joined takes at most one argument: the separator');
      const elements = yield* collect(receiver);
      const separator = args.length ? args[0] : undefined;
      const elementLock = knownElementLock(receiver);
      const probe = separator !== undefined ? separator : elements.length ? elements[0] : undefined;
      let stringMode;
      if (probe === undefined) stringMode = elementLock?.name !== 'Array';
      else if (typeof probe === 'string') stringMode = true;
      else if (kindOf(probe) === 'array') stringMode = false;
      else throw SwiftalkError.type(`.joined joins Strings or Arrays — not ${typeName(probe)}`);
      if (stringMode) {
        let sep = '';
        if (separator !== undefined) { if (typeof separator !== 'string') throw SwiftalkError.type(`.joined of Strings takes a String separator, not a ${typeName(separator)}`); sep = separator; }
        return elements.map((e) => { if (typeof e !== 'string') throw SwiftalkError.type(`.joined of Strings met a ${typeName(e)} — map it to a String first`); return e; }).join(sep);
      }
      let sep = [];
      if (separator !== undefined) { if (kindOf(separator) !== 'array') throw SwiftalkError.type(`.joined of Arrays takes an Array separator, not a ${typeName(separator)}`); sep = separator.items; }
      const out = [];
      elements.forEach((e, i) => { if (kindOf(e) !== 'array') throw SwiftalkError.type(`.joined of Arrays met a ${typeName(e)}`); if (i > 0) out.push(...sep); out.push(...e.items); });
      const inferred = tryInfer(new SArray(out), 'joined', false);
      if (inferred && inferred.parameters.length) return new SArray(out, inferred);
      if (elementLock && elementLock.name === 'Array' && elementLock.parameters.length) return new SArray(out, ann('Array', false, [elementLock.parameters[0]]));
      return new SArray(out);
    }
    case 'replacing()': {
      if (rk !== 'string') throw SwiftalkError.unknownMember(`${typeName(receiver)}.replacing()`);
      const usage = '.replacing takes what to find (a Regex or a String) and the replacement (a String, or a Function of the match)';
      if (args.length !== 2) throw SwiftalkError.type(usage);
      if (typeof args[0] !== 'string' || typeof args[1] !== 'string') throw SwiftalkError.type(usage);
      if (args[0] === '') return args[1] + graphemes(receiver).join(args[1]) + args[1];
      return receiver.split(args[0]).join(args[1]);   // FIXME: code-unit matching, not Character-wise canonical equivalence
    }
    case 'split()': {
      if (args.length !== 1) throw SwiftalkError.type('.split takes one separator: a value, a Function, or (on a String) a Regex');
      const strings = ann('Array', false, [stringType]);
      if (rk === 'string') {
        if (typeof args[0] === 'string') return new SArray(receiver.split(args[0]).filter((p) => p !== ''), strings);
        if (!isFn(args[0])) throw SwiftalkError.type('String.split takes a String, a Function of a grapheme — or a Regex, with the Regex module');
      }
      requireFinite(receiver, 'split');
      const pieces = [];
      let current = [];
      const it = yield* iteratorOf(receiver);
      for (;;) {
        const e = yield* it.next(); if (e === undefined) break;
        const isSep = isFn(args[0]) ? yield* holds(args[0], e, 'split') : equals(e, args[0]);
        if (isSep) { if (current.length) pieces.push(current); current = []; } else current.push(e);
      }
      if (current.length) pieces.push(current);
      let pieceLock;
      switch (rk) {
        case 'string': pieceLock = stringType; break;
        case 'data': pieceLock = ann('Data'); break;
        case 'set': { const k = knownElementLock(receiver); pieceLock = k ? ann('Set', false, [k]) : null; break; }
        case 'dictionary': pieceLock = receiver.lock; break;
        default: { const k = knownElementLock(receiver); pieceLock = k ? ann('Array', false, [k]) : null; }
      }
      return new SArray(pieces.map((p) => restamp(reshape(p, receiver), receiver)), pieceLock ? ann('Array', false, [pieceLock]) : null);
    }
    case 'and()': case 'or()': case 'xor()': {
      if (rk !== 'bool') throw SwiftalkError.unknownMember(`${typeName(receiver)}.${name}()` + (rk === 'int' ? ` — bitwise is .bit${name[0].toUpperCase()}${name.slice(1)}()` : ''));
      if (args.length !== 1 || typeof args[0] !== 'boolean') throw SwiftalkError.type(`Bool.${name} takes one Bool — nothing is truthy (§3b)`);
      return name === 'and' ? receiver && args[0] : name === 'or' ? receiver || args[0] : receiver !== args[0];
    }
    case 'bitAnd()': case 'bitOr()': case 'bitXor()': case 'shifted()': {
      const smartShift = (a, b) => (b >= 64n ? 0n : b <= -64n ? (a < 0n ? -1n : 0n) : b >= 0n ? BigInt.asIntN(64, a << b) : a >> -b);
      if (rk === 'byte') {
        let b;
        if (args.length === 1 && args[0] instanceof Byte) b = BigInt(args[0].v);
        else if (args.length === 1 && typeof args[0] === 'bigint') b = args[0];
        else throw SwiftalkError.type(`.${name} takes one Int or Byte`);
        const x = BigInt(receiver.v);
        const r = name === 'bitAnd' ? x & b : name === 'bitOr' ? x | b : name === 'bitXor' ? x ^ b : smartShift(x, b);
        return new Byte(Number(BigInt.asUintN(8, r)));
      }
      if (rk !== 'int') throw SwiftalkError.unknownMember(`${typeName(receiver)}.${name}()`);
      if (args.length !== 1 || typeof args[0] !== 'bigint') throw SwiftalkError.type(`.${name} takes one Int`);
      const b = args[0];
      switch (name) {
        case 'bitAnd': return receiver & b;
        case 'bitOr': return receiver | b;
        case 'bitXor': return receiver ^ b;
        default: return smartShift(receiver, b);
      }
    }
    case 'not()':
      if (args.length) throw SwiftalkError.type('.not() takes no arguments');
      if (rk !== 'bool') throw SwiftalkError.unknownMember(`${typeName(receiver)}.not()` + (rk === 'int' ? ' — bitwise is .bitNot()' : ''));
      return !receiver;
    case 'bitNot()':
      if (args.length) throw SwiftalkError.type('.bitNot() takes no arguments');
      if (rk === 'byte') return new Byte(~receiver.v & 0xff);
      if (rk !== 'int') throw SwiftalkError.unknownMember(`${typeName(receiver)}.bitNot()`);
      return ~receiver;
    case 'bit()':
      if (rk !== 'int') throw SwiftalkError.unknownMember(`${typeName(receiver)}.bit()`);
      if (args.length !== 1 || typeof args[0] !== 'bigint' || args[0] < 0n || args[0] >= 64n) throw SwiftalkError.type('.bit(i) takes an Int in 0..<64');
      return ((receiver >> args[0]) & 1n) === 1n;
    case 'bits':
      if (rk !== 'int') throw SwiftalkError.unknownMember(`${typeName(receiver)}.bits`);
      return new SArray(Array.from({ length: 64 }, (_, i) => ((receiver >> BigInt(i)) & 1n) === 1n));
    case 'nonzeroBitCount': case 'leadingZeroBitCount': case 'trailingZeroBitCount': {
      if (rk !== 'int') throw SwiftalkError.unknownMember(`${typeName(receiver)}.${name}`);
      const u = BigInt.asUintN(64, receiver);
      const bits = u.toString(2).padStart(64, '0');
      if (name === 'nonzeroBitCount') return BigInt(bits.split('1').length - 1);
      if (name === 'leadingZeroBitCount') return BigInt(bits.indexOf('1') < 0 ? 64 : bits.indexOf('1'));
      const last = bits.lastIndexOf('1');
      return BigInt(last < 0 ? 64 : 63 - last);
    }
    case 'normalized()': case 'isNormalized()': {
      if (rk !== 'string') throw SwiftalkError.unknownMember(`${typeName(receiver)}.${name}()`);
      const forms = { nfc: 'NFC', nfd: 'NFD', nfkc: 'NFKC', nfkd: 'NFKD' };
      if (args.length !== 1 || typeof args[0] !== 'string' || !(args[0] in forms)) throw SwiftalkError.type(`.${name}(with:) takes one form: .nfc, .nfd, .nfkc, or .nfkd`);
      const normalized = receiver.normalize(forms[args[0]]);
      return name === 'normalized' ? normalized : normalized === receiver;
    }
    case 'uppercased()': case 'lowercased()': case 'ucfirst()': case 'lcfirst()': {
      if (rk !== 'string') throw SwiftalkError.unknownMember(`${typeName(receiver)}.${name}()`);
      if (args.length) throw SwiftalkError.type(`.${name}() takes no arguments`);
      if (name === 'uppercased') return receiver.toUpperCase();
      if (name === 'lowercased') return receiver.toLowerCase();
      const gs = graphemes(receiver);
      if (!gs.length) return '';
      const head = name === 'ucfirst' ? gs[0].toUpperCase() : gs[0].toLowerCase();
      return head + gs.slice(1).join('');
    }
    case 'trimmed()': {
      if (rk !== 'string') throw SwiftalkError.unknownMember(`${typeName(receiver)}.trimmed()`);
      let unwanted;
      if (args.length === 0) unwanted = isWhite;
      else if (args.length === 1) {
        if (typeof args[0] !== 'string') throw SwiftalkError.type(`.trimmed(chars) takes a String of the graphemes to strip, not ${typeName(args[0])}`);
        const set = new Set(graphemes(args[0]));
        unwanted = (g) => set.has(g);
      } else throw SwiftalkError.type('.trimmed() takes no arguments, or one String of graphemes to strip');
      const gs = graphemes(receiver);
      let a = 0, b = gs.length;
      while (a < b && unwanted(gs[a])) a++;
      while (b > a && unwanted(gs[b - 1])) b--;
      return gs.slice(a, b).join('');
    }
    case 'escaped()': case 'unescaped()':
      if (rk !== 'string') throw SwiftalkError.unknownMember(`${typeName(receiver)}.${name}()`);
      if (args.length) throw SwiftalkError.type(`.${name}() takes no arguments`);
      return name === 'escaped' ? StringEscapes.escaped(receiver) : StringEscapes.unescaped(receiver);
    case 'unicodeScalars': case 'utf32': case 'utf8':
      if (rk !== 'string') throw SwiftalkError.unknownMember(`${typeName(receiver)}.${name}`);
      if (name === 'utf8') return new SArray(Array.from(new TextEncoder().encode(receiver), (b) => BigInt(b)));
      return new SArray(Array.from(receiver, (c) => BigInt(c.codePointAt(0))));
    case 'merging()':
      if (rk !== 'dictionary') throw SwiftalkError.unknownMember(`${typeName(receiver)}.merging()`);
      return yield* mergeDictionaries(receiver, args);
    case 'keys': case 'values': {
      if (rk !== 'dictionary') throw SwiftalkError.unknownMember(`${typeName(receiver)}.${name}`);
      const lock = receiver.lock;
      if (name === 'keys') {
        if (lock && lock.parameters.length) return new SSet(receiver.keys(), ann('Set', false, [lock.parameters[0]]));
        return Builtins.stampedSet(receiver.keys(), null);
      }
      const values = receiver.values();
      if (lock && lock.parameters.length === 2) return new SArray(values, ann('Array', false, [lock.parameters[1]]));
      const inferred = tryInfer(new SArray(values), 'values', false);
      return inferred && inferred.parameters.length ? new SArray(values, inferred) : new SArray(values);
    }
    case 'union()': case 'intersection()': case 'subtracting()': case 'symmetricDifference()':
    case 'isSubset()': case 'isSuperset()': case 'isStrictSubset()': case 'isStrictSuperset()': case 'isDisjoint()': {
      if (rk !== 'set') throw SwiftalkError.unknownMember(`${typeName(receiver)}.${name}()`);
      if (args.length !== 1) throw SwiftalkError.type(`.${name} takes one argument: a Set, or any Sequence`);
      const other = yield* setElements(args[0]);
      const s = receiver;
      const subset = (x, y) => x.values().every((e) => y.has(e));
      switch (name) {
        case 'union': { const u = new SSet(s.values()); for (const e of other.values()) u.add(e); return u; }
        case 'intersection': return new SSet(s.values().filter((e) => other.has(e)));
        case 'subtracting': return new SSet(s.values().filter((e) => !other.has(e)));
        case 'symmetricDifference': return new SSet([...s.values().filter((e) => !other.has(e)), ...other.values().filter((e) => !s.has(e))]);
        case 'isSubset': return subset(s, other);
        case 'isSuperset': return subset(other, s);
        case 'isStrictSubset': return subset(s, other) && s.size < other.size;
        case 'isStrictSuperset': return subset(other, s) && other.size < s.size;
        default: return s.values().every((e) => !other.has(e));
      }
    }
    case 'keys()': case 'values()':
      if (rk !== 'dictionary') throw SwiftalkError.unknownMember(`${typeName(receiver)}.${name}()`);
      throw SwiftalkError.type(`.${name} is a property, as in Swift — d.${name}, not d.${name}()`);
    case 'has()':
      if (rk !== 'dictionary') throw SwiftalkError.unknownMember(`${typeName(receiver)}.has()`);
      if (args.length !== 1) throw SwiftalkError.type('.has(key) takes exactly one argument');
      return receiver.has(args[0]);
    default: throw unknown();
  }
}
