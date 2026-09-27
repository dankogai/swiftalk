// Bindings and lexical scopes — Eval.swift's Binding and Environment.
import { SwiftalkError } from './errors.js';

export class Binding {
  constructor(mutable, lock, value) { this.mutable = mutable; this.lock = lock; this.value = value; }
}

/// Set by types.js at load time (a cycle: stamping needs the type machinery).
export const hooks = { stamp: (v) => v, checkValue: () => {} };

export class Environment {
  constructor(parent = null) {
    this.bindings = new Map();
    this.parent = parent;
    this.isFileScope = false;
    this.redefining = false;
    this.exports = [];
  }
  get root() { return this.parent ? this.parent.root : this; }
  removeBinding(name) { const b = this.bindings.get(name); this.bindings.delete(name); return b ?? null; }
  putBinding(name, binding) { this.bindings.set(name, binding); }
  declare(name, binding) {
    if (this.bindings.has(name)) throw SwiftalkError.type(`redeclaration of '${name}'`);
    if (this.isFileScope && this.parent && this.parent.bindings.has(name)) {
      throw SwiftalkError.type(`redeclaration of '${name}' — a builtin`);
    }
    binding.value = hooks.stamp(binding.value, binding.lock);
    this.bindings.set(name, binding);
  }
  assign(name, value) {
    const binding = this.bindings.get(name);
    if (!binding) {
      if (this.parent) { this.parent.assign(name, value); return; }
      throw SwiftalkError.type(`cannot assign to undeclared '${name}' — declare it with let or var`);
    }
    if (!binding.mutable) {
      const v = binding.value;
      if (!(v && v.kind === 'function' && v.role.k === 'todo')) throw SwiftalkError.type(`cannot assign to let constant '${name}'`);
    }
    hooks.checkValue(value, binding.lock, `'${name}'`);
    binding.value = hooks.stamp(value, binding.lock);
  }
  names() {
    const out = new Set(this.bindings.keys());
    if (this.parent) for (const n of this.parent.names()) out.add(n);
    return [...out];
  }
  has(name) { return this.bindings.has(name) || (this.parent ? this.parent.has(name) : false); }
  lookup(name) {
    const b = this.bindings.get(name);
    if (b) return b.value;
    if (this.parent) return this.parent.lookup(name);
    throw SwiftalkError.type(`undefined variable '${name}'`);
  }
  tryLookup(name) {
    const b = this.bindings.get(name);
    if (b) return b.value;
    return this.parent ? this.parent.tryLookup(name) : undefined;
  }
  check(value, lock, name) { hooks.checkValue(value, lock, `'${name}'`); }
}
