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
import { execute, run, constructEnumCase, valueSourceText, scheduler } from './eval.js';
import './members.js';

/// A cooperative scheduler over generators (§12): a task is a generator
/// stepped until it finishes; a request it yields is answered here.
class Scheduler {
  constructor() { this.tasks = []; }
  /// Runs `gen` to completion, answering its requests; returns its value.
  /// A `sleep` here (the main context's) runs the parked tasks first —
  /// the time it would have waited is theirs. FIXME: milestone C waits
  /// on real timers, asynchronously.
  drive(gen) {
    let step = gen.next();
    for (;;) {
      if (step.done) return step.value;
      step = gen.next(this.answer(step.value, null));
    }
  }
  /// Answers one request; `task` is the task that asked, or null for main.
  answer(request, task) {
    if (!request || typeof request !== 'object') return undefined;
    switch (request.suspend) {
      case 'spawn': return { task: this.spawn(request.body) };
      case 'await': return { value: this.finish(request.task) };
      case 'sleep': this.runOthers(task); return { done: true };
      case 'yield': return { coroutine: false };             // no coroutine caught it
      default: return undefined;
    }
  }
  /// Swift's tasks start eagerly (round 53): the body runs until its
  /// first suspension before the spawner continues.
  spawn(body) {
    const task = new TaskObject(body);
    task.gen = run(body, []);
    task.state = 'ready';
    this.tasks.push(task);
    this.step(task);
    return task;
  }
  /// Steps a task until it finishes or sleeps (parks).
  step(task) {
    if (task.state !== 'ready') return;
    task.state = 'running';
    try {
      let step = task.gen.next(task.pending);
      task.pending = undefined;
      for (;;) {
        if (step.done) { task.result = step.value.result; task.state = 'done'; break; }
        const request = step.value;
        if (request && request.suspend === 'sleep') { task.pending = { done: true }; task.state = 'ready'; return; }
        step = task.gen.next(this.answer(request, task));
      }
    } catch (e) {
      if (!(e instanceof SwiftalkError)) throw e;
      task.error = e; task.state = 'failed';
    }
    const i = this.tasks.indexOf(task);
    if (i >= 0) this.tasks.splice(i, 1);
  }
  runOthers(except) {
    for (const t of this.tasks.slice()) if (t !== except) this.step(t);
  }
  /// Runs a task to completion and returns its value, or rethrows its error.
  finish(task) {
    while (task.state === 'ready') this.step(task);
    if (task.state === 'running') throw SwiftalkError.type('a Task cannot await itself');
    if (task.state === 'failed') throw task.error;
    return task.result;
  }
  /// The tasks nobody awaited still run, at the end of an eval.
  drain() { let guard = 0; while (this.tasks.length && guard++ < 10000) this.runOthers(null); }
}

/// A stand-in for the module system (round 100+) until milestone D.
class ModuleSystem {
  constructor() { this.nativeExtensions = new Map(); this.nativeStatics = new Map(); }
  *load(spec) { throw SwiftalkError.type(`FIXME: import from "${spec}" — modules are not ported yet`); }
  namespaceType() { throw SwiftalkError.type('FIXME: modules are not ported yet'); }
}

export class Interpreter {
  constructor(relaxed = false) {
    this.relaxed = relaxed;
    this.builtins = new Environment();
    this.environment = new Environment(this.builtins);
    this.environment.isFileScope = true;
    this.modules = new ModuleSystem();
    this.scheduler = new Scheduler();
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
  /// Evaluates a program and returns its last statement's value.
  eval(source) {
    return this.withContext(() => {
      const value = this.scheduler.drive(this.program(source, this.environment));
      this.scheduler.drain();
      return value;
    });
  }
  withContext(body) {
    const previous = { current: scheduler.current, modules: scheduler.modules };
    scheduler.current = this;
    scheduler.modules = this.modules;
    try { return body(); } finally { scheduler.current = previous.current; scheduler.modules = previous.modules; }
  }
  /// A value's source form for the REPL's echo (round 152): a String
  /// quoted, a user type's own `String` member honored.
  sourceText(value) { return this.withContext(() => this.scheduler.drive(valueSourceText(value))); }
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
  Interpreter,
  needsMoreInput,
};
