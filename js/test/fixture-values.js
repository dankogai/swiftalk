// The fixture JSON (tools/extract-fixtures.mjs) back into Values.
import { SArray, SDictionary, SSet, Byte, SData, SDate, TupleValue } from '../src/value.js';

/// The fixture JSON back into a Value.
export function valueOf(x) {
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
  if ('dictionary' in x) return new SDictionary(x.dictionary.map(([k, v]) => [valueOf(k), valueOf(v)]));
  if ('byte' in x) return new Byte(Number(x.byte));
  if ('data' in x) return new SData(x.data.map(Number));
  if ('date' in x) return new SDate(Number(x.date));
  if ('tuple' in x) return new TupleValue(x.tuple.map(valueOf), x.labels ?? null);
  throw new Error(`unknown fixture value ${JSON.stringify(x)}`);
}
