// The evaluator — Eval.swift's execute/evaluate/apply/assign, as
// GENERATORS: every function that can run swiftalk code is a `function*`
// invoked with `yield*`, so that a suspension (await, yield, sleep — the
// scheduler's business) can unwind and resume the whole interpreter stack.
// A yielded value is a suspension request; the driver in interpreter.js
// handles it. Pure helpers stay plain functions.
import { SwiftalkError } from './errors.js';
import { TypeAnnotation } from './parser.js';
import { kindOf, typeName, equals, keyOf, sourceString, graphemes, SArray, SDictionary, SSet, Byte, SData, SDate, SRange, TupleValue,
  INT64_MAX, INT64_MIN, fits64, compareStrings, must,
  isBool, isInt, isDouble, isString, isArray, isDictionary, isSet, isByte, isData, isDate, isRange, isTuple, isFunction, isSequence, isTask, isEnumCase, isStructValue, isHost } from './value.js';
import { FunctionObject, EnumType, EnumCaseValue, StructType, StructValue, SequenceObject, TaskObject, ControlFlow, ReturnSignal, ContextObject, HostValue, isGenerator } from './objects.js';
import type { ComputedMember, StaticThunk, G, Puller } from './objects.js';
import type { Value, LabeledArg } from './value.js';
import type { Expr, Stmt, LValue, Pattern, Condition, CasePattern, Clause, FunctionExpr, Computed, Property, Statics, Arg } from './parser.js';
import type { ModuleSystem } from './modules.js';
import type { Interpreter } from './interpreter.js';

export type { G } from './objects.js';
type MethodExpr = Extract<Expr, { k: 'method' }>;

/// `Context()` (round 237): a copy of the file scope the call sits in, with an `eval` of its own
export function makeContextObject(env: Environment): ContextObject {
  const scope = env.fileScope().copy();
  scope.removeBinding('eval');
  if (scope.evalInstaller) scope.evalInstaller(scope);
  return new ContextObject(scope, false);
}
export function makeContext(env: Environment): HostValue {
  return new HostValue(makeContextObject(env), must(Builtins.types.get('Context'), 'the Context type'));
}
import { Environment, Binding } from './env.js';
import { Builtins, power, isResult, success, failure } from './builtins.js';
import { ann, checkValue, inferLock, stamp, admits, containerStamp, knownElementLock, stampedArray, tryInfer, annotationOfType,
  typeValue, typeValueForParameter, optionalType, resolveTypeNames, annotationIsKnown, resolveEnumAnnotation, isUserType, callBuiltin } from './types.js';
import { method, convert, asksCanonical, userConversion, plainValues } from './members.js';

export const calleeKey = '@callee';
export const scheduler: { current: Interpreter | null; modules: ModuleSystem | null } = { current: null, modules: null };   // installed by interpreter.js while an eval runs

// ---- printing that may run swiftalk (a type's own String member) ----
export function* valueSourceText(value: Value): G<string> {
  const owned = new Map<Value, string>();
  const walk = function* (v: Value): G<void> {
    const m = userConversion(v, 'String');
    if (m) {
      const [bound] = boundMethod(m, v);
      const s = yield* apply(bound, []);
      if (typeof s !== 'string') throw SwiftalkError.type(`${typeName(v)}.String() must return a String`);
      owned.set(v, s);
      return;                                  // the member speaks for the whole subtree
    }
    if (isArray(v)) for (const x of v.items) yield* walk(x);
    else if (isSet(v)) for (const x of v.values()) yield* walk(x);
    else if (isDictionary(v)) for (const [k, x] of v.entries()) { yield* walk(k); yield* walk(x); }
    else if (isTuple(v)) for (const x of v.values) yield* walk(x);
    else if (isStructValue(v)) for (const x of v.values.values()) yield* walk(x);
    else if (isEnumCase(v)) for (const x of v.associated) yield* walk(x);
  };
  yield* walk(value);
  if (owned.size === 0) return sourceString(value);
  return sourceString(value, false, (v) => owned.get(v) ?? null);
}
export function* displayString(value: Value): G<string> {
  if (typeof value === 'string') return value;
  return yield* valueSourceText(value);
}

export function* regexLiteral(pattern: string, flags: string, env: Environment): G<Value> {
  const t = env.tryLookup('Regex');
  if (!isFunction(t) || t.role.k !== 'type' || t.role.name !== 'Regex' || !t.builtin) {
    throw SwiftalkError.type(`/${pattern}/${flags}: a regex literal needs the Regex module — import from "Regex" (the CLI preimports it)`);
  }
  return yield* callBuiltin(t.builtin, [pattern, flags]);
}

/// `123n` (round 201): the BigInt module's — the `BigInt` type in scope is
/// called with the digits; without it, an error naming the module.
export function* bigintLiteral(text: string, env: Environment): G<Value> {
  const t = env.tryLookup('BigInt');
  if (!isFunction(t) || t.role.k !== 'type' || t.role.name !== 'BigInt' || !t.builtin) {
    throw SwiftalkError.type(`${text}n: a BigInt literal needs the BigInt module — import from "BigInt" (the CLI preimports it)`);
  }
  return yield* callBuiltin(t.builtin, [text]);
}

// ---- statements ----
export function* execute(statement: Stmt, env: Environment, relaxed = false): G<Value> {
  switch (statement.k) {
    case 'expression': return yield* evaluate(statement.expr, env);
    case 'return': throw new ReturnSignal(statement.expr ? yield* evaluate(statement.expr, env) : null);
    case 'break': throw new ControlFlow('break', statement.label);
    case 'continue': throw new ControlFlow('continue', statement.label);
    default: return yield* executeSlow(statement, env, relaxed);
  }
}

function* executeSlow(s: Stmt, env: Environment, relaxed: boolean): G<Value> {
  switch (s.k) {
    case 'declaration': {
      const annotation = s.annotation ? resolveTypeNames(s.annotation, env) : null;
      const annotatedEnum = annotation ? resolveEnumAnnotation(annotation, env) : null;
      let value: Value;
      const init = s.initializer;
      if (init.k === 'memberLiteral' && init.name === 'todo' && (annotation === null || annotation.name === 'Function')) {
        value = Builtins.todo;
      } else if (annotatedEnum && init.k === 'memberLiteral') {
        value = constructEnumCase(annotatedEnum, init.name, [], false);
      } else if (annotatedEnum && init.k === 'call' && init.callee.k === 'memberLiteral') {
        value = constructEnumCase(annotatedEnum, init.callee.name, yield* evaluateArgs(init.args, env), true);
      } else {
        value = yield* evaluate(init, env);
      }
      if (s.name === '_') {
        if (annotation) env.check(value, annotation, s.name);
        return value;
      }
      let lock: TypeAnnotation;
      if (annotation) {
        if (!(annotationIsKnown(annotation, env) || annotatedEnum)) throw SwiftalkError.type(`unknown type '${annotation.display}'`);
        lock = annotation;
      } else {
        lock = inferLock(value, s.name);
      }
      env.check(value, lock, s.name);
      env.declare(s.name, new Binding(s.mutable, lock, value));
      return value;
    }
    case 'destructure': {
      const value = yield* evaluate(s.initializer, env);
      bind(s.pattern, value, s.mutable, env, true);
      return value;
    }
    case 'compoundAssignment': {
      const { target, op, expr } = s;
      if (op === '??') {
        return yield* assign(target, null, env, function* (old: Value) {
          if (isDictionary(old)) return coalesceDictionaries(old, yield* evaluate(expr, env), '??=');
          return isAbsent(old) ? yield* evaluate(expr, env) : old;
        });
      }
      if (op === '!!') {
        const rhs = yield* evaluate(expr, env);
        // d[k] !!= v (round 211): an existing entry is overridden, a missing key is not created — the key evaluated once
        let where: LValue = target;
        if (target.k === 'index') {
          const key = yield* evaluate(target.index, env);
          where = { k: 'index', base: target.base, index: { k: 'literal', v: key } };
          const container = yield* readPath(target.base, env);
          if (isDictionary(container) && !container.has(key)) return null;
        }
        return yield* assign(where, null, env, function* (old: Value) {
          if (isDictionary(rhs)) return coalesceDictionaries(rhs, old, '!!=');
          return isAbsent(rhs) ? old : rhs;
        });
      }
      if (op === '^^') {
        const rhs = yield* evaluate(expr, env);
        return yield* assign(target, null, env, function* (old: Value) {
          if (typeof old !== 'boolean' || typeof rhs !== 'boolean') throw SwiftalkError.type("'^^=' takes Bools — nothing is truthy (§3b)");
          return old !== rhs;
        });
      }
      if (op === '&&' || op === '||') {
        const name = op + '=';
        return yield* assign(target, null, env, function* (old: Value) {
          if (typeof old !== 'boolean') throw SwiftalkError.type(`'${name}' takes a Bool target, not ${typeName(old)} — nothing is truthy (§3b)`);
          if ((op === '&&') !== old) return old;
          const rhs = yield* evaluate(expr, env);
          if (typeof rhs !== 'boolean') throw SwiftalkError.type(`'${name}' takes a Bool — nothing is truthy (§3b)`);
          return rhs;
        });
      }
      const rhs = yield* evaluate(expr, env);
      if (op === '**') return yield* assign(target, rhs, env, function* (old: Value) { return yield* power(old, rhs); });
      if (op.startsWith('+') && op.length === 2) return yield* assign(target, rhs, env, function* (old: Value) { return yield* bitwise(op, old, rhs); });
      return yield* assign(target, rhs, env, function* (old: Value) { return yield* binary(op, old, rhs); });
    }
    case 'assignment': {
      const value = yield* evaluate(s.expr, env);
      if (relaxed) yield* assignRelaxed(s.target, value, env);
      else yield* assign(s.target, value, env);
      return value;
    }
    case 'whileLet': {
      for (;;) {
        const scope = new Environment(env);
        if (!(yield* conditionsHold(s.conditions, scope))) break;
        if (!(yield* runLoopBody(s.body, scope, false, s.label))) break;
      }
      return null;
    }
    case 'while': {
      for (;;) {
        const flag = yield* evaluate(s.condition, env);
        if (typeof flag !== 'boolean') throw SwiftalkError.type("the 'while' condition must be a Bool — nothing is truthy (§3b)");
        if (!flag) break;
        if (!(yield* runLoopBody(s.body, env, true, s.label))) break;
      }
      return null;
    }
    case 'repeat': {
      for (;;) {
        if (!(yield* runLoopBody(s.body, env, true, s.label))) break;
        const flag = yield* evaluate(s.condition, env);
        if (typeof flag !== 'boolean') throw SwiftalkError.type("the 'repeat' condition must be a Bool — nothing is truthy (§3b)");
        if (!flag) break;
      }
      return null;
    }
    case 'import': {
      if (!env.isFileScope) throw SwiftalkError.type("import belongs at a file's top level");
      const modules = scheduler.modules;
      if (!modules) throw SwiftalkError.type('import needs a running Interpreter');
      const module = yield* modules.load(s.spec);
      const names = s.namespace === null && s.names.length === 0 ? module.names : s.names;
      // idempotent (round 202): a name already bound to this very value is skipped; to anything else, the usual error
      const bind = (name: string, value: Value, lock: TypeAnnotation) => {
        const existing = env.tryLookup(name);
        if (existing !== undefined && equals(existing, value)) return;
        env.declare(name, new Binding(false, lock, value));
      };
      if (s.namespace !== null) {
        const type = modules.namespaceType(module, s.namespace);
        bind(s.namespace, must(type.constructor_, `${s.namespace}'s namespace type`), ann('Function'));
      }
      for (const name of names) {
        const index = module.names.indexOf(name);
        if (index < 0) throw SwiftalkError.type(`module '${s.spec}' exports no '${name}'` + (module.names.length ? ` — it exports ${module.names.join(', ')}` : ''));
        const value = module.values[index];
        bind(name, value, ann(typeName(value), true));
      }
      return null;
    }
    case 'export': {
      if (!env.isFileScope) throw SwiftalkError.type("export belongs at a file's top level");
      if (s.declaration) yield* execute(s.declaration, env);
      for (const name of s.names) {
        env.lookup(name);
        if (!env.exports.includes(name)) env.exports.push(name);
      }
      return null;
    }
    case 'for': {
      const it = yield* iteratorOf(yield* evaluate(s.sequence, env));
      for (;;) {
        const element = yield* it.next();
        if (element === undefined) break;
        const scope = new Environment(env);
        bind(s.pattern, element, false, scope, false);
        if (s.condition) {
          const keep = yield* evaluate(s.condition, scope);
          if (typeof keep !== 'boolean') throw SwiftalkError.type("a 'where' clause must be a Bool — nothing is truthy (§3b)");
          if (!keep) continue;
        }
        if (!(yield* runLoopBody(s.body, scope, false, s.label))) break;
      }
      return null;
    }
    case 'break': throw new ControlFlow('break', s.label);
    case 'continue': throw new ControlFlow('continue', s.label);
    case 'return': throw new ReturnSignal(s.expr ? yield* evaluate(s.expr, env) : null);
    case 'yield': {
      const value = s.expr ? yield* evaluate(s.expr, env) : null;
      // dynamic yield (round 52): the innermost running coroutine takes it
      const handled = yield { suspend: 'yield', value };
      if (!handled || !('coroutine' in handled) || !handled.coroutine) throw SwiftalkError.type("'yield' outside a coroutine — wrap the function: Sequence(f)");
      return null;
    }
    case 'enumDecl': {
      const cases = new Map<string, { label: string | null; typeName: string | null }[]>();
      for (const [caseName, payloads] of s.cases) {
        cases.set(caseName, payloads.map((p) => (p.typeName === null ? p : { label: p.label, typeName: resolveTypeNames(ann(p.typeName), env).name })));
      }
      const et = new EnumType(s.name, s.caseOrder, cases);
      const constructor = new FunctionObject([], [], env,
        () => { throw SwiftalkError.type(`construct ${s.name} via a case: ${s.name}.${s.caseOrder[0] ?? 'someCase'}`); }, { k: 'enumType', type: et });
      et.constructor_ = constructor;
      const typeEnv = typeScope(env, constructor);
      et.methods = makeMethods(s.methods, typeEnv);
      mergeStatics(installStatics(s.statics, typeEnv, et, s.name, false), et);
      env.declare(s.name, new Binding(false, ann('Function'), constructor));
      return constructor;
    }
    case 'structDecl': {
      const properties = new Map<string, Property>();
      for (const [key, prop] of s.properties) {
        properties.set(key, { ...prop, annotation: prop.annotation ? resolveTypeNames(prop.annotation, env) : null });
      }
      const st = new StructType(s.name, s.propertyOrder, properties, env);
      const constructor = new FunctionObject([], [], env, null, { k: 'structType', type: st });
      st.constructor_ = constructor;
      const typeEnv = typeScope(env, constructor);
      st.methods = makeMethods(s.methods, typeEnv);
      st.computed = makeComputed(s.computed, typeEnv);
      st.observers = makeObservers(s.propertyOrder, properties, typeEnv);
      st.inits = s.inits.filter((f) => f.k === 'function').map((f) => new FunctionObject(f.parameters, f.body, typeEnv));
      mergeStatics(installStatics(s.statics, typeEnv, st, s.name, false), st);
      env.declare(s.name, new Binding(false, ann('Function'), constructor));
      return constructor;
    }
    case 'extensionDecl': {
      const f = env.tryLookup(s.typeName);
      if (!isFunction(f)) throw SwiftalkError.type(`unknown type '${s.typeName}'`);
      const typeEnv = typeScope(env, f);
      const fns = makeMethods(s.methods, typeEnv);
      const overwrite = env.redefining;
      switch (f.role.k) {
        case 'structType': {
          const st = f.role.type;
          for (const [name, fn] of fns) {
            if (st.properties.has(name) || !(overwrite || (!st.methods.has(name) && !st.computed.has(name)))) throw SwiftalkError.type(`${s.typeName} already has a member '${name}'`);
            st.computed.delete(name);
            st.methods.set(name, fn);
          }
          for (const [name, c] of makeComputed(s.computed, typeEnv)) {
            if (st.properties.has(name) || !(overwrite || (!st.methods.has(name) && !st.computed.has(name)))) throw SwiftalkError.type(`${s.typeName} already has a member '${name}'`);
            st.methods.delete(name);
            st.computed.set(name, c);
          }
          mergeStatics(installStatics(s.statics, typeEnv, st, s.typeName, overwrite), st);
          break;
        }
        case 'enumType': {
          const et = f.role.type;
          if (s.computed.size) throw SwiftalkError.type('computed properties on enums are not (yet) supported');
          for (const [name, fn] of fns) {
            if (et.cases.has(name) || !(overwrite || !et.methods.has(name))) throw SwiftalkError.type(`${s.typeName} already has a member '${name}'`);
            et.methods.set(name, fn);
          }
          for (const name of s.statics.lets.keys()) if (et.cases.has(name)) throw SwiftalkError.type(`${s.typeName} has a case '${name}' — a static may not share its name`);
          mergeStatics(installStatics(s.statics, typeEnv, et, s.typeName, overwrite), et);
          break;
        }
        case 'type': case 'protocol': {
          const n = f.role.name;
          if (s.statics.ops.size) throw SwiftalkError.type(`operators are implemented on structs and enums, not on ${n} (round 146)`);
          const store = env.root;
          for (const [name, expr] of s.statics.lets) {
            if (overwrite) { store.removeBinding(`@ext:${n}:static:${name}`); store.removeBinding(`@ext:${n}:static:get:${name}`); }
            store.declare(`@ext:${n}:static:${name}`, new Binding(false, ann('Any', true), yield* evaluate(expr, typeEnv)));
          }
          for (const [name, spec] of s.statics.vars) {
            if (spec.get.k !== 'function') continue;
            if (overwrite) { store.removeBinding(`@ext:${n}:static:${name}`); store.removeBinding(`@ext:${n}:static:get:${name}`); }
            store.declare(`@ext:${n}:static:get:${name}`, new Binding(false, ann('Function'), new FunctionObject(spec.get.parameters, spec.get.body, typeEnv)));
          }
          for (const [name, c] of makeComputed(s.computed, typeEnv)) {
            if (c.set) throw SwiftalkError.type(`a computed setter on a builtin type is not (yet) supported — ${n}.${name}`);
            if (overwrite) store.removeBinding(`@ext:${n}:get:${name}`);
            store.declare(`@ext:${n}:get:${name}`, new Binding(false, ann('Function'), c.get));
          }
          for (const [name, fn] of fns) {
            if (overwrite) store.removeBinding(`@ext:${n}:${name}`);
            store.declare(`@ext:${n}:${name}`, new Binding(false, ann('Function'), fn));
          }
          break;
        }
        default: throw SwiftalkError.type(`'${s.typeName}' is not a type`);
      }
      return null;
    }
    default: throw SwiftalkError.type(`FIXME: statement ${s.k} is not ported`);
  }
}

// ---- switch ----
function* evaluateSwitch(subjectExpr: Expr, clauses: Clause[], defaultBody: Stmt[] | null, env: Environment): G<Value> {
  const subject = yield* evaluate(subjectExpr, env);
  for (const clause of clauses) {
    for (const { pattern, condition } of clause.patterns) {
      const scope = new Environment(env);
      if (!(yield* match(pattern, subject, scope))) continue;
      if (condition) {
        const flag = yield* evaluate(condition, scope);
        if (typeof flag !== 'boolean') throw SwiftalkError.type("a 'where' guard must be a Bool — nothing is truthy (§3b)");
        if (!flag) continue;
      }
      return yield* runBlock(clause.body, scope);
    }
  }
  if (defaultBody) return yield* runBlock(defaultBody, env);
  throw SwiftalkError.type(`switch is not exhaustive — nothing matches ${sourceString(subject)}`);
}
function* match(pattern: CasePattern, subject: Value, scope: Environment): G<boolean> {
  switch (pattern.k) {
    case 'wildcard': return true;
    case 'expr': {
      const v = yield* evaluate(pattern.e, scope);
      if (equals(v, subject)) return true;
      if (isRange(v) && isInt(subject)) {
        if (v.from <= subject && (v.to === null || (v.closed ? subject <= v.to : subject < v.to))) return true;
      }
      if (isHost(v)) return (yield* hostPattern(v, subject, false)) !== null;
      return false;
    }
    case 'enumCase': return subject instanceof EnumCaseValue && subject.caseName === pattern.name;
    case 'binding': {
      let value: Value | null;
      if (pattern.source.k === 'member') {
        const caseName = pattern.source.name;
        if (!(subject instanceof EnumCaseValue) || !subject.type.cases.has(caseName)) throw SwiftalkError.type(`case .${caseName}: ${typeName(subject)} has no such case`);
        value = caseAccessor(subject, caseName, subject);
      } else {
        const h = yield* evaluate(pattern.source.e, scope);
        if (!isHost(h)) throw SwiftalkError.type('a case binds from a case of the subject (case r = .circle) or a Regex (case m = /re/)');
        value = yield* hostPattern(h, subject, true);
      }
      if (value === null) return false;
      bind(pattern.pattern, value, pattern.mutable, scope, false);
      return true;
    }
    default: return false;
  }
}
function* hostPattern(h: HostValue, subject: Value, binding: boolean): G<Value> {
  return h.object.patternMatch ? h.object.patternMatch(subject, binding) : null;
}
export function caseAccessor(ev: EnumCaseValue, name: string, receiver: Value): Value | null {
  if (ev.caseName !== name) return null;
  switch (ev.associated.length) {
    case 0: return receiver;
    case 1: return ev.associated[0];
    default: return new TupleValue(ev.associated, (ev.type.cases.get(ev.caseName) ?? []).map((p) => p.label));
  }
}
export function constructEnumCase(et: EnumType, caseName: string, args: LabeledArg[], called: boolean): EnumCaseValue {
  const params = et.cases.get(caseName);
  if (!params) throw SwiftalkError.unknownMember(`${et.name}.${caseName}`);
  if (!called || params.length === 0) {
    if (params.length) throw SwiftalkError.type(`${et.name}.${caseName} has associated values — call it`);
    if (args.length) throw SwiftalkError.type(`${et.name}.${caseName} takes no associated values`);
    return new EnumCaseValue(et, caseName, []);
  }
  if (args.length !== params.length) throw SwiftalkError.type(`${et.name}.${caseName} takes ${params.length} associated value(s), got ${args.length}`);
  const slots: (Value | undefined)[] = new Array(params.length).fill(undefined);
  for (const a of args) if (a.label !== null) {
    const index = params.findIndex((p) => p.label === a.label);
    if (index < 0) throw SwiftalkError.type(`unknown label '${a.label}' for ${et.name}.${caseName}`);
    if (slots[index] !== undefined) throw SwiftalkError.type(`duplicate label '${a.label}'`);
    slots[index] = a.value;
  }
  const positionals = args.filter((a) => a.label === null).map((a) => a.value);
  const associated = slots.map((slot, index) => {
    let value: Value;
    const next = positionals.shift();
    if (slot !== undefined) value = slot;
    else if (next !== undefined) value = next;
    else throw SwiftalkError.type('missing associated value');
    const expected = params[index].typeName;
    if (expected !== null && typeName(value) !== expected) throw SwiftalkError.type(`${et.name}.${caseName} expects ${expected}, got ${typeName(value)}`);
    return value;
  });
  return new EnumCaseValue(et, caseName, associated);
}

export function containsSubstring(haystack: string, needle: string): boolean {
  if (needle === '') return true;
  const h = graphemes(haystack), n = graphemes(needle);
  if (n.length > h.length) return false;
  outer: for (let start = 0; start + n.length <= h.length; start++) {
    if (h[start] !== n[0]) continue;
    for (let i = 1; i < n.length; i++) if (h[start + i] !== n[i]) continue outer;
    return true;
  }
  return false;
}

export function* runBlock(body: Stmt[], env: Environment): G<Value> {
  const scope = new Environment(env);
  let last: Value = null;
  for (const statement of body) last = yield* execute(statement, scope);
  return last;
}
function* conditionsHold(conditions: Condition[], scope: Environment): G<boolean> {
  for (const c of conditions) {
    switch (c.k) {
      case 'binding': {
        const value = yield* evaluate(c.expr, scope);
        if (value === null) return false;
        bind(c.pattern, value, c.mutable, scope, false);
        break;
      }
      case 'boolean': {
        const flag = yield* evaluate(c.expr, scope);
        if (typeof flag !== 'boolean') throw SwiftalkError.type("an 'if'/'while' condition must be a Bool — nothing is truthy (§3b)");
        if (!flag) return false;
        break;
      }
      case 'variable': {
        const v = scope.lookup(c.name);
        if (typeof v === 'boolean') { if (!v) return false; }
        else if (v === null) return false;
        break;
      }
      default: break;
    }
  }
  return true;
}
function* runLoopBody(body: Stmt[], env: Environment, freshScope = true, label: string | null = null): G<boolean> {
  const scope = freshScope ? new Environment(env) : env;
  try {
    for (const statement of body) yield* execute(statement, scope);
  } catch (e) {
    if (e instanceof ControlFlow && (e.label === null || e.label === label)) return e.kind === 'continue';
    throw e;
  }
  return true;
}

// ---- iteration ----
export class ValueIterator {
  nextImpl: () => G<Value | undefined>;
  constructor(next: () => G<Value | undefined>) { this.nextImpl = next; }
  *next(): G<Value | undefined> { return yield* this.nextImpl(); }         // undefined ends the sequence
}
const plainIter = (arr: Value[]): ValueIterator => { let i = 0; return new ValueIterator(function* () { return i < arr.length ? arr[i++] : undefined; }); };
export function isSequenceValue(v: Value): boolean { return must(Builtins.conformance.get('Sequence'), 'the Sequence conformance').has(typeName(v)); }
export function* iteratorOf(sequence: Value): G<ValueIterator> {
  if (isArray(sequence)) return plainIter(sequence.items);
  if (isString(sequence)) return plainIter(graphemes(sequence));
  if (isSet(sequence)) return plainIter(sequence.values());
  if (isDictionary(sequence)) return plainIter(sequence.entries().map(([k, v]) => new TupleValue([k, v], ['key', 'value'])));
  if (isRange(sequence)) {
    const { from, to, closed } = sequence;
    if (to === null) return countingIterator(from);
    let current = from, exhausted = false;
    return new ValueIterator(function* () {
      if (exhausted) return undefined;
      if (closed) { const v = current; if (current === to) exhausted = true; else current += 1n; return v; }
      if (!(current < to)) { exhausted = true; return undefined; }
      return current++;
    });
  }
  if (isSequence(sequence)) return makeIterator(sequence);
  if (isTuple(sequence)) return plainIter(sequence.values);
  if (isData(sequence)) return plainIter(Array.from(sequence.bytes, (b) => new Byte(b)));
  throw SwiftalkError.type(`cannot iterate a ${typeName(sequence)}`);
}
function countingIterator(from: bigint): ValueIterator {
  let current: bigint | null = from;
  return new ValueIterator(function* () {
    if (current === null) throw SwiftalkError.overflow('this Range ran past Int.max');
    const v = current;
    current = v === INT64_MAX ? null : v + 1n;
    return v;
  });
}
export function requireFinite(value: Value, member: string): void {
  if (isRange(value) && value.to === null) throw SwiftalkError.type(`an unbounded Range is infinite — .prefix(n) or .prefix { } it before .${member}`);
}
export function lazyBase(receiver: Value): SequenceObject | null {
  if (isSequence(receiver)) return receiver;
  if (isRange(receiver) && receiver.to === null) return new SequenceObject({ kind: 'counting', from: receiver.from });
  return null;
}
export function restamp(result: Value, receiver: Value): Value {
  let stampAnn = containerStamp(receiver);
  if (!stampAnn) { const known = knownElementLock(receiver); if (known) stampAnn = ann('Array', false, [known]); }
  if (!stampAnn) return result;
  if (isArray(result) && result.lock === null && stampAnn.name === 'Array') return new SArray(result.items, stampAnn);
  if (isSet(result) && result.lock === null && stampAnn.name === 'Set') return new SSet(result.values(), stampAnn);
  if (isDictionary(result) && result.lock === null && stampAnn.name === 'Dictionary') return new SDictionary(result.entries(), stampAnn);
  return result;
}
export function reshape(kept: Value[], receiver: Value): Value {
  if (isString(receiver)) return kept.map((x) => (isString(x) ? x : '')).join('');
  if (isData(receiver)) return new SData(kept.flatMap((x) => (isByte(x) ? [x.v] : (isInt(x) && x >= 0n && x <= 255n) ? [Number(x)] : [])));
  if (isDictionary(receiver)) return new SDictionary(kept.filter((p): p is TupleValue => isTuple(p) && p.count === 2).map((p): [Value, Value] => [p.values[0], p.values[1]]));
  if (isSet(receiver)) return new SSet(kept);
  return new SArray(kept);
}
export function* holds(fn: FunctionObject, element: Value, member: string): G<boolean> {
  const flag = yield* apply(fn, [{ label: null, value: element }]);
  if (typeof flag !== 'boolean') throw SwiftalkError.type(`the .${member} Function must return a Bool`);
  return flag;
}
export function* collect(sequence: Value): G<Value[]> {
  requireFinite(sequence, 'Array()');
  const out: Value[] = [];
  const it = yield* iteratorOf(sequence);
  for (;;) { const e = yield* it.next(); if (e === undefined) break; out.push(e); }
  return out;
}
function makeIterator(seq: SequenceObject): ValueIterator {
  const k = seq.k;
  switch (k.kind) {
    case 'generator': {
      let state: Value[] = k.initial, done = false;
      return new ValueIterator(function* () {
        if (done) return undefined;
        const { result, local } = yield* run(k.next, state);
        if (result === null) { done = true; return undefined; }
        const next = local.lookup('$');
        if (!isArray(next)) throw SwiftalkError.type("a Sequence generator's '$' must stay an Array");
        state = next.items;
        return result;
      });
    }
    case 'coroutine': return coroutineIterator(k.body);
    case 'enumerated': {
      const it = makeIterator(k.base);
      let index = 0n;
      return new ValueIterator(function* () {
        const e = yield* it.next();
        if (e === undefined) return undefined;
        return new TupleValue([index++, e], ['key', 'value']);
      });
    }
    case 'mapped': {
      const it = makeIterator(k.base);
      return new ValueIterator(function* () {
        const e = yield* it.next();
        if (e === undefined) return undefined;
        return yield* apply(k.fn, [{ label: null, value: e }]);
      });
    }
    case 'filtered': {
      const it = makeIterator(k.base);
      return new ValueIterator(function* () {
        for (;;) {
          const e = yield* it.next();
          if (e === undefined) return undefined;
          const keep = yield* apply(k.fn, [{ label: null, value: e }]);
          if (typeof keep !== 'boolean') throw SwiftalkError.type('the .filter Function must return a Bool');
          if (keep) return e;
        }
      });
    }
    case 'counting': return countingIterator(k.from);
    case 'native': {
      // a module's Sequence (round 191): `make` builds a puller on the first pull; either may be a generator
      let next: Puller | null = null;
      return new ValueIterator(function* () {
        if (!next) { const made = k.make(); next = isGenerator(made) ? yield* made : made; }
        const r = yield* next();
        return r === null || r === undefined ? undefined : r;
      });
    }
    case 'takenWhile': {
      const it = makeIterator(k.base);
      let done = false;
      return new ValueIterator(function* () {
        if (done) return undefined;
        const e = yield* it.next();
        if (e === undefined || !(yield* holds(k.fn, e, 'prefix { }'))) { done = true; return undefined; }
        return e;
      });
    }
    case 'dropped': {
      const it = makeIterator(k.base);
      let skipped = false;
      return new ValueIterator(function* () {
        if (!skipped) { skipped = true; for (let i = 0; i < k.n; i++) if ((yield* it.next()) === undefined) return undefined; }
        return yield* it.next();
      });
    }
    case 'droppedWhile': {
      const it = makeIterator(k.base);
      let dropping = true;
      return new ValueIterator(function* () {
        for (;;) {
          const e = yield* it.next();
          if (e === undefined) return undefined;
          if (dropping) { if (yield* holds(k.fn, e, 'dropFirst { }')) continue; dropping = false; }
          return e;
        }
      });
    }
    default: { const unported: never = k; throw SwiftalkError.type(`FIXME: sequence kind ${String(unported)}`); }
  }
}
/// Coroutine sequences (round 52): the body runs as its own generator; a
/// `yield` statement inside surfaces as a {suspend:'yield'} request that
/// this iterator answers, resuming the body on the next pull.
function coroutineIterator(body: FunctionObject): ValueIterator {
  let gen: G<unknown> | null = null, done = false;
  return new ValueIterator(function* () {
    if (done) return undefined;
    if (!gen) gen = run(body, []);
    let step = gen.next({ coroutine: true });
    for (;;) {
      if (step.done) { done = true; return undefined; }
      const request = step.value;
      if (request && request.suspend === 'yield') return request.value;
      // another suspension (await, sleep) inside the body: hand it up, feed the answer back
      const answer = yield request;
      step = gen.next(answer);
    }
  });
}
export function rangeCount(from: bigint, to: bigint, closed: boolean): bigint {
  const span = to - from;
  if (!fits64(span) || (closed && span === INT64_MAX)) throw SwiftalkError.overflow("this Range's count does not fit in an Int");
  return closed ? span + 1n : span;
}

// ---- expressions ----
export function* evaluate(expr: Expr, env: Environment): G<Value> {
  switch (expr.k) {
    case 'regexLiteral': return yield* regexLiteral(expr.pattern, expr.flags, env);
    case 'bigintLiteral': return yield* bigintLiteral(expr.text, env);
    case 'literal': return expr.v;
    case 'variable': return env.lookup(expr.name);
    case 'binary': return yield* binary(expr.op, yield* evaluate(expr.lhs, env), yield* evaluate(expr.rhs, env));
    case 'bitwise': return yield* bitwise(expr.op, yield* evaluate(expr.lhs, env), yield* evaluate(expr.rhs, env));
    case 'bitNot': return yield* bitNot(yield* evaluate(expr.e, env));
    case 'comparison': return yield* compare(expr.op, yield* evaluate(expr.lhs, env), yield* evaluate(expr.rhs, env));
    case 'ternary': {
      const flag = yield* evaluate(expr.condition, env);
      if (typeof flag !== 'boolean') throw SwiftalkError.type("the '?:' condition must be a Bool — nothing is truthy (§3b)");
      return yield* evaluate(flag ? expr.a : expr.b, env);
    }
    case 'call': {
      const callee = expr.callee;
      if (callee.k === 'memberLiteral') {
        const name = callee.name;
        const resultCase = Builtins.resultType.cases.has(name);
        if (env.tryLookup('self') !== undefined) {
          try {
            return yield* evaluateSlow({ k: 'method', receiver: { k: 'variable', name: 'self' }, name, args: expr.args, called: true }, env);
          } catch (e) {
            if (!(e instanceof SwiftalkError && e.kind === 'unknownMember' && resultCase)) throw e;
          }
        }
        const f = env.tryLookup(name);
        if (isFunction(f) && ['type', 'protocol', 'enumType', 'structType'].includes(f.role.k)) {
          return yield* apply(f, yield* evaluateArgs(expr.args, env));
        }
        if (resultCase) return constructEnumCase(Builtins.resultType, name, yield* evaluateArgs(expr.args, env), true);
      }
      const fn = yield* evaluate(callee, env);
      if (!isFunction(fn)) throw SwiftalkError.type(`cannot call a ${typeName(fn)}`);
      // Round 237: Context() copies the top level it is made in, so it is built here, where the scope is known
      if (fn === Builtins.types.get('Context')) {
        if (expr.args.length) throw SwiftalkError.type('Context() takes no arguments — it copies the top level it is made in');
        return makeContext(env);
      }
      return yield* apply(fn, yield* evaluateArgs(expr.args, env));
    }
    case 'selfCall': {
      const fn = env.tryLookup(calleeKey);
      if (!isFunction(fn)) throw SwiftalkError.type("'$()' recurses — it only works inside a function");
      return yield* apply(fn, yield* evaluateArgs(expr.args, env));
    }
    case 'subscript': return subscriptRead(yield* evaluate(expr.base, env), yield* evaluate(expr.index, env));
    case 'if': {
      if (expr.conditions.length === 1 && expr.conditions[0].k === 'boolean') {
        const flag = yield* evaluate(expr.conditions[0].expr, env);
        if (typeof flag !== 'boolean') throw SwiftalkError.type("the 'if' condition must be a Bool — nothing is truthy (§3b)");
        if (flag) return yield* runBlock(expr.then, env);
        if (expr.else) return yield* runBlock(expr.else, env);
        return null;
      }
      const scope = new Environment(env);
      if (yield* conditionsHold(expr.conditions, scope)) return yield* runBlock(expr.then, scope);
      if (expr.else) return yield* runBlock(expr.else, env);
      return null;
    }
    default: return yield* evaluateSlow(expr, env);
  }
}

function* evaluateSlow(expr: Expr, env: Environment): G<Value> {
  switch (expr.k) {
    case 'switch': return yield* evaluateSwitch(expr.subject, expr.clauses, expr.defaultBody, env);
    case 'if': case 'literal': case 'variable': case 'binary': case 'bitwise': case 'bitNot': case 'comparison': case 'ternary':
    case 'call': case 'selfCall': case 'subscript': case 'regexLiteral': case 'bigintLiteral':
      return yield* evaluate(expr, env);
    case 'tuple': {
      const values: Value[] = [];
      for (const e of expr.elements) values.push(yield* evaluate(e.expr, env));
      return new TupleValue(values, expr.elements.map((e) => e.label));
    }
    case 'array': {
      const values: Value[] = [];
      for (const e of expr.elements) values.push(yield* evaluate(e, env));
      if (values.length === 1) { const element = annotationOfType(values[0]); if (element) return typeValue(ann('Array', false, [element])); }
      return new SArray(values);
    }
    case 'dictionary': {
      const d = new SDictionary([]);
      for (const [ke, ve] of expr.pairs) d.set(yield* evaluate(ke, env), yield* evaluate(ve, env));
      if (expr.pairs.length === 1) {
        const [k, v] = d.entries()[0];
        const key = annotationOfType(k), val = annotationOfType(v);
        if (key && val) return typeValue(ann('Dictionary', false, [key, val]));
      }
      return d;
    }
    case 'unaryMinus': {
      const operand = yield* evaluate(expr.e, env);
      const r = yield* userOperator('prefix:-', [operand]);
      if (r !== undefined) return r;
      if (isInt(operand)) { if (operand === INT64_MIN) throw SwiftalkError.overflow(`negating ${operand}`); return -operand; }
      if (isDouble(operand)) return -operand;
      throw SwiftalkError.type(`cannot negate ${typeName(operand)}`);
    }
    case 'unaryPlus': {
      const v = yield* evaluate(expr.e, env);
      const r = yield* userOperator('prefix:+', [v]);
      if (r !== undefined) return r;
      const k = kindOf(v);
      if (k === 'int' || k === 'double' || k === 'byte') return v;
      throw SwiftalkError.type(`cannot apply prefix + to ${typeName(v)}`);
    }
    case 'power': return yield* power(yield* evaluate(expr.lhs, env), yield* evaluate(expr.rhs, env));
    case 'operatorRef': return operatorFunction(expr.op);
    case 'function': return new FunctionObject(expr.parameters, expr.body, env);
    case 'method': return yield* evaluateMethodCall(expr, env);
    case 'range': {
      const a = yield* evaluate(expr.lhs, env);
      if (typeof a !== 'bigint') throw SwiftalkError.type('Range bounds must be Ints');
      if (expr.rhs === null) return new SRange(a, null, true);
      const b = yield* evaluate(expr.rhs, env);
      if (typeof b !== 'bigint') throw SwiftalkError.type('Range bounds must be Ints');
      if (a > b) throw SwiftalkError.type(`range lower bound ${a} exceeds upper bound ${b}`);
      return new SRange(a, b, expr.op === '...');
    }
    case 'memberLiteral': {
      const selfValue = env.tryLookup('self');
      if (selfValue !== undefined) {
        try { return yield* method(selfValue, expr.name, [], false, env); }
        catch (e) { if (!(e instanceof SwiftalkError && e.kind === 'unknownMember')) throw e; }
      }
      return expr.name;
    }
    case 'await': {
      const value = yield* evaluate(expr.e, env);
      if (!isTask(value)) throw SwiftalkError.type(`can only await a Task — got ${typeName(value)}`);
      return yield* awaitTask(value);
    }
    case 'logicalAnd': {
      const a = yield* evaluate(expr.lhs, env);
      if (typeof a !== 'boolean') throw SwiftalkError.type("'&&' takes Bools — nothing is truthy (§3b)");
      if (!a) return false;
      const b = yield* evaluate(expr.rhs, env);
      if (typeof b !== 'boolean') throw SwiftalkError.type("'&&' takes Bools — nothing is truthy (§3b)");
      return b;
    }
    case 'logicalOr': {
      const a = yield* evaluate(expr.lhs, env);
      if (typeof a !== 'boolean') throw SwiftalkError.type("'||' takes Bools — nothing is truthy (§3b)");
      if (a) return true;
      const b = yield* evaluate(expr.rhs, env);
      if (typeof b !== 'boolean') throw SwiftalkError.type("'||' takes Bools — nothing is truthy (§3b)");
      return b;
    }
    case 'logicalXor': {
      const a = yield* evaluate(expr.lhs, env), b = yield* evaluate(expr.rhs, env);
      if (typeof a !== 'boolean' || typeof b !== 'boolean') throw SwiftalkError.type("'^^' takes Bools — nothing is truthy (§3b)");
      return a !== b;
    }
    case 'logicalNot': {
      const operand = yield* evaluate(expr.e, env);
      const r = yield* userOperator('prefix:!', [operand]);
      if (r !== undefined) return r;
      if (typeof operand !== 'boolean') throw SwiftalkError.type("prefix '!' takes a Bool — nothing is truthy (§3b)");
      return !operand;
    }
    case 'typeSpelling': return typeValueForParameter(resolveTypeNames(expr.annotation, env), env);
    case 'propagate': {
      const v = yield* evaluate(expr.e, env);
      if (isFunction(v) && annotationOfType(v)) return optionalType(v, env);
      const r = yield* userOperator('postfix:?', [v]);
      if (r !== undefined) return r;
      if (v === null) throw new ReturnSignal(null);
      if (isResult(v)) { if (v.caseName !== 'success') throw new ReturnSignal(v); return v.associated[0]; }
      return v;
    }
    case 'forceUnwrap': {
      const v = yield* evaluate(expr.e, env);
      const r = yield* userOperator('postfix:!', [v]);
      if (r !== undefined) return r;
      if (v === null) throw SwiftalkError.type('force-unwrapped nil');
      if (isResult(v)) { if (v.caseName !== 'success') throw SwiftalkError.type(`force-unwrapped a failure: ${sourceString(v.associated[0])}`); return v.associated[0]; }
      return v;
    }
    case 'coalesce': {
      const v = yield* evaluate(expr.lhs, env);
      if (v === null) return yield* evaluate(expr.rhs, env);
      if (isResult(v)) return v.caseName === 'success' ? v.associated[0] : yield* evaluate(expr.rhs, env);
      if (isDictionary(v)) return coalesceDictionaries(v, yield* evaluate(expr.rhs, env), '??');
      return v;
    }
    case 'override': {
      const a = yield* evaluate(expr.lhs, env), b = yield* evaluate(expr.rhs, env);
      if (isDictionary(b)) return coalesceDictionaries(b, a, '!!');
      return isAbsent(b) ? a : b;
    }
    case 'optionalMember': {
      const receiver = yield* evaluate(expr.receiver, env);
      if (receiver === null) return null;
      return yield* evaluateSlow({ k: 'method', receiver: { k: 'literal', v: receiver }, name: expr.name, args: expr.args, called: expr.called }, env);
    }
    case 'interpolation': {
      let out = '';
      for (const part of expr.parts) out += yield* displayString(yield* evaluate(part, env));
      return out;
    }
    default: { const unported: never = expr; throw SwiftalkError.type(`FIXME: expression ${String(unported)} is not ported`); }
  }
}

function* evaluateMethodCall(expr: MethodExpr, env: Environment): G<Value> {
  const { receiver: receiverExpr, name, args: argExprs, called } = expr;
  if (called && (name === 'remove' || name === 'insert' || name === 'merge' || name === 'subtract')) {
    const mutated = yield* mutatingMethod(expr, env);
    if (mutated !== undefined) return mutated;
  }
  const receiver = yield* evaluate(receiverExpr, env);
  const evaluated: LabeledArg[] = [];
  for (const a of argExprs) evaluated.push({ label: a.label, value: yield* evaluate(a.expr, env) });
  if (called) {
    if (name === 'append' && isArray(receiver)) {
      const array = receiver;
      const target = asLValue(receiverExpr);
      if (!target) throw SwiftalkError.type("'.append' mutates — call it on a var Array");
      if (!evaluated.length || !evaluated.every((a) => a.label === null)) throw SwiftalkError.type('.append takes unlabeled item(s)');
      yield* assign(target, new SArray([...array.items, ...evaluated.map((a) => a.value)], array.lock), env);
      return null;
    }
    // Bool mutator (round 276): b.flip() is b = !b; nil, as append is.
    // Round 278: n.flip(i) flips bit i of an Int (0..<64, beyond is the overflow trap) or of a
    // module's integer type, composed from its own operators as n +^ (T(1) +< T(i)).
    if (name === 'flip') {
      const bitIndex = (): bigint => {
        const i = evaluated.length === 1 && evaluated[0].label === null ? evaluated[0].value : undefined;
        if (!isInt(i)) throw SwiftalkError.type('.flip(i) takes one Int, the bit to flip');
        return i;
      };
      if (isBool(receiver)) {
        if (evaluated.length) throw SwiftalkError.type('.flip() takes no arguments on a Bool');
        const target = asLValue(receiverExpr);
        if (!target) throw SwiftalkError.type("'.flip' mutates — call it on a var Bool");
        yield* assign(target, !receiver, env);
        return null;
      }
      if (isInt(receiver)) {
        const i = bitIndex();
        if (i < 0n || i >= 64n) throw SwiftalkError.overflow(`Int.flip(${i}): an Int has bits 0..<64 — a BigInt has no width`);
        const target = asLValue(receiverExpr);
        if (!target) throw SwiftalkError.type("'.flip' mutates — call it on a var Int");
        yield* assign(target, BigInt.asIntN(64, receiver ^ (1n << i)), env);
        return null;
      }
      if (isHost(receiver) && receiver.object.hasOperator?.('infix:+^') && receiver.object.hasOperator?.('infix:+<')) {
        const i = bitIndex();
        if (i < 0n) throw SwiftalkError.type(`${typeName(receiver)}.flip(${i}): a bit index is not negative`);
        const target = asLValue(receiverExpr);
        if (!target) throw SwiftalkError.type(`'.flip' mutates — call it on a var ${typeName(receiver)}`);
        const make = receiver.type;
        const mask = isFunction(make)
          ? yield* userOperator('infix:+<', [yield* apply(make, [{ label: null, value: 1n }]), yield* apply(make, [{ label: null, value: i }])])
          : undefined;
        const flipped = mask === undefined ? undefined : yield* userOperator('infix:+^', [receiver, mask]);
        if (flipped === undefined) throw SwiftalkError.unknownMember(`${typeName(receiver)}.flip()`);
        yield* assign(target, flipped, env);
        return null;
      }
    }
    let userMethod: FunctionObject | null = null;
    if (asksCanonical(name, evaluated)) { /* the interpreter's word */ }
    else if (isStructValue(receiver) || isEnumCase(receiver)) userMethod = receiver.type.methods.get(name) ?? lookupExtension(env, typeName(receiver), name);
    else { const m = lookupExtension(env, typeName(receiver), name); if (m) userMethod = m; }
    if (userMethod) {
      const [bound, selfEnv] = boundMethod(userMethod, receiver, true);
      const result = yield* apply(bound, evaluated);
      // Round 233: a String member's result is a String on this spelling too, not only where the value prints
      if (name === 'String' && typeof result !== 'string') throw SwiftalkError.type(`${typeName(receiver)}.String() must return a String`);
      const newSelf = selfEnv.lookup('self');
      if (!equals(newSelf, receiver) || (isStructValue(receiver) && newSelf !== receiver && keyOf(newSelf) !== keyOf(receiver))) {
        const target = asLValue(receiverExpr);
        if (!target) throw SwiftalkError.type(`method '${name}' mutated a temporary — call it on a var`);
        yield* assign(target, newSelf, env);
      }
      return result;
    }
  }
  return yield* method(receiver, name, evaluated, called, env);
}
function* mutatingMethod(expr: MethodExpr, env: Environment): G<Value | undefined> {
  const { receiver: receiverExpr, name, args: argExprs } = expr;
  const container = yield* evaluate(receiverExpr, env);
  if (name === 'remove') {
    if (argExprs.length !== 1 || argExprs[0].label !== null) throw SwiftalkError.type('.remove(key) takes exactly one unlabeled argument');
    const target = asLValue(receiverExpr);
    if (!target) throw SwiftalkError.type(`cannot mutate an immutable ${typeName(container)} — bind it to a var first`);
    if (isDictionary(container)) {
      const key = yield* evaluate(argExprs[0].expr, env);
      const removed = container.has(key) ? container.get(key) ?? null : null;
      const d = container.clone(); d.delete(key);
      yield* assign(target, d, env);
      return removed;
    }
    if (isSet(container)) {
      const x = yield* evaluate(argExprs[0].expr, env);
      const removed = container.has(x) ? container.map.get(keyOf(x)) ?? null : null;
      const s = container.clone(); s.delete(x);
      yield* assign(target, s, env);
      return removed;
    }
    throw SwiftalkError.unknownMember(`${typeName(container)}.remove()`);
  }
  if (name === 'insert') {
    if (argExprs.length !== 1 || argExprs[0].label !== null) throw SwiftalkError.type('.insert(x) takes exactly one unlabeled argument');
    if (!isSet(container)) throw SwiftalkError.unknownMember(`${typeName(container)}.insert()`);
    const target = asLValue(receiverExpr);
    if (!target) throw SwiftalkError.type("'.insert' mutates — call it on a var Set");
    const x = yield* evaluate(argExprs[0].expr, env);
    const inserted = !container.has(x);
    const s = container.clone(); s.add(x);
    yield* assign(target, s, env);
    return inserted;
  }
  if (name === 'merge') {
    const target = asLValue(receiverExpr);
    if (!target) throw SwiftalkError.type(`'.merge' mutates — call it on a var ${typeName(container)}`);
    const args: LabeledArg[] = [];
    for (const a of argExprs) args.push({ label: a.label === 'uniquingKeysWith' ? null : a.label, value: yield* evaluate(a.expr, env) });
    if (isDictionary(container)) { yield* assign(target, yield* mergeDictionaries(container, plainValues(args, '.merge')), env); return null; }
    if (isSet(container)) {
      const values = plainValues(args, '.merge');
      if (values.length !== 1) throw SwiftalkError.type('Set.merge takes one Set, or any Sequence');
      const s = container.clone();
      for (const e of (yield* setElements(values[0])).values()) s.add(e);
      yield* assign(target, s, env);
      return null;
    }
    throw SwiftalkError.unknownMember(`${typeName(container)}.merge()`);
  }
  if (name === 'subtract') {
    const target = asLValue(receiverExpr);
    if (!target) throw SwiftalkError.type(`'.subtract' mutates — call it on a var ${typeName(container)}`);
    const args: LabeledArg[] = [];
    for (const a of argExprs) args.push({ label: a.label, value: yield* evaluate(a.expr, env) });
    const values = plainValues(args, '.subtract');
    if (values.length !== 1) throw SwiftalkError.type('.subtract takes one Set, or any Sequence');
    if (isSet(container)) {
      const s = container.clone();
      for (const e of (yield* setElements(values[0])).values()) s.delete(e);
      yield* assign(target, s, env);
      return null;
    }
    if (isDictionary(container)) {
      const other = values[0];
      const keys = isDictionary(other) ? new SSet(other.keys()) : yield* setElements(other);
      const d = container.clone();
      for (const key of keys.values()) d.delete(key);
      yield* assign(target, d, env);
      return null;
    }
    throw SwiftalkError.unknownMember(`${typeName(container)}.subtract()`);
  }
  return undefined;
}

// ---- subscripts ----
function sliceBounds(index: SRange, lower: bigint, upper: bigint | null, closed: boolean, count: number): [number, number] {
  let end = BigInt(count);
  if (upper !== null) {
    end = closed ? upper + 1n : upper;
    if (!fits64(end)) throw SwiftalkError.type(`range ${sourceString(index)} is out of range (count ${count})`);
  }
  if (!(lower >= 0n && lower <= end && end <= BigInt(count))) throw SwiftalkError.type(`range ${sourceString(index)} is out of range (count ${count})`);
  return [Number(lower), Number(end)];
}
function position(i: bigint, count: number): number {
  const resolved = i < 0n ? i + BigInt(count) : i;
  if (!(resolved >= 0n && resolved < BigInt(count))) throw SwiftalkError.type(`index ${i} out of range (count ${count})`);
  return Number(resolved);
}
/// The value an assignment path names, read without writing (round 211).
function* readPath(target: LValue, env: Environment): G<Value> {
  switch (target.k) {
    case 'variable': return env.lookup(target.name);
    case 'index': return subscriptRead(yield* readPath(target.base, env), yield* evaluate(target.index, env));
    case 'property': return yield* propertyRead(yield* readPath(target.base, env), target.name);
    default: throw SwiftalkError.type('a tuple pattern cannot be part of an assignment path');
  }
}
export function subscriptRead(container: Value, index: Value): Value {
  if (isArray(container)) {
    if (isRange(index)) { const [a, b] = sliceBounds(index, index.from, index.to, index.closed, container.items.length); return new SArray(container.items.slice(a, b)); }
    if (!isInt(index)) throw SwiftalkError.type(`Array index must be an Int or a Range, not ${typeName(index)}`);
    return container.items[position(index, container.items.length)];
  }
  if (isDictionary(container)) { const v = container.get(index); return v === undefined ? null : v; }
  if (isRange(container)) {
    if (!isInt(index)) throw SwiftalkError.type(`Range index must be an Int, not ${typeName(index)}`);
    if (index < 0n) throw SwiftalkError.type(`Range index ${index} is out of range`);
    if (container.to !== null) {
      const count = rangeCount(container.from, container.to, container.closed);
      if (!(index < count)) throw SwiftalkError.type(`Range index ${index} is out of range (count ${count})`);
    }
    const v = container.from + index;
    if (!fits64(v)) throw SwiftalkError.overflow('this Range element does not fit in an Int');
    return v;
  }
  if (isData(container)) {
    if (isRange(index)) { const [a, b] = sliceBounds(index, index.from, index.to, index.closed, container.bytes.length); return new SData(container.bytes.slice(a, b)); }
    if (!isInt(index)) throw SwiftalkError.type(`Data index must be an Int or a Range, not ${typeName(index)}`);
    return new Byte(container.bytes[position(index, container.bytes.length)]);
  }
  if (isString(container)) throw SwiftalkError.type('no String subscripts (round 89, Design.md §11) — index s.Array(), or slice with prefix/suffix/dropFirst/dropLast');
  throw SwiftalkError.type(`cannot subscript ${typeName(container)}`);
}
function subscriptWrite(container: Value, index: Value, newValue: Value): Value {
  if (isArray(container)) {
    const items = container.items.slice();
    if (isRange(index)) {
      if (!isArray(newValue)) throw SwiftalkError.type(`assigning through a Range takes an Array, not a ${typeName(newValue)}`);
      const [a, b] = sliceBounds(index, index.from, index.to, index.closed, items.length);
      items.splice(a, b - a, ...newValue.items);
      return new SArray(items);
    }
    if (!isInt(index)) throw SwiftalkError.type(`Array index must be an Int or a Range, not ${typeName(index)}`);
    items[position(index, items.length)] = newValue;
    return new SArray(items);
  }
  if (isDictionary(container)) { const d = container.clone(null); d.set(index, newValue); return d; }
  if (isData(container)) {
    const bytes = Array.from(container.bytes);
    if (isRange(index)) {
      if (!isData(newValue)) throw SwiftalkError.type(`assigning through a Range of a Data takes a Data, not a ${typeName(newValue)}`);
      const [a, b] = sliceBounds(index, index.from, index.to, index.closed, bytes.length);
      bytes.splice(a, b - a, ...newValue.bytes);
      return new SData(bytes);
    }
    if (!isInt(index)) throw SwiftalkError.type(`Data index must be an Int or a Range, not ${typeName(index)}`);
    const at = position(index, bytes.length);
    let byte: number;
    if (isByte(newValue)) byte = newValue.v;
    else if (isInt(newValue) && newValue >= 0n && newValue <= 255n) byte = Number(newValue);
    else throw SwiftalkError.type(`a Data byte is a Byte, or an Int in 0...255, not ${sourceString(newValue)}`);
    bytes[at] = byte;
    return new SData(bytes);
  }
  if (isString(container)) throw SwiftalkError.type('no String subscripts (round 89, Design.md §11) — index s.Array(), or slice with prefix/suffix/dropFirst/dropLast');
  throw SwiftalkError.type(`cannot subscript ${typeName(container)}`);
}
export function asLValue(expr: Expr): LValue | null {
  switch (expr.k) {
    case 'variable': return { k: 'variable', name: expr.name };
    case 'subscript': { const inner = asLValue(expr.base); return inner ? { k: 'index', base: inner, index: expr.index } : null; }
    case 'method': { if (expr.called || expr.args.length) return null; const inner = asLValue(expr.receiver); return inner ? { k: 'property', base: inner, name: expr.name } : null; }
    case 'memberLiteral': return { k: 'property', base: { k: 'variable', name: 'self' }, name: expr.name };
    case 'tuple': {
      const elements: { label: string | null; target: LValue }[] = [];
      for (const e of expr.elements) { const target = asLValue(e.expr); if (!target) return null; elements.push({ label: e.label, target }); }
      return { k: 'tuple', elements };
    }
    default: return null;
  }
}
function select(tuple: TupleValue, labels: (string | null)[], what: string): Value[] {
  if (tuple.count !== labels.length) throw SwiftalkError.type(`cannot destructure a ${tuple.count}-tuple into ${labels.length} ${what}`);
  return labels.map((label, pos) => {
    if (label === null) return tuple.values[pos];
    const index = tuple.indexOfLabel(label);
    if (index === null) throw SwiftalkError.type(`the tuple has no element labeled '${label}'`);
    return tuple.values[index];
  });
}
export function bind(pattern: Pattern, value: Value, mutable: boolean, env: Environment, strict: boolean): void {
  if (pattern.k === 'name') {
    if (pattern.name === '_') return;
    const lock = strict ? inferLock(value, pattern.name) : ann(typeName(value), true);
    env.declare(pattern.name, new Binding(mutable, lock, value));
    return;
  }
  if (!isTuple(value)) throw SwiftalkError.type(`cannot destructure a ${typeName(value)} — a tuple pattern needs a Tuple`);
  const values = select(value, pattern.elements.map((e) => e.label), 'names');
  pattern.elements.forEach((e, i) => bind(e.pattern, values[i], mutable, env, strict));
}
function* assignRelaxed(target: LValue, value: Value, env: Environment): G<void> {
  if (target.k === 'tuple') {
    if (!isTuple(value)) throw SwiftalkError.type(`cannot assign a ${typeName(value)} to ${target.elements.length} targets`);
    const values = select(value, target.elements.map((e) => e.label), 'targets');
    for (let i = 0; i < target.elements.length; i++) yield* assignRelaxed(target.elements[i].target, values[i], env);
    return;
  }
  if (target.k === 'variable' && target.name !== '_' && !env.has(target.name)) {
    env.declare(target.name, new Binding(true, inferLock(value, target.name), value));
    return;
  }
  yield* assign(target, value, env);
}

// ---- properties ----
export function makeComputed(exprs: Map<string, Computed>, env: Environment): Map<string, ComputedMember> {
  const out = new Map<string, ComputedMember>();
  for (const [name, spec] of exprs) {
    if (spec.get.k !== 'function') continue;
    const setter = spec.set && spec.set.k === 'function' ? new FunctionObject(spec.set.parameters, spec.set.body, env) : null;
    out.set(name, { annotation: spec.annotation, get: new FunctionObject(spec.get.parameters, spec.get.body, env), set: setter });
  }
  return out;
}
export function computedProperty(receiver: Value, name: string): ComputedMember | null {
  return isStructValue(receiver) ? (receiver.type.computed.get(name) ?? null) : null;
}
export function* readComputed(c: ComputedMember, receiver: Value): G<Value> {
  const [bound] = boundMethod(c.get, receiver);
  const value = yield* apply(bound, []);
  if (c.annotation) checkValue(value, c.annotation, `computed ${typeName(receiver)} property`);
  return value;
}
export function* writeComputed(c: ComputedMember, receiver: Value, name: string, newValue: Value): G<Value> {
  if (!c.set) throw SwiftalkError.type(`${typeName(receiver)}.${name} is a read-only computed property`);
  if (c.annotation) checkValue(newValue, c.annotation, `${typeName(receiver)}.${name}`);
  const [bound, selfEnv] = boundMethod(c.set, receiver, true);
  yield* apply(bound, [{ label: null, value: newValue }]);
  return selfEnv.lookup('self');
}
function makeObservers(order: string[], props: Map<string, Property>, env: Environment): Map<string, { will: FunctionObject | null; did: FunctionObject | null }> {
  const out = new Map<string, { will: FunctionObject | null; did: FunctionObject | null }>();
  for (const name of order) {
    const p = props.get(name);
    if (!p || (!p.willSetExpr && !p.didSetExpr)) continue;
    const build = (e: FunctionExpr | null) => (e && e.k === 'function' ? new FunctionObject(e.parameters, e.body, env) : null);
    out.set(name, { will: build(p.willSetExpr), did: build(p.didSetExpr) });
  }
  return out;
}
export function makeMethods(exprs: Map<string, FunctionExpr>, env: Environment): Map<string, FunctionObject> {
  const out = new Map<string, FunctionObject>();
  for (const [name, expr] of exprs) if (expr.k === 'function') out.set(name, new FunctionObject(expr.parameters, expr.body, env));
  return out;
}
export function lookupExtension(env: Environment, typeNameText: string, name: string): FunctionObject | null {
  const v = env.tryLookup(`@ext:${typeNameText}:${name}`);
  return isFunction(v) ? v : null;
}
export function boundMethod(m: FunctionObject, receiver: Value, mutableSelf = false): [FunctionObject, Environment] {
  const selfEnv = new Environment(m.closure);
  selfEnv.declare('self', new Binding(mutableSelf, ann(typeName(receiver)), receiver));
  return [new FunctionObject(m.parameters, m.body, selfEnv), selfEnv];
}
function initMatches(params: string[], args: LabeledArg[]): boolean {
  if (params.length === 0) return true;
  if (args.length !== params.length) return false;
  const used = new Set<string>();
  for (const a of args) if (a.label !== null) {
    if (!params.includes(a.label) || used.has(a.label)) return false;
    used.add(a.label);
  }
  return true;
}
const observerGuard = new Set<string>();
export function* constructStruct(st: StructType, args: LabeledArg[]): G<StructValue> {
  for (const initFn of st.inits) {
    if (!initMatches(initFn.parameters, args)) continue;
    const values = new Map<string, Value>();
    for (const prop of st.propertyOrder) {
      const def = must(st.properties.get(prop), `${st.name}.${prop}`);
      values.set(prop, def.defaultExpr ? yield* evaluate(def.defaultExpr, new Environment(st.declEnv)) : null);
    }
    const underConstruction = new StructValue(st, values);
    const [fn, selfEnv] = boundMethod(initFn, underConstruction, true);
    const claimed = [...st.observers.keys()].map((k) => `${st.name}.${k}`).filter((key) => { if (observerGuard.has(key)) return false; observerGuard.add(key); return true; });
    try { yield* apply(fn, args); } finally { for (const key of claimed) observerGuard.delete(key); }
    const sv = selfEnv.lookup('self');
    if (!isStructValue(sv)) throw SwiftalkError.type(`${st.name}'s init replaced self with a ${typeName(sv)}`);
    for (const prop of st.propertyOrder) {
      const a = must(st.properties.get(prop), `${st.name}.${prop}`).annotation;
      if (a && !a.optional && a.name !== 'Nil' && (sv.values.get(prop) ?? null) === null) throw SwiftalkError.type(`${st.name}.${prop} was not initialized by init`);
    }
    return sv;
  }
  const slots = new Map<string, Value>();
  const positionals: Value[] = [];
  for (const a of args) {
    if (a.label !== null) {
      if (!st.properties.has(a.label)) throw SwiftalkError.type(`${st.name} has no property '${a.label}'`);
      if (slots.has(a.label)) throw SwiftalkError.type(`duplicate property '${a.label}'`);
      slots.set(a.label, a.value);
    } else positionals.push(a.value);
  }
  const values = new Map<string, Value>();
  for (const prop of st.propertyOrder) {
    const def = must(st.properties.get(prop), `${st.name}.${prop}`);
    let value: Value;
    let given = true;
    const slotted = slots.get(prop), next = slots.has(prop) ? undefined : positionals.shift();
    if (slots.has(prop)) value = slotted ?? null;
    else if (next !== undefined) value = next;
    else if (def.defaultExpr) { value = yield* evaluate(def.defaultExpr, new Environment(st.declEnv)); given = false; }
    else throw SwiftalkError.type(`missing property '${prop}' of ${st.name}`);
    if (def.annotation) { checkValue(value, def.annotation, `${st.name}.${prop}`); value = stamp(value, def.annotation); }
    else if (given && def.defaultExpr) {
      // Round 233: the §3 lock reaches the memberwise init — a property without an annotation
      // is locked to its default's type, as on assignment; a nil default locks nothing.
      const initial = yield* evaluate(def.defaultExpr, new Environment(st.declEnv));
      if (initial !== null && typeName(value) !== typeName(initial)) throw SwiftalkError.type(`cannot assign ${typeName(value)} to ${st.name}.${prop} of type ${typeName(initial)}`);
    }
    values.set(prop, value);
  }
  if (positionals.length) throw SwiftalkError.type(`too many values for ${st.name}`);
  return new StructValue(st, values);
}
function* propertyRead(container: Value, name: string): G<Value> {
  if (isTuple(container)) {
    const index: number | null = /^\d+$/.test(name) ? Number(name) : container.indexOfLabel(name);
    if (index !== null && index !== undefined) {
      if (!(index >= 0 && index < container.count)) throw SwiftalkError.type(`tuple index ${index} out of range (count ${container.count})`);
      return container.values[index];
    }
  }
  if (!isStructValue(container)) throw SwiftalkError.type(`cannot assign through a property of ${typeName(container)}`);
  const c = container.type.computed.get(name);
  if (c) return yield* readComputed(c, container);
  const stored = container.values.get(name);
  if (stored === undefined) throw SwiftalkError.unknownMember(`${container.type.name}.${name}`);
  return stored;
}
function* propertyWrite(container: Value, name: string, newValue: Value): G<Value> {
  if (isTuple(container)) {
    const index: number | null = /^\d+$/.test(name) ? Number(name) : container.indexOfLabel(name);
    if (index !== null && index !== undefined) {
      if (!(index >= 0 && index < container.count)) throw SwiftalkError.type(`tuple index ${index} out of range (count ${container.count})`);
      const values = container.values.slice(); values[index] = newValue;
      return new TupleValue(values, container.labels);
    }
  }
  if (isHost(container)) {
    const taken = container.object.setMember ? container.object.setMember(name, newValue) : false;
    const ok = isGenerator(taken) ? yield* taken : taken;
    if (!ok) throw SwiftalkError.type(`cannot assign to ${container.object.typeName}.${name}`);
    return container;
  }
  if (!isStructValue(container)) throw SwiftalkError.type(`cannot assign through a property of ${typeName(container)}`);
  const sv = container.clone();
  const c = sv.type.computed.get(name);
  if (c) return yield* writeComputed(c, container, name, newValue);
  const def = sv.type.properties.get(name);
  const current = sv.values.get(name);
  if (!def || current === undefined) throw SwiftalkError.unknownMember(`${sv.type.name}.${name}`);
  if (!def.mutable) throw SwiftalkError.type(`cannot assign to let property '${sv.type.name}.${name}'`);
  if (def.annotation) { checkValue(newValue, def.annotation, `${sv.type.name}.${name}`); newValue = stamp(newValue, def.annotation); }
  else if (current !== null && typeName(newValue) !== typeName(current)) throw SwiftalkError.type(`cannot assign ${typeName(newValue)} to ${sv.type.name}.${name} of type ${typeName(current)}`);
  const guardKey = `${sv.type.name}.${name}`;
  const observers = sv.type.observers.get(name);
  if (!observers || observerGuard.has(guardKey)) { sv.values.set(name, newValue); return sv; }
  observerGuard.add(guardKey);
  try {
    if (observers.will) { const [bound] = boundMethod(observers.will, sv); yield* apply(bound, [{ label: null, value: newValue }]); }
    sv.values.set(name, newValue);
    if (observers.did) {
      const [bound, selfEnv] = boundMethod(observers.did, sv, true);
      yield* apply(bound, [{ label: null, value: current }]);
      return selfEnv.lookup('self');
    }
    return sv;
  } finally { observerGuard.delete(guardKey); }
}
export function isAbsent(v: Value): boolean { return v === null || (isResult(v) && v.caseName === 'failure'); }

type Step = { index: Value } | { property: string };
export function* assign(target: LValue, value: Value, env: Environment, combine: ((old: Value) => G<Value>) | null = null): G<Value> {
  if (target.k === 'variable' && target.name === '_') {
    if (combine) throw SwiftalkError.type("'_' discards — it has no value to combine with");
    return value;
  }
  if (target.k === 'tuple') {
    if (combine) throw SwiftalkError.type('compound assignment takes one target, not a tuple pattern');
    if (!(value instanceof TupleValue)) throw SwiftalkError.type(`cannot assign a ${typeName(value)} to ${target.elements.length} targets — a tuple pattern needs a Tuple`);
    const values = select(value, target.elements.map((e) => e.label), 'targets');
    for (let i = 0; i < target.elements.length; i++) yield* assign(target.elements[i].target, values[i], env);
    return value;
  }
  const steps: Step[] = [];
  let root: LValue = target;
  while (root.k !== 'variable') {
    if (root.k === 'index') { steps.unshift({ index: yield* evaluate(root.index, env) }); root = root.base; }
    else if (root.k === 'property') { steps.unshift({ property: root.name }); root = root.base; }
    else throw SwiftalkError.type('a tuple pattern cannot be part of an assignment path');
  }
  const name = root.name;
  const landing = function* (old: () => G<Value>): G<Value> { return combine ? yield* combine(yield* old()) : value; };
  if (steps.length === 0) {
    const final = yield* landing(function* () { return env.lookup(name); });
    env.assign(name, final);
    return final;
  }
  let written = value;
  const read = function* (container: Value, step: Step): G<Value> { return 'index' in step ? subscriptRead(container, step.index) : yield* propertyRead(container, step.property); };
  const write = function* (container: Value, step: Step, v: Value): G<Value> { return 'index' in step ? subscriptWrite(container, step.index, v) : yield* propertyWrite(container, step.property, v); };
  const rebuild = function* (container: Value, depth: number): G<Value> {
    if (depth === steps.length - 1) {
      written = yield* landing(function* () { return yield* read(container, steps[depth]); });
      return yield* write(container, steps[depth], written);
    }
    const inner = yield* read(container, steps[depth]);
    const newInner = yield* rebuild(inner, depth + 1);
    return yield* write(container, steps[depth], newInner);
  };
  const rebuilt = yield* rebuild(env.lookup(name), 0);
  env.assign(name, rebuilt);
  return written;
}
export function* evaluateArgs(args: Arg[], env: Environment): G<LabeledArg[]> {
  const out: LabeledArg[] = [];
  for (const a of args) out.push({ label: a.label, value: yield* evaluate(a.expr, env) });
  return out;
}

// ---- application ----
export function* apply(fn: FunctionObject, args: LabeledArg[]): G<Value> {
  if (fn.role.k === 'structType') {
    if (fn.role.type.isModule) throw SwiftalkError.type(`${fn.role.type.name} is a module, not a type with instances — its members are ${fn.role.type.name}.name`);
    return yield* constructStruct(fn.role.type, args);
  }
  if (fn.role.k === 'type') {
    const tn = fn.role.name;
    if (fn.builtin && !Builtins.types.has(tn) && !Builtins.protocols.has(tn)) return yield* callBuiltin(fn.builtin, args.map((a) => a.value));
    let subject: Value | undefined = undefined;
    const extra: LabeledArg[] = [];
    args.forEach((a, i) => { if (i === 0 && a.label === null) subject = a.value; else extra.push(a); });
    const built = yield* convert(tn, subject, extra);
    if (fn.annotation) { checkValue(built, fn.annotation, `${fn.annotation.display}()`); return stamp(built, fn.annotation); }
    return built;
  }
  const sole = args.length === 1 && args[0].label === null ? args[0].value : undefined;
  if (!fn.builtin && isTuple(sole)) args = sole.values.map((v): LabeledArg => ({ label: null, value: v }));
  let ordered: Value[];
  if (fn.parameters.length === 0) {
    const label = args.map((a) => a.label).find((l) => l !== null);
    if (label !== undefined) throw SwiftalkError.type(`unknown argument label '${label}': this function declares no parameter names`);
    ordered = args.map((a) => a.value);
  } else {
    if (args.length !== fn.parameters.length) throw SwiftalkError.type(`expected ${fn.parameters.length} argument(s), got ${args.length}`);
    const slots: (Value | undefined)[] = new Array(fn.parameters.length).fill(undefined);
    for (const a of args) if (a.label !== null) {
      const index = fn.parameters.indexOf(a.label);
      if (index < 0) throw SwiftalkError.type(`unknown argument label '${a.label}'`);
      if (slots[index] !== undefined) throw SwiftalkError.type(`duplicate argument label '${a.label}'`);
      slots[index] = a.value;
    }
    const positionals = args.filter((a) => a.label === null).map((a) => a.value);
    ordered = slots.map((slot) => {
      if (slot !== undefined) return slot;
      const next = positionals.shift();
      if (next === undefined) throw SwiftalkError.type('missing argument');
      return next;
    });
  }
  if (fn.builtin) return yield* callBuiltin(fn.builtin, ordered);
  return (yield* run(fn, ordered)).result;
}
export function* run(fn: FunctionObject, ordered: Value[]): G<{ result: Value; local: Environment }> {
  const local = new Environment(fn.closure);
  if (fn.builtin) return { result: yield* callBuiltin(fn.builtin, ordered), local };
  fn.parameters.forEach((name, i) => { if (name !== '_') local.declare(name, new Binding(false, ann(typeName(ordered[i]), true), ordered[i])); });
  local.declare('$', new Binding(true, ann('Array'), new SArray(ordered)));
  ordered.forEach((value, index) => local.declare(`$${index}`, new Binding(false, ann(typeName(value), true), value)));
  local.declare(calleeKey, new Binding(false, ann('Function'), fn));
  let last: Value = null;
  try {
    for (const statement of fn.body) last = yield* execute(statement, local);
  } catch (e) {
    if (e instanceof ReturnSignal) return { result: e.value, local };
    if (e instanceof ControlFlow) throw SwiftalkError.syntax("'break'/'continue' outside a loop");
    throw e;
  }
  return { result: last, local };
}

// ---- operators ----
export function* userOperator(key: string, operands: Value[]): G<Value | undefined> {
  for (const v of operands) {
    let table: Map<string, FunctionObject> | null = null;
    if (isStructValue(v) || isEnumCase(v)) table = v.type.operators;
    else if (isHost(v) && v.object.operate) {                 // a module's value (round 201: BigInt's arithmetic)
      const answered = v.object.operate(key, operands);
      const r = isGenerator(answered) ? yield* answered : answered;
      if (r !== undefined) return r;
      continue;
    } else continue;
    const fn = table.get(key);
    if (fn) return yield* apply(fn, operands.map((x) => ({ label: null, value: x })));
  }
  return undefined;
}
export function hasUserOperator(v: Value, key: string): boolean {
  if (isStructValue(v) || isEnumCase(v)) return v.type.operators.has(key);
  if (isHost(v)) return v.object.hasOperator ? v.object.hasOperator(key) : false;
  return false;
}
const userTyped = (v: Value): boolean => isStructValue(v) || (isEnumCase(v) && !isResult(v)) || isHost(v);
const byteOrInt = (v: Byte | bigint): bigint => (isByte(v) ? BigInt(v.v) : v);
export function* bitwise(op: string, lhs: Value, rhs: Value): G<Value> {
  const r = yield* userOperator(`infix:${op}`, [lhs, rhs]);
  if (r !== undefined) return r;
  const combine = (a: bigint, b: bigint): bigint => {
    switch (op) {
      case '+&': return a & b;
      case '+|': return a | b;
      case '+^': return a ^ b;
      case '+<': return b >= 64n ? 0n : b <= -64n ? (a < 0n ? -1n : 0n) : b >= 0n ? BigInt.asIntN(64, a << b) : a >> -b;
      default: return b >= 64n ? (a < 0n ? -1n : 0n) : b <= -64n ? 0n : b >= 0n ? a >> b : BigInt.asIntN(64, a << -b);
    }
  };
  if (isByte(lhs) && isByte(rhs)) return new Byte(Number(BigInt.asUintN(8, combine(BigInt(lhs.v), BigInt(rhs.v)))));
  if ((isByte(lhs) || isInt(lhs)) && (isByte(rhs) || isInt(rhs))) return combine(byteOrInt(lhs), byteOrInt(rhs));
  throw SwiftalkError.type(`'${op}' is a bitwise operator on Ints and Bytes — not defined between ${typeName(lhs)} and ${typeName(rhs)}`
    + ((isBool(lhs) || isBool(rhs)) ? '; Bools use && || ^^ !' : '') + ((isSet(lhs) || isSet(rhs)) ? '; Sets use & | ^' : ''));
}
export function* bitNot(operand: Value): G<Value> {
  const r = yield* userOperator('prefix:+^', [operand]);
  if (r !== undefined) return r;
  if (isInt(operand)) return ~operand;
  if (isByte(operand)) return new Byte(~operand.v & 0xff);
  throw SwiftalkError.type(`prefix '+^' is bitwise not, on an Int or a Byte — not ${typeName(operand)}`);
}
export function* binary(op: string, lhs: Value, rhs: Value): G<Value> {
  const r = yield* userOperator(`infix:${op}`, [lhs, rhs]);
  if (r !== undefined) return r;
  if ('|&^'.includes(op) && !(isSet(lhs) && isSet(rhs))) {
    throw SwiftalkError.type(`'${op}' is a Set operator — not defined between ${typeName(lhs)} and ${typeName(rhs)}; Bools use '${op}${op}', Ints +${op}`);
  }
  if (isByte(lhs) && isByte(rhs)) {
    const a = lhs.v, b = rhs.v;
    if ((op === '/' || op === '%') && b === 0) throw SwiftalkError.zeroDivision();
    let result: number;
    switch (op) {
      case '+': result = a + b; break; case '-': result = a - b; break; case '*': result = a * b; break;
      case '/': result = Math.trunc(a / b); break; case '%': result = a % b; break;
      default: throw SwiftalkError.type(`'${op}' is not defined between Byte and Byte`);
    }
    if (result < 0 || result > 255) throw SwiftalkError.overflow(`Byte(${a}) ${op} Byte(${b})`);
    return new Byte(result);
  }
  if (isByte(lhs) && isInt(rhs)) return yield* binary(op, BigInt(lhs.v), rhs);
  if (isInt(lhs) && isByte(rhs)) return yield* binary(op, lhs, BigInt(rhs.v));
  if (isInt(lhs) && isInt(rhs)) {
    const a = lhs, b = rhs;
    if ((op === '/' || op === '%') && b === 0n) throw SwiftalkError.zeroDivision();
    let result: bigint;
    switch (op) {
      case '+': result = a + b; break; case '-': result = a - b; break; case '*': result = a * b; break;
      case '/': result = a / b; break;
      case '%': if (a === INT64_MIN && b === -1n) throw SwiftalkError.overflow(`${a} % ${b}`); result = a % b; break;   // Swift traps: the quotient overflows
      default: throw SwiftalkError.type(`'${op}' is not defined between Int and Int`);
    }
    if (!fits64(result)) throw SwiftalkError.overflow(`${a} ${op} ${b}`);
    return result;
  }
  if (isDouble(lhs) && isDouble(rhs)) {
    const a = lhs, b = rhs;
    switch (op) {
      case '+': return a + b; case '-': return a - b; case '*': return a * b; case '/': return a / b;
      case '%': throw SwiftalkError.type("'%' is for Ints — as in Swift, a Double has no remainder operator");
      default: break;
    }
  }
  if (isString(lhs) && isString(rhs) && op === '+') return lhs + rhs;
  if (isArray(lhs) && isArray(rhs) && op === '+') return new SArray([...lhs.items, ...rhs.items]);
  if (isSet(lhs) && isSet(rhs)) {
    const l = lhs, r = rhs;
    switch (op) {
      case '|': { const s = l.clone(null); for (const e of r.values()) s.add(e); return s; }
      case '-': { const s = l.clone(null); for (const e of r.values()) s.delete(e); return s; }
      case '&': return new SSet(l.values().filter((e) => r.has(e)));
      case '^': return new SSet([...l.values().filter((e) => !r.has(e)), ...r.values().filter((e) => !l.has(e))]);
      default: break;
    }
  }
  throw SwiftalkError.type(`'${op}' is not defined between ${typeName(lhs)} and ${typeName(rhs)}`);
}
export function* setElements(value: Value): G<SSet> {
  if (isSet(value)) return value;
  return new SSet(yield* collect(value));
}
export function coalesceDictionaries(base: SDictionary, fill: Value, op: string): SDictionary {
  if (!isDictionary(fill)) throw SwiftalkError.type(`'${op}' between a Dictionary and a ${typeName(fill)} — a Dictionary coalesces with a Dictionary`);
  const out = base.clone(null);
  for (const [key, value] of fill.entries()) { const cur = out.get(key); if (cur === undefined || isAbsent(cur)) out.set(key, value); }
  return out;
}
export function* mergeDictionaries(base: SDictionary, args: Value[]): G<SDictionary> {
  const [other, fn] = args;
  if (!(args.length === 1 || args.length === 2) || !isDictionary(other)) throw SwiftalkError.type('.merging(dictionary) { current, new in } — a Dictionary, and optionally a function');
  let combine: FunctionObject | null = null;
  if (args.length === 2) { if (!isFunction(fn)) throw SwiftalkError.type(".merging's second argument is the combine function: { current, new in }"); combine = fn; }
  const merged = base.clone(null);
  for (const [key, nu] of other.entries()) {
    const current = merged.get(key);
    if (combine && current !== undefined) merged.set(key, yield* apply(combine, [{ label: null, value: current }, { label: null, value: nu }]));
    else merged.set(key, nu);
  }
  return merged;
}
export function identical(a: Value, b: Value): boolean {
  if (kindOf(a) !== kindOf(b)) return false;
  const all = (xs: Value[], ys: Value[]) => xs.length === ys.length && xs.every((e, i) => identical(e, ys[i]));
  if (isDouble(a) && isDouble(b)) return Object.is(a, b) || (Number.isNaN(a) && Number.isNaN(b));
  if (isString(a)) return a === b;
  if (isArray(a) && isArray(b)) return all(a.items, b.items);
  if (isTuple(a) && isTuple(b)) return all(a.values, b.values);
  if (isDictionary(a) && isDictionary(b)) return a.size === b.size && a.entries().every(([k, v]) => b.entries().some(([k2, v2]) => identical(k, k2) && identical(v, v2)));
  if (isStructValue(a) && isStructValue(b)) return a.type === b.type && a.values.size === b.values.size && [...a.values].every(([k, v]) => b.values.has(k) && identical(v, b.values.get(k) ?? null));
  if (isEnumCase(a) && isEnumCase(b)) return a.type === b.type && a.caseName === b.caseName && all(a.associated, b.associated);
  return equals(a, b);
}
export function* compare(op: string, lhs: Value, rhs: Value): G<boolean> {
  if (op !== '===' && op !== '!==' && (userTyped(lhs) || userTyped(rhs))) {
    const bool = (v: Value, negated = false): boolean => {
      if (typeof v !== 'boolean') throw SwiftalkError.type(`a comparison operator must return a Bool, not a ${typeName(v)}`);
      return negated ? !v : v;
    };
    let r = yield* userOperator(`infix:${op}`, [lhs, rhs]);
    if (r !== undefined) return bool(r);
    switch (op) {
      case '!=': r = yield* userOperator('infix:==', [lhs, rhs]); if (r !== undefined) return bool(r, true); break;
      case '>': r = yield* userOperator('infix:<', [rhs, lhs]); if (r !== undefined) return bool(r); break;
      case '<=': r = yield* userOperator('infix:<', [rhs, lhs]); if (r !== undefined) return bool(r, true); break;
      case '>=': r = yield* userOperator('infix:<', [lhs, rhs]); if (r !== undefined) return bool(r, true); break;
      default: break;
    }
  }
  if (op === '==' || op === '!=') {
    const byteInt = (isByte(lhs) && isInt(rhs)) || (isInt(lhs) && isByte(rhs));
    if (lhs !== null && rhs !== null && !byteInt && typeName(lhs) !== typeName(rhs)) throw SwiftalkError.type(`'${op}' is not defined between ${typeName(lhs)} and ${typeName(rhs)}`);
    return op === '==' ? equals(lhs, rhs) : !equals(lhs, rhs);
  }
  if (op === '===' || op === '!==') return identical(lhs, rhs) === (op === '===');
  let ascending: boolean;
  if ((isInt(lhs) || isByte(lhs)) && (isInt(rhs) || isByte(rhs))) ascending = byteOrInt(lhs) < byteOrInt(rhs);
  else if (isDouble(lhs) && isDouble(rhs)) ascending = lhs < rhs;
  else if (isString(lhs) && isString(rhs)) ascending = compareStrings(lhs, rhs) < 0;
  else if (isDate(lhs) && isDate(rhs)) ascending = lhs.epoch < rhs.epoch;
  else throw SwiftalkError.type(`'${op}' is not defined between ${typeName(lhs)} and ${typeName(rhs)}`);
  const equal = equals(lhs, rhs);
  switch (op) {
    case '<': return ascending;
    case '<=': return ascending || equal;
    case '>': return !ascending && !equal;
    default: return !ascending;
  }
}

// ---- operator Functions ----
const operatorTable = new Map<string, FunctionObject>();
export function operatorFunction(op: string): FunctionObject {
  let f = operatorTable.get(op);
  if (!f) {
    f = new FunctionObject([], [], Builtins.emptyEnvironment, function* (args: Value[]) { return yield* applyOperator(op, args); }, { k: 'operator', op });
    operatorTable.set(op, f);
  }
  return f;
}
function* applyOperator(op: string, args: Value[]): G<Value> {
  if (args.length === 1) {
    switch (op) {
      case '-': {
        const r = yield* userOperator('prefix:-', [args[0]]); if (r !== undefined) return r;
        const v = args[0];
        if (isInt(v)) { if (v === INT64_MIN) throw SwiftalkError.overflow(`negating ${v}`); return -v; }
        if (isDouble(v)) return -v;
        throw SwiftalkError.type(`cannot negate ${typeName(v)}`);
      }
      case '+': {
        const r = yield* userOperator('prefix:+', [args[0]]); if (r !== undefined) return r;
        const k = kindOf(args[0]);
        if (k === 'int' || k === 'double' || k === 'byte') return args[0];
        throw SwiftalkError.type(`cannot apply prefix + to ${typeName(args[0])}`);
      }
      case '!': {
        const r = yield* userOperator('prefix:!', [args[0]]); if (r !== undefined) return r;
        if (typeof args[0] !== 'boolean') throw SwiftalkError.type("'!' takes a Bool — nothing is truthy (§3b)");
        return !args[0];
      }
      case '+^': return yield* bitNot(args[0]);
      default: break;
    }
  }
  if (args.length === 2) {
    const [a, b] = args;
    switch (op) {
      case '+&': case '+|': case '+^': case '+<': case '+>': return yield* bitwise(op, a, b);
      case '+': case '-': case '*': case '/': case '%': case '|': case '&': case '^': return yield* binary(op, a, b);
      case '**': return yield* power(a, b);
      case '==': case '!=': case '===': case '!==': case '<': case '<=': case '>': case '>=': return yield* compare(op, a, b);
      case '&&': case '||': case '^^':
        if (typeof a !== 'boolean' || typeof b !== 'boolean') throw SwiftalkError.type(`'${op}' takes Bools — nothing is truthy (§3b)`);
        return op === '&&' ? a && b : op === '||' ? a || b : a !== b;
      case '??': if (isDictionary(a)) return coalesceDictionaries(a, b, '??'); return isAbsent(a) ? b : a;
      case '!!': if (isDictionary(b)) return coalesceDictionaries(b, a, '!!'); return isAbsent(b) ? a : b;
      default: throw SwiftalkError.type(`(${op}) is not a function`);
    }
  }
  const unary = ['-', '+', '!'].includes(op) ? 'one or ' : '';
  throw SwiftalkError.type(`(${op}) takes ${unary}two arguments, got ${args.length}`);
}

// ---- types: scopes and statics ----
export function typeScope(env: Environment, type: Value): Environment {
  const scope = new Environment(env);
  try { scope.declare('Self', new Binding(false, ann('Function'), type)); } catch (e) { /* unreachable */ }
  return scope;
}
type StaticEntries = { thunks: Map<string, StaticThunk>; getters: Map<string, FunctionObject>; ops: Map<string, FunctionObject> };
export function installStatics(spec: Statics, typeEnv: Environment, holder: StructType | EnumType, typeNameText: string, overwrite: boolean): StaticEntries {
  const out: StaticEntries = { thunks: new Map(), getters: new Map(), ops: new Map() };
  for (const [key, expr] of spec.ops) {
    if (expr.k !== 'function') continue;
    if (!overwrite && holder.operators.has(key)) { const [fix, op] = key.split(':'); throw SwiftalkError.type(`${typeNameText} already implements ${fix}(${op})`); }
    out.ops.set(key, new FunctionObject(expr.parameters, expr.body, typeEnv));
  }
  for (const [name, expr] of spec.lets) {
    if (!overwrite && (holder.statics.has(name) || holder.staticGetters.has(name) || holder.staticThunks.has(name))) throw SwiftalkError.type(`${typeNameText} already has a static member '${name}'`);
    out.thunks.set(name, { expr, env: typeEnv });
  }
  for (const [name, cspec] of spec.vars) {
    if (cspec.get.k !== 'function') continue;
    if ((!overwrite && (holder.statics.has(name) || holder.staticGetters.has(name) || holder.staticThunks.has(name))) || out.thunks.has(name)) throw SwiftalkError.type(`${typeNameText} already has a static member '${name}'`);
    out.getters.set(name, new FunctionObject(cspec.get.parameters, cspec.get.body, typeEnv));
  }
  return out;
}
export function mergeStatics(entries: StaticEntries, holder: StructType | EnumType): void {
  for (const [name, t] of entries.thunks) { holder.staticGetters.delete(name); holder.statics.delete(name); holder.staticThunks.set(name, t); }
  for (const [name, g] of entries.getters) { holder.statics.delete(name); holder.staticThunks.delete(name); holder.staticGetters.set(name, g); }
  for (const [key, f] of entries.ops) holder.operators.set(key, f);
}
export function* resolveStatic(name: string, holder: StructType | EnumType): G<Value | undefined> {
  if (holder.statics.has(name)) return holder.statics.get(name);
  const thunk = holder.staticThunks.get(name);
  if (!thunk) return undefined;
  holder.staticThunks.delete(name);
  let value: Value;
  try { value = yield* evaluate(thunk.expr, thunk.env); }
  catch (e) { holder.staticThunks.set(name, thunk); throw e; }
  holder.statics.set(name, value);
  return value;
}

// ---- tasks (milestone C): the requests the scheduler answers ----
export function* spawnTask(f: FunctionObject): G<TaskObject> {
  const answer = yield { suspend: 'spawn', body: f };
  if (!answer || !('task' in answer)) throw SwiftalkError.type('Task { ... } needs a running Interpreter');
  return answer.task;
}
export function* awaitTask(task: TaskObject): G<Value> {
  const answer = yield { suspend: 'await', task };
  if (!answer || !('value' in answer)) throw SwiftalkError.type("'await' needs a running Interpreter");
  return answer.value;
}
/// `Task.sleep(seconds)`'s request: only the current context waits.
export function* sleep(seconds: number): G<void> {
  const answer = yield { suspend: 'sleep', seconds };
  if (!answer || !('done' in answer) || !answer.done) throw SwiftalkError.type("'sleep' needs a running Interpreter");
}
/// A Promise the host answers (round 163's offload): this context parks
/// until it settles; the others run meanwhile. Only the async driver waits.
export function* offload(promise: Promise<unknown>): G<unknown> {
  const answer = yield { suspend: 'offload', promise };
  if (!answer || !('offloaded' in answer)) throw SwiftalkError.type('this operation waits on the host — run it with evalAsync');
  return answer.offloaded;
}
