// Milestone B: every fixture the Swift core evaluates to a value must
// evaluate to the same value in JS; every `throws` fixture must throw a
// SwiftalkError. Fixtures are extracted from Tests/SwiftalkTests by
// tools/extract-fixtures.mjs.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { Interpreter } from '../src/interpreter.js';
import { withPrelude } from '../src/prelude.js';
import { SwiftalkError } from '../src/errors.js';
import { equals, sourceString } from '../src/value.js';
import { valueOf } from './fixture-values.js';

const fixtures = JSON.parse(readFileSync(new URL('./fixtures.json', import.meta.url), 'utf8'));

const same = (a, b) => {
  if (typeof a === 'number' && typeof b === 'number' && Number.isNaN(a) && Number.isNaN(b)) return true;
  return equals(a, b);
};

/// The prelude — IO, Net, Regex, Sequence, Task — as JS modules, preimported
/// as the CLI does; output silenced, no host hooks (no stdin, files, or network).
function interpreter() {
  const i = withPrelude(new Interpreter());
  i.output = () => {};
  i.errorOutput = () => {};
  return i;
}

/// Where the JS runtime knowingly differs from the Swift core, by fixture
/// source: Swift's Regex matches Characters (grapheme clusters), RegExp
/// matches code points (FIXME in modules/Regex.js). Each of these must
/// still fail — a divergence that heals is removed from the list.
export const knownDivergences = new Map([
  ['"👨‍👩‍👧".matches(/./).count', 'a grapheme is one `.` in Swift, five code points here'],
  ['"か\\u{309A}き".matches(/[\\u{3040}-\\u{309F}]/)', 'a class matches whole Characters in Swift'],
  ['"🇯🇵🇺🇸".matches(/[\\u{1F1E6}-\\u{1F1FF}]/)', 'a flag is one Character of two scalars in Swift'],
  ['"か\\u{309A}き".matches(/\\p{Hiragana}+/)', 'the combining mark rides with its base in Swift'],
  ['"🇯🇵🇺🇸".matches(/\\p{RegionalIndicator}/)', 'a flag is one Character in Swift'],
  ['"か\\u{309A}".matches(/[か\\u{309A}]/)', 'a class matches whole Characters in Swift'],
]);

const verbose = process.env.SWIFTALK_VERBOSE === '1';
test('the fixtures evaluate as the Swift core does', async () => {
  const failures = [];
  let passed = 0, diverged = 0;
  const byFile = new Map();
  const unhealed = new Set();
  for (const f of fixtures) {
    const known = knownDivergences.has(f.source);
    const interp = interpreter();
    let outcome;
    try {
      const got = await interp.evalAsync(f.source);
      if (f.throws) outcome = `expected an error, got ${sourceString(got)}`;
      else {
        const want = valueOf(f.expect);
        if (!same(got, want)) outcome = `expected ${sourceString(want)}, got ${sourceString(got)}`;
      }
    } catch (e) {
      if (f.throws && e instanceof SwiftalkError) { /* as expected */ }
      else outcome = e instanceof SwiftalkError ? `threw ${e.description}` : `crashed: ${e && e.stack ? e.stack.split('\n').slice(0, 3).join(' | ') : e}`;
    }
    if (known) {
      if (outcome) { diverged++; unhealed.add(f.source); }
      else failures.push(`${f.file}: a known divergence now agrees with Swift — drop it from knownDivergences\n    ${JSON.stringify(f.source)}`);
      continue;
    }
    if (outcome) {
      failures.push(`${f.file}: ${outcome}\n    ${JSON.stringify(f.source)}`);
      byFile.set(f.file, (byFile.get(f.file) ?? 0) + 1);
    } else passed++;
  }
  for (const source of knownDivergences.keys()) if (!unhealed.has(source)) failures.push(`knownDivergences names no fixture: ${source}`);
  if (failures.length && verbose) console.error([...byFile].sort((a, b) => b[1] - a[1]).map(([k, v]) => `${v}\t${k}`).join('\n'));
  if (verbose) console.error(`${passed} passed, ${diverged} known divergences`);
  assert.equal(failures.length, 0,
    `${failures.length} of ${passed + failures.length} fixtures failed:\n  ${failures.slice(0, verbose ? 400 : 30).join('\n  ')}`);
});

test('the synchronous driver runs the same programs, time not passing', () => {
  const i = interpreter();
  // sleepers wake in deadline order, at once
  assert.deepEqual(i.eval('var log = []\nlet t1 = async { log.append(1); Task.sleep(0.03); log.append(3) }\nlet t2 = async { log.append(2); Task.sleep(0.01); log.append(4) }\nTask.sleep(0.05)\nlog').items, [1n, 2n, 4n, 3n]);
  assert.equal(i.eval('let t = async { Task.sleep(60.0); 1 }\n42'), 42n);
  assert.throws(() => i.eval('var u = async { Task.sleep(0.01); await u }\nawait u'), (e) => /deadlock/.test(e.description));
});

test('the asynchronous driver waits on real timers', async () => {
  const i = interpreter();
  const t0 = Date.now();
  assert.deepEqual((await i.evalAsync('let a = async { Task.sleep(0.05); 1 }\nlet b = async { Task.sleep(0.01); 2 }\n[await a, await b]')).items, [1n, 2n]);
  assert.ok(Date.now() - t0 >= 45, 'slept for the longer sleeper');
  // a parked task persists into the next eval, the REPL's world
  await i.evalAsync('let t = async { Task.sleep(0.01); 42 }');
  assert.equal(await i.evalAsync('await t'), 42n);
  // a host Promise through offload
  i.declareBuiltin('later', () => new Promise((r) => setTimeout(() => r(7n), 5)));
  assert.equal(await i.evalAsync('later()'), 7n);
});

test('a source module loads through the host loader, once, and binds a namespace type', async () => {
  const i = interpreter();
  const files = { 'lib/m.swt': 'export let twice = { x in x * 2 }\nexport let name = "m"' };
  let reads = 0;
  i.moduleLoader = (spec) => { reads++; if (!(spec in files)) throw SwiftalkError.type(`no file ${spec}`); return Promise.resolve(files[spec]); };
  assert.equal(await i.evalAsync('import (twice) from "./lib/m.swt"\ntwice(21)'), 42n);
  assert.equal(await i.evalAsync('import M from "./lib/m.swt"\nM.name + M.twice(1).String()'), 'm2');
  assert.equal(reads, 1);
  await assert.rejects(i.evalAsync('import from "./lib/none.swt"'), (e) => e instanceof SwiftalkError);
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
