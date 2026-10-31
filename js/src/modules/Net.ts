// `Net` — `fetch` and its `Response` (round 189's module, in JavaScript).
// `fetch(url[, options])` is a Task whose value is a Result:
// `.success(Response)` for any HTTP answer, `.failure(message)` when none
// came. The transport is the host's "fetch" hook when it lends one (a
// request Dictionary in — url, method, headers, body — a response
// Dictionary out — status, headers, body), else the platform's `fetch`;
// either way a Promise, awaited by an offload, so other tasks run
// meanwhile. `Response` is declared in swiftalk, in the module's prelude.
import { SwiftalkError } from '../errors.js';
import { Module } from '../modules.js';
import { kindOf, typeName, SDictionary, SData, TupleValue } from '../value.js';
import { FunctionObject } from '../objects.js';
import { Builtins, success, failure } from '../builtins.js';
import { apply, spawnTask, offload, scheduler } from '../eval.js';
import type { Value } from '../value.js';
import type { Hook } from '../interpreter.js';

type Request = { url: string; method: string; headers: Map<string, string>; body: Uint8Array | null };
type Answer = { status: number; headers: Map<string, string>; body: Uint8Array };

function request(args: Value[]): Request {
  if (!(args.length === 1 || args.length === 2) || typeof args[0] !== 'string') throw SwiftalkError.type('fetch(url) or fetch(url, options) — the url a String');
  const r: Request = { url: args[0], method: 'GET', headers: new Map(), body: null };
  if (args.length === 1) return r;
  let options: [string, Value][];
  const given = args[1];
  if (kindOf(given) === 'dictionary') {
    options = (given as SDictionary).entries().map(([k, v]): [string, Value] => { if (typeof k !== 'string') throw SwiftalkError.type('fetch options: String keys — method, headers, body'); return [k, v]; });
  } else if (given instanceof TupleValue) {
    options = given.values.map((v, i): [string, Value] => { const l = given.labels[i]; if (l === null) throw SwiftalkError.type('fetch options: a labeled tuple — (method:, headers:, body:)'); return [l, v]; });
  } else throw SwiftalkError.type(`fetch options are a Dictionary or a labeled tuple, not a ${typeName(args[1])}`);
  for (const [key, value] of options) {
    if (key === 'method' && typeof value === 'string') r.method = value.toUpperCase();
    else if (key === 'headers' && kindOf(value) === 'dictionary') {
      for (const [k, v] of (value as SDictionary).entries()) { if (typeof k !== 'string' || typeof v !== 'string') throw SwiftalkError.type('fetch headers: [String: String]'); r.headers.set(k, v); }
    } else if (key === 'body' && typeof value === 'string') r.body = new TextEncoder().encode(value);
    else if (key === 'body' && value instanceof SData) r.body = value.bytes;
    else if (key === 'body' && value === null) r.body = null;
    else throw SwiftalkError.type(`fetch option '${key}': method (String), headers ([String: String]), body (String or Data)`);
  }
  return r;
}
const requestValue = (r: Request): SDictionary => new SDictionary([
  ['url', r.url], ['method', r.method], ['headers', new SDictionary([...r.headers])], ['body', r.body ? new SData(r.body) : null]]);
/// The hook's answer, a Dictionary (status, headers, body), or the platform fetch's Response.
async function answerOf(r: Request, hook: Hook | null): Promise<Answer> {
  if (hook) {
    const v: Value = await hook([requestValue(r)]);
    if (kindOf(v) !== 'dictionary') throw SwiftalkError.type(`the fetch hook must answer a Dictionary (status, headers, body), not a ${typeName(v)}`);
    const d = v as SDictionary;
    const status = d.get('status'), headers = d.get('headers'), body = d.get('body');
    const h = new Map<string, string>();
    if (headers instanceof SDictionary) for (const [k, x] of headers.entries()) if (typeof k === 'string' && typeof x === 'string') h.set(k, x);
    return { status: typeof status === 'bigint' ? Number(status) : 0, headers: h,
      body: body instanceof SData ? body.bytes : typeof body === 'string' ? new TextEncoder().encode(body) : new Uint8Array(0) };
  }
  if (typeof globalThis.fetch !== 'function') throw SwiftalkError.type('fetch: this host has no fetch');
  const res = await globalThis.fetch(r.url, { method: r.method, headers: Object.fromEntries(r.headers), body: r.body && r.method !== 'GET' && r.method !== 'HEAD' ? r.body : undefined });
  const h = new Map<string, string>();
  res.headers.forEach((v, k) => h.set(k, v));
  return { status: res.status, headers: h, body: new Uint8Array(await res.arrayBuffer()) };
}

export const responsePrelude = `export struct Response {
    var status: Int = 0
    var headers: [String: String] = [:]
    var body: Data = Data()
    var ok { 200 <= .status && .status < 300 }
    let text = { .body.String(.utf8) }
    let json = { SION(json: .body.String(.utf8)!) }
}`;

export function NetModule(): Module {
  const m = new Module('Net');
  m.prelude = responsePrelude;
  m.function('fetch', function* (args: Value[]) {
    const r = request(args);
    const interp = scheduler.current;
    const hook = interp ? interp.hooks.get('fetch') ?? null : null;
    const responseType = m.value('Response') as FunctionObject | undefined;
    if (!responseType) throw SwiftalkError.type('fetch: the Response type is missing');
    const body = new FunctionObject([], [], Builtins.emptyEnvironment, function* () {
      let answer: Answer;
      try { answer = yield* offload(answerOf(r, hook)); }
      catch (e) { if (e instanceof SwiftalkError) return failure((e as any).fromHost ? e.detail : e.description); return failure(String(e && e.message ? e.message : e)); }
      const headers = new SDictionary([...answer.headers].map(([k, v]): [Value, Value] => [k.toLowerCase(), v]));
      const response = yield* apply(responseType, [
        { label: 'status', value: BigInt(answer.status) }, { label: 'headers', value: headers }, { label: 'body', value: new SData(answer.body) }]);
      return success(response);
    });
    return yield* spawnTask(body);
  });
  return m;
}
