// The runtime's object classes — Value.swift's FunctionObject, EnumType,
// StructType, SequenceObject, and the control-flow signals. Each carries
// `kind`, which value.js's kindOf answers with.
import { TypeAnnotation } from './parser.js';
import type { Stmt, FunctionExpr, Computed, Property, Expr } from './parser.js';
import type { Value } from './value.js';
import type { Environment } from './env.js';

let nextId = 1;

/// What a Function is for: a closure, an operator, a type or protocol constructor, a `.todo`, a user type.
export type Role =
  | { k: 'plain' }
  | { k: 'operator'; op: string }
  | { k: 'type'; name: string }
  | { k: 'protocol'; name: string }
  | { k: 'todo' }
  | { k: 'enumType'; type: EnumType }
  | { k: 'structType'; type: StructType };
/// A builtin's body: Values in, a Value out — or a generator of one, when it runs swiftalk code.
export type Builtin = (args: Value[], labels?: (string | null)[], ...rest: any[]) => Value | Generator<any, Value, any>;

export class FunctionObject {
  readonly kind = 'function' as const;
  id: number;
  parameters: string[];
  body: Stmt[];
  closure: Environment;
  builtin: Builtin | null;
  role: Role;
  /// a type value's parameters (round 165): `[Int]`, `Set<Int>`, `Int?`
  annotation: TypeAnnotation | null;
  /// set by the evaluator for a closure's `self` (a method bound at call), its sourcing extension, and the like
  [extra: string]: any;
  constructor(parameters: string[], body: Stmt[], closure: Environment, builtin: Builtin | null = null, role: Role = { k: 'plain' }, annotation: TypeAnnotation | null = null) {
    this.id = nextId++;
    this.parameters = parameters;
    this.body = body;
    this.closure = closure;
    this.builtin = builtin;
    this.role = role;
    this.annotation = annotation;
  }
  /// What a type value is a type of: a name for builtins, the type object for user types.
  typeBase(): string | EnumType | StructType | null {
    switch (this.role.k) {
      case 'type': return this.role.name;
      case 'protocol': return 'protocol:' + this.role.name;
      case 'structType': case 'enumType': return this.role.type;
      default: return null;
    }
  }
  identityKey(): string {
    const base = this.typeBase();
    if (base === null) return String(this.id);
    return typeof base === 'string' ? base : 'T' + base.id;
  }
  /// Identity, except for types (round 165): types compare by what they name.
  sameAs(other: unknown): boolean {
    if (this === other) return true;
    if (!(other instanceof FunctionObject)) return false;
    const a = this.typeBase(), b = other.typeBase();
    if (a === null || b === null || a !== b) return false;
    const l = this.annotation, r = other.annotation;
    if ((l?.optional ?? false) !== (r?.optional ?? false)) return false;
    if (!l || !r || l.parameters.length === 0 || r.parameters.length === 0) return true;
    return l.parameters.length === r.parameters.length && l.parameters.every((p, i) => p.equals(r.parameters[i]));
  }
  sourceString(): string {
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

/// A computed property, compiled: the getter and setter as Functions over `self`.
export type ComputedMember = { annotation: TypeAnnotation | null; get: FunctionObject; set: FunctionObject | null };
/// A `static let` not yet evaluated (round 149: lazy, on first read).
export type StaticThunk = { expr: Expr; env: Environment };

export class EnumType {
  id: number;
  name: string;
  caseOrder: string[];
  cases: Map<string, { label: string | null; typeName: string | null }[]>;
  constructor_: FunctionObject | null;
  methods: Map<string, FunctionObject>;
  statics: Map<string, Value>;
  staticGetters: Map<string, FunctionObject>;
  staticThunks: Map<string, StaticThunk>;
  operators: Map<string, FunctionObject>;
  [extra: string]: any;
  constructor(name: string, caseOrder: string[], cases: Map<string, { label: string | null; typeName: string | null }[]>) {
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
  readonly kind = 'enumCase' as const;
  type: EnumType;
  caseName: string;
  associated: Value[];
  constructor(type: EnumType, caseName: string, associated: Value[]) {
    this.type = type;
    this.caseName = caseName;
    this.associated = associated;
  }
}

export class StructType {
  id: number;
  name: string;
  propertyOrder: string[];
  properties: Map<string, Property>;
  declEnv: Environment;
  constructor_: FunctionObject | null;
  methods: Map<string, FunctionObject>;
  inits: FunctionObject[];
  computed: Map<string, ComputedMember>;
  observers: Map<string, { will: FunctionObject | null; did: FunctionObject | null }>;
  statics: Map<string, Value>;
  staticGetters: Map<string, FunctionObject>;
  staticThunks: Map<string, StaticThunk>;
  operators: Map<string, FunctionObject>;
  isModule: boolean;
  [extra: string]: any;
  constructor(name: string, propertyOrder: string[], properties: Map<string, Property>, declEnv: Environment, isModule = false) {
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
  readonly kind = 'structValue' as const;
  type: StructType;
  values: Map<string, Value>;
  constructor(type: StructType, values: Map<string, Value>) {
    this.type = type;
    this.values = values;                // Map name → Value
  }
  clone(): StructValue { return new StructValue(this.type, new Map(this.values)); }
}

/// A puller: the next element, or undefined at the end — a generator, since pulling may run swiftalk code.
export type Puller = () => Generator<any, Value | undefined, any>;
export type SequenceKind =
  | { kind: 'generator'; initial: Value[]; next: FunctionObject }
  | { kind: 'coroutine'; body: FunctionObject }
  | { kind: 'mapped'; base: SequenceObject; fn: FunctionObject }
  | { kind: 'filtered'; base: SequenceObject; fn: FunctionObject }
  | { kind: 'enumerated'; base: SequenceObject }
  | { kind: 'counting'; from: bigint }
  | { kind: 'takenWhile'; base: SequenceObject; fn: FunctionObject }
  | { kind: 'droppedWhile'; base: SequenceObject; fn: FunctionObject }
  | { kind: 'dropped'; base: SequenceObject; n: bigint }
  | { kind: 'native'; make: (() => Puller) | (() => Generator<any, Puller, any>); element: TypeAnnotation | null };
export class SequenceObject {
  /// k: {kind:'generator', initial, next} {kind:'coroutine', body} {kind:'mapped', base, fn}
  ///    {kind:'filtered', base, fn} {kind:'enumerated', base} {kind:'counting', from}
  ///    {kind:'takenWhile', base, fn} {kind:'droppedWhile', base, fn} {kind:'dropped', base, n}
  ///    {kind:'native', make, element}
  readonly kind = 'sequence' as const;
  id: number;
  k: SequenceKind;
  constructor(k: SequenceKind) { this.id = nextId++; this.k = k; }
}

export class TaskObject {
  readonly kind = 'task' as const;
  id: number;
  body: FunctionObject | null;
  state: 'ready' | 'running' | 'done' | 'failed' | string;
  result: Value | undefined;
  error: Error | null;
  [extra: string]: any;
  constructor(body: FunctionObject | null) { this.id = nextId++; this.body = body; this.state = 'ready'; this.result = undefined; this.error = null; }
}

/// A value a module owns (round 186): `object` answers for its type name,
/// members, equality (`isEqual`), hashing (`hashKey`), printed form
/// (`sourceString(debug)`), `switch` matching (`patternMatch(subject,
/// binding)`), and assignment (`setMember(name, value)`); `type` is the
/// type value `.Type` answers.
export interface HostObject {
  typeName: string;
  /// a member read or call; undefined when the object has no such member
  member(name: string, args: Value[], called: boolean, ...rest: any[]): Generator<any, Value | undefined, any> | Value | undefined;
  isEqual(other: HostObject): boolean;
  hashKey(): string;
  sourceString(debug: boolean): string;
  patternMatch?(subject: Value, binding: boolean): any;
  setMember?(name: string, value: Value): any;
  operate?(key: string, operands: Value[]): any;
  [extra: string]: any;
}
export class HostValue {
  readonly kind = 'host' as const;
  object: HostObject;
  type: Value;
  constructor(object: HostObject, type: Value) { this.object = object; this.type = type; }
}

/// A `Context` (round 237): an execution state — a top level of its own. `global` is the
/// program's; `Context()` copies the top level it is made in; `eval(source, ctx)` runs there.
let nextContextId = 1;
export class ContextObject implements HostObject {
  env: Environment;
  isGlobal: boolean;
  id: number;
  typeName: string;
  constructor(env: Environment, isGlobal: boolean) { this.env = env; this.isGlobal = isGlobal; this.id = nextContextId++; this.typeName = 'Context'; }
  *member(): Generator<any, Value | undefined, any> { return undefined; }
  isEqual(other: HostObject): boolean { return other === this; }
  hashKey(): string { return `Context:${this.id}`; }
  sourceString(): string { return this.isGlobal ? 'global' : 'Context()'; }
}

/// `break`/`continue` travel as thrown signals; loops catch them.
export class ControlFlow extends Error {
  kind: 'break' | 'continue';
  label: string | null;
  constructor(kind: 'break' | 'continue', label?: string | null) { super(kind); this.kind = kind; this.label = label ?? null; }
}
/// `return` travels the same way; `apply` catches it at the function boundary.
export class ReturnSignal extends Error {
  value: Value;
  constructor(value: Value) { super('return'); this.value = value; }
}
export { TypeAnnotation };
