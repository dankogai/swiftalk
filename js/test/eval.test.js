// Milestone B: every fixture the Swift core evaluates to a value must
// evaluate to the same value in JS; every `throws` fixture must throw a
// SwiftalkError. Fixtures are extracted from Tests/SwiftalkTests by
// tools/extract-fixtures.mjs.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { Interpreter } from '../src/interpreter.js';
import { Lexer } from '../src/lexer.js';
import { SwiftalkError } from '../src/errors.js';
import { equals, sourceString } from '../src/value.js';
import { valueOf } from './fixture-values.js';

const fixtures = JSON.parse(readFileSync(new URL('./fixtures.json', import.meta.url), 'utf8'));

const same = (a, b) => {
  if (typeof a === 'number' && typeof b === 'number' && Number.isNaN(a) && Number.isNaN(b)) return true;
  return equals(a, b);
};

/// The prelude modules (IO, Net, Regex, Sequence.zip, Task.sleep) are
/// milestone D: a fixture that names one of them — or spells a regex
/// literal — waits for it. Decided by the lexer, not by guessing.
const moduleNames = new Set(['Regex', 'print', 'debugPrint', 'readLine', 'zip', 'sleep', 'fetch', 'IO', 'Net', 'POSIX']);
export function needsModule(source) {
  let tokens;
  try { tokens = new Lexer(source).tokenize(); } catch (e) { return false; }
  return tokens.some((t) => t.t === 'regex' || (t.t === 'identifier' && moduleNames.has(t.v)));
}

const verbose = process.env.SWIFTALK_VERBOSE === '1';
test('the fixtures evaluate as the Swift core does', () => {
  const failures = [];
  let passed = 0, skipped = 0;
  const byFile = new Map();
  for (const f of fixtures) {
    if (needsModule(f.source)) { skipped++; continue; }
    const interp = new Interpreter();
    interp.output = () => {};
    interp.errorOutput = () => {};
    let outcome;
    try {
      const got = interp.eval(f.source);
      if (f.throws) outcome = `expected an error, got ${sourceString(got)}`;
      else {
        const want = valueOf(f.expect);
        if (!same(got, want)) outcome = `expected ${sourceString(want)}, got ${sourceString(got)}`;
      }
    } catch (e) {
      if (f.throws && e instanceof SwiftalkError) { /* as expected */ }
      else outcome = e instanceof SwiftalkError ? `threw ${e.description}` : `crashed: ${e && e.stack ? e.stack.split('\n').slice(0, 3).join(' | ') : e}`;
    }
    if (outcome) {
      failures.push(`${f.file}: ${outcome}\n    ${JSON.stringify(f.source)}`);
      byFile.set(f.file, (byFile.get(f.file) ?? 0) + 1);
    } else passed++;
  }
  if (failures.length && verbose) console.error([...byFile].sort((a, b) => b[1] - a[1]).map(([k, v]) => `${v}\t${k}`).join('\n'));
  if (verbose) console.error(`${passed} passed, ${skipped} wait for the prelude modules`);
  assert.equal(failures.length, 0,
    `${failures.length} of ${passed + failures.length} fixtures failed:\n  ${failures.slice(0, verbose ? 400 : 30).join('\n  ')}`);
});

test('the module-dependent fixtures are only those', () => {
  // the skip list must not hide core failures: every skipped fixture names a module or spells a regex literal
  const skipped = fixtures.filter((f) => needsModule(f.source));
  assert.ok(skipped.length < 120, `${skipped.length} fixtures skipped — too many`);
  for (const f of skipped) assert.ok(/Regex|print|readLine|zip|sleep|fetch|\bIO\b|Net|POSIX|\//.test(f.source), f.source);
});

test('an Interpreter keeps its globals between evals', () => {
  const i = new Interpreter();
  i.eval('let x = 40');
  assert.equal(i.eval('x + 2'), 42n);
  assert.throws(() => i.eval('let x = 1'), (e) => e instanceof SwiftalkError);
});

test('output goes where the host says', () => {
  const i = new Interpreter();
  let out = '';
  i.output = (s) => { out += s; };
  i.declareBuiltin('print', (args) => { out += args.map((a) => (typeof a === 'string' ? a : sourceString(a))).join(' ') + '\n'; return null; });
  i.eval('print("hi", 42)');
  assert.equal(out, 'hi 42\n');
});
