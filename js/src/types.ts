// Type locks, stamps, inference — Eval.swift's checkValue, inferLock,
// stamp, admits, knownElementLock, typeValue, annotationOfType.
import { SwiftalkError } from './errors.js';
import { TypeAnnotation } from './parser.js';
import { kindOf, typeName, SArray, SDictionary, SSet, keyOf, sourceString, must, isArray, isDictionary, isSet, isFunction, isRange, isString, isData, isSequence, isContainer } from './value.js';
import { FunctionObject, isGenerator } from './objects.js';
import type { Builtin, EnumType, G } from './objects.js';
import { hooks } from './env.js';
import type { Environment } from './env.js';
import { Builtins } from './builtins.js';
import type { Value, Lock } from './value.js';

export const knownTypeNames = new Set(['Context', 'Nil', 'Bool', 'Int', 'Double', 'String', 'Array', 'Dictionary', 'Set', 'Function',
  'Range', 'Sequence', 'Data', 'Date', 'Task', 'Tuple', 'Byte', 'SION', 'Any']);
export const ann = (name: string, optional = false, parameters: TypeAnnotation[] = []): TypeAnnotation => new TypeAnnotation(name, optional, parameters);

export function isSION(v: Value): boolean {
  if (isArray(v)) return v.items.every(isSION);
  if (isDictionary(v)) return v.entries().every(([k, x]) => isSION(k) && isSION(x));
  switch (kindOf(v)) {
    case 'nil': case 'bool': case 'int': case 'double': case 'string': case 'data': case 'date': return true;
    default: return false;
  }
}
export function typeMatches(value: Value, lockName: string): boolean { return typeName(value) === lockName; }

export function isUserType(name: string, env: Environment): boolean {
  const v = env.tryLookup(name);
  if (!isFunction(v)) return false;
  switch (v.role.k) {
    case 'enumType': case 'structType': return true;
    case 'type': return v.builtin !== null && !Builtins.types.has(v.role.name);
    default: return false;
  }
}
export function resolveTypeNames(annotation: TypeAnnotation, env: Environment): TypeAnnotation {
  let name = annotation.name;
  if (!knownTypeNames.has(name)) {
    const f = env.tryLookup(name);
    if (isFunction(f)) {
      if (f.annotation) return new TypeAnnotation(f.annotation.name, annotation.optional || f.annotation.optional, f.annotation.parameters);
      switch (f.role.k) {
        case 'type': name = f.role.name; break;
        case 'enumType': case 'structType': name = f.role.type.name; break;
        default: break;
      }
    }
  }
  return new TypeAnnotation(name, annotation.optional, annotation.parameters.map((p) => resolveTypeNames(p, env)));
}
export function annotationIsKnown(annotation: TypeAnnotation, env: Environment): boolean {
  return (knownTypeNames.has(annotation.name) || isUserType(annotation.name, env))
    && annotation.parameters.every((p) => annotationIsKnown(p, env));
}
export function resolveEnumAnnotation(annotation: TypeAnnotation, env: Environment): EnumType | null {
  if (knownTypeNames.has(annotation.name)) return null;
  const v = env.tryLookup(annotation.name);
  if (isFunction(v) && v.role.k === 'enumType') return v.role.type;
  return null;
}

export function containerStamp(v: Value): Lock {
  return isContainer(v) ? v.lock : null;
}
export function isSIONType(t: TypeAnnotation): boolean {
  switch (t.name) {
    case 'Nil': case 'Bool': case 'Int': case 'Double': case 'String': case 'Data': case 'Date': case 'SION': return true;
    case 'Array': case 'Dictionary': return t.parameters.every(isSIONType);
    default: return false;
  }
}
export function admits(lock: TypeAnnotation, other: TypeAnnotation): boolean {
  if (lock.name === 'Any') return true;
  if (lock.name === 'SION') return isSIONType(other);
  if (lock.name !== other.name) return false;
  if (other.optional && !lock.optional) return false;
  if (lock.parameters.length === 0 || other.parameters.length === 0) return true;
  if (lock.parameters.length !== other.parameters.length) return false;
  return lock.parameters.every((p, i) => admits(p, other.parameters[i]));
}
export function stamp(value: Value, lock: Lock): Value {
  if (!lock || lock.parameters.length === 0) return value;
  const own = new TypeAnnotation(lock.name, false, lock.parameters);
  if (isArray(value) && lock.name === 'Array') {
    const e = lock.parameters[0];
    return new SArray(e.parameters.length ? value.items.map((x) => stamp(x, e)) : value.items, own);
  }
  if (isSet(value) && lock.name === 'Set') {
    const e = lock.parameters[0];
    return new SSet(e.parameters.length ? value.values().map((x) => stamp(x, e)) : value.values(), own);
  }
  if (isDictionary(value) && lock.name === 'Dictionary' && lock.parameters.length === 2) {
    const v = lock.parameters[1];
    return new SDictionary(value.entries().map(([key, x]): [Value, Value] => [key, v.parameters.length ? stamp(x, v) : x]), own);
  }
  return value;
}
export function checkValue(value: Value, lock: TypeAnnotation, context: string): void {
  if (value === null) {
    if (lock.optional || lock.name === 'Nil' || lock.name === 'Any' || lock.name === 'SION') return;
    throw SwiftalkError.type(`cannot assign nil to ${context} of type ${lock.display} — declare it ${lock.display}?`);
  }
  if (lock.name === 'Any') return;
  if (lock.name === 'SION') {
    if (!isSION(value)) throw SwiftalkError.type(`cannot assign ${typeName(value)} to ${context} of type SION`);
    return;
  }
  if (!typeMatches(value, lock.name)) throw SwiftalkError.type(`cannot assign ${typeName(value)} to ${context} of type ${lock.display}`);
  if (lock.parameters.length) {
    const s = containerStamp(value);
    if (s && !admits(lock, s)) throw SwiftalkError.type(`cannot assign ${s.display} to ${context} of type ${lock.display}`);
  }
  if (lock.name === 'Array' && lock.parameters.length === 1 && isArray(value)) {
    value.items.forEach((e, i) => checkValue(e, lock.parameters[0], `${context}[${i}]`));
  }
  if (lock.name === 'Set' && lock.parameters.length === 1 && isSet(value)) {
    for (const e of value.values()) checkValue(e, lock.parameters[0], `an element of ${context}`);
  }
  if (lock.name === 'Dictionary' && lock.parameters.length === 2 && isDictionary(value)) {
    for (const [key, val] of value.entries()) {
      checkValue(key, lock.parameters[0], `a key of ${context}`);
      if (val !== null) checkValue(val, lock.parameters[1], `${context}[${sourceString(key)}]`);
    }
  }
}
hooks.stamp = stamp;
hooks.checkValue = (v, lock, what) => { if (lock) checkValue(v, lock, what); };

export function knownElementLock(v: Value): Lock {
  if (isRange(v)) return ann('Int');
  if (isString(v)) return ann('String');
  if (isData(v)) return ann('Byte');
  if (isArray(v) || isSet(v)) return v.lock ? (v.lock.parameters[0] ?? null) : null;
  if (isDictionary(v)) return ann('Tuple');
  if (isSequence(v)) {
    const s = v.k;
    switch (s.kind) {
      case 'counting': return ann('Int');
      case 'filtered': case 'takenWhile': case 'droppedWhile': case 'dropped': return knownElementLock(s.base);
      case 'enumerated': return ann('Tuple');
      case 'native': return s.element ?? null;
      default: return null;
    }
  }
  return null;
}
export function stampedArray(elements: Value[], receiver: Value): SArray {
  const inferred = tryInfer(new SArray(elements), 'Array', false);
  if (inferred && inferred.parameters.length) return new SArray(elements, inferred);
  const known = knownElementLock(receiver);
  if (known) return new SArray(elements, ann('Array', false, [known]));
  return new SArray(elements);
}
export function tryInfer(value: Value, name: string, defaulting: boolean): TypeAnnotation | null {
  try { return inferLock(value, name, defaulting); } catch (e) { if (e instanceof SwiftalkError) return null; throw e; }
}

export function annotationOfType(value: Value): TypeAnnotation | null {
  if (!isFunction(value)) return null;
  if (value.annotation) return value.annotation;
  switch (value.role.k) {
    case 'type': return ann(value.role.name);
    case 'protocol': return value.role.name === 'Sequence' ? ann('Sequence') : null;
    case 'enumType': case 'structType': return ann(value.role.type.name);
    default: return null;
  }
}
/// The type value for a builtin annotation (round 165).
export function typeValue(annotation: TypeAnnotation): FunctionObject | null {
  const base = Builtins.types.get(annotation.name);
  if (!base) return null;
  if (annotation.parameters.length === 0 && !annotation.optional) return base;
  const own = annotation;
  return new FunctionObject([], [], base.closure, function* (args: Value[]) {
    const built = yield* callBuiltin(must(base.builtin, `${annotation.name}'s constructor`), args);
    checkValue(built, own, `${own.display}()`);
    return stamp(built, own);
  }, { k: 'type', name: annotation.name }, own);
}
/// A builtin body may be plain or a generator; this runs either.
export function* callBuiltin(builtin: Builtin, args: Value[]): G<Value> {
  const r = builtin(args);
  return isGenerator(r) ? yield* r : r;
}
export function optionalType(f: FunctionObject, env: Environment): FunctionObject | null {
  const base = annotationOfType(f);
  if (!base) return f;
  if (base.optional) return f;
  const own = new TypeAnnotation(base.name, true, base.parameters);
  if (f.role.k === 'type' && Builtins.types.has(base.name)) return typeValue(own);
  return new FunctionObject(f.parameters, f.body, f.closure, f.builtin, f.role, own);
}
export function typeValueForParameter(annotation: TypeAnnotation, env: Environment): FunctionObject | null {
  if (annotation.name === 'Any') throw SwiftalkError.type(`${annotation.display} is an annotation, not a value`);
  if (Builtins.types.has(annotation.name)) return typeValue(annotation);
  let plain: FunctionObject | undefined = Builtins.protocols.get(annotation.name);
  if (!plain) {
    const t = env.tryLookup(annotation.name);
    if (!isFunction(t) || !annotationOfType(t)) throw SwiftalkError.type(`no type named ${annotation.display} is in scope`);
    plain = t;
  }
  return annotation.optional ? optionalType(plain, env) : plain;
}

function unify(a: TypeAnnotation, b: TypeAnnotation): TypeAnnotation | null {
  if (a.equals(b)) return a;
  if (a.name !== b.name || a.optional !== b.optional) return null;
  if (a.parameters.length === 0) return b;
  if (b.parameters.length === 0) return a;
  if (a.parameters.length !== b.parameters.length) return null;
  const parameters: TypeAnnotation[] = [];
  for (let i = 0; i < a.parameters.length; i++) {
    const j = unify(a.parameters[i], b.parameters[i]);
    if (!j) return null;
    parameters.push(j);
  }
  return new TypeAnnotation(a.name, a.optional, parameters);
}
function defaulted(t: TypeAnnotation): TypeAnnotation {
  const sion = ann('SION');
  if ((t.name === 'Array' || t.name === 'Set') && t.parameters.length === 0) return new TypeAnnotation(t.name, t.optional, [sion]);
  if (t.name === 'Dictionary' && t.parameters.length === 0) return new TypeAnnotation(t.name, t.optional, [sion, sion]);
  return new TypeAnnotation(t.name, t.optional, t.parameters.map(defaulted));
}
export function inferLock(value: Value, name: string, defaulting = true): TypeAnnotation {
  const sion = ann('SION');
  if (value === null) return ann('Any', true);
  if (isArray(value)) {
      if (value.lock) return value.lock;
      if (value.items.length === 0) return ann('Array', false, defaulting ? [sion] : []);
      let element: TypeAnnotation | null = null, sawNil = false;
      for (const v of value.items) {
        if (v === null) { sawNil = true; continue; }
        const t = inferLock(v, name, false);
        if (element) {
          const joined = unify(element, t);
          if (!joined) throw SwiftalkError.type(`cannot infer one element type for '${name}' (${element.display} vs ${t.display}) — annotate it: [SION], SION, or Any`);
          element = joined;
        } else element = t;
      }
      if (!element) return ann('Array', false, [ann('Any', true)]);
      if (defaulting) element = defaulted(element);
      const elementLock = sawNil ? new TypeAnnotation(element.name, true, element.parameters) : element;
      return ann('Array', false, [elementLock]);
  }
  if (isSet(value)) {
      if (value.lock) return value.lock;
      if (value.size === 0) return ann('Set', false, defaulting ? [sion] : []);
      const elements = inferLock(new SArray(value.values()), name, defaulting);
      return ann('Set', false, elements.parameters);
  }
  if (isDictionary(value)) {
      if (value.lock) return value.lock;
      if (value.size === 0) return ann('Dictionary', false, defaulting ? [sion, sion] : []);
      let key: TypeAnnotation | null = null, val: TypeAnnotation | null = null, sawNilKey = false;
      for (const [k, v] of value.entries()) {
        if (k === null) sawNilKey = true;
        else {
          const kt = inferLock(k, name, false);
          if (key) {
            const joined = unify(key, kt);
            if (!joined) throw SwiftalkError.type(`cannot infer one key type for '${name}' (${key.display} vs ${kt.display}) — annotate it, e.g. [SION: SION]`);
            key = joined;
          } else key = kt;
        }
        if (v === null) continue;
        const vt = inferLock(v, name, false);
        if (val) {
          const joined = unify(val, vt);
          if (!joined) throw SwiftalkError.type(`cannot infer one value type for '${name}' (${val.display} vs ${vt.display}) — annotate it, e.g. [${key ? key.display : 'SION'}: SION]`);
          val = joined;
        } else val = vt;
      }
      if (defaulting) { if (key) key = defaulted(key); if (val) val = defaulted(val); }
      let keyLock = key ?? ann('Any', true);
      if (sawNilKey && key) keyLock = new TypeAnnotation(key.name, true, key.parameters);
      const valLock = val ?? ann('Any', true);
      return ann('Dictionary', false, [keyLock, valLock]);
  }
  return ann(typeName(value));
}
export { keyOf };
