// The cooperative scheduler (§12, round 53) — Task.swift without threads.
// A context is a generator: the main program's, or a task body's. It
// runs until it yields a suspension request — spawn, await, sleep,
// offload, yield — and the scheduler answers it: at once (spawn, a
// settled await), or by parking the context and seating the next ready
// one, exactly the baton-passing of the Swift scheduler. Determinism is
// the Swift core's: a newborn task runs first, its spawner is next in
// line; sleepers wake in deadline order; an await that can never
// complete is a deadlock error, not a hang.
//
// Two drivers share the machinery. `AsyncScheduler.run` is the real one:
// it awaits timers and Promises, so `Task.sleep` takes the time it says
// and `offload` (a fetch) suspends only its own context. `SyncScheduler`
// runs a program to completion without waiting: a sleep runs the other
// ready contexts and returns, an offloaded Promise is refused — for
// `Swiftalk.eval` the one-liner and the fixture corpus.
import { SwiftalkError } from './errors.js';
import { TaskObject, isRunResult } from './objects.js';
import type { Request, Answer, RunResult } from './objects.js';
import type { Value } from './value.js';
import { run } from './eval.js';

/// The answer a context resumes with: a value, or an error to throw into it.
type Pending = { value: Answer; throw?: undefined } | { throw: Error; value?: undefined } | undefined;
type Sleeper = { deadline: number; seq: number; ctx: Context };
/// The main program's generator answers its last value; a task body's answers `run`'s result.
type ContextGenerator = Generator<Request, Value | RunResult, Answer>;

/// A generator with the baton, or parked: the main program's, or a task's.
export class Context {
  gen: ContextGenerator;
  task: TaskObject | null;
  pending: Pending;
  parkedOn: TaskObject | null;
  constructor(gen: ContextGenerator, task: TaskObject | null = null) {
    this.gen = gen;
    this.task = task;                 // null for the main context
    this.pending = undefined;         // the answer to resume with: {value} or {throw}
    this.parkedOn = null;             // the Task this context awaits, while parked
  }
  /// One step: resumes with the pending answer.
  resume(): IteratorResult<Request, Value | RunResult> {
    const p = this.pending;
    this.pending = undefined;
    if (p && p.throw !== undefined) return this.gen.throw(p.throw);
    return this.gen.next(p ? p.value : undefined);
  }
}

const now = () => Date.now() / 1000;

abstract class SchedulerBase {
  ready: Context[];
  sleepers: Sleeper[];
  seq: number;
  offloaded: number;
  wake: (() => void) | null;
  constructor() {
    this.ready = [];                  // resumable contexts, FIFO
    this.sleepers = [];               // {deadline, seq, ctx}
    this.seq = 0;
    this.offloaded = 0;
    this.wake = null;                 // resolves when an offload finishes
  }
  /// Publishes a task's outcome and readies its awaiters (Task.swift's complete).
  complete(task: TaskObject, result: Value, error: Error | null): void {
    if (error) { task.state = 'failed'; task.error = error; } else { task.state = 'done'; task.result = result; }
    for (const ctx of task.awaiters) { ctx.pending = error ? { throw: error } : { value: { value: result } }; ctx.parkedOn = null; this.ready.push(ctx); }
    task.awaiters = [];
  }
  wakeDueSleepers(): void {
    const time = now();
    const due = this.sleepers.filter((s) => s.deadline <= time).sort((a, b) => a.deadline - b.deadline || a.seq - b.seq);
    if (!due.length) return;
    this.sleepers = this.sleepers.filter((s) => s.deadline > time);
    for (const s of due) this.ready.push(s.ctx);
  }
  /// Answers a request from `current`; returns the context to run next
  /// (`current` itself when answered at once, another when it parks).
  abstract park(current: Context, seconds: number): Context | null;
  abstract offload(current: Context, promise: Promise<unknown>): Context | null;
  dispatch(current: Context, request: Request | undefined): Context | null {
    if (!request || typeof request !== 'object') { current.pending = { value: undefined }; return current; }
    switch (request.suspend) {
      case 'spawn': {
        const task = new TaskObject(request.body);
        task.state = 'running';
        const ctx = new Context(run(request.body, []), task);
        current.pending = { value: { task } };
        this.ready.unshift(current);                // the spawner is first in line behind the newborn
        return ctx;
      }
      case 'await': {
        const t = request.task;
        if (t.state === 'done') { current.pending = { value: { value: t.result ?? null } }; return current; }
        if (t.state === 'failed') { current.pending = { throw: t.error ?? new Error('a failed Task without an error') }; return current; }
        t.awaiters.push(current);
        current.parkedOn = t;
        return null;
      }
      case 'sleep':
        current.pending = { value: { done: true } };
        return this.park(current, request.seconds);
      case 'offload': return this.offload(current, request.promise);
      case 'yield': current.pending = { value: { coroutine: false } }; return current;
      default: current.pending = { value: undefined }; return current;
    }
  }
}

/// The real driver: timers and Promises awaited.
export class AsyncScheduler extends SchedulerBase {
  park(current: Context, seconds: number): Context | null {
    this.sleepers.push({ deadline: now() + seconds, seq: this.seq++, ctx: current });
    return null;
  }
  offload(current: Context, promise: Promise<unknown>): Context | null {
    this.offloaded++;
    Promise.resolve(promise).then(
      (v) => { current.pending = { value: { offloaded: v } }; },
      (e: unknown) => {
        let error: SwiftalkError;
        if (e instanceof SwiftalkError) error = e;
        else { error = SwiftalkError.type(e instanceof Error ? e.message : String(e)); error.fromHost = true; }
        current.pending = { throw: error };
      },
    ).then(() => { this.offloaded--; this.ready.push(current); if (this.wake) { const w = this.wake; this.wake = null; w(); } });
    return null;
  }
  /// Runs the main generator to completion, its value the result; tasks
  /// it leaves parked stay parked for the next run (the REPL's world).
  async run(gen: ContextGenerator): Promise<Value | RunResult> {
    const main = new Context(gen);
    let current: Context | null = main;
    for (;;) {
      if (current === null) {
        this.wakeDueSleepers();
        const seated = this.ready.shift();
        if (seated !== undefined) current = seated;
        else if (this.sleepers.length) {
          const deadline = Math.min(...this.sleepers.map((s) => s.deadline));
          await new Promise((r) => setTimeout(r, Math.max(0, (deadline - now()) * 1000)));
          continue;
        } else if (this.offloaded > 0) {
          await new Promise<void>((r) => { this.wake = r; });
          continue;
        } else {
          // nothing ready, nothing sleeping, nobody running: what the parked
          // wait for can never happen — fail the main context if it is
          // parked, else the first parked awaiter (failing a task wakes its
          // own awaiters, so the error propagates)
          const victim = main.parkedOn ? main : this.firstParked();
          if (!victim) throw SwiftalkError.type("deadlock: 'await' on a Task that can never complete");
          this.unpark(victim);
          victim.pending = { throw: SwiftalkError.type("deadlock: 'await' on a Task that can never complete") };
          current = victim;
        }
      }
      // the main context has no task; a task body's context has its own
      const task = current.task;
      let step: IteratorResult<Request, Value | RunResult>;
      try { step = current.resume(); }
      catch (e) {
        if (task === null || !(e instanceof SwiftalkError)) throw e;
        this.complete(task, null, e);
        current = null;
        continue;
      }
      if (step.done) {
        if (task === null) return step.value;
        this.complete(task, isRunResult(step.value) ? step.value.result : null, null);
        current = null;
        continue;
      }
      current = this.dispatch(current, step.value);
    }
  }
  firstParked(): Context | null {
    for (const t of this.allAwaited()) if (t.awaiters.length) return t.awaiters[0];
    return null;
  }
  allAwaited(): TaskObject[] {
    // every task some parked context awaits is reachable from a parked context's parkedOn
    const seen = new Set<TaskObject>();
    const out: TaskObject[] = [];
    const visit = (ctx: Context) => { const t = ctx.parkedOn; if (t && !seen.has(t)) { seen.add(t); out.push(t); for (const a of t.awaiters) visit(a); } };
    for (const s of this.sleepers) visit(s.ctx);
    for (const t of out.slice()) for (const a of t.awaiters) visit(a);
    return out;
  }
  unpark(ctx: Context): void {
    const t = ctx.parkedOn;
    if (t) { t.awaiters = t.awaiters.filter((a) => a !== ctx); ctx.parkedOn = null; }
  }
}

/// The synchronous driver: no waiting — a sleep runs the other ready
/// contexts (as if the time had passed), an offload is refused.
export class SyncScheduler extends SchedulerBase {
  clock: number;
  constructor() { super(); this.clock = 0; }         // virtual time: advances only when nothing can run
  park(current: Context, seconds: number): Context | null {
    this.sleepers.push({ deadline: this.clock + seconds, seq: this.seq++, ctx: current });
    return null;
  }
  offload(current: Context, promise: Promise<unknown>): Context | null {
    current.pending = { throw: SwiftalkError.type('this operation waits on the host (a Promise) — run it with evalAsync') };
    return current;
  }
  wakeDueSleepers(): void {
    // nothing can run: the clock jumps to the earliest deadline, and the
    // sleepers due then wake in deadline order — the same order real time gives
    if (!this.sleepers.length) return;
    this.clock = Math.min(...this.sleepers.map((s) => s.deadline));
    const due = this.sleepers.filter((s) => s.deadline <= this.clock).sort((a, b) => a.deadline - b.deadline || a.seq - b.seq);
    this.sleepers = this.sleepers.filter((s) => s.deadline > this.clock);
    for (const s of due) this.ready.push(s.ctx);
  }
  run(gen: ContextGenerator): Value | RunResult {
    const main = new Context(gen);
    let current: Context | null = main;
    for (;;) {
      if (current === null) {
        if (!this.ready.length) this.wakeDueSleepers();
        const seated = this.ready.shift();
        if (seated !== undefined) current = seated;
        else {
          const awaited = main.parkedOn;
          if (!awaited) throw new Error('the scheduler has nothing to run and the program is not waiting');     // unreachable: main finished or is running
          awaited.awaiters = awaited.awaiters.filter((a) => a !== main);
          main.parkedOn = null;
          main.pending = { throw: SwiftalkError.type("deadlock: 'await' on a Task that can never complete") };
          current = main;
        }
      }
      // the main context has no task; a task body's context has its own
      const task = current.task;
      let step: IteratorResult<Request, Value | RunResult>;
      try { step = current.resume(); }
      catch (e) {
        if (task === null || !(e instanceof SwiftalkError)) throw e;
        this.complete(task, null, e);
        current = null;
        continue;
      }
      if (step.done) {
        if (task === null) return step.value;
        this.complete(task, isRunResult(step.value) ? step.value.result : null, null);
        current = null;
        continue;
      }
      current = this.dispatch(current, step.value);
    }
  }
}
