// Modules (§15, rounds 100 and 182–192) — Modules.swift and the module
// API of Native.swift, for JavaScript. A native module is JS that
// speaks Values directly: `Module.function(name, body)` wraps a JS
// function (or generator) as a builtin Function, `export(name, value)`
// publishes a constant, `type(name, construct)` a type the module
// exports, `extend(type, member, body)` a member added to a core type
// that may decline by answering null, `static(type, name, value)` a
// static on a type. `Interpreter.register(m)` makes it importable by
// name; `preimport([...])` declares its exports into the builtins scope
// — the CLI's prelude. A `.swt` source module resolves through
// `Interpreter.moduleLoader` (a function of the resolved spec, which
// may return a Promise — `fetch` in a browser), evaluated once per
// Interpreter in a scope of its own under the builtins.
import { SwiftalkError } from './errors.js';
import { parse } from './parser.js';
import { kindOf } from './value.js';
import { FunctionObject, StructType, ControlFlow, ReturnSignal } from './objects.js';
import { Environment, Binding } from './env.js';
import { Builtins } from './builtins.js';
import { ann } from './types.js';
import { execute, offload } from './eval.js';

export class Module {
  constructor(name) {
    this.name = name;
    this.names = [];
    this.values = [];
    this.extensions = [];             // {type, member, body(receiver, args, called)}
    this.statics = [];                // {type, name, value}
    this.prelude = null;              // swiftalk source whose exports join the module's
  }
  export(name, value) {
    const i = this.names.indexOf(name);
    if (i >= 0) this.values[i] = value; else { this.names.push(name); this.values.push(value); }
    return this;
  }
  /// A builtin Function over Values: arguments in order, labels dropped;
  /// `body` may be a plain function or a generator (it may run swiftalk code).
  function(name, body) { return this.export(name, Module.builtin(body)); }
  /// A type the module exports: constructed through round 47's law in both spellings.
  type(name, construct) { return this.export(name, new FunctionObject([], [], Builtins.emptyEnvironment, construct, { k: 'type', name })); }
  extend(type, member, body) { this.extensions.push({ type, member, body }); return this; }
  static(type, name, value) { this.statics.push({ type, name, value }); return this; }
  value(named) { const i = this.names.indexOf(named); return i < 0 ? undefined : this.values[i]; }
  static builtin(body) { return new FunctionObject([], [], Builtins.emptyEnvironment, body); }
}

/// A loaded module's exports, and the namespace type `import M from` binds.
class Loaded {
  constructor(names, values) { this.names = names; this.values = values; this.namespaceType = null; }
}

export class ModuleSystem {
  constructor(builtins) {
    this.builtins = builtins;
    this.native = new Map();          // bare name → Loaded
    this.cache = new Map();           // resolved spec → Loaded
    this.loading = new Set();
    this.baseStack = ['.'];
    this.fileScopeSetup = null;       // the Interpreter installs `eval` in a module scope
    this.loader = null;               // resolved spec → source (or a Promise of it)
    this.nativeExtensions = new Map();   // type → Map(member → body)
    this.nativeStatics = new Map();      // type → Map(name → value)
  }
  register(module) {
    if (module.prelude !== null) {
      const declared = this.evaluateSync(module.prelude, `the ${module.name} module's prelude`);
      declared.names.forEach((n, i) => module.export(n, declared.values[i]));
    }
    this.native.set(module.name, new Loaded(module.names.slice(), module.values.slice()));
    for (const e of module.extensions) {
      if (!this.nativeExtensions.has(e.type)) this.nativeExtensions.set(e.type, new Map());
      this.nativeExtensions.get(e.type).set(e.member, e.body);
    }
    for (const s of module.statics) {
      if (!this.nativeStatics.has(s.type)) this.nativeStatics.set(s.type, new Map());
      this.nativeStatics.get(s.type).set(s.name, s.value);
    }
  }
  namespaceType(module, name) {
    if (module.namespaceType) return module.namespaceType;
    const st = new StructType(name, [], new Map(), this.builtins, true);
    st.constructor_ = new FunctionObject([], [], this.builtins, null, { k: 'structType', type: st });
    module.names.forEach((n, i) => st.statics.set(n, module.values[i]));
    module.namespaceType = st;
    return st;
  }
  static isURL(s) { return s.startsWith('http://') || s.startsWith('https://'); }
  static isBare(spec) { return !ModuleSystem.isURL(spec) && !spec.includes('/') && !spec.endsWith('.swt'); }
  static resolve(spec, base) {
    if (ModuleSystem.isURL(spec) || spec.startsWith('/')) return spec;
    if (ModuleSystem.isURL(base)) return base + '/' + spec.split('/').filter((p) => p !== '.').join('/');
    const parts = base === '.' ? [] : base.split('/');
    for (const piece of spec.split('/')) {
      if (piece === '.' || piece === '') continue;
      if (piece === '..') { if (parts.length && parts[parts.length - 1] !== '..' && parts[parts.length - 1] !== '') parts.pop(); else parts.push('..'); }
      else parts.push(piece);
    }
    return parts.join('/');
  }
  static directory(path) { const i = path.lastIndexOf('/'); if (i < 0) return '.'; const dir = path.slice(0, i); return dir === '' ? '/' : dir; }
  /// Loads a module by spec — a generator, since a source module's
  /// loader may hand back a Promise (an `offload` request answers it).
  *load(spec) {
    if (ModuleSystem.isBare(spec)) {
      const m = this.native.get(spec);
      if (m) return m;
      throw SwiftalkError.type(`no module named '${spec}' — the JavaScript runtime has no library path; register it, or import a swiftalk file by its path, "./${spec}.swt"`);
    }
    const resolved = ModuleSystem.resolve(spec, this.baseStack[this.baseStack.length - 1] ?? '.');
    const cached = this.cache.get(resolved);
    if (cached) return cached;
    if (this.loading.has(resolved)) throw SwiftalkError.type(`circular import of '${resolved}'`);
    if (!this.loader) throw SwiftalkError.type(`cannot read '${resolved}' — the JavaScript runtime reads modules through Interpreter.moduleLoader, and none is set`);
    let source = this.loader(resolved);
    if (source && typeof source.then === 'function') source = yield* offload(source);
    if (typeof source !== 'string') throw SwiftalkError.type(`the module loader gave no source for '${resolved}'`);
    this.loading.add(resolved);
    this.baseStack.push(ModuleSystem.directory(resolved));
    try {
      const module = yield* this.evaluate(source, `module '${resolved}'`);
      this.cache.set(resolved, module);
      return module;
    } finally {
      this.loading.delete(resolved);
      this.baseStack.pop();
    }
  }
  /// Runs source as a module's top level: strict, a scope of its own under the builtins.
  *evaluate(source, label) {
    const env = new Environment(this.builtins);
    env.isFileScope = true;
    if (this.fileScopeSetup) this.fileScopeSetup(env);
    try {
      for (const s of parse(source)) yield* execute(s, env, false);
    } catch (e) {
      if (e instanceof SwiftalkError) throw SwiftalkError.type(`in ${label}: ${e.description}`);
      if (e instanceof ControlFlow) throw SwiftalkError.type(`in ${label}: 'break'/'continue' outside a loop`);
      if (e instanceof ReturnSignal) throw SwiftalkError.type(`in ${label}: 'return' outside a function`);
      throw e;
    }
    return new Loaded(env.exports.slice(), env.exports.map((n) => env.lookup(n)));
  }
  /// A prelude is evaluated at registration, before any driver runs: synchronously.
  evaluateSync(source, label) {
    const gen = this.evaluate(source, label);
    let step = gen.next();
    while (!step.done) {
      if (step.value && step.value.suspend) throw SwiftalkError.type(`in ${label}: a prelude cannot suspend`);
      step = gen.next(undefined);
    }
    return step.value;
  }
}
