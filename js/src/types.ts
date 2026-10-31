// Type locks, stamps, inference — Eval.swift's checkValue, inferLock,
// stamp, admits, knownElementLock, typeValue, annotationOfType.
import { SwiftalkError } from './errors.js';
import { TypeAnnotation } from './parser.js';
import { kindOf, typeName, SArray, SDictionary, SSet, keyOf, sourceString } from './value.js';
import { FunctionObject } from './objects.js';
import type { Builtin, EnumType } from './objects.js';
import { hooks } from './env.js';
import type { Environment } from './env.js';
import { Builtins } from './builtins.js';
import type { Value, Lock } from './value.js';

export const knownTypeNames = new Set(['Context', 'Nil', 'Bool', 'Int', 'Double', 'String', 'Array', 'Dictionary', 'Set', 'Function',
  'Range', 'Sequence', 'Data', 'Date', 'Task', 'Tuple', 'Byte', 'SION', 'Any']);
export const ann = (name: string, optional = false, parameters: TypeAnnotation[] = []): TypeAnnotation => new TypeAnnotation(name, optional, parameters);

export function isSION(v: Value): boolean {
  switch (kindOf(v)) {
    case 'nil': case 'bool': case 'int': case 'double': case 'string': case 'data': case 'date': return true;
    case 'array': return (v as SArray).items.every(isSION);
    case 'dictionary': return (v as SDictionary).entries().every(([k, x]) => isSION(k) && isSION(x));
    default: return false;
  }
}
export function typeMatches(value: Value, lockName: string): boolean { return typeName(value) === lockName; }

export function isUserType(name: string, env: Environment): boolean {
  const v = env.tryLookup(name) as FunctionObject | undefined;
  if (!v || kindOf(v) !== 'function') return false;
  switch (v.role.k) {
    case 'enumType': case 'structType': return true;
    case 'type': return v.builtin !== null && !Builtins.types.has(v.role.name);
    default: return false;
  }
}
export function resolveTypeNames(annotation: TypeAnnotation, env: Environment): TypeAnnotation {
  let name = annotation.name;
  if (!knownTypeNames.has(name)) {
    const f = env.tryLookup(name) as FunctionObject | undefined;
    if (f && kindOf(f) === 'function') {
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
  const v = env.tryLookup(annotation.name) as FunctionObject | undefined;
  if (v && kindOf(v) === 'function' && v.role.k === 'enumType') return v.role.type;
  return null;
}

export function containerStamp(v: Value): Lock {
  const k = kindOf(v);
  return k === 'array' || k === 'dictionary' || k === 'set' ? (v as SArray | SDictionary | SSet).lock : null;
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
  const k = kindOf(value);
  if (k === 'array' && lock.name === 'Array') {
    const e = lock.parameters[0], a = value as SArray;
    return new SArray(e.parameters.length ? a.items.map((x) => stamp(x, e)) : a.items, own);
  }
  if (k === 'set' && lock.name === 'Set') {
    const e = lock.parameters[0], st = value as SSet;
    return new SSet(e.parameters.length ? st.values().map((x) => stamp(x, e)) : st.values(), own);
  }
  if (k === 'dictionary' && lock.name === 'Dictionary' && lock.parameters.length === 2) {
    const v = lock.parameters[1], d = value as SDictionary;
    return new SDictionary(d.entries().map(([key, x]): [Value, Value] => [key, v.parameters.length ? stamp(x, v) : x]), own);
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
  const k = kindOf(value);
  if (lock.name === 'Array' && lock.parameters.length === 1 && k === 'array') {
    (value as SArray).items.forEach((e, i) => checkValue(e, lock.parameters[0], `${context}[${i}]`));
  }
  if (lock.name === 'Set' && lock.parameters.length === 1 && k === 'set') {
    for (const e of (value as SSet).values()) checkValue(e, lock.parameters[0], `an element of ${context}`);
  }
  if (lock.name === 'Dictionary' && lock.parameters.length === 2 && k === 'dictionary') {
    for (const [key, val] of (value as SDictionary).entries()) {
      checkValue(key, lock.parameters[0], `a key of ${context}`);
      if (val !== null) checkValue(val, lock.parameters[1], `${context}[${sourceString(key)}]`);
    }
  }
}
hooks.stamp = stamp;
hooks.checkValue = (v, lock, what) => { if (lock) checkValue(v, lock, what); };

export function knownElementLock(v: Value): Lock {
  const x = v as any;
  switch (kindOf(v)) {
    case 'range': return ann('Int');
    case 'string': return ann('String');
    case 'data': return ann('Byte');
    case 'array': case 'set': return x.lock ? (x.lock.parameters[0] ?? null) : null;
    case 'dictionary': return ann('Tuple');
    case 'sequence': {
      const s = x.k;
      switch (s.kind) {
        case 'counting': return ann('Int');
        case 'filtered': case 'takenWhile': case 'droppedWhile': case 'dropped': return knownElementLock(s.base);
        case 'enumerated': return ann('Tuple');
        case 'native': return s.element ?? null;
        default: return null;
      }
    }
    default: return null;
  }
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
  if (kindOf(value) !== 'function') return null;
  const f = value as FunctionObject;
  if (f.annotation) return f.annotation;
  switch (f.role.k) {
    case 'type': return ann(f.role.name);
    case 'protocol': return f.role.name === 'Sequence' ? ann('Sequence') : null;
    case 'enumType': case 'structType': return ann(f.role.type.name);
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
    const built = yield* callBuiltin(base.builtin!, args);
    checkValue(built, own, `${own.display}()`);
    return stamp(built, own);
  }, { k: 'type', name: annotation.name }, own);
}
/// A builtin body may be plain or a generator; this runs either.
export function* callBuiltin(builtin: Builtin, args: Value[], ...rest: any[]): Generator<any, Value, any> {
  const r: any = (builtin as any)(args, ...rest);
  if (r && typeof r.next === 'function' && typeof r[Symbol.iterator] === 'function') return yield* r;
  return r as Value;
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
    if (!t || kindOf(t) !== 'function' || !annotationOfType(t)) throw SwiftalkError.type(`no type named ${annotation.display} is in scope`);
    plain = t as FunctionObject;
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
  const x = value as any;
  switch (kindOf(value)) {
    case 'nil': return ann('Any', true);
    case 'array': {
      if (x.lock) return x.lock;
      if (x.items.length === 0) return ann('Array', false, defaulting ? [sion] : []);
      let element: TypeAnnotation | null = null, sawNil = false;
      for (const v of x.items as Value[]) {
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
    case 'set': {
      if (x.lock) return x.lock;
      if (x.size === 0) return ann('Set', false, defaulting ? [sion] : []);
      const elements = inferLock(new SArray(x.values()), name, defaulting);
      return ann('Set', false, elements.parameters);
    }
    case 'dictionary': {
      if (x.lock) return x.lock;
      if (x.size === 0) return ann('Dictionary', false, defaulting ? [sion, sion] : []);
      let key: TypeAnnotation | null = null, val: TypeAnnotation | null = null, sawNilKey = false;
      for (const [k, v] of x.entries() as [Value, Value][]) {
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
    default: return ann(typeName(value));
  }
}
export { keyOf };
