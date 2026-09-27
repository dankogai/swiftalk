// The value model: Swift's Double spellings, quoting, keys, equality.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { formatDouble, hexFloat, quote, sourceString, keyOf, equals, V, graphemeCount, compareStrings } from '../src/value.js';

test('Double prints as Swift does', () => {
  const cases = [[1.0, '1.0'], [0.1, '0.1'], [100.0, '100.0'], [1e15, '1000000000000000.0'], [1e16, '1e+16'], [1e17, '1e+17'],
    [123456789012345680.0, '1.2345678901234568e+17'], [1.5e300, '1.5e+300'], [0.001, '0.001'], [0.0001, '0.0001'], [0.00001, '1e-05'],
    [1e-7, '1e-07'], [5e-324, '5e-324'], [1.7976931348623157e308, '1.7976931348623157e+308'], [0.1 + 0.2, '0.30000000000000004'],
    [2.5e-5, '2.5e-05'], [12345.678, '12345.678'], [-0.0, '-0.0'], [0.0, '0.0'], [Infinity, 'inf'], [-Infinity, '-inf'], [NaN, 'nan'],
    [9007199254740993.0, '9007199254740992.0'], [1e21, '1e+21'], [1e22, '1e+22'], [1e20, '1e+20'], [3.0e-4, '0.0003'], [1234567.0, '1234567.0'], [0.5, '0.5'], [1e2, '100.0']];
  for (const [d, s] of cases) assert.equal(formatDouble(d), s, `formatDouble(${d})`);
});

test('hex floats as Swift spells them', () => {
  const cases = [[1.0, '0x1p0'], [0.1, '0x1.999999999999ap-4'], [1e16, '0x1.1c37937e08p53'], [1e-7, '0x1.ad7f29abcaf48p-24'], [3.5, '0x1.cp1'], [-2.25, '-0x1.2p1'], [1e100, '0x1.249ad2594c37dp332']];
  for (const [d, s] of cases) assert.equal(hexFloat(d), s, `hexFloat(${d})`);
  assert.equal(hexFloat(1.0, true), '+0x1p0');
});

test('quoting, source forms, keys, equality', () => {
  assert.equal(quote('a"b\\c\n\u0001'), '"a\\"b\\\\c\\n\\u{1}"');
  assert.equal(sourceString(V.array([1n, 'a', null, true])), '[1, "a", nil, true]');
  assert.equal(sourceString(V.dictionary([['b', 2n], ['a', 1n]])), '["a": 1, "b": 2]');
  assert.equal(sourceString(V.set([3n, 1n, 2n])), 'Set(1, 2, 3)');
  assert.equal(sourceString(V.set([V.array([1n])])), 'Set([[1]])');
  assert.equal(sourceString(V.tuple([1n], [null])), '(1,)');
  assert.equal(sourceString(V.tuple([1n, 2n], ['x', null])), '(x: 1, 2)');
  assert.equal(sourceString(V.data([255, 0])), '.Data("/wA=")');
  assert.equal(sourceString(V.data([255]), true), 'Data([0xff])');
  assert.equal(sourceString(V.byte(255)), 'Byte(255)');
  assert.equal(sourceString(V.range(1n, 3n, true)), '1...3');
  assert.equal(sourceString(V.range(1n, null, true)), '1...');
  assert.equal(sourceString(255n, true), '+0xff');
  assert.equal(sourceString(-255n, true), '-0xff');
  assert.equal(sourceString(V.date(0)), '.Date(0.0)');
  assert.ok(equals('é', 'é'));                        // canonical equivalence
  assert.equal(keyOf('é'), keyOf('é'));
  assert.ok(equals(V.byte(3), 3n));
  assert.ok(!equals(1n, 1.0));
  assert.ok(equals(V.array([1n, V.array([2n])]), V.array([1n, V.array([2n])])));
  assert.equal(graphemeCount('é🇯🇵a'), 3);
  assert.equal(compareStrings('a', 'b'), -1);
  assert.equal(compareStrings('😀', '￿'), 1);            // scalar order, not UTF-16 units
});
