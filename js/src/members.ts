// Member dispatch — Eval.swift's method(on:), convert, stringFormat,
// staticMember, and Value.prettyString. Generators, like eval.js: a
// member may run swiftalk code (a closure argument, a user type's own
// String member), so everything here is `function*` called with `yield*`.
import { SwiftalkError } from './errors.js';
import { TypeAnnotation } from './parser.js';
import { typeName, equals, keyOf, sourceString, graphemes, spreadsInSet, hexFloat, compareStrings, must,
  SArray, SDictionary, SSet, Byte, SData, SDate, TupleValue,
  isBool, isInt, isDouble, isString, isArray, isDictionary, isSet, isByte, isData, isDate, isRange, isTuple, isFunction, isSequence, isEnumCase, isStructValue, isHost, isContainer } from './value.js';
import { FunctionObject, SequenceObject, isGenerator } from './objects.js';
import type { HostObject } from './objects.js';
import { Builtins, isResult, DoubleMath, IntStatics, stringFromCodePoint, dataRandom, intRandom } from './builtins.js';
import { ann, inferLock, tryInfer, knownElementLock, stampedArray, typeValue, typeValueForParameter, callBuiltin } from './types.js';
import { JSONFormat, PlistXML, PlistBinary, StringEscapes, CivilDate } from './formats.js';
import { apply, boundMethod, iteratorOf, collect, lazyBase, restamp, reshape, holds, requireFinite, rangeCount,
  compare, hasUserOperator, containsSubstring, constructEnumCase, caseAccessor, computedProperty, readComputed,
  lookupExtension, mergeDictionaries, setElements, resolveStatic, scheduler } from './eval.js';
import type { G } from './eval.js';
import type { Value, LabeledArg } from './value.js';
import type { Environment } from './env.js';

/// A host value's member, run: a generator when it runs swiftalk code; undefined when declined.
export function* callMember(object: HostObject, name: string, args: Value[], called: boolean): G<Value | undefined> {
  const r = object.member(name, args, called);
  return isGenerator(r) ? yield* r : r;
}

// ---- the law's hooks ----
/// `.String(.canonical)` (round 153): the builtin source form, no type's String member asked.
export function asksCanonical(name: string, args: LabeledArg[]): boolean {
  return name === 'String' && args.some((a) => a.label === null && a.value === 'canonical');
}
/// A user type's own conversion member (round 151): `let Double = { ... }` in a struct or enum body.
export function userConversion(value: Value, tn: string): FunctionObject | null {
  if (isStructValue(value) || isEnumCase(value)) return value.type.methods.get(tn) ?? null;
  return null;
}
/// Rejects labeled arguments where a member takes none, yielding the bare values.
export function plainValues(args: LabeledArg[], member: string): Value[] {
  const label = args.map((a) => a.label).find((l) => l !== null);
  if (label !== undefined) throw SwiftalkError.type(`${member} takes no argument label '${label}'`);
  return args.map((a) => a.value);
}

// ---- pretty printing (round 117) ----
/// `.pretty`'s callback (round 151): a type declaring `let String = { }` owns its
/// pretty text at every depth — precomputed here, since calling it runs swiftalk.
function* userPrettyMap(value: Value): G<Map<Value, string>> {
  const owned = new Map<Value, string>();
  const walk = function* (v: Value): G<void> {
    const m = userConversion(v, 'String');
    if (m) {
      const [bound] = boundMethod(m, v);
      const text = yield* apply(bound, [{ label: null, value: 'pretty' }]);
      if (typeof text !== 'string') throw SwiftalkError.type(`${typeName(v)}.String(.pretty) must return a String`);
      owned.set(v, text);
      return;
    }
    if (isArray(v)) for (const x of v.items) yield* walk(x);
    else if (isSet(v)) for (const x of v.values()) yield* walk(x);
    else if (isDictionary(v)) for (const [k, x] of v.entries()) { yield* walk(k); yield* walk(x); }
    else if (isTuple(v)) for (const x of v.values) yield* walk(x);
    else if (isStructValue(v)) for (const x of v.values.values()) yield* walk(x);
    else if (isEnumCase(v)) for (const x of v.associated) yield* walk(x);
  };
  yield* walk(value);
  return owned;
}
export function prettyString(value: Value, owned: Map<Value, string> | null = null, depth = 0): string {
  const custom = (v: Value): string | null => (owned && owned.has(v) ? owned.get(v) ?? null : null);
  const own = custom(value);
  if (own !== null) return own;
  const pad = '  '.repeat(depth + 1), close = '  '.repeat(depth);
  const inner = (v: Value): string => prettyString(v, owned, depth + 1);
  const bySource = (a: { key: string }, b: { key: string }) => (a.key < b.key ? -1 : a.key > b.key ? 1 : 0);
  if (isArray(value)) {
    if (value.items.length === 0) return '[]';
    return '[\n' + value.items.map((x) => pad + inner(x)).join(',\n') + '\n' + close + ']';
  }
  if (isSet(value)) {
    const xs = value.values();
    if (xs.length === 0) return 'Set()';
    const body = xs.map((x) => ({ key: custom(x) ?? sourceString(x), text: inner(x) })).sort(bySource).map((e) => pad + e.text).join(',\n');
    const [open, shut] = xs.length === 1 && spreadsInSet(xs[0]) ? ['Set([\n', '])'] : ['Set(\n', ')'];
    return open + body + '\n' + close + shut;
  }
  if (isDictionary(value)) {
    if (value.size === 0) return '[:]';
    const body = value.entries().map(([k, v]) => ({ key: custom(k) ?? sourceString(k), value: inner(v) })).sort(bySource)
      .map((e) => `${pad}${e.key}: ${e.value}`).join(',\n');
    return '[\n' + body + '\n' + close + ']';
  }
  if (isTuple(value)) {
    if (value.count === 0) return '()';
    const lonely = value.count === 1 && value.labels[0] === null;
    const body = value.values.map((v, i) => pad + (value.labels[i] !== null ? `${value.labels[i]}: ` : '') + inner(v)).join(',\n');
    return '(\n' + body + (lonely ? ',\n' : '\n') + close + ')';
  }
  if (isStructValue(value)) {
    if (value.type.propertyOrder.length === 0) return sourceString(value);
    const body = value.type.propertyOrder.map((p) => `${pad}${p}: ${inner(value.values.get(p) ?? null)}`).join(',\n');
    return value.type.name + '(\n' + body + '\n' + close + ')';
  }
  if (isEnumCase(value)) {
    if (value.associated.length === 0) return sourceString(value);
    const params = value.type.cases.get(value.caseName) ?? [];
    const body = value.associated.map((v, i) => { const t = inner(v); const label = params[i]?.label ?? null; return pad + (label !== null ? `${label}: ${t}` : t); }).join(',\n');
    return `${value.type.name}.${value.caseName}(\n` + body + '\n' + close + ')';
  }
  return sourceString(value);
}
export function* prettyText(value: Value): G<string> { return prettyString(value, yield* userPrettyMap(value)); }

// ---- conversion: x.T(...) is T(x, ...) (round 47) ----
export function* convert(tn: string, subject: Value | undefined, extra: LabeledArg[]): G<Value> {
  if (subject !== undefined && !asksCanonical(tn, extra)) {
    const m = userConversion(subject, tn);
    if (m) {
      const [bound] = boundMethod(m, subject);
      const result = yield* apply(bound, extra);
      // Round 233: the String member's result is a String on every spelling — x.String() and String(x) too
      if (tn === 'String' && typeof result !== 'string') throw SwiftalkError.type(`${typeName(subject)}.String() must return a String`);
      return result;
    }
  }
  // ...and a module's value (round 201): `Int(b)` is `b.Int()`, the host's member, labels dropped
  if (isHost(subject)) {
    const v = yield* callMember(subject.object, tn, extra.map((a) => a.value), true);
    if (v !== undefined) return v;
  }
  const object = must(Builtins.types.get(tn) ?? Builtins.protocols.get(tn), `the ${tn} constructor`);
  const builtin = must(object.builtin, `the ${tn} constructor's body`);
  if (extra.length === 0) return yield* callBuiltin(builtin, subject === undefined ? [] : [subject]);
  switch (tn) {
    case 'String':
      if (subject === undefined) throw SwiftalkError.type('String formats need a value to format');
      return yield* stringFormat(subject, extra);
    case 'SION': {
      if (subject !== undefined || extra.length !== 1 || extra[0].label === null) throw SwiftalkError.type('SION(json: text) or SION(propertyList: text or data)');
      const { label, value } = extra[0];
      if (label === 'json' && isString(value)) return JSONFormat.parse(value);
      if (label === 'propertyList' && isString(value)) return PlistXML.parse(value);
      if (label === 'propertyList' && isData(value)) return PlistBinary.parse(value.bytes);
      throw SwiftalkError.type(`SION(${label}:) takes a String${label === 'propertyList' ? ' or a Data' : ''}, not a ${typeName(value)}`);
    }
    case 'Data': {
      const format = extra[0]?.value;
      if (subject === undefined || extra.length !== 1 || extra[0].label !== null || !isString(format)) throw SwiftalkError.type('.Data() takes one format: .utf8 or .propertyList');
      switch (format) {
        case 'utf8':
          if (!isString(subject)) throw SwiftalkError.type('.Data(.utf8) encodes a String');
          return new SData(new TextEncoder().encode(subject));
        case 'propertyList': return PlistBinary.emit(subject);
        default: throw SwiftalkError.type(`unknown .Data() format .${format}`);
      }
    }
    case 'Int': {
      const given = extra[0]?.value;
      if (subject !== undefined || extra.length !== 1 || extra[0].label !== 'bits' || !isArray(given)) throw SwiftalkError.type('Int(bits: [Bool]) — the bits, bit 0 first');
      const bits = given.items;
      if (bits.length > 64) throw SwiftalkError.overflow(`Int(bits:) takes at most 64 bits, got ${bits.length}`);
      let word = 0n;
      bits.forEach((bit, i) => {
        if (!isBool(bit)) throw SwiftalkError.type(`Int(bits:) takes Bools, not a ${typeName(bit)} at ${i}`);
        if (bit) word |= 1n << BigInt(i);
      });
      return BigInt.asIntN(64, word);
    }
    case 'Set':
      if (subject === undefined || !extra.every((a) => a.label === null)) throw SwiftalkError.type('Set(a, b, ...) takes unlabeled elements');
      return Builtins.stampedSet([subject, ...extra.map((a) => a.value)], null);
    case 'Sequence':
      if (subject === undefined || extra.length !== 1 || extra[0].label !== null) throw SwiftalkError.type('Sequence(initialState) { next } — an Array state and a Function');
      return yield* callBuiltin(builtin, [subject, extra[0].value]);
    default: throw SwiftalkError.type(`${tn}() takes no format arguments`);
  }
}

const radixText = (i: bigint, radix: number): string => (i < 0n ? -i : i).toString(radix);
/// String's format vocabulary (rounds 20–21, 42, 117, 125, 153).
function* stringFormat(subject: Value, formatsIn: LabeledArg[]): G<Value> {
  let formats = formatsIn.slice();
  let pretty = false, sign = false, canonical = false;
  const take = (word: string) => { const i = formats.findIndex((a) => a.label === null && a.value === word); if (i >= 0) { formats.splice(i, 1); return true; } return false; };
  pretty = take('pretty'); sign = take('sign'); canonical = take('canonical');
  if (formats.length > 1) throw SwiftalkError.type('.String() takes at most one format argument, plus .pretty or .sign');
  if (pretty && sign) throw SwiftalkError.type('.pretty lays out text and .sign marks a number — not both');
  if (canonical) {
    if (formats.length || sign) throw SwiftalkError.type('.canonical is the source form itself — alone or with .pretty, not with another format');
    return pretty ? prettyString(subject) : sourceString(subject);
  }
  const plus = (negative: boolean) => (negative ? '-' : sign ? '+' : '');
  if (formats.length === 0) {
    if (pretty) return yield* prettyText(subject);
    if (isInt(subject)) return plus(subject < 0n) + radixText(subject, 10);
    if (isByte(subject)) return plus(false) + String(subject.v);
    if (isDouble(subject)) return Number.isNaN(subject) ? 'nan' : plus(subject < 0 || Object.is(subject, -0)) + sourceString(Math.abs(subject));
    throw SwiftalkError.type(`.sign is a number's modifier, not a ${typeName(subject)}'s`);
  }
  const { label, value: format } = formats[0];
  if (pretty && !(isString(format) && ['quoted', 'sion', 'json', 'propertyList'].includes(format))) throw SwiftalkError.type(`.pretty lays out .sion (the default), .json, or .propertyList — not ${sourceString(format)}`);
  if (sign && label !== 'radix' && !(isString(format) && ['hex', 'oct', 'bin'].includes(format))) throw SwiftalkError.type(`.sign goes with a number's format — .hex, .oct, .bin, radix:, or none — not ${sourceString(format)}`);
  if (label === 'radix') {
    if (!isInt(format) || format < 2n || format > 36n) throw SwiftalkError.type('.String(radix:) takes an Int in 2...36');
    if (!isInt(subject)) throw SwiftalkError.type(".String(radix:) is an Int's format");
    return plus(subject < 0n) + radixText(subject, Number(format));
  }
  if (label !== null) throw SwiftalkError.type(`unknown .String() format label '${label}'`);
  switch (format) {
    case 'quoted': case 'sion': return pretty ? yield* prettyText(subject) : sourceString(subject);
    case 'json': return JSONFormat.emit(subject, pretty);
    case 'propertyList': return PlistXML.emit(subject);
    case 'iso8601':
      if (!isDate(subject)) throw SwiftalkError.type(".String(.iso8601) is a Date's format");
      return CivilDate.iso8601(subject.epoch);
    case 'utf8': {
      if (!isData(subject)) throw SwiftalkError.type('.String(.utf8) decodes Data');
      try { return new TextDecoder('utf-8', { fatal: true }).decode(subject.bytes); } catch (e) { return null; }
    }
    case 'hex':
      if (isInt(subject)) return plus(subject < 0n) + '0x' + radixText(subject, 16);
      if (isDouble(subject)) return hexFloat(subject, sign);
      throw SwiftalkError.type(".String(.hex) is a number's format");
    case 'oct': case 'bin': {
      if (!isInt(subject)) throw SwiftalkError.type(".String(.oct)/.String(.bin) are an Int's formats");
      const [prefix, radix] = format === 'oct' ? ['0o', 8] : ['0b', 2];
      return plus(subject < 0n) + prefix + radixText(subject, radix);
    }
    default: throw SwiftalkError.type(`unknown .String() format ${sourceString(format)}`);
  }
}

// ---- statics ----
function parameterMember(f: FunctionObject, name: string, env: Environment): FunctionObject | null {
  if (f.role.k !== 'type') return null;
  const base = f.role.name;
  let wanted: number;
  if ((base === 'Array' || base === 'Set') && name === 'Element') wanted = 0;
  else if (base === 'Dictionary' && name === 'Key') wanted = 0;
  else if (base === 'Dictionary' && name === 'Value') wanted = 1;
  else return null;
  if (!f.annotation || f.annotation.parameters.length <= wanted) {
    throw SwiftalkError.type(`${base} is the erased type and has no ${name} — a parameterized one does: ${base === 'Dictionary' ? '[Int: String]' : base === 'Set' ? 'Set([1]).Type' : '[Int]'}.${name}`);
  }
  return typeValueForParameter(f.annotation.parameters[wanted], env);
}
function* staticMember(f: FunctionObject, name: string, args: LabeledArg[], called: boolean, env: Environment): G<Value | undefined> {
  const p = parameterMember(f, name, env);
  if (p !== null) {
    if (!called) return p;
    return yield* apply(p, args);
  }
  let stored: Value | undefined, getter: FunctionObject | null = null, tn: string;
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
      else if (scheduler.modules?.nativeStatics.get(n)?.has(name)) stored = scheduler.modules.nativeStatics.get(n)?.get(name);
      else { const g = env.tryLookup(`@ext:${n}:static:get:${name}`); if (isFunction(g)) getter = g; }
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
  if (!isFunction(stored)) throw SwiftalkError.type(`cannot call ${tn}.${name}, a ${typeName(stored)}`);
  return yield* apply(stored, args);
}

// ---- sorting with a suspending comparator: a merge sort over yield* ----
type Less = (a: Value, b: Value) => G<boolean>;
function* sortedBy(elements: Value[], less: Less): G<Value[]> {
  if (elements.length <= 1) return elements.slice();
  const mid = elements.length >> 1;
  const a = yield* sortedBy(elements.slice(0, mid), less);
  const b = yield* sortedBy(elements.slice(mid), less);
  const out: Value[] = [];
  let i = 0, j = 0;
  while (i < a.length && j < b.length) {
    if (yield* less(b[j], a[i])) out.push(b[j++]); else out.push(a[i++]);   // stable
  }
  while (i < a.length) out.push(a[i++]);
  while (j < b.length) out.push(b[j++]);
  return out;
}
const lessBuiltin: Less = function* (a, b) { const r = yield* compare('<', a, b); return typeof r === 'boolean' ? r : false; };
const lessBy = (fn: FunctionObject, who: string): Less => function* (a, b) {
  const r = yield* apply(fn, [{ label: null, value: a }, { label: null, value: b }]);
  if (typeof r !== 'boolean') throw SwiftalkError.type(`the .${who} Function must return a Bool`);
  return r;
};

const swiftLabels = (name: string): string[] => {
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
const isWhite = (g: string): boolean => /^[\s\p{White_Space}]+$/u.test(g);   // a grapheme, so "\r\n" is one
const stringType = ann('String');

// ---- the member switch ----
/// `.Bool()`, `.Int()`, `.Double()`, `.Byte()`, `.Data()`, `.Date()`, `.SION()` are a
/// String's parses and nothing else's (rounds 205–210): the constructors convert; a
/// type's own member of the name (round 151) or an extension's stands.
const stringParses = new Set(['Bool', 'Int', 'Double', 'Byte', 'Data', 'Date', 'SION']);
function parseOnly(tn: string, receiver: Value, called: boolean, env: Environment): void {
  if (!called || !stringParses.has(tn) || typeof receiver === 'string') return;
  if (userConversion(receiver, tn) || lookupExtension(env, typeName(receiver), tn)) return;
  const hint = tn === 'Bool' ? 'a Bool is a Bool already, and an Int is not one (i != 0)' : `${tn}(x) converts`;
  throw SwiftalkError.unknownMember(`${typeName(receiver)}.${tn}() — .${tn}() is a String's parse; ${hint}`);
}

export function* method(receiver: Value, name: string, labeledArgs: LabeledArg[], called: boolean, env: Environment): G<Value> {
  const fnLike = isFunction(receiver) ? receiver : null;
  parseOnly(name, receiver, called, env);
  // A module's extension of a core type (round 186) answers first
  if (scheduler.modules) {
    const ext = scheduler.modules.nativeExtensions.get(typeName(receiver))?.get(name);
    if (ext) {
      const r = ext(receiver, labeledArgs.map((a) => a.value), called);
      const answer = isGenerator(r) ? yield* r : r;
      if (answer !== undefined) return answer;                 // undefined declines; null is nil
    }
  }
  if (isHost(receiver)) {
    const answer = yield* callMember(receiver.object, name, labeledArgs.map((a) => a.value), called);
    if (answer !== undefined) return answer;
  }
  if (name === 'conforms' && called) {
    if (!fnLike) throw SwiftalkError.type("'.conforms(to:)' is a question asked of a type");
    if (labeledArgs.length !== 1 || !(labeledArgs[0].label === null || labeledArgs[0].label === 'to')) throw SwiftalkError.type('.conforms(to:) takes exactly one argument');
    const p = labeledArgs[0].value;
    if (!isFunction(p) || p.role.k !== 'protocol') throw SwiftalkError.type('the argument to .conforms(to:) must be a protocol');
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
      if (!called) return new FunctionObject([], [], Builtins.emptyEnvironment, (xs: Value[]) => stringFromCodePoint(xs));
      return stringFromCodePoint(labeledArgs.map((a) => a.value));
    }
    const table = IntStatics.get(tn);
    if (table && table.has(name)) {
      if (called) throw SwiftalkError.type(`${tn}.${name} is a constant, not a function`);
      return must(table.get(name), `${tn}.${name}`);
    }
    if (tn === 'Data' && name === 'random') {
      if (!called) return new FunctionObject([], [], Builtins.emptyEnvironment, (xs: Value[]) => dataRandom(xs));
      const label = labeledArgs.map((a) => a.label).find((l) => l !== null);
      if (label !== undefined) throw SwiftalkError.type(`Data.random takes no argument label '${label}'`);
      return dataRandom(labeledArgs.map((a) => a.value));
    }
    if (tn === 'Int' && name === 'random') {
      if (called) return intRandom(labeledArgs);
      return new FunctionObject([], [], Builtins.emptyEnvironment, (xs: Value[]) => intRandom(xs.map((v): LabeledArg => ({ label: null, value: v }))));
    }
  }
  if (fnLike && fnLike.role.k === 'enumType' && fnLike.role.type.cases.has(name)) return constructEnumCase(fnLike.role.type, name, labeledArgs, called);
  if (fnLike) { const v = yield* staticMember(fnLike, name, labeledArgs, called, env); if (v !== undefined) return v; }
  if (isEnumCase(receiver) && !called && receiver.type.cases.has(name)) return caseAccessor(receiver, name, receiver);
  if (isTuple(receiver)) {
    const index: number | null = /^\d+$/.test(name) ? Number(name) : receiver.indexOfLabel(name);
    if (index !== null) {
      if (!(index >= 0 && index < receiver.count)) throw SwiftalkError.type(`tuple index ${index} out of range (count ${receiver.count})`);
      const value = receiver.values[index];
      if (!called) return value;
      if (!isFunction(value)) throw SwiftalkError.type(`cannot call Tuple.${name}, a ${typeName(value)}`);
      return yield* apply(value, labeledArgs);
    }
  }
  const c = computedProperty(receiver, name);
  if (c) {
    const value = yield* readComputed(c, receiver);
    if (!called) return value;
    if (!isFunction(value)) throw SwiftalkError.type(`cannot call ${typeName(receiver)}.${name}, a ${typeName(value)}`);
    return yield* apply(value, labeledArgs);
  }
  if (isStructValue(receiver) && receiver.values.has(name)) {
    const value = receiver.values.get(name) ?? null;
    if (!called) return value;
    if (!isFunction(value)) throw SwiftalkError.type(`cannot call ${receiver.type.name}.${name}, a ${typeName(value)}`);
    return yield* apply(value, labeledArgs);
  }
  const ownMethod = (isStructValue(receiver) || isEnumCase(receiver)) && !asksCanonical(name, labeledArgs) ? receiver.type.methods.get(name) : undefined;
  if (ownMethod) {
    const [bound] = boundMethod(ownMethod, receiver, true);
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
      if (!isFunction(value)) throw SwiftalkError.type(`cannot call ${typeName(receiver)}.${name}, a ${typeName(value)}`);
      return yield* apply(value, labeledArgs);
    }
  }
  if (called && (Builtins.types.has(name) || Builtins.protocols.has(name))) return yield* convert(name, receiver, labeledArgs);
  if (called && !Builtins.types.has(name)) {
    const f = env.tryLookup(name);
    if (isFunction(f) && f.role.k === 'type') {
      const tn = f.role.name;
      if (Builtins.types.has(tn) || Builtins.protocols.has(tn)) { parseOnly(tn, receiver, true, env); return yield* convert(tn, receiver, labeledArgs); }   // the alias path (round 111)
      if (f.builtin) return yield* callBuiltin(f.builtin, [receiver, ...labeledArgs.map((a) => a.value)]);
    }
  }
  const dropped = called ? swiftLabels(name) : [];
  const args = plainValues(dropped.length ? labeledArgs.map((a) => (a.label !== null && dropped.includes(a.label) ? { label: null, value: a.value } : a)) : labeledArgs, `.${name}`);
  const unknown = () => SwiftalkError.unknownMember(`${typeName(receiver)}.${name}${called ? '()' : ''}`);
  const isFn = isFunction;
  const key = `${name}${called ? '()' : ''}`;
  switch (key) {
    case 'Type': {
      if (isEnumCase(receiver) || isStructValue(receiver)) return receiver.type.constructor_;
      if (isHost(receiver)) return receiver.type;
      if (isContainer(receiver)) {
        const inferred = tryInfer(receiver, '', true);
        if (inferred) { const t = typeValue(inferred); if (t) return t; }
      }
      return Builtins.types.get(typeName(receiver)) ?? Builtins.protocols.get(typeName(receiver)) ?? null;
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
      if (isArray(receiver)) return BigInt(receiver.items.length);
      if (isString(receiver)) return BigInt(graphemes(receiver).length);
      if (isDictionary(receiver) || isSet(receiver)) return BigInt(receiver.size);
      if (isRange(receiver)) {
        if (receiver.to === null) throw SwiftalkError.type('an unbounded Range is infinite — .prefix(n) or .prefix { } it deliberately');
        return rangeCount(receiver.from, receiver.to, receiver.closed);
      }
      if (isData(receiver)) return BigInt(receiver.bytes.length);
      if (isTuple(receiver)) return BigInt(receiver.count);
      if (isSequence(receiver)) throw SwiftalkError.type('a Sequence may be infinite — take .prefix(n) or .Array() it deliberately');
      throw SwiftalkError.unknownMember(`${typeName(receiver)}.count`);
    case 'enumerated()': {
      if (args.length) throw SwiftalkError.type('.enumerated() takes no arguments');
      const base = lazyBase(receiver);
      if (base) return new SequenceObject({ kind: 'enumerated', base });
      if (isDictionary(receiver)) return receiver;
      const out: Value[] = [];
      const it = yield* iteratorOf(receiver);
      for (;;) { const e = yield* it.next(); if (e === undefined) break; out.push(new TupleValue([BigInt(out.length), e], ['key', 'value'])); }
      return new SArray(out, ann('Array', false, [ann('Tuple')]));
    }
    case 'prefix()': {
      if (args.length === 1 && isFn(args[0])) {
        const base = lazyBase(receiver);
        if (base) return new SequenceObject({ kind: 'takenWhile', base, fn: args[0] });
        const kept: Value[] = [];
        const it = yield* iteratorOf(receiver);
        for (;;) { const e = yield* it.next(); if (e === undefined || !(yield* holds(args[0], e, 'prefix'))) break; kept.push(e); }
        return restamp(reshape(kept, receiver), receiver);
      }
      const n = args[0];
      if (args.length !== 1 || !isInt(n) || n < 0n) throw SwiftalkError.type('.prefix takes a non-negative Int, or a Function x -> Bool');
      const out: Value[] = [];
      const it = yield* iteratorOf(receiver);
      while (BigInt(out.length) < n) { const e = yield* it.next(); if (e === undefined) break; out.push(e); }
      return restamp(reshape(out, receiver), receiver);
    }
    case 'suffix()': case 'dropFirst()': case 'dropLast()': {
      if (name === 'dropFirst' && args.length === 1 && isFn(args[0])) {
        const base = lazyBase(receiver);
        if (base) return new SequenceObject({ kind: 'droppedWhile', base, fn: args[0] });
        const kept: Value[] = [];
        let dropping = true;
        const it = yield* iteratorOf(receiver);
        for (;;) {
          const e = yield* it.next(); if (e === undefined) break;
          if (dropping) { if (yield* holds(args[0], e, 'dropFirst')) continue; dropping = false; }
          kept.push(e);
        }
        return restamp(reshape(kept, receiver), receiver);
      }
      let n: bigint;
      const given = args[0];
      if (args.length === 0 && name !== 'suffix') n = 1n;
      else if (args.length === 1) {
        if (!isInt(given) || given < 0n) throw SwiftalkError.type(`.${name}(n) takes one non-negative Int`);
        n = given;
      } else {
        throw SwiftalkError.type(name === 'suffix' ? '.suffix(n) takes one non-negative Int'
          : name === 'dropFirst' ? '.dropFirst takes a non-negative Int (default 1), or a Function x -> Bool' : '.dropLast(n) takes one non-negative Int (default 1)');
      }
      if (name === 'dropFirst') { const base = lazyBase(receiver); if (base) return new SequenceObject({ kind: 'dropped', base, n: n > 1n << 40n ? 1n << 40n : n }); }
      requireFinite(receiver, name);
      const all = yield* collect(receiver);
      const count = Math.min(Number(n), all.length);
      const kept = name === 'suffix' ? all.slice(all.length - count) : name === 'dropFirst' ? all.slice(count) : all.slice(0, all.length - count);
      return restamp(reshape(kept, receiver), receiver);
    }
    case 'catch()': {
      if (!isResult(receiver)) throw SwiftalkError.type(".catch is a Result's — for nil, `??` is the form");
      const handler = args[0];
      if (args.length !== 1 || !isFn(handler)) throw SwiftalkError.type('.catch takes a single Function: r.catch { err in ... }');
      return receiver.caseName === 'success' ? receiver.associated[0] : yield* apply(handler, [{ label: null, value: receiver.associated[0] }]);
    }
    case 'then()': {
      if (!isResult(receiver)) throw SwiftalkError.type(".then is a Result's");
      const next = args[0];
      if (args.length !== 1 || !isFn(next)) throw SwiftalkError.type('.then takes a single Function: r.then { v in ... }');
      if (receiver.caseName !== 'success') return receiver;
      const out = yield* apply(next, [{ label: null, value: receiver.associated[0] }]);
      if (isResult(out)) return out;
      return constructEnumCase(Builtins.resultType, 'success', [{ label: null, value: out }], true);
    }
    case 'description': return isString(receiver) ? receiver : sourceString(receiver);
    case 'debugDescription': return sourceString(receiver, true);
    case 'map()': {
      if (args.length !== 1 || !isFn(args[0])) throw SwiftalkError.type('.map takes a single Function');
      const base = lazyBase(receiver);
      if (base) return new SequenceObject({ kind: 'mapped', base, fn: args[0] });
      const out: Value[] = [];
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
      const kept: Value[] = [];
      const it = yield* iteratorOf(receiver);
      for (;;) {
        const e = yield* it.next(); if (e === undefined) break;
        const keep = yield* apply(args[0], [{ label: null, value: e }]);
        if (typeof keep !== 'boolean') throw SwiftalkError.type('the .filter Function must return a Bool');
        if (keep) kept.push(e);
      }
      if (isData(receiver) || isSet(receiver) || isString(receiver) || isDictionary(receiver)) return restamp(reshape(kept, receiver), receiver);
      return restamp(new SArray(kept), receiver);
    }
    case 'reduce()': {
      if (args.length !== 2 || !isFn(args[1])) throw SwiftalkError.type('.reduce takes an initial value and a Function');
      requireFinite(receiver, 'reduce');
      let acc: Value = args[0];
      const it = yield* iteratorOf(receiver);
      for (;;) { const e = yield* it.next(); if (e === undefined) break; acc = yield* apply(args[1], [{ label: null, value: acc }, { label: null, value: e }]); }
      return acc;
    }
    case 'first': { const e = yield* (yield* iteratorOf(receiver)).next(); return e === undefined ? null : e; }
    case 'min()': case 'max()': {
      const elements = yield* collect(receiver);
      let less: Less;
      if (args.length === 0) {
        const comparable = must(Builtins.conformance.get('Comparable'), 'the Comparable conformance');
        const odd = elements.find((e) => !comparable.has(typeName(e)) && !hasUserOperator(e, 'infix:<'));
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
      if (isString(receiver)) {
        const needle = args[0];
        if (!isString(needle)) throw SwiftalkError.type(`String.contains looks for a String or a Regex, not a ${typeName(needle)}`);
        return containsSubstring(receiver, needle);
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
      let stringMode: boolean;
      if (probe === undefined) stringMode = elementLock?.name !== 'Array';
      else if (isString(probe)) stringMode = true;
      else if (isArray(probe)) stringMode = false;
      else throw SwiftalkError.type(`.joined joins Strings or Arrays — not ${typeName(probe)}`);
      if (stringMode) {
        let sep = '';
        if (separator !== undefined) { if (!isString(separator)) throw SwiftalkError.type(`.joined of Strings takes a String separator, not a ${typeName(separator)}`); sep = separator; }
        return elements.map((e) => { if (!isString(e)) throw SwiftalkError.type(`.joined of Strings met a ${typeName(e)} — map it to a String first`); return e; }).join(sep);
      }
      let sep: Value[] = [];
      if (separator !== undefined) { if (!isArray(separator)) throw SwiftalkError.type(`.joined of Arrays takes an Array separator, not a ${typeName(separator)}`); sep = separator.items; }
      const out: Value[] = [];
      elements.forEach((e, i) => { if (!isArray(e)) throw SwiftalkError.type(`.joined of Arrays met a ${typeName(e)}`); if (i > 0) out.push(...sep); out.push(...e.items); });
      const inferred = tryInfer(new SArray(out), 'joined', false);
      if (inferred && inferred.parameters.length) return new SArray(out, inferred);
      if (elementLock && elementLock.name === 'Array' && elementLock.parameters.length) return new SArray(out, ann('Array', false, [elementLock.parameters[0]]));
      return new SArray(out);
    }
    case 'replacing()': {
      if (!isString(receiver)) throw SwiftalkError.unknownMember(`${typeName(receiver)}.replacing()`);
      const usage = '.replacing takes what to find (a Regex or a String) and the replacement (a String, or a Function of the match)';
      const [find, replacement] = args;
      if (args.length !== 2 || !isString(find) || !isString(replacement)) throw SwiftalkError.type(usage);
      if (find === '') return replacement + graphemes(receiver).join(replacement) + replacement;
      return receiver.split(find).join(replacement);   // FIXME: code-unit matching, not Character-wise canonical equivalence
    }
    case 'split()': {
      if (args.length !== 1) throw SwiftalkError.type('.split takes one separator: a value, a Function, or (on a String) a Regex');
      const strings = ann('Array', false, [stringType]);
      const separator = args[0];
      if (isString(receiver)) {
        if (isString(separator)) return new SArray(receiver.split(separator).filter((p) => p !== ''), strings);
        if (!isFn(separator)) throw SwiftalkError.type('String.split takes a String, a Function of a grapheme — or a Regex, with the Regex module');
      }
      requireFinite(receiver, 'split');
      const pieces: Value[][] = [];
      let current: Value[] = [];
      const it = yield* iteratorOf(receiver);
      for (;;) {
        const e = yield* it.next(); if (e === undefined) break;
        const isSep = isFn(separator) ? yield* holds(separator, e, 'split') : equals(e, separator);
        if (isSep) { if (current.length) pieces.push(current); current = []; } else current.push(e);
      }
      if (current.length) pieces.push(current);
      let pieceLock: TypeAnnotation | null;
      if (isString(receiver)) pieceLock = stringType;
      else if (isData(receiver)) pieceLock = ann('Data');
      else if (isSet(receiver)) { const k = knownElementLock(receiver); pieceLock = k ? ann('Set', false, [k]) : null; }
      else if (isDictionary(receiver)) pieceLock = receiver.lock;
      else { const k = knownElementLock(receiver); pieceLock = k ? ann('Array', false, [k]) : null; }
      return new SArray(pieces.map((p) => restamp(reshape(p, receiver), receiver)), pieceLock ? ann('Array', false, [pieceLock]) : null);
    }
    case 'and()': case 'or()': case 'xor()': {
      if (!isBool(receiver)) throw SwiftalkError.unknownMember(`${typeName(receiver)}.${name}()` + (isInt(receiver) ? ` — bitwise is .bit${name[0].toUpperCase()}${name.slice(1)}()` : ''));
      const other = args[0];
      if (args.length !== 1 || !isBool(other)) throw SwiftalkError.type(`Bool.${name} takes one Bool — nothing is truthy (§3b)`);
      return name === 'and' ? receiver && other : name === 'or' ? receiver || other : receiver !== other;
    }
    case 'bitAnd()': case 'bitOr()': case 'bitXor()': case 'shifted()': {
      const smartShift = (a: bigint, b: bigint): bigint => (b >= 64n ? 0n : b <= -64n ? (a < 0n ? -1n : 0n) : b >= 0n ? BigInt.asIntN(64, a << b) : a >> -b);
      const operand = args[0];
      if (isByte(receiver)) {
        let b: bigint;
        if (args.length === 1 && isByte(operand)) b = BigInt(operand.v);
        else if (args.length === 1 && isInt(operand)) b = operand;
        else throw SwiftalkError.type(`.${name} takes one Int or Byte`);
        const x = BigInt(receiver.v);
        const r = name === 'bitAnd' ? x & b : name === 'bitOr' ? x | b : name === 'bitXor' ? x ^ b : smartShift(x, b);
        return new Byte(Number(BigInt.asUintN(8, r)));
      }
      if (!isInt(receiver)) throw SwiftalkError.unknownMember(`${typeName(receiver)}.${name}()`);
      if (args.length !== 1 || !isInt(operand)) throw SwiftalkError.type(`.${name} takes one Int`);
      const b = operand;
      const x = receiver;
      switch (name) {
        case 'bitAnd': return x & b;
        case 'bitOr': return x | b;
        case 'bitXor': return x ^ b;
        default: return smartShift(x, b);
      }
    }
    case 'not()':
      if (args.length) throw SwiftalkError.type('.not() takes no arguments');
      if (!isBool(receiver)) throw SwiftalkError.unknownMember(`${typeName(receiver)}.not()` + (isInt(receiver) ? ' — bitwise is .bitNot()' : ''));
      return !receiver;
    case 'bitNot()':
      if (args.length) throw SwiftalkError.type('.bitNot() takes no arguments');
      if (isByte(receiver)) return new Byte(~receiver.v & 0xff);
      if (!isInt(receiver)) throw SwiftalkError.unknownMember(`${typeName(receiver)}.bitNot()`);
      return ~receiver;
    case 'bit()': {
      if (!isInt(receiver)) throw SwiftalkError.unknownMember(`${typeName(receiver)}.bit()`);
      const i = args[0];
      if (args.length !== 1 || !isInt(i) || i < 0n || i >= 64n) throw SwiftalkError.type('.bit(i) takes an Int in 0..<64');
      return ((receiver >> i) & 1n) === 1n;
    }
    case 'bits':
      if (!isInt(receiver)) throw SwiftalkError.unknownMember(`${typeName(receiver)}.bits`);
      return new SArray(Array.from({ length: 64 }, (_, i) => ((receiver >> BigInt(i)) & 1n) === 1n));
    case 'nonzeroBitCount': case 'leadingZeroBitCount': case 'trailingZeroBitCount': {
      if (!isInt(receiver)) throw SwiftalkError.unknownMember(`${typeName(receiver)}.${name}`);
      const u = BigInt.asUintN(64, receiver);
      const bits = u.toString(2).padStart(64, '0');
      if (name === 'nonzeroBitCount') return BigInt(bits.split('1').length - 1);
      if (name === 'leadingZeroBitCount') return BigInt(bits.indexOf('1') < 0 ? 64 : bits.indexOf('1'));
      const last = bits.lastIndexOf('1');
      return BigInt(last < 0 ? 64 : 63 - last);
    }
    case 'normalized()': case 'isNormalized()': {
      if (!isString(receiver)) throw SwiftalkError.unknownMember(`${typeName(receiver)}.${name}()`);
      const forms: Record<string, string> = { nfc: 'NFC', nfd: 'NFD', nfkc: 'NFKC', nfkd: 'NFKD' };
      const form = args[0];
      if (args.length !== 1 || !isString(form) || !(form in forms)) throw SwiftalkError.type(`.${name}(with:) takes one form: .nfc, .nfd, .nfkc, or .nfkd`);
      const normalized = receiver.normalize(forms[form]);
      return name === 'normalized' ? normalized : normalized === receiver;
    }
    case 'uppercased()': case 'lowercased()': case 'ucfirst()': case 'lcfirst()': {
      if (!isString(receiver)) throw SwiftalkError.unknownMember(`${typeName(receiver)}.${name}()`);
      if (args.length) throw SwiftalkError.type(`.${name}() takes no arguments`);
      if (name === 'uppercased') return receiver.toUpperCase();
      if (name === 'lowercased') return receiver.toLowerCase();
      const gs = graphemes(receiver);
      if (!gs.length) return '';
      const head = name === 'ucfirst' ? gs[0].toUpperCase() : gs[0].toLowerCase();
      return head + gs.slice(1).join('');
    }
    case 'trimmed()': {
      if (!isString(receiver)) throw SwiftalkError.unknownMember(`${typeName(receiver)}.trimmed()`);
      let unwanted: (g: string) => boolean;
      const chars = args[0];
      if (args.length === 0) unwanted = isWhite;
      else if (args.length === 1) {
        if (!isString(chars)) throw SwiftalkError.type(`.trimmed(chars) takes a String of the graphemes to strip, not ${typeName(chars)}`);
        const set = new Set(graphemes(chars));
        unwanted = (g: string) => set.has(g);
      } else throw SwiftalkError.type('.trimmed() takes no arguments, or one String of graphemes to strip');
      const gs = graphemes(receiver);
      let a = 0, b = gs.length;
      while (a < b && unwanted(gs[a])) a++;
      while (b > a && unwanted(gs[b - 1])) b--;
      return gs.slice(a, b).join('');
    }
    case 'escaped()': case 'unescaped()':
      if (!isString(receiver)) throw SwiftalkError.unknownMember(`${typeName(receiver)}.${name}()`);
      if (args.length) throw SwiftalkError.type(`.${name}() takes no arguments`);
      return name === 'escaped' ? StringEscapes.escaped(receiver) : StringEscapes.unescaped(receiver);
    case 'unicodeScalars': case 'utf32': case 'utf8':
      if (!isString(receiver)) throw SwiftalkError.unknownMember(`${typeName(receiver)}.${name}`);
      if (name === 'utf8') return new SArray(Array.from(new TextEncoder().encode(receiver), (b) => BigInt(b)));
      return new SArray(Array.from(receiver, (c) => BigInt(must(c.codePointAt(0), 'a scalar'))));
    case 'merging()':
      if (!isDictionary(receiver)) throw SwiftalkError.unknownMember(`${typeName(receiver)}.merging()`);
      return yield* mergeDictionaries(receiver, args);
    case 'keys': case 'values': {
      if (!isDictionary(receiver)) throw SwiftalkError.unknownMember(`${typeName(receiver)}.${name}`);
      const d = receiver;
      const lock = d.lock;
      if (name === 'keys') {
        if (lock && lock.parameters.length) return new SSet(d.keys(), ann('Set', false, [lock.parameters[0]]));
        return Builtins.stampedSet(d.keys(), null);
      }
      const values = d.values();
      if (lock && lock.parameters.length === 2) return new SArray(values, ann('Array', false, [lock.parameters[1]]));
      const inferred = tryInfer(new SArray(values), 'values', false);
      return inferred && inferred.parameters.length ? new SArray(values, inferred) : new SArray(values);
    }
    case 'union()': case 'intersection()': case 'subtracting()': case 'symmetricDifference()':
    case 'isSubset()': case 'isSuperset()': case 'isStrictSubset()': case 'isStrictSuperset()': case 'isDisjoint()': {
      if (!isSet(receiver)) throw SwiftalkError.unknownMember(`${typeName(receiver)}.${name}()`);
      if (args.length !== 1) throw SwiftalkError.type(`.${name} takes one argument: a Set, or any Sequence`);
      const other = yield* setElements(args[0]);
      const s = receiver;
      const subset = (x: SSet, y: SSet) => x.values().every((e) => y.has(e));
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
      if (!isDictionary(receiver)) throw SwiftalkError.unknownMember(`${typeName(receiver)}.${name}()`);
      throw SwiftalkError.type(`.${name} is a property, as in Swift — d.${name}, not d.${name}()`);
    case 'has()':
      if (!isDictionary(receiver)) throw SwiftalkError.unknownMember(`${typeName(receiver)}.has()`);
      if (args.length !== 1) throw SwiftalkError.type('.has(key) takes exactly one argument');
      return receiver.has(args[0]);
    default: throw unknown();
  }
}
