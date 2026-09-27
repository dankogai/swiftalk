// `Sequence` — the module that extends the core type `Sequence` (round
// 192): `Sequence.zip(a, b)`, Swift's `zip`. Pairs until the shorter
// side ends, as unlabeled 2-tuples: lazy when either side is a lazy
// Sequence (or `a...`), else an Array stamped `[Tuple]`.
import { SwiftalkError } from '../errors.js';
import { Module } from '../modules.js';
import { typeName, SArray, TupleValue } from '../value.js';
import { SequenceObject } from '../objects.js';
import { ann } from '../types.js';
import { iteratorOf, isSequenceValue, lazyBase } from '../eval.js';

export function SequenceModule() {
  const m = new Module('Sequence');
  m.static('Sequence', 'zip', Module.builtin(function* (args) {
    if (args.length !== 2) throw SwiftalkError.type('Sequence.zip(a, b) takes exactly two Sequences');
    for (const side of args) if (!isSequenceValue(side)) throw SwiftalkError.type(`Sequence.zip(a, b): ${typeName(side)} is not a Sequence`);
    const [lhs, rhs] = args;
    const tuple = ann('Tuple');
    if (lazyBase(lhs) || lazyBase(rhs)) {
      return new SequenceObject({
        kind: 'native', element: tuple,
        make: function* () {
          const a = yield* iteratorOf(lhs), b = yield* iteratorOf(rhs);
          return function* () {
            const x = yield* a.next(); if (x === undefined) return undefined;
            const y = yield* b.next(); if (y === undefined) return undefined;
            return new TupleValue([x, y], [null, null]);
          };
        },
      });
    }
    const a = yield* iteratorOf(lhs), b = yield* iteratorOf(rhs);
    const pairs = [];
    for (;;) {
      const x = yield* a.next(); if (x === undefined) break;
      const y = yield* b.next(); if (y === undefined) break;
      pairs.push(new TupleValue([x, y], [null, null]));
    }
    return new SArray(pairs, ann('Array', false, [tuple]));
  }));
  return m;
}
