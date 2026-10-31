// Bindings and lexical scopes — Eval.swift's Binding and Environment.
import { SwiftalkError } from './errors.js';
import { isFunction } from './value.js';
import type { Value, Lock } from './value.js';

export class Binding {
  mutable: boolean;
  lock: Lock;
  value: Value;
  constructor(mutable: boolean, lock: Lock, value: Value) { this.mutable = mutable; this.lock = lock; this.value = value; }
}

/// Set by types.ts at load time (a cycle: stamping needs the type machinery).
export const hooks: { stamp: (v: Value, lock: Lock) => Value; checkValue: (v: Value, lock: Lock, what: string) => void } = {
  stamp: (v) => v,
  checkValue: () => {},
};

export class Environment {
  bindings: Map<string, Binding>;
  parent: Environment | null;
  isFileScope: boolean;
  redefining: boolean;
  exports: string[];
  evalInstaller: ((copy: Environment) => void) | null;
  constructor(parent: Environment | null = null) {
    this.bindings = new Map();
    this.parent = parent;
    this.isFileScope = false;
    this.redefining = false;
    this.exports = [];
    /// how a file scope gets its `eval` (round 237) — carried into a Context's copy
    this.evalInstaller = null;
  }
  get root(): Environment { return this.parent ? this.parent.root : this; }
  /// the enclosing file scope (round 237): what Context() copies
  fileScope(): Environment { let scope: Environment = this; while (!scope.isFileScope && scope.parent) scope = scope.parent; return scope; }
  /// a Context's state (round 237): a file scope of its own with these bindings as they are now
  copy(): Environment {
    const twin = new Environment(this.parent);
    twin.bindings = new Map([...this.bindings].map(([name, b]) => [name, new Binding(b.mutable, b.lock, b.value)]));   // bindings by value, as Swift's structs are
    twin.isFileScope = true;
    twin.evalInstaller = this.evalInstaller;
    return twin;
  }
  removeBinding(name: string): Binding | null { const b = this.bindings.get(name); this.bindings.delete(name); return b ?? null; }
  putBinding(name: string, binding: Binding): void { this.bindings.set(name, binding); }
  declare(name: string, binding: Binding): void {
    if (this.bindings.has(name)) throw SwiftalkError.type(`redeclaration of '${name}'`);
    if (this.isFileScope && this.parent && this.parent.bindings.has(name)) {
      throw SwiftalkError.type(`redeclaration of '${name}' — a builtin`);
    }
    binding.value = hooks.stamp(binding.value, binding.lock);
    this.bindings.set(name, binding);
  }
  assign(name: string, value: Value): void {
    const binding = this.bindings.get(name);
    if (!binding) {
      if (this.parent) { this.parent.assign(name, value); return; }
      throw SwiftalkError.type(`cannot assign to undeclared '${name}' — declare it with let or var`);
    }
    if (!binding.mutable) {
      const v = binding.value;
      if (!(isFunction(v) && v.role.k === 'todo')) throw SwiftalkError.type(`cannot assign to let constant '${name}'`);
    }
    hooks.checkValue(value, binding.lock, `'${name}'`);
    binding.value = hooks.stamp(value, binding.lock);
  }
  names(): string[] {
    const out = new Set<string>(this.bindings.keys());
    if (this.parent) for (const n of this.parent.names()) out.add(n);
    return [...out];
  }
  has(name: string): boolean { return this.bindings.has(name) || (this.parent ? this.parent.has(name) : false); }
  lookup(name: string): Value {
    const b = this.bindings.get(name);
    if (b) return b.value;
    if (this.parent) return this.parent.lookup(name);
    throw SwiftalkError.type(`undefined variable '${name}'`);
  }
  tryLookup(name: string): Value | undefined {
    const b = this.bindings.get(name);
    if (b) return b.value;
    return this.parent ? this.parent.tryLookup(name) : undefined;
  }
  check(value: Value, lock: Lock, name: string): void { hooks.checkValue(value, lock, `'${name}'`); }
}
