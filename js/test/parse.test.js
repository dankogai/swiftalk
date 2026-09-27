// Milestone A: every fixture that the Swift core evaluates to a value must
// at least lex and parse in JS; a `throws` fixture may fail either way.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { parse } from '../src/parser.js';
import { SwiftalkError } from '../src/errors.js';

const fixtures = JSON.parse(readFileSync(new URL('./fixtures.json', import.meta.url), 'utf8'));

test('the value fixtures all parse', () => {
  const failures = [];
  let parsed = 0;
  for (const f of fixtures) {
    if (f.throws) continue;
    try { parse(f.source); parsed++; }
    catch (e) { failures.push(`${f.file}: ${e instanceof SwiftalkError ? e.description : e}\n    ${JSON.stringify(f.source)}`); }
  }
  assert.equal(failures.length, 0, `${failures.length} of ${parsed + failures.length} did not parse:\n  ${failures.slice(0, 40).join('\n  ')}`);
});

test('a syntax error is a SwiftalkError with the core\'s wording', () => {
  assert.throws(() => parse('let x = '), (e) => e instanceof SwiftalkError && e.kind === 'syntax');
  assert.throws(() => parse(''), (e) => e.description === 'syntax error: empty program');
  assert.throws(() => parse("'..' is"), (e) => e.description.startsWith('syntax error'));
});
