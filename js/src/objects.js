// The runtime's object classes — Value.swift's FunctionObject, EnumType,
// StructType, SequenceObject, and the control-flow signals. Each carries
// `kind`, which value.js's kindOf answers with.
import { TypeAnnotation } from './parser.js';

let nextId = 1;

export class FunctionObject {
  /// role: {k:'plain'} {k:'operator', op} {k:'type', name} {k:'protocol', name} {k:'todo'}
  ///       {k:'enumType', type} {k:'structType', type}
  constructor(parameters, body, closure, builtin = null, role = { k: 'plain' }, annotation = null) {
    this.kind = 'function';
    this.id = nextId++;
    this.parameters = parameters;
    this.body = body;
    this.closure = closure;
    this.builtin = builtin;
    this.role = role;
    this.annotation = annotation;
  }
  /// What a type value is a type of: a name for builtins, the type object for user types.
  typeBase() {
    switch (this.role.k) {
      case 'type': return this.role.name;
      case 'protocol': return 'protocol:' + this.role.name;
      case 'structType': case 'enumType': return this.role.type;
      default: return null;
    }
  }
  identityKey() {
    const base = this.typeBase();
    if (base === null) return String(this.id);
    return typeof base === 'string' ? base : 'T' + base.id;
  }
  /// Identity, except for types (round 165): types compare by what they name.
  sameAs(other) {
    if (this === other) return true;
    if (!(other instanceof FunctionObject)) return false;
    const a = this.typeBase(), b = other.typeBase();
    if (a === null || b === null || a !== b) return false;
    const l = this.annotation, r = other.annotation;
    if ((l?.optional ?? false) !== (r?.optional ?? false)) return false;
    if (!l || !r || l.parameters.length === 0 || r.parameters.length === 0) return true;
    return l.parameters.length === r.parameters.length && l.parameters.every((p, i) => p.equals(r.parameters[i]));
  }
  sourceString() {
    if (this.annotation) return this.annotation.display;
    switch (this.role.k) {
      case 'type': case 'protocol': return this.role.name;
      case 'enumType': case 'structType': return this.role.type.name;
      case 'todo': return '.todo';
      case 'operator': return `(${this.role.op})`;
      default: {
        const params = this.parameters.length ? this.parameters.join(', ') + ' in ' : '';
        return `{ ${params}... }`;
      }
    }
  }
}

export class EnumType {
  constructor(name, caseOrder, cases) {
    this.id = nextId++;
    this.name = name;
    this.caseOrder = caseOrder;
    this.cases = cases;                  // Map name → [{label, typeName}]
    this.constructor_ = null;
    this.methods = new Map();
    this.statics = new Map();
    this.staticGetters = new Map();
    this.staticThunks = new Map();
    this.operators = new Map();
  }
}
export class EnumCaseValue {
  constructor(type, caseName, associated) {
    this.kind = 'enumCase';
    this.type = type;
    this.caseName = caseName;
    this.associated = associated;
  }
}

export class StructType {
  constructor(name, propertyOrder, properties, declEnv, isModule = false) {
    this.id = nextId++;
    this.name = name;
    this.propertyOrder = propertyOrder;
    this.properties = properties;        // Map name → {mutable, annotation, defaultExpr, willSetExpr, didSetExpr}
    this.declEnv = declEnv;
    this.constructor_ = null;
    this.methods = new Map();
    this.inits = [];
    this.computed = new Map();           // name → {annotation, get, set}
    this.observers = new Map();          // name → {will, did}
    this.statics = new Map();
    this.staticGetters = new Map();
    this.staticThunks = new Map();
    this.operators = new Map();
    this.isModule = isModule;
  }
}
export class StructValue {
  constructor(type, values) {
    this.kind = 'structValue';
    this.type = type;
    this.values = values;                // Map name → Value
  }
  clone() { return new StructValue(this.type, new Map(this.values)); }
}

export class SequenceObject {
  /// k: {kind:'generator', initial, next} {kind:'coroutine', body} {kind:'mapped', base, fn}
  ///    {kind:'filtered', base, fn} {kind:'enumerated', base} {kind:'counting', from}
  ///    {kind:'takenWhile', base, fn} {kind:'droppedWhile', base, fn} {kind:'dropped', base, n}
  ///    {kind:'native', make, element}
  constructor(k) { this.kind = 'sequence'; this.id = nextId++; this.k = k; }
}

export class TaskObject {
  constructor(body) { this.kind = 'task'; this.id = nextId++; this.body = body; this.state = 'ready'; this.result = undefined; this.error = null; }
}

/// A value a module owns (round 186): `object` answers for its type name,
/// members, equality (`isEqual`), hashing (`hashKey`), printed form
/// (`sourceString(debug)`), `switch` matching (`patternMatch(subject,
/// binding)`), and assignment (`setMember(name, value)`); `type` is the
/// type value `.Type` answers.
export class HostValue {
  constructor(object, type) { this.kind = 'host'; this.object = object; this.type = type; }
}

/// `break`/`continue` travel as thrown signals; loops catch them.
export class ControlFlow extends Error {
  constructor(kind, label) { super(kind); this.kind = kind; this.label = label ?? null; }
}
/// `return` travels the same way; `apply` catches it at the function boundary.
export class ReturnSignal extends Error {
  constructor(value) { super('return'); this.value = value; }
}
export { TypeAnnotation };
