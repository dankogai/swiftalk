// The prelude modules in JS: IO, Net, Regex — over a host that lends
// output, input, files, and the network as functions.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Interpreter } from '../src/interpreter.js';
import { withPrelude, preludeModules } from '../src/prelude.js';
import { SwiftalkError } from '../src/errors.js';
import { SDictionary, SData, sourceString } from '../src/value.js';

function make() {
  const i = withPrelude(new Interpreter(true));
  const log = { out: '', err: '' };
  i.output = (s) => { log.out += s; };
  i.errorOutput = (s) => { log.err += s; };
  return [i, log];
}

test('print and debugPrint write to the host sinks', () => {
  const [i, log] = make();
  i.eval('print("a", 1, [2.5], "b" + "c")\ndebugPrint("x", 255)');
  assert.equal(log.out, 'a 1 [2.5] bc\n');
  assert.equal(log.err, '"x" +0xff\n');                       // the debug form is .String(.sign, .hex), round 125
  assert.equal(i.eval('IO.stdout.print("via the handle")'), null);
  assert.equal(log.out.endsWith('via the handle\n'), true);
  assert.throws(() => i.eval('print(x: 1)'), (e) => e instanceof SwiftalkError);
  assert.throws(() => i.eval('let print = 42'), (e) => /builtin/.test(e.description));
});

test('readLine comes from the host hook, nil at its end', async () => {
  const [i] = make();
  const lines = ['first', 'second'];
  i.hooks.set('readLine', () => Promise.resolve(lines.shift() ?? null));
  assert.deepEqual((await i.evalAsync('[readLine(), readLine(), readLine()]')).items, ['first', 'second', null]);
  const [bare] = [new Interpreter()];
  assert.throws(() => bare.eval('readLine()'), (e) => /undefined variable/.test(e.description));
});

test('IO(path:) runs over the host file object', async () => {
  const [i] = make();
  const files = new Map();
  i.hooks.set('openFile', (path, mode) => {
    if (mode === 'read' && !files.has(path)) throw new Error('No such file or directory');
    if (mode === 'write' || !files.has(path)) files.set(path, new Uint8Array(0));
    let pos = mode === 'append' ? files.get(path).length : 0;
    return {
      read(size) { const b = files.get(path); if (pos >= b.length) return null; const c = b.slice(pos, pos + size); pos += c.length; return c; },
      write(bytes) { const b = files.get(path); const n = new Uint8Array(pos + bytes.length > b.length ? pos + bytes.length : b.length); n.set(b); n.set(bytes, pos); files.set(path, n); pos += bytes.length; },
      seekStart() { pos = 0; return true; }, seekEnd() { pos = files.get(path).length; return true; },
      truncate() { files.set(path, new Uint8Array(0)); pos = 0; }, close() {},
    };
  });
  assert.equal(await i.evalAsync('var fh = IO(path: "notes.txt", mode: .write)\nfh.print("one")\nfh.append("two\\n")\nfh.data.String(.utf8)'), 'one\ntwo\n');
  assert.deepEqual((await i.evalAsync('IO(path: "notes.txt").lines.Array()')).items, ['one', 'two']);
  assert.equal(await i.evalAsync('var g = IO(path: "notes.txt", mode: .readWrite)\ng.data = "replaced"\ng.data.String(.utf8)'), 'replaced');
  assert.deepEqual((await i.evalAsync('IO(path: "notes.txt").read(3).map { $0.count }.Array()')).items, [3n, 3n, 2n], 'chunks');
  await assert.rejects(i.evalAsync('IO(path: "missing.txt")'), (e) => /No such file/.test(e.description));
  assert.equal(await i.evalAsync('fh.close()\nfh.isClosed'), true);
});

test('fetch is a Task of a Result, over the host hook', async () => {
  const [i] = make();
  i.hooks.set('fetch', (args) => {
    const req = args[0];
    assert.equal(req.get('method'), 'POST');
    assert.equal(new TextDecoder().decode(req.get('body').bytes), '{"q":1}');
    return Promise.resolve(new SDictionary([['status', 200n], ['headers', new SDictionary([['Content-Type', 'application/json']])], ['body', '{"answer": 42}']]));
  });
  const r = await i.evalAsync('let r = await fetch("https://api.example/x", (method: "post", body: "{\\"q\\":1}"))\n[r!.status, r!.ok, r!.headers["content-type"], r!.json()["answer"]]');
  assert.deepEqual(r.items, [200n, true, 'application/json', 42n]);
  i.hooks.set('fetch', () => Promise.reject(new Error('no route to host')));
  assert.equal(await i.evalAsync('(await fetch("https://nowhere")) ?? "failed"'), 'failed');
  assert.match(sourceString(await i.evalAsync('await fetch("https://nowhere")')), /failure\("no route to host"\)/);
});

test('Regex: literals, flags, matches, and the String members', () => {
  const [i] = make();
  assert.equal(i.eval('/a\\/b/i.String()'), '/a\\/b/i');
  assert.equal(i.eval('"Hello World".replacing(/o/, "0")'), 'Hell0 W0rld');
  assert.equal(i.eval('"2026-09-28".firstMatch(/(?<y>\\d+)-(?<m>\\d+)-(?<d>\\d+)/).d'), '28');
  assert.deepEqual(i.eval('"a1b2".matches(/\\d/)').items, ['1', '2']);
  assert.equal(i.eval('"e\\u{301}".contains(/^é$/)'), true, 'canonical equivalence: the subject is matched in NFC');
  assert.throws(() => i.eval('/a/q'), (e) => e.kind === 'syntax');
  assert.throws(() => i.eval('Regex("(")'), (e) => e.kind === 'syntax');
  assert.equal(i.eval('[/a/: 1, /a/i: 2][/a/]'), 1n);
  assert.equal(i.eval('"漢字かな".matches(/\\p{Han}+/)[0]'), '漢字');
});

test('a bare Interpreter has no prelude; import brings a module by name', () => {
  const bare = new Interpreter();
  assert.throws(() => bare.eval('print(1)'), (e) => /undefined variable 'print'/.test(e.description));
  assert.throws(() => bare.eval('/a/'), (e) => /Regex module/.test(e.description));
  let out = '';
  bare.output = (s) => { out += s; };
  for (const m of preludeModules()) bare.register(m);
  bare.eval('import (print) from "IO"\nprint("now")');
  assert.equal(out, 'now\n');
  assert.equal(bare.eval('import IO from "IO"\nIO.IO.stdout.Type == IO.IO'), true, 'the namespace and the type share a name — the Complex trap, accepted (round 191)');
  assert.equal(bare.eval('import (Regex) from "Regex"\n/x/.pattern'), 'x');
});

test('import is idempotent (round 202): what is already bound to the same value is skipped', async () => {
  const [i, log] = make();
  assert.equal(i.eval('import from "BigInt"\n(2n ** 70n).String()'), '1180591620717411303424n');   // the prelude brought it already
  assert.equal(i.eval('import (print) from "IO"\nprint("still")'), null);
  assert.equal(log.out, 'still\n');
  i.moduleLoader = () => 'export let twice = { x in x * 2 }\nexport let name = "m"';
  assert.equal(await i.evalAsync('import (twice) from "./m.swt"\ntwice(1)'), 2n);
  assert.equal(await i.evalAsync('import (twice) from "./m.swt"\ntwice(2)'), 4n);
  assert.equal(await i.evalAsync('import M from "./m.swt"\nimport M from "./m.swt"\nM.name'), 'm');
  assert.equal(await i.evalAsync('import N from "./m.swt"\nN == M'), true);
  await i.evalAsync('let other = 1');
  const j = make()[0];
  j.moduleLoader = () => 'export let other = 2';
  await j.evalAsync('let other = 1');
  await assert.rejects(j.evalAsync('import (other) from "./o.swt"'), (e) => /redeclaration/.test(e.description));
  assert.throws(() => i.eval('import IO from "IO"'), (e) => /redeclaration/.test(e.description));   // the Complex trap stays
});
