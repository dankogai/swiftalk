// The Interpreter — Eval.swift's Swiftalk.Interpreter: a persistent
// global environment over the builtins scope, `eval` driving the
// generator-based evaluator, and the cooperative scheduler that answers
// its suspension requests (spawn, await, sleep). Synchronous in
// milestone B: `eval` runs the program to completion; `sleep` waits
// nothing yet (FIXME, milestone C makes the driver async over timers).
import { SwiftalkError } from './errors.js';
import { Lexer, isPunct, isOp } from './lexer.js';
import { parse } from './parser.js';
import { typeName } from './value.js';
import { FunctionObject, TaskObject, ControlFlow, ReturnSignal } from './objects.js';
import { Environment, Binding } from './env.js';
import { Builtins } from './builtins.js';
import { ann } from './types.js';
import { execute, constructEnumCase, valueSourceText, scheduler } from './eval.js';
import { AsyncScheduler, SyncScheduler } from './scheduler.js';
import { Module, ModuleSystem } from './modules.js';
import './members.js';

export class Interpreter {
  constructor(relaxed = false) {
    this.relaxed = relaxed;
    this.builtins = new Environment();
    this.environment = new Environment(this.builtins);
    this.environment.isFileScope = true;
    this.modules = new ModuleSystem(this.builtins);
    this.modules.fileScopeSetup = (scope) => this.installEval(scope);
    /// resolved spec → source, or a Promise of it — how `import "./m.swt"` reads (round 100); none by default
    this.moduleLoader = null;
    this.scriptPath = null;
    /// named functions over Values the host lends the modules (round 189): Net's "fetch"
    this.hooks = new Map();
    this.sync = new SyncScheduler();
    this.async = new AsyncScheduler();
    this.queue = Promise.resolve();
    this.output = (s) => { if (typeof process !== 'undefined' && process.stdout) process.stdout.write(s); else console.log(s); };
    this.errorOutput = (s) => { if (typeof process !== 'undefined' && process.stderr) process.stderr.write(s); else console.error(s); };
    this.installBuiltins();
    this.installEval(this.environment);
  }
  installBuiltins() {
    const fn = ann('Function');
    for (const [name, object] of Builtins.types) this.builtins.declare(name, new Binding(false, fn, object));
    for (const [name, object] of Builtins.protocols) if (!this.builtins.bindings.has(name)) this.builtins.declare(name, new Binding(false, fn, object));
    this.builtins.declare('Result', new Binding(false, fn, Builtins.resultType.constructor_));
  }
  /// The language's own `eval` (rounds 122–123, 159): a Result, never thrown.
  installEval(scope) {
    const self = this;
    const fn = new FunctionObject([], [], scope, function* (args) {
      if (args.length !== 1 || typeof args[0] !== 'string') throw SwiftalkError.type('eval takes one String of swiftalk source');
      try {
        const value = yield* self.program(args[0], scope);
        return constructEnumCase(Builtins.resultType, 'success', [{ label: null, value }], true);
      } catch (e) {
        if (!(e instanceof SwiftalkError)) throw e;
        return constructEnumCase(Builtins.resultType, 'failure', [{ label: null, value: e.description }], true);
      }
    });
    scope.declare('eval', new Binding(false, ann('Function'), fn));
  }
  /// Declares a host Function in the builtins scope (an embedder's `print`).
  declareBuiltin(name, body) {
    const fn = new FunctionObject([], [], this.builtins, body);
    this.builtins.declare(name, new Binding(false, ann('Function'), fn));
  }
  /// The evaluator proper, as a generator: lex, parse, execute in a file scope.
  *program(source, scope) {
    const statements = parse(source);
    let last = null;
    try {
      for (const s of statements) last = yield* execute(s, scope, this.relaxed);
    } catch (e) {
      if (e instanceof ControlFlow) throw SwiftalkError.syntax("'break'/'continue' outside a loop");
      if (e instanceof ReturnSignal) throw SwiftalkError.syntax("'return' outside a function");
      throw e;
    }
    return last;
  }
  /// Makes a native module importable by its name (round 182); its prelude runs now.
  register(module) { this.withContext(() => this.modules.register(module)); }
  /// Imports every export of the named modules into the builtins scope
  /// (round 185) — the CLI's prelude. A name already bound to the same
  /// value is skipped; to something else, an error.
  preimport(specs = ['IO', 'Net']) {
    for (const spec of specs) {
      const module = this.modules.native.get(spec);
      if (!module) throw SwiftalkError.type(`preimport: no module named '${spec}' is registered`);
      module.names.forEach((name, i) => {
        const value = module.values[i];
        const existing = this.builtins.tryLookup(name);
        if (existing !== undefined) {
          if (existing !== value) throw SwiftalkError.type(`preimport: '${name}' from '${spec}' is already bound to something else`);
          return;
        }
        this.builtins.declare(name, new Binding(false, ann(typeName(value), true), value));
      });
    }
  }
  prepare() {
    this.modules.loader = this.moduleLoader;
    this.modules.baseStack = [this.scriptPath ? ModuleSystem.directory(this.scriptPath) : '.'];
  }
  /// Evaluates a program and returns its last statement's value —
  /// synchronously: a `Task.sleep` lets the other ready tasks run and
  /// goes on without waiting, a host Promise is refused. The one-liner's
  /// and the corpus's driver; `evalAsync` is the faithful one.
  eval(source) {
    return this.withContext(() => { this.prepare(); return this.sync.run(this.program(source, this.environment)); });
  }
  /// Evaluates a program with the real scheduler: `Task.sleep` waits on
  /// a timer, an offloaded Promise parks only its context. Calls on one
  /// Interpreter are serialized; tasks left parked persist to the next.
  evalAsync(source) {
    const job = () => this.withContextAsync(() => { this.prepare(); return this.async.run(this.program(source, this.environment)); });
    const result = this.queue.then(job, job);
    this.queue = result.catch(() => {});
    return result;
  }
  withContext(body) {
    const previous = { current: scheduler.current, modules: scheduler.modules };
    scheduler.current = this;
    scheduler.modules = this.modules;
    try { return body(); } finally { scheduler.current = previous.current; scheduler.modules = previous.modules; }
  }
  async withContextAsync(body) {
    // one Interpreter runs at a time on the JS thread, but an await inside
    // hands the thread on: the context is reinstalled around every resumption
    // by being the only live one — evalAsync calls are serialized per Interpreter,
    // and two Interpreters' evalAsyncs must not interleave (FIXME: per-context installation)
    const previous = { current: scheduler.current, modules: scheduler.modules };
    scheduler.current = this;
    scheduler.modules = this.modules;
    try { return await body(); } finally { scheduler.current = previous.current; scheduler.modules = previous.modules; }
  }
  /// A value's source form for the REPL's echo (round 152): a String
  /// quoted, a user type's own `String` member honored.
  sourceText(value) { return this.withContext(() => this.sync.run(valueSourceText(value))); }
  /// The REPL's `:d name` (round 131).
  undefine(name) {
    if (this.environment.removeBinding(name) === null) throw SwiftalkError.type(`':d' — no top-level binding named '${name}'`);
  }
  /// The REPL's `:r let x = ...` (round 131): one declaration whose names replace what they had.
  redefine(source) {
    const program = parse(source);
    let names;
    const only = program.length === 1 ? program[0] : null;
    switch (only?.k) {
      case 'declaration': names = [only.name]; break;
      case 'destructure': names = namesIn(only.pattern); break;
      case 'structDecl': case 'enumDecl': names = [only.name]; break;
      case 'extensionDecl': names = []; break;
      default: throw SwiftalkError.syntax("':r' takes one declaration: let, var, struct, enum, or extension");
    }
    const saved = names.map((n) => [n, this.environment.removeBinding(n)]);
    this.environment.redefining = true;
    try { return this.eval(source); }
    catch (e) {
      for (const [n, b] of saved) { this.environment.removeBinding(n); if (b) this.environment.putBinding(n, b); }
      throw e;
    } finally { this.environment.redefining = false; }
  }
}
function namesIn(pattern) {
  if (pattern.k === 'name') return pattern.name === '_' ? [] : [pattern.name];
  return pattern.elements.flatMap((e) => namesIn(e.pattern));
}

/// True when `source` is a syntactically incomplete prefix — open brackets
/// awaiting their close — so a REPL should read more lines.
export function needsMoreInput(source) {
  const lexer = new Lexer(source);
  let tokens;
  try { tokens = lexer.tokenize(); }
  catch (e) {
    return e instanceof SwiftalkError && e.kind === 'syntax' && e.detail.startsWith('unterminated multi-line string');
  }
  const last = tokens.length ? tokens[tokens.length - 1] : null;
  if (Lexer.continuesLine(last) && !(isOp(last, '>') && lexer.closingAngle)) return true;
  let depth = 0;
  for (const t of tokens) {
    if (isPunct(t, '[') || isPunct(t, '(') || isPunct(t, '{')) depth++;
    else if (isPunct(t, ']') || isPunct(t, ')') || isPunct(t, '}')) depth--;
  }
  return depth > 0;
}

/// `Swiftalk.eval`: source in, value out — one-shot.
export const Swiftalk = {
  eval: (source) => new Interpreter().eval(source),
  evalAsync: (source) => new Interpreter().evalAsync(source),
  Interpreter,
  Module,
  needsMoreInput,
};
