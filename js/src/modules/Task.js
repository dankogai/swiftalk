// `Task` — the module that extends the core type `Task` (round 192):
// `Task.sleep(seconds)`. Suspends only the current context — parked
// tasks run meanwhile; at the top level it doubles as "run the loop for
// a while". Under the synchronous driver time does not pass: the other
// ready contexts run, then this one continues.
import { SwiftalkError } from '../errors.js';
import { Module } from '../modules.js';
import { sleep } from '../eval.js';

export function TaskModule() {
  const m = new Module('Task');
  m.static('Task', 'sleep', Module.builtin(function* (args) {
    let seconds;
    if (args.length === 1 && typeof args[0] === 'number' && args[0] >= 0) seconds = args[0];
    else if (args.length === 1 && typeof args[0] === 'bigint' && args[0] >= 0n) seconds = Number(args[0]);
    else throw SwiftalkError.type('Task.sleep(seconds) — a non-negative Int or Double');
    yield* sleep(seconds);
    return null;
  }));
  return m;
}
