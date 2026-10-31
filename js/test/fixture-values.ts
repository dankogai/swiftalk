// The fixture JSON (tools/extract-fixtures.mjs) back into Values.
import { SArray, SDictionary, SSet, Byte, SData, SDate, TupleValue } from '../src/value.js';
import type { Value } from '../src/value.js';

/// A Swift Value literal as the extractor writes it (tools/extract-fixtures.mjs): one key names the kind.
export type FixtureValue =
  | { nil: true } | { bool: boolean } | { int: string } | { double: string } | { string: string }
  | { array: FixtureValue[] } | { set: FixtureValue[] } | { dictionary: [FixtureValue, FixtureValue][] }
  | { byte: string } | { data: string[] } | { date: string } | { tuple: FixtureValue[]; labels?: (string | null)[] | null };
/// One extracted expectation: the swiftalk source, the test file it came from, and the Swift value or a throw.
export type Fixture = { source: string; file: string; throws?: boolean; expect?: FixtureValue };

/// The fixture JSON back into a Value.
export function valueOf(x: FixtureValue): Value {
  if ('nil' in x) return null;
  if ('bool' in x) return x.bool;
  if ('int' in x) return BigInt(x.int);
  if ('double' in x) {
    const d = x.double;
    if (d === 'inf' || d === '+inf') return Infinity;
    if (d === '-inf') return -Infinity;
    if (d === 'nan' || d === '-nan') return NaN;
    return Number(d.replace(/_/g, ''));
  }
  if ('string' in x) return x.string;
  if ('array' in x) return new SArray(x.array.map(valueOf));
  if ('set' in x) return new SSet(x.set.map(valueOf));
  if ('dictionary' in x) return new SDictionary(x.dictionary.map(([k, v]): [Value, Value] => [valueOf(k), valueOf(v)]));
  if ('byte' in x) return new Byte(Number(x.byte));
  if ('data' in x) return new SData(x.data.map(Number));
  if ('date' in x) return new SDate(Number(x.date));
  if ('tuple' in x) return new TupleValue(x.tuple.map(valueOf), x.labels ?? null);
  const unknown: never = x;
  throw new Error(`unknown fixture value ${JSON.stringify(unknown)}`);
}
