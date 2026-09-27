// The evaluator — Eval.swift's execute/evaluate/apply/assign, as
// GENERATORS: every function that can run swiftalk code is a `function*`
// invoked with `yield*`, so that a suspension (await, yield, sleep — the
// scheduler's business) can unwind and resume the whole interpreter stack.
// A yielded value is a suspension request; the driver in interpreter.js
// handles it. Pure helpers stay plain functions.
import { SwiftalkError } from './errors.js';
import { TypeAnnotation } from './parser.js';
import { kindOf, typeName, equals, keyOf, sourceString, graphemes, SArray, SDictionary, SSet, Byte, SData, SDate, SRange, TupleValue,
  INT64_MAX, INT64_MIN, fits64, compareStrings } from './value.js';
import { FunctionObject, EnumType, EnumCaseValue, StructType, StructValue, SequenceObject, TaskObject, ControlFlow, ReturnSignal } from './objects.js';
import { Environment, Binding } from './env.js';
import { Builtins, power, isResult, success, failure } from './builtins.js';
import { ann, checkValue, inferLock, stamp, admits, containerStamp, knownElementLock, stampedArray, tryInfer, annotationOfType,
  typeValue, typeValueForParameter, optionalType, resolveTypeNames, annotationIsKnown, resolveEnumAnnotation, isUserType, callBuiltin } from './types.js';
import { method, convert, asksCanonical, userConversion, plainValues } from './members.js';

export const calleeKey = '@callee';
export const scheduler = { current: null, modules: null };   // installed by interpreter.js while an eval runs

// ---- printing that may run swiftalk (a type's own String member) ----
export function* valueSourceText(value) {
  const owned = new Map();
  const walk = function* (v) {
    const m = userConversion(v, 'String');
    if (m) {
      const [bound] = boundMethod(m, v);
      const s = yield* apply(bound, []);
      if (typeof s !== 'string') throw SwiftalkError.type(`${typeName(v)}.String() must return a String`);
      owned.set(v, s);
      return;                                  // the member speaks for the whole subtree
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
  if (owned.size === 0) return sourceString(value);
  return sourceString(value, false, (v) => (owned.has(v) ? owned.get(v) : null));
}
export function* displayString(value) {
  if (typeof value === 'string') return value;
  return yield* valueSourceText(value);
}
export const plainString = (v) => (typeof v === 'string' ? v : sourceString(v));

export function* regexLiteral(pattern, flags, env) {
  const t = env.tryLookup('Regex');
  if (!t || kindOf(t) !== 'function' || t.role.k !== 'type' || t.role.name !== 'Regex' || !t.builtin) {
    throw SwiftalkError.type(`/${pattern}/${flags}: a regex literal needs the Regex module — import from "Regex" (the CLI preimports it)`);
  }
  return yield* callBuiltin(t.builtin, [pattern, flags]);
}

// ---- statements ----
export function* execute(statement, env, relaxed = false) {
  switch (statement.k) {
    case 'expression': return yield* evaluate(statement.expr, env);
    case 'return': throw new ReturnSignal(statement.expr ? yield* evaluate(statement.expr, env) : null);
    case 'break': throw new ControlFlow('break', statement.label);
    case 'continue': throw new ControlFlow('continue', statement.label);
    default: return yield* executeSlow(statement, env, relaxed);
  }
}

function* executeSlow(s, env, relaxed) {
  switch (s.k) {
    case 'declaration': {
      const annotation = s.annotation ? resolveTypeNames(s.annotation, env) : null;
      const annotatedEnum = annotation ? resolveEnumAnnotation(annotation, env) : null;
      let value;
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
      let lock;
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
        return yield* assign(target, null, env, function* (old) {
          if (kindOf(old) === 'dictionary') return coalesceDictionaries(old, yield* evaluate(expr, env), '??=');
          return isAbsent(old) ? yield* evaluate(expr, env) : old;
        });
      }
      if (op === '!!') {
        const rhs = yield* evaluate(expr, env);
        return yield* assign(target, null, env, function* (old) {
          if (kindOf(rhs) === 'dictionary') return coalesceDictionaries(rhs, old, '!!=');
          return isAbsent(rhs) ? old : rhs;
        });
      }
      if (op === '^^') {
        const rhs = yield* evaluate(expr, env);
        return yield* assign(target, null, env, function* (old) {
          if (typeof old !== 'boolean' || typeof rhs !== 'boolean') throw SwiftalkError.type("'^^=' takes Bools — nothing is truthy (§3b)");
          return old !== rhs;
        });
      }
      if (op === '&&' || op === '||') {
        const name = op + '=';
        return yield* assign(target, null, env, function* (old) {
          if (typeof old !== 'boolean') throw SwiftalkError.type(`'${name}' takes a Bool target, not ${typeName(old)} — nothing is truthy (§3b)`);
          if ((op === '&&') !== old) return old;
          const rhs = yield* evaluate(expr, env);
          if (typeof rhs !== 'boolean') throw SwiftalkError.type(`'${name}' takes a Bool — nothing is truthy (§3b)`);
          return rhs;
        });
      }
      const rhs = yield* evaluate(expr, env);
      if (op === '**') return yield* assign(target, rhs, env, function* (old) { return yield* power(old, rhs); });
      if (op.startsWith('+') && op.length === 2) return yield* assign(target, rhs, env, function* (old) { return yield* bitwise(op, old, rhs); });
      return yield* assign(target, rhs, env, function* (old) { return yield* binary(op, old, rhs); });
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
      if (s.namespace !== null) {
        const type = modules.namespaceType(module, s.namespace);
        env.declare(s.namespace, new Binding(false, ann('Function'), type.constructor_));
      }
      for (const name of names) {
        const index = module.names.indexOf(name);
        if (index < 0) throw SwiftalkError.type(`module '${s.spec}' exports no '${name}'` + (module.names.length ? ` — it exports ${module.names.join(', ')}` : ''));
        const value = module.values[index];
        env.declare(name, new Binding(false, ann(typeName(value), true), value));
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
      if (!handled || !handled.coroutine) throw SwiftalkError.type("'yield' outside a coroutine — wrap the function: Sequence(f)");
      return null;
    }
    case 'enumDecl': {
      const cases = new Map();
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
      const properties = new Map();
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
      const value = env.tryLookup(s.typeName);
      if (!value || kindOf(value) !== 'function') throw SwiftalkError.type(`unknown type '${s.typeName}'`);
      const f = value;
      const typeEnv = typeScope(env, value);
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
function* evaluateSwitch(subjectExpr, clauses, defaultBody, env) {
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
function* match(pattern, subject, scope) {
  switch (pattern.k) {
    case 'wildcard': return true;
    case 'expr': {
      const v = yield* evaluate(pattern.e, scope);
      if (equals(v, subject)) return true;
      if (kindOf(v) === 'range' && typeof subject === 'bigint') {
        if (v.from <= subject && (v.to === null || (v.closed ? subject <= v.to : subject < v.to))) return true;
      }
      if (kindOf(v) === 'host') return (yield* hostPattern(v, subject, false)) !== null;
      return false;
    }
    case 'enumCase': return subject instanceof EnumCaseValue && subject.caseName === pattern.name;
    case 'binding': {
      let value;
      if (pattern.source.k === 'member') {
        const caseName = pattern.source.name;
        if (!(subject instanceof EnumCaseValue) || !subject.type.cases.has(caseName)) throw SwiftalkError.type(`case .${caseName}: ${typeName(subject)} has no such case`);
        value = caseAccessor(subject, caseName, subject);
      } else {
        const h = yield* evaluate(pattern.source.e, scope);
        if (kindOf(h) !== 'host') throw SwiftalkError.type('a case binds from a case of the subject (case r = .circle) or a Regex (case m = /re/)');
        value = (yield* hostPattern(h, subject, true)) ?? null;
      }
      if (value === null) return false;
      bind(pattern.pattern, value, pattern.mutable, scope, false);
      return true;
    }
    default: return false;
  }
}
function* hostPattern(h, subject, binding) {
  const r = h.object.patternMatch ? h.object.patternMatch(subject, binding) : null;
  return r === undefined ? null : r;
}
export function caseAccessor(ev, name, receiver) {
  if (ev.caseName !== name) return null;
  switch (ev.associated.length) {
    case 0: return receiver;
    case 1: return ev.associated[0];
    default: return new TupleValue(ev.associated, (ev.type.cases.get(ev.caseName) ?? []).map((p) => p.label));
  }
}
export function constructEnumCase(et, caseName, args, called) {
  const params = et.cases.get(caseName);
  if (!params) throw SwiftalkError.unknownMember(`${et.name}.${caseName}`);
  if (!called || params.length === 0) {
    if (params.length) throw SwiftalkError.type(`${et.name}.${caseName} has associated values — call it`);
    if (args.length) throw SwiftalkError.type(`${et.name}.${caseName} takes no associated values`);
    return new EnumCaseValue(et, caseName, []);
  }
  if (args.length !== params.length) throw SwiftalkError.type(`${et.name}.${caseName} takes ${params.length} associated value(s), got ${args.length}`);
  const slots = new Array(params.length).fill(undefined);
  for (const a of args) if (a.label !== null) {
    const index = params.findIndex((p) => p.label === a.label);
    if (index < 0) throw SwiftalkError.type(`unknown label '${a.label}' for ${et.name}.${caseName}`);
    if (slots[index] !== undefined) throw SwiftalkError.type(`duplicate label '${a.label}'`);
    slots[index] = a.value;
  }
  const positionals = args.filter((a) => a.label === null).map((a) => a.value);
  const associated = slots.map((slot, index) => {
    let value;
    if (slot !== undefined) value = slot;
    else if (positionals.length) value = positionals.shift();
    else throw SwiftalkError.type('missing associated value');
    const expected = params[index].typeName;
    if (expected !== null && typeName(value) !== expected) throw SwiftalkError.type(`${et.name}.${caseName} expects ${expected}, got ${typeName(value)}`);
    return value;
  });
  return new EnumCaseValue(et, caseName, associated);
}

export function containsSubstring(haystack, needle) {
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

export function* runBlock(body, env) {
  const scope = new Environment(env);
  let last = null;
  for (const statement of body) last = yield* execute(statement, scope);
  return last;
}
function* conditionsHold(conditions, scope) {
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
function* runLoopBody(body, env, freshScope = true, label = null) {
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
  constructor(next) { this.nextImpl = next; }
  *next() { return yield* this.nextImpl(); }         // undefined ends the sequence
}
const plainIter = (arr) => { let i = 0; return new ValueIterator(function* () { return i < arr.length ? arr[i++] : undefined; }); };
export function isSequenceValue(v) { return Builtins.conformance.get('Sequence').has(typeName(v)); }
export function* iteratorOf(sequence) {
  switch (kindOf(sequence)) {
    case 'array': return plainIter(sequence.items);
    case 'string': return plainIter(graphemes(sequence));
    case 'set': return plainIter(sequence.values());
    case 'dictionary': return plainIter(sequence.entries().map(([k, v]) => new TupleValue([k, v], ['key', 'value'])));
    case 'range': {
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
    case 'sequence': return makeIterator(sequence);
    case 'tuple': return plainIter(sequence.values);
    case 'data': return plainIter(Array.from(sequence.bytes, (b) => new Byte(b)));
    default: throw SwiftalkError.type(`cannot iterate a ${typeName(sequence)}`);
  }
}
function countingIterator(from) {
  let current = from;
  return new ValueIterator(function* () {
    if (current === null) throw SwiftalkError.overflow('this Range ran past Int.max');
    const v = current;
    current = v === INT64_MAX ? null : v + 1n;
    return v;
  });
}
export function requireFinite(value, member) {
  if (kindOf(value) === 'range' && value.to === null) throw SwiftalkError.type(`an unbounded Range is infinite — .prefix(n) or .prefix { } it before .${member}`);
}
export function lazyBase(receiver) {
  if (kindOf(receiver) === 'sequence') return receiver;
  if (kindOf(receiver) === 'range' && receiver.to === null) return new SequenceObject({ kind: 'counting', from: receiver.from });
  return null;
}
export function restamp(result, receiver) {
  let stampAnn = containerStamp(receiver);
  if (!stampAnn) { const known = knownElementLock(receiver); if (known) stampAnn = ann('Array', false, [known]); }
  if (!stampAnn) return result;
  const k = kindOf(result);
  if (k === 'array' && result.lock === null && stampAnn.name === 'Array') return new SArray(result.items, stampAnn);
  if (k === 'set' && result.lock === null && stampAnn.name === 'Set') return new SSet(result.values(), stampAnn);
  if (k === 'dictionary' && result.lock === null && stampAnn.name === 'Dictionary') return new SDictionary(result.entries(), stampAnn);
  return result;
}
export function reshape(kept, receiver) {
  switch (kindOf(receiver)) {
    case 'string': return kept.map((x) => (typeof x === 'string' ? x : '')).join('');
    case 'data': return new SData(kept.flatMap((x) => (x instanceof Byte ? [x.v] : (typeof x === 'bigint' && x >= 0n && x <= 255n) ? [Number(x)] : [])));
    case 'dictionary': return new SDictionary(kept.filter((p) => p instanceof TupleValue && p.count === 2).map((p) => [p.values[0], p.values[1]]));
    case 'set': return new SSet(kept);
    default: return new SArray(kept);
  }
}
export function* holds(fn, element, member) {
  const flag = yield* apply(fn, [{ label: null, value: element }]);
  if (typeof flag !== 'boolean') throw SwiftalkError.type(`the .${member} Function must return a Bool`);
  return flag;
}
export function* collect(sequence) {
  requireFinite(sequence, 'Array()');
  const out = [];
  const it = yield* iteratorOf(sequence);
  for (;;) { const e = yield* it.next(); if (e === undefined) break; out.push(e); }
  return out;
}
function makeIterator(seq) {
  const k = seq.k;
  switch (k.kind) {
    case 'generator': {
      let state = k.initial, done = false;
      return new ValueIterator(function* () {
        if (done) return undefined;
        const { result, local } = yield* run(k.next, state);
        if (result === null) { done = true; return undefined; }
        const next = local.lookup('$');
        if (kindOf(next) !== 'array') throw SwiftalkError.type("a Sequence generator's '$' must stay an Array");
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
    case 'native': { const next = k.make(); return new ValueIterator(function* () { const v = next(); const r = (v && typeof v.next === 'function') ? yield* v : v; return r === null || r === undefined ? undefined : r; }); }
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
    default: throw SwiftalkError.type(`FIXME: sequence kind ${k.kind}`);
  }
}
/// Coroutine sequences (round 52): the body runs as its own generator; a
/// `yield` statement inside surfaces as a {suspend:'yield'} request that
/// this iterator answers, resuming the body on the next pull.
function coroutineIterator(body) {
  let gen = null, done = false;
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
export function rangeCount(from, to, closed) {
  const span = to - from;
  if (!fits64(span) || (closed && span === INT64_MAX)) throw SwiftalkError.overflow("this Range's count does not fit in an Int");
  return closed ? span + 1n : span;
}

// ---- expressions ----
export function* evaluate(expr, env) {
  switch (expr.k) {
    case 'regexLiteral': return yield* regexLiteral(expr.pattern, expr.flags, env);
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
        if (f && kindOf(f) === 'function' && ['type', 'protocol', 'enumType', 'structType'].includes(f.role.k)) {
          return yield* apply(f, yield* evaluateArgs(expr.args, env));
        }
        if (resultCase) return constructEnumCase(Builtins.resultType, name, yield* evaluateArgs(expr.args, env), true);
      }
      const fn = yield* evaluate(callee, env);
      if (kindOf(fn) !== 'function') throw SwiftalkError.type(`cannot call a ${typeName(fn)}`);
      return yield* apply(fn, yield* evaluateArgs(expr.args, env));
    }
    case 'selfCall': {
      const fn = env.tryLookup(calleeKey);
      if (!fn || kindOf(fn) !== 'function') throw SwiftalkError.type("'$()' recurses — it only works inside a function");
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

function* evaluateSlow(expr, env) {
  switch (expr.k) {
    case 'switch': return yield* evaluateSwitch(expr.subject, expr.clauses, expr.defaultBody, env);
    case 'if': case 'literal': case 'variable': case 'binary': case 'bitwise': case 'bitNot': case 'comparison': case 'ternary':
    case 'call': case 'selfCall': case 'subscript': case 'regexLiteral':
      return yield* evaluate(expr, env);
    case 'tuple': {
      const values = [];
      for (const e of expr.elements) values.push(yield* evaluate(e.expr, env));
      return new TupleValue(values, expr.elements.map((e) => e.label));
    }
    case 'array': {
      const values = [];
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
      if (typeof operand === 'bigint') { if (operand === INT64_MIN) throw SwiftalkError.overflow(`negating ${operand}`); return -operand; }
      if (typeof operand === 'number') return -operand;
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
      if (kindOf(value) !== 'task') throw SwiftalkError.type(`can only await a Task — got ${typeName(value)}`);
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
      if (kindOf(v) === 'function' && annotationOfType(v)) return optionalType(v, env);
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
      if (kindOf(v) === 'dictionary') return coalesceDictionaries(v, yield* evaluate(expr.rhs, env), '??');
      return v;
    }
    case 'override': {
      const a = yield* evaluate(expr.lhs, env), b = yield* evaluate(expr.rhs, env);
      if (kindOf(b) === 'dictionary') return coalesceDictionaries(b, a, '!!');
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
    default: throw SwiftalkError.type(`FIXME: expression ${expr.k} is not ported`);
  }
}

function* evaluateMethodCall(expr, env) {
  const { receiver: receiverExpr, name, args: argExprs, called } = expr;
  if (called && (name === 'remove' || name === 'insert' || name === 'merge' || name === 'subtract')) {
    const mutated = yield* mutatingMethod(expr, env);
    if (mutated !== undefined) return mutated;
  }
  const receiver = yield* evaluate(receiverExpr, env);
  const evaluated = [];
  for (const a of argExprs) evaluated.push({ label: a.label, value: yield* evaluate(a.expr, env) });
  if (called) {
    if (name === 'append' && kindOf(receiver) === 'array') {
      const target = asLValue(receiverExpr);
      if (!target) throw SwiftalkError.type("'.append' mutates — call it on a var Array");
      if (!evaluated.length || !evaluated.every((a) => a.label === null)) throw SwiftalkError.type('.append takes unlabeled item(s)');
      yield* assign(target, new SArray([...receiver.items, ...evaluated.map((a) => a.value)], receiver.lock), env);
      return null;
    }
    let userMethod = null;
    if (asksCanonical(name, evaluated)) { /* the interpreter's word */ }
    else if (receiver instanceof StructValue && receiver.type.methods.has(name)) userMethod = receiver.type.methods.get(name);
    else if (receiver instanceof EnumCaseValue && receiver.type.methods.has(name)) userMethod = receiver.type.methods.get(name);
    else { const m = lookupExtension(env, typeName(receiver), name); if (m) userMethod = m; }
    if (userMethod) {
      const [bound, selfEnv] = boundMethod(userMethod, receiver, true);
      const result = yield* apply(bound, evaluated);
      const newSelf = selfEnv.lookup('self');
      if (!equals(newSelf, receiver) || (receiver instanceof StructValue && newSelf !== receiver && keyOf(newSelf) !== keyOf(receiver))) {
        const target = asLValue(receiverExpr);
        if (!target) throw SwiftalkError.type(`method '${name}' mutated a temporary — call it on a var`);
        yield* assign(target, newSelf, env);
      }
      return result;
    }
  }
  return yield* method(receiver, name, evaluated, called, env);
}
function* mutatingMethod(expr, env) {
  const { receiver: receiverExpr, name, args: argExprs } = expr;
  const container = yield* evaluate(receiverExpr, env);
  const k = kindOf(container);
  if (name === 'remove') {
    if (argExprs.length !== 1 || argExprs[0].label !== null) throw SwiftalkError.type('.remove(key) takes exactly one unlabeled argument');
    const target = asLValue(receiverExpr);
    if (!target) throw SwiftalkError.type(`cannot mutate an immutable ${typeName(container)} — bind it to a var first`);
    if (k === 'dictionary') {
      const key = yield* evaluate(argExprs[0].expr, env);
      const removed = container.has(key) ? container.get(key) : null;
      const d = container.clone(); d.delete(key);
      yield* assign(target, d, env);
      return removed;
    }
    if (k === 'set') {
      const x = yield* evaluate(argExprs[0].expr, env);
      const removed = container.has(x) ? container.map.get(keyOf(x)) : null;
      const s = container.clone(); s.delete(x);
      yield* assign(target, s, env);
      return removed;
    }
    throw SwiftalkError.unknownMember(`${typeName(container)}.remove()`);
  }
  if (name === 'insert') {
    if (argExprs.length !== 1 || argExprs[0].label !== null) throw SwiftalkError.type('.insert(x) takes exactly one unlabeled argument');
    if (k !== 'set') throw SwiftalkError.unknownMember(`${typeName(container)}.insert()`);
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
    const args = [];
    for (const a of argExprs) args.push({ label: a.label === 'uniquingKeysWith' ? null : a.label, value: yield* evaluate(a.expr, env) });
    if (k === 'dictionary') { yield* assign(target, yield* mergeDictionaries(container, plainValues(args, '.merge')), env); return null; }
    if (k === 'set') {
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
    const args = [];
    for (const a of argExprs) args.push({ label: a.label, value: yield* evaluate(a.expr, env) });
    const values = plainValues(args, '.subtract');
    if (values.length !== 1) throw SwiftalkError.type('.subtract takes one Set, or any Sequence');
    if (k === 'set') {
      const s = container.clone();
      for (const e of (yield* setElements(values[0])).values()) s.delete(e);
      yield* assign(target, s, env);
      return null;
    }
    if (k === 'dictionary') {
      const keys = kindOf(values[0]) === 'dictionary' ? new SSet(values[0].keys()) : yield* setElements(values[0]);
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
function sliceBounds(index, lower, upper, closed, count) {
  let end = BigInt(count);
  if (upper !== null) {
    end = closed ? upper + 1n : upper;
    if (!fits64(end)) throw SwiftalkError.type(`range ${sourceString(index)} is out of range (count ${count})`);
  }
  if (!(lower >= 0n && lower <= end && end <= BigInt(count))) throw SwiftalkError.type(`range ${sourceString(index)} is out of range (count ${count})`);
  return [Number(lower), Number(end)];
}
function position(i, count) {
  const resolved = i < 0n ? i + BigInt(count) : i;
  if (!(resolved >= 0n && resolved < BigInt(count))) throw SwiftalkError.type(`index ${i} out of range (count ${count})`);
  return Number(resolved);
}
export function subscriptRead(container, index) {
  switch (kindOf(container)) {
    case 'array':
      if (kindOf(index) === 'range') { const [a, b] = sliceBounds(index, index.from, index.to, index.closed, container.items.length); return new SArray(container.items.slice(a, b)); }
      if (typeof index !== 'bigint') throw SwiftalkError.type(`Array index must be an Int or a Range, not ${typeName(index)}`);
      return container.items[position(index, container.items.length)];
    case 'dictionary': { const v = container.get(index); return v === undefined ? null : v; }
    case 'range': {
      if (typeof index !== 'bigint') throw SwiftalkError.type(`Range index must be an Int, not ${typeName(index)}`);
      if (index < 0n) throw SwiftalkError.type(`Range index ${index} is out of range`);
      if (container.to !== null) {
        const count = rangeCount(container.from, container.to, container.closed);
        if (!(index < count)) throw SwiftalkError.type(`Range index ${index} is out of range (count ${count})`);
      }
      const v = container.from + index;
      if (!fits64(v)) throw SwiftalkError.overflow('this Range element does not fit in an Int');
      return v;
    }
    case 'data':
      if (kindOf(index) === 'range') { const [a, b] = sliceBounds(index, index.from, index.to, index.closed, container.bytes.length); return new SData(container.bytes.slice(a, b)); }
      if (typeof index !== 'bigint') throw SwiftalkError.type(`Data index must be an Int or a Range, not ${typeName(index)}`);
      return new Byte(container.bytes[position(index, container.bytes.length)]);
    case 'string': throw SwiftalkError.type('String subscripts are undecided (Design.md §11)');
    default: throw SwiftalkError.type(`cannot subscript ${typeName(container)}`);
  }
}
function subscriptWrite(container, index, newValue) {
  switch (kindOf(container)) {
    case 'array': {
      const items = container.items.slice();
      if (kindOf(index) === 'range') {
        if (kindOf(newValue) !== 'array') throw SwiftalkError.type(`assigning through a Range takes an Array, not a ${typeName(newValue)}`);
        const [a, b] = sliceBounds(index, index.from, index.to, index.closed, items.length);
        items.splice(a, b - a, ...newValue.items);
        return new SArray(items);
      }
      if (typeof index !== 'bigint') throw SwiftalkError.type(`Array index must be an Int or a Range, not ${typeName(index)}`);
      items[position(index, items.length)] = newValue;
      return new SArray(items);
    }
    case 'dictionary': { const d = container.clone(null); d.set(index, newValue); return d; }
    case 'data': {
      const bytes = Array.from(container.bytes);
      if (kindOf(index) === 'range') {
        if (kindOf(newValue) !== 'data') throw SwiftalkError.type(`assigning through a Range of a Data takes a Data, not a ${typeName(newValue)}`);
        const [a, b] = sliceBounds(index, index.from, index.to, index.closed, bytes.length);
        bytes.splice(a, b - a, ...newValue.bytes);
        return new SData(bytes);
      }
      if (typeof index !== 'bigint') throw SwiftalkError.type(`Data index must be an Int or a Range, not ${typeName(index)}`);
      const at = position(index, bytes.length);
      let byte;
      if (newValue instanceof Byte) byte = newValue.v;
      else if (typeof newValue === 'bigint' && newValue >= 0n && newValue <= 255n) byte = Number(newValue);
      else throw SwiftalkError.type(`a Data byte is a Byte, or an Int in 0...255, not ${sourceString(newValue)}`);
      bytes[at] = byte;
      return new SData(bytes);
    }
    case 'string': throw SwiftalkError.type('String subscripts are undecided (Design.md §11)');
    default: throw SwiftalkError.type(`cannot subscript ${typeName(container)}`);
  }
}
export function asLValue(expr) {
  switch (expr.k) {
    case 'variable': return { k: 'variable', name: expr.name };
    case 'subscript': { const inner = asLValue(expr.base); return inner ? { k: 'index', base: inner, index: expr.index } : null; }
    case 'method': { if (expr.called || expr.args.length) return null; const inner = asLValue(expr.receiver); return inner ? { k: 'property', base: inner, name: expr.name } : null; }
    case 'memberLiteral': return { k: 'property', base: { k: 'variable', name: 'self' }, name: expr.name };
    case 'tuple': {
      const targets = expr.elements.map((e) => asLValue(e.expr));
      if (targets.some((t) => t === null)) return null;
      return { k: 'tuple', elements: expr.elements.map((e, i) => ({ label: e.label, target: targets[i] })) };
    }
    default: return null;
  }
}
function select(tuple, labels, what) {
  if (tuple.count !== labels.length) throw SwiftalkError.type(`cannot destructure a ${tuple.count}-tuple into ${labels.length} ${what}`);
  return labels.map((label, pos) => {
    if (label === null) return tuple.values[pos];
    const index = tuple.indexOfLabel(label);
    if (index === null) throw SwiftalkError.type(`the tuple has no element labeled '${label}'`);
    return tuple.values[index];
  });
}
export function bind(pattern, value, mutable, env, strict) {
  if (pattern.k === 'name') {
    if (pattern.name === '_') return;
    const lock = strict ? inferLock(value, pattern.name) : ann(typeName(value), true);
    env.declare(pattern.name, new Binding(mutable, lock, value));
    return;
  }
  if (!(value instanceof TupleValue)) throw SwiftalkError.type(`cannot destructure a ${typeName(value)} — a tuple pattern needs a Tuple`);
  const values = select(value, pattern.elements.map((e) => e.label), 'names');
  pattern.elements.forEach((e, i) => bind(e.pattern, values[i], mutable, env, strict));
}
function* assignRelaxed(target, value, env) {
  if (target.k === 'tuple') {
    if (!(value instanceof TupleValue)) throw SwiftalkError.type(`cannot assign a ${typeName(value)} to ${target.elements.length} targets`);
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
export function makeComputed(exprs, env) {
  const out = new Map();
  for (const [name, spec] of exprs) {
    if (spec.get.k !== 'function') continue;
    const setter = spec.set && spec.set.k === 'function' ? new FunctionObject(spec.set.parameters, spec.set.body, env) : null;
    out.set(name, { annotation: spec.annotation, get: new FunctionObject(spec.get.parameters, spec.get.body, env), set: setter });
  }
  return out;
}
export function computedProperty(receiver, name) {
  return receiver instanceof StructValue ? (receiver.type.computed.get(name) ?? null) : null;
}
export function* readComputed(c, receiver) {
  const [bound] = boundMethod(c.get, receiver);
  const value = yield* apply(bound, []);
  if (c.annotation) checkValue(value, c.annotation, `computed ${typeName(receiver)} property`);
  return value;
}
export function* writeComputed(c, receiver, name, newValue) {
  if (!c.set) throw SwiftalkError.type(`${typeName(receiver)}.${name} is a read-only computed property`);
  if (c.annotation) checkValue(newValue, c.annotation, `${typeName(receiver)}.${name}`);
  const [bound, selfEnv] = boundMethod(c.set, receiver, true);
  yield* apply(bound, [{ label: null, value: newValue }]);
  return selfEnv.lookup('self');
}
function makeObservers(order, props, env) {
  const out = new Map();
  for (const name of order) {
    const p = props.get(name);
    if (!p || (!p.willSetExpr && !p.didSetExpr)) continue;
    const build = (e) => (e && e.k === 'function' ? new FunctionObject(e.parameters, e.body, env) : null);
    out.set(name, { will: build(p.willSetExpr), did: build(p.didSetExpr) });
  }
  return out;
}
export function makeMethods(exprs, env) {
  const out = new Map();
  for (const [name, expr] of exprs) if (expr.k === 'function') out.set(name, new FunctionObject(expr.parameters, expr.body, env));
  return out;
}
export function lookupExtension(env, typeNameText, name) {
  const v = env.tryLookup(`@ext:${typeNameText}:${name}`);
  return v && kindOf(v) === 'function' ? v : null;
}
export function boundMethod(m, receiver, mutableSelf = false) {
  const selfEnv = new Environment(m.closure);
  selfEnv.declare('self', new Binding(mutableSelf, ann(typeName(receiver)), receiver));
  return [new FunctionObject(m.parameters, m.body, selfEnv), selfEnv];
}
function initMatches(params, args) {
  if (params.length === 0) return true;
  if (args.length !== params.length) return false;
  const used = new Set();
  for (const a of args) if (a.label !== null) {
    if (!params.includes(a.label) || used.has(a.label)) return false;
    used.add(a.label);
  }
  return true;
}
const observerGuard = new Set();
export function* constructStruct(st, args) {
  for (const initFn of st.inits) {
    if (!initMatches(initFn.parameters, args)) continue;
    const values = new Map();
    for (const prop of st.propertyOrder) {
      const def = st.properties.get(prop);
      values.set(prop, def.defaultExpr ? yield* evaluate(def.defaultExpr, new Environment(st.declEnv)) : null);
    }
    const underConstruction = new StructValue(st, values);
    const [fn, selfEnv] = boundMethod(initFn, underConstruction, true);
    const claimed = [...st.observers.keys()].map((k) => `${st.name}.${k}`).filter((key) => { if (observerGuard.has(key)) return false; observerGuard.add(key); return true; });
    try { yield* apply(fn, args); } finally { for (const key of claimed) observerGuard.delete(key); }
    const sv = selfEnv.lookup('self');
    for (const prop of st.propertyOrder) {
      const a = st.properties.get(prop).annotation;
      if (a && !a.optional && a.name !== 'Nil' && (sv.values.get(prop) ?? null) === null) throw SwiftalkError.type(`${st.name}.${prop} was not initialized by init`);
    }
    return sv;
  }
  const slots = new Map();
  const positionals = [];
  for (const a of args) {
    if (a.label !== null) {
      if (!st.properties.has(a.label)) throw SwiftalkError.type(`${st.name} has no property '${a.label}'`);
      if (slots.has(a.label)) throw SwiftalkError.type(`duplicate property '${a.label}'`);
      slots.set(a.label, a.value);
    } else positionals.push(a.value);
  }
  const values = new Map();
  for (const prop of st.propertyOrder) {
    const def = st.properties.get(prop);
    let value;
    if (slots.has(prop)) value = slots.get(prop);
    else if (positionals.length) value = positionals.shift();
    else if (def.defaultExpr) value = yield* evaluate(def.defaultExpr, new Environment(st.declEnv));
    else throw SwiftalkError.type(`missing property '${prop}' of ${st.name}`);
    if (def.annotation) { checkValue(value, def.annotation, `${st.name}.${prop}`); value = stamp(value, def.annotation); }
    values.set(prop, value);
  }
  if (positionals.length) throw SwiftalkError.type(`too many values for ${st.name}`);
  return new StructValue(st, values);
}
function* propertyRead(container, name) {
  if (container instanceof TupleValue) {
    const index = /^\d+$/.test(name) ? Number(name) : container.indexOfLabel(name);
    if (index !== null && index !== undefined) {
      if (!(index >= 0 && index < container.count)) throw SwiftalkError.type(`tuple index ${index} out of range (count ${container.count})`);
      return container.values[index];
    }
  }
  if (!(container instanceof StructValue)) throw SwiftalkError.type(`cannot assign through a property of ${typeName(container)}`);
  const c = container.type.computed.get(name);
  if (c) return yield* readComputed(c, container);
  if (!container.values.has(name)) throw SwiftalkError.unknownMember(`${container.type.name}.${name}`);
  return container.values.get(name);
}
function* propertyWrite(container, name, newValue) {
  if (container instanceof TupleValue) {
    const index = /^\d+$/.test(name) ? Number(name) : container.indexOfLabel(name);
    if (index !== null && index !== undefined) {
      if (!(index >= 0 && index < container.count)) throw SwiftalkError.type(`tuple index ${index} out of range (count ${container.count})`);
      const values = container.values.slice(); values[index] = newValue;
      return new TupleValue(values, container.labels);
    }
  }
  if (kindOf(container) === 'host') {
    const ok = container.object.setMember ? container.object.setMember(name, newValue) : false;
    if (!ok) throw SwiftalkError.type(`cannot assign to ${container.object.typeName}.${name}`);
    return container;
  }
  if (!(container instanceof StructValue)) throw SwiftalkError.type(`cannot assign through a property of ${typeName(container)}`);
  const sv = container.clone();
  const c = sv.type.computed.get(name);
  if (c) return yield* writeComputed(c, container, name, newValue);
  const def = sv.type.properties.get(name);
  if (!def || !sv.values.has(name)) throw SwiftalkError.unknownMember(`${sv.type.name}.${name}`);
  const current = sv.values.get(name);
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
export function isAbsent(v) { return v === null || (isResult(v) && v.caseName === 'failure'); }

export function* assign(target, value, env, combine = null) {
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
  const steps = [];
  let root = target;
  for (;;) {
    if (root.k === 'index') { steps.unshift({ index: yield* evaluate(root.index, env) }); root = root.base; }
    else if (root.k === 'property') { steps.unshift({ property: root.name }); root = root.base; }
    else if (root.k === 'variable') break;
    else throw SwiftalkError.type('a tuple pattern cannot be part of an assignment path');
  }
  const name = root.name;
  const landing = function* (old) { return combine ? yield* combine(yield* old()) : value; };
  if (steps.length === 0) {
    const final = yield* landing(function* () { return env.lookup(name); });
    env.assign(name, final);
    return final;
  }
  let written = value;
  const read = function* (container, step) { return 'index' in step ? subscriptRead(container, step.index) : yield* propertyRead(container, step.property); };
  const write = function* (container, step, v) { return 'index' in step ? subscriptWrite(container, step.index, v) : yield* propertyWrite(container, step.property, v); };
  const rebuild = function* (container, depth) {
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
export function* evaluateArgs(args, env) {
  const out = [];
  for (const a of args) out.push({ label: a.label, value: yield* evaluate(a.expr, env) });
  return out;
}

// ---- application ----
export function* apply(fn, args) {
  if (fn.role.k === 'structType') {
    if (fn.role.type.isModule) throw SwiftalkError.type(`${fn.role.type.name} is a module, not a type with instances — its members are ${fn.role.type.name}.name`);
    return yield* constructStruct(fn.role.type, args);
  }
  if (fn.role.k === 'type') {
    const tn = fn.role.name;
    if (fn.builtin && !Builtins.types.has(tn) && !Builtins.protocols.has(tn)) return yield* callBuiltin(fn.builtin, args.map((a) => a.value));
    let subject = undefined;
    const extra = [];
    args.forEach((a, i) => { if (i === 0 && a.label === null) subject = a.value; else extra.push(a); });
    const built = yield* convert(tn, subject, extra);
    if (fn.annotation) { checkValue(built, fn.annotation, `${fn.annotation.display}()`); return stamp(built, fn.annotation); }
    return built;
  }
  if (!fn.builtin && args.length === 1 && args[0].label === null && args[0].value instanceof TupleValue) {
    args = args[0].value.values.map((v) => ({ label: null, value: v }));
  }
  let ordered;
  if (fn.parameters.length === 0) {
    const label = args.map((a) => a.label).find((l) => l !== null);
    if (label !== undefined) throw SwiftalkError.type(`unknown argument label '${label}': this function declares no parameter names`);
    ordered = args.map((a) => a.value);
  } else {
    if (args.length !== fn.parameters.length) throw SwiftalkError.type(`expected ${fn.parameters.length} argument(s), got ${args.length}`);
    const slots = new Array(fn.parameters.length).fill(undefined);
    for (const a of args) if (a.label !== null) {
      const index = fn.parameters.indexOf(a.label);
      if (index < 0) throw SwiftalkError.type(`unknown argument label '${a.label}'`);
      if (slots[index] !== undefined) throw SwiftalkError.type(`duplicate argument label '${a.label}'`);
      slots[index] = a.value;
    }
    const positionals = args.filter((a) => a.label === null).map((a) => a.value);
    ordered = slots.map((slot) => {
      if (slot !== undefined) return slot;
      if (!positionals.length) throw SwiftalkError.type('missing argument');
      return positionals.shift();
    });
  }
  if (fn.builtin) return yield* callBuiltin(fn.builtin, ordered);
  return (yield* run(fn, ordered)).result;
}
export function* run(fn, ordered) {
  const local = new Environment(fn.closure);
  if (fn.builtin) return { result: yield* callBuiltin(fn.builtin, ordered), local };
  fn.parameters.forEach((name, i) => { if (name !== '_') local.declare(name, new Binding(false, ann(typeName(ordered[i]), true), ordered[i])); });
  local.declare('$', new Binding(true, ann('Array'), new SArray(ordered)));
  ordered.forEach((value, index) => local.declare(`$${index}`, new Binding(false, ann(typeName(value), true), value)));
  local.declare(calleeKey, new Binding(false, ann('Function'), fn));
  let last = null;
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
export function* userOperator(key, operands) {
  for (const v of operands) {
    let table = null;
    if (v instanceof StructValue) table = v.type.operators;
    else if (v instanceof EnumCaseValue) table = v.type.operators;
    else continue;
    const fn = table.get(key);
    if (fn) return yield* apply(fn, operands.map((x) => ({ label: null, value: x })));
  }
  return undefined;
}
export function hasUserOperator(v, key) {
  if (v instanceof StructValue) return v.type.operators.has(key);
  if (v instanceof EnumCaseValue) return v.type.operators.has(key);
  return false;
}
const userTyped = (v) => v instanceof StructValue || (v instanceof EnumCaseValue && !isResult(v));
const byteOrInt = (v) => (v instanceof Byte ? BigInt(v.v) : v);
export function* bitwise(op, lhs, rhs) {
  const r = yield* userOperator(`infix:${op}`, [lhs, rhs]);
  if (r !== undefined) return r;
  const combine = (a, b) => {
    switch (op) {
      case '+&': return a & b;
      case '+|': return a | b;
      case '+^': return a ^ b;
      case '+<': return b >= 64n ? 0n : b <= -64n ? (a < 0n ? -1n : 0n) : b >= 0n ? BigInt.asIntN(64, a << b) : a >> -b;
      default: return b >= 64n ? (a < 0n ? -1n : 0n) : b <= -64n ? 0n : b >= 0n ? a >> b : BigInt.asIntN(64, a << -b);
    }
  };
  const kl = kindOf(lhs), kr = kindOf(rhs);
  if (kl === 'byte' && kr === 'byte') return new Byte(Number(BigInt.asUintN(8, combine(BigInt(lhs.v), BigInt(rhs.v)))));
  if ((kl === 'byte' || kl === 'int') && (kr === 'byte' || kr === 'int')) return combine(byteOrInt(lhs), byteOrInt(rhs));
  throw SwiftalkError.type(`'${op}' is a bitwise operator on Ints and Bytes — not defined between ${typeName(lhs)} and ${typeName(rhs)}`
    + ((kl === 'bool' || kr === 'bool') ? '; Bools use && || ^^ !' : '') + ((kl === 'set' || kr === 'set') ? '; Sets use & | ^' : ''));
}
export function* bitNot(operand) {
  const r = yield* userOperator('prefix:+^', [operand]);
  if (r !== undefined) return r;
  if (typeof operand === 'bigint') return ~operand;
  if (operand instanceof Byte) return new Byte(~operand.v & 0xff);
  throw SwiftalkError.type(`prefix '+^' is bitwise not, on an Int or a Byte — not ${typeName(operand)}`);
}
export function* binary(op, lhs, rhs) {
  const r = yield* userOperator(`infix:${op}`, [lhs, rhs]);
  if (r !== undefined) return r;
  const kl = kindOf(lhs), kr = kindOf(rhs);
  if ('|&^'.includes(op) && !(kl === 'set' && kr === 'set')) {
    throw SwiftalkError.type(`'${op}' is a Set operator — not defined between ${typeName(lhs)} and ${typeName(rhs)}; Bools use '${op}${op}', Ints +${op}`);
  }
  if (kl === 'byte' && kr === 'byte') {
    const a = lhs.v, b = rhs.v;
    if ((op === '/' || op === '%') && b === 0) throw SwiftalkError.zeroDivision();
    let result;
    switch (op) {
      case '+': result = a + b; break; case '-': result = a - b; break; case '*': result = a * b; break;
      case '/': result = Math.trunc(a / b); break; case '%': result = a % b; break;
      default: throw SwiftalkError.type(`'${op}' is not defined between Byte and Byte`);
    }
    if (result < 0 || result > 255) throw SwiftalkError.overflow(`Byte(${a}) ${op} Byte(${b})`);
    return new Byte(result);
  }
  if (kl === 'byte' && kr === 'int') return yield* binary(op, BigInt(lhs.v), rhs);
  if (kl === 'int' && kr === 'byte') return yield* binary(op, lhs, BigInt(rhs.v));
  if (kl === 'int' && kr === 'int') {
    const a = lhs, b = rhs;
    if ((op === '/' || op === '%') && b === 0n) throw SwiftalkError.zeroDivision();
    let result;
    switch (op) {
      case '+': result = a + b; break; case '-': result = a - b; break; case '*': result = a * b; break;
      case '/': result = a / b; break;
      case '%': if (a === INT64_MIN && b === -1n) throw SwiftalkError.overflow(`${a} % ${b}`); result = a % b; break;   // Swift traps: the quotient overflows
      default: throw SwiftalkError.type(`'${op}' is not defined between Int and Int`);
    }
    if (!fits64(result)) throw SwiftalkError.overflow(`${a} ${op} ${b}`);
    return result;
  }
  if (kl === 'double' && kr === 'double') {
    switch (op) {
      case '+': return lhs + rhs; case '-': return lhs - rhs; case '*': return lhs * rhs; case '/': return lhs / rhs;
      case '%': throw SwiftalkError.type("'%' is for Ints — as in Swift, a Double has no remainder operator");
      default: break;
    }
  }
  if (kl === 'string' && kr === 'string' && op === '+') return lhs + rhs;
  if (kl === 'array' && kr === 'array' && op === '+') return new SArray([...lhs.items, ...rhs.items]);
  if (kl === 'set' && kr === 'set') {
    switch (op) {
      case '|': { const s = lhs.clone(null); for (const e of rhs.values()) s.add(e); return s; }
      case '-': { const s = lhs.clone(null); for (const e of rhs.values()) s.delete(e); return s; }
      case '&': return new SSet(lhs.values().filter((e) => rhs.has(e)));
      case '^': return new SSet([...lhs.values().filter((e) => !rhs.has(e)), ...rhs.values().filter((e) => !lhs.has(e))]);
      default: break;
    }
  }
  throw SwiftalkError.type(`'${op}' is not defined between ${typeName(lhs)} and ${typeName(rhs)}`);
}
export function* setElements(value) {
  if (kindOf(value) === 'set') return value;
  return new SSet(yield* collect(value));
}
export function coalesceDictionaries(base, fill, op) {
  if (kindOf(fill) !== 'dictionary') throw SwiftalkError.type(`'${op}' between a Dictionary and a ${typeName(fill)} — a Dictionary coalesces with a Dictionary`);
  const out = base.clone(null);
  for (const [key, value] of fill.entries()) { const cur = out.get(key); if (cur === undefined || isAbsent(cur)) out.set(key, value); }
  return out;
}
export function* mergeDictionaries(base, args) {
  if (!(args.length === 1 || args.length === 2) || kindOf(args[0]) !== 'dictionary') throw SwiftalkError.type('.merging(dictionary) { current, new in } — a Dictionary, and optionally a function');
  let combine = null;
  if (args.length === 2) { if (kindOf(args[1]) !== 'function') throw SwiftalkError.type(".merging's second argument is the combine function: { current, new in }"); combine = args[1]; }
  const merged = base.clone(null);
  for (const [key, nu] of args[0].entries()) {
    const current = merged.get(key);
    if (combine && current !== undefined) merged.set(key, yield* apply(combine, [{ label: null, value: current }, { label: null, value: nu }]));
    else merged.set(key, nu);
  }
  return merged;
}
export function identical(a, b) {
  const ka = kindOf(a), kb = kindOf(b);
  if (ka !== kb) return false;
  const all = (xs, ys) => xs.length === ys.length && xs.every((x, i) => identical(x, ys[i]));
  switch (ka) {
    case 'double': return Object.is(a, b) || (Number.isNaN(a) && Number.isNaN(b));
    case 'string': return a === b;
    case 'array': return all(a.items, b.items);
    case 'tuple': return all(a.values, b.values);
    case 'dictionary': return a.size === b.size && a.entries().every(([k, v]) => b.entries().some(([k2, v2]) => identical(k, k2) && identical(v, v2)));
    case 'structValue': return a.type === b.type && a.values.size === b.values.size && [...a.values].every(([k, v]) => b.values.has(k) && identical(v, b.values.get(k)));
    case 'enumCase': return a.type === b.type && a.caseName === b.caseName && all(a.associated, b.associated);
    default: return equals(a, b);
  }
}
export function* compare(op, lhs, rhs) {
  if (op !== '===' && op !== '!==' && (userTyped(lhs) || userTyped(rhs))) {
    const bool = (v, negated = false) => {
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
  const kl = kindOf(lhs), kr = kindOf(rhs);
  if (op === '==' || op === '!=') {
    const byteInt = (kl === 'byte' && kr === 'int') || (kl === 'int' && kr === 'byte');
    if (lhs !== null && rhs !== null && !byteInt && typeName(lhs) !== typeName(rhs)) throw SwiftalkError.type(`'${op}' is not defined between ${typeName(lhs)} and ${typeName(rhs)}`);
    return op === '==' ? equals(lhs, rhs) : !equals(lhs, rhs);
  }
  if (op === '===' || op === '!==') return identical(lhs, rhs) === (op === '===');
  let ascending;
  if ((kl === 'int' || kl === 'byte') && (kr === 'int' || kr === 'byte')) ascending = byteOrInt(lhs) < byteOrInt(rhs);
  else if (kl === 'double' && kr === 'double') ascending = lhs < rhs;
  else if (kl === 'string' && kr === 'string') ascending = compareStrings(lhs, rhs) < 0;
  else if (kl === 'date' && kr === 'date') ascending = lhs.epoch < rhs.epoch;
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
const operatorTable = new Map();
export function operatorFunction(op) {
  let f = operatorTable.get(op);
  if (!f) {
    f = new FunctionObject([], [], Builtins.emptyEnvironment, function* (args) { return yield* applyOperator(op, args); }, { k: 'operator', op });
    operatorTable.set(op, f);
  }
  return f;
}
function* applyOperator(op, args) {
  if (args.length === 1) {
    switch (op) {
      case '-': {
        const r = yield* userOperator('prefix:-', [args[0]]); if (r !== undefined) return r;
        const v = args[0];
        if (typeof v === 'bigint') { if (v === INT64_MIN) throw SwiftalkError.overflow(`negating ${v}`); return -v; }
        if (typeof v === 'number') return -v;
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
      case '??': if (kindOf(a) === 'dictionary') return coalesceDictionaries(a, b, '??'); return isAbsent(a) ? b : a;
      case '!!': if (kindOf(b) === 'dictionary') return coalesceDictionaries(b, a, '!!'); return isAbsent(b) ? a : b;
      default: throw SwiftalkError.type(`(${op}) is not a function`);
    }
  }
  const unary = ['-', '+', '!'].includes(op) ? 'one or ' : '';
  throw SwiftalkError.type(`(${op}) takes ${unary}two arguments, got ${args.length}`);
}

// ---- types: scopes and statics ----
export function typeScope(env, type) {
  const scope = new Environment(env);
  try { scope.declare('Self', new Binding(false, ann('Function'), type)); } catch (e) { /* unreachable */ }
  return scope;
}
export function installStatics(spec, typeEnv, holder, typeNameText, overwrite) {
  const out = { thunks: new Map(), getters: new Map(), ops: new Map() };
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
export function mergeStatics(entries, holder) {
  for (const [name, t] of entries.thunks) { holder.staticGetters.delete(name); holder.statics.delete(name); holder.staticThunks.set(name, t); }
  for (const [name, g] of entries.getters) { holder.statics.delete(name); holder.staticThunks.delete(name); holder.staticGetters.set(name, g); }
  for (const [key, f] of entries.ops) holder.operators.set(key, f);
}
export function* resolveStatic(name, holder) {
  if (holder.statics.has(name)) return holder.statics.get(name);
  const thunk = holder.staticThunks.get(name);
  if (!thunk) return undefined;
  holder.staticThunks.delete(name);
  let value;
  try { value = yield* evaluate(thunk.expr, thunk.env); }
  catch (e) { holder.staticThunks.set(name, thunk); throw e; }
  holder.statics.set(name, value);
  return value;
}

// ---- tasks (milestone C): the requests the scheduler answers ----
export function* spawnTask(f) {
  const answer = yield { suspend: 'spawn', body: f };
  if (!answer || !answer.task) throw SwiftalkError.type('Task { ... } needs a running Interpreter');
  return answer.task;
}
export function* awaitTask(task) {
  const answer = yield { suspend: 'await', task };
  if (!answer || !('value' in answer)) throw SwiftalkError.type("'await' needs a running Interpreter");
  return answer.value;
}
