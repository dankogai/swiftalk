// The prelude (round 185): the modules the CLI preimports — IO, Net,
// Regex, Sequence, Task, BigInt — as JavaScript, registered and preimported on
// an Interpreter in one call. An embedder that wants a silent interpreter
// never calls it; `import from "IO"` still brings `print` on request.
import { IOModule } from './modules/IO.js';
import { NetModule } from './modules/Net.js';
import { RegexModule } from './modules/Regex.js';
import { SequenceModule } from './modules/Sequence.js';
import { TaskModule } from './modules/Task.js';
import { BigIntModule } from './modules/BigInt.js';

export const preludeModules = () => [IOModule(), NetModule(), RegexModule(), SequenceModule(), TaskModule(), BigIntModule()];
export const preludeNames = ['IO', 'Net', 'Regex', 'Sequence', 'Task', 'BigInt'];

/// Registers the five and preimports them; returns the interpreter.
export function withPrelude(interp) {
  for (const m of preludeModules()) interp.register(m);
  interp.preimport(preludeNames);
  return interp;
}
