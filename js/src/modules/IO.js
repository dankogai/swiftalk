// `IO` — output, input, and files (round 191's module, in JavaScript).
//
//     print(1, "two")                    // Interpreter.output
//     debugPrint("two")                  // Interpreter.errorOutput
//     let name = readLine()              // one line of input, nil at EOF — the host's "readLine" hook
//     IO.stdin, IO.stdout, IO.stderr     // the three handles
//     var fh = IO(path: "notes.txt")     // the host's "openFile" hook opens it: .read (default), .write, .append, .readWrite
//     fh.data; fh.data = "x"; fh.lines; fh.read(4096); fh.append(d); fh.write(d); fh.print(x); fh.readLine(); fh.close()
//
// The host lends the I/O: `Interpreter.hooks` "readLine" (→ a String, null
// at EOF, or a Promise of one) and "openFile" (path, mode → a file object
// with read(size) → bytes or null, write(bytes), seekStart() → Bool,
// truncate(), close()). Node's are in host/node.js; a browser page lends
// what it can (a prompt for readLine, no files). Failures are errors, not
// Results, as in the Swift module.
import { SwiftalkError } from '../errors.js';
import { Module } from '../modules.js';
import { kindOf, typeName, sourceString, SData } from '../value.js';
import { HostValue, SequenceObject } from '../objects.js';
import { ann } from '../types.js';
import { displayString, scheduler, offload } from '../eval.js';

const encoder = new TextEncoder();
const decoder = new TextDecoder();
const current = () => {
  const i = scheduler.current;
  if (!i) throw SwiftalkError.type('IO needs a running Interpreter');
  return i;
};
const hook = (name) => current().hooks.get(name) ?? null;
/// A host answer that may be a Promise: waited on through the scheduler.
function* settled(v) { return v && typeof v.then === 'function' ? yield* offload(v) : v; }

class Handle {
  constructor(file, path, mode, standardName = null) {
    this.file = file;               // null for a standard handle without a file object
    this.path = path;
    this.mode = mode;
    this.standardName = standardName;
    this.closed = false;
    this.buffer = new Uint8Array(0);
    this.typeName = 'IO';
  }
  get label() { return this.path !== null ? `IO(path: "${this.path}")` : `IO.${this.standardName}`; }
  live() { if (this.closed) throw SwiftalkError.type(`${this.label} is closed`); }
  bytesOf(v, call) {
    if (v instanceof SData) return v.bytes;
    if (typeof v === 'string') return encoder.encode(v);
    throw SwiftalkError.type(`${this.label}.${call} takes a Data or a String, not ${typeName(v)}`);
  }
  // ---- reading ----
  *fill(size = 65536) {
    this.live();
    if (!this.file || !this.file.read) throw SwiftalkError.type(`${this.label} cannot be read`);
    const chunk = yield* settled(this.file.read(size));
    if (!chunk || chunk.length === 0) return false;
    const joined = new Uint8Array(this.buffer.length + chunk.length);
    joined.set(this.buffer); joined.set(chunk, this.buffer.length);
    this.buffer = joined;
    return true;
  }
  *readLine() {
    if (this.standardName === 'stdin' && !this.file) {
      const h = hook('readLine');
      if (!h) throw SwiftalkError.type('readLine: the host lends no input (no "readLine" hook)');
      const line = yield* settled(h());
      return line === null || line === undefined ? null : String(line);
    }
    for (;;) {
      const nl = this.buffer.indexOf(10);
      if (nl >= 0) {
        let line = this.buffer.slice(0, nl);
        this.buffer = this.buffer.slice(nl + 1);
        if (line.length && line[line.length - 1] === 13) line = line.slice(0, -1);
        return decoder.decode(line);
      }
      if (!(yield* this.fill())) {
        if (this.buffer.length === 0) return null;
        const line = this.buffer; this.buffer = new Uint8Array(0);
        return decoder.decode(line);
      }
    }
  }
  *readChunk(size) {
    while (this.buffer.length < size) if (!(yield* this.fill(Math.max(size, 65536)))) break;
    if (this.buffer.length === 0) return null;
    const n = Math.min(size, this.buffer.length);
    const chunk = this.buffer.slice(0, n);
    this.buffer = this.buffer.slice(n);
    return new SData(chunk);
  }
  *wholeData() {
    this.live();
    if (!this.file || !this.file.seekStart || !(yield* settled(this.file.seekStart()))) throw SwiftalkError.type(`${this.label}.data: not seekable — read it with .lines or .read(size)`);
    this.buffer = new Uint8Array(0);
    const parts = [];
    while (yield* this.fill()) { parts.push(this.buffer); this.buffer = new Uint8Array(0); }
    const total = parts.reduce((n, p) => n + p.length, 0);
    const out = new Uint8Array(total);
    let at = 0;
    for (const p of parts) { out.set(p, at); at += p.length; }
    return new SData(out);
  }
  // ---- writing ----
  *writeAll(bytes, call) {
    this.live();
    if (this.standardName === 'stdout' && !this.file) { current().output(decoder.decode(bytes)); return BigInt(bytes.length); }
    if (this.standardName === 'stderr' && !this.file) { current().errorOutput(decoder.decode(bytes)); return BigInt(bytes.length); }
    if (!this.file || !this.file.write) throw SwiftalkError.type(`${this.label}.${call}: not writable`);
    yield* settled(this.file.write(bytes));
    return BigInt(bytes.length);
  }
  *setMember(name, value) {
    if (name !== 'data') return false;
    this.live();
    const content = this.bytesOf(value, 'data');
    if (!this.file || !this.file.seekStart || !(yield* settled(this.file.seekStart()))) throw SwiftalkError.type(`${this.label}.data: not seekable — write it with .write or .append`);
    if (this.file.truncate) yield* settled(this.file.truncate());
    this.buffer = new Uint8Array(0);
    yield* this.writeAll(content, 'data');
    return true;
  }
  *member(name, args, called) {
    const key = `${name}${called ? '()' : ''}`;
    switch (key) {
      case 'path': return this.path;
      case 'mode': return this.mode;
      case 'data': return yield* this.wholeData();
      case 'lines': return new SequenceObject({ kind: 'native', element: ann('String'), make: () => () => this.readLine() });
      case 'read()': {
        let size = 65536;
        if (args.length) {
          if (args.length !== 1 || typeof args[0] !== 'bigint' || args[0] <= 0n) throw SwiftalkError.type(`${this.label}.read(size) takes one positive Int`);
          size = Number(args[0]);
        }
        return new SequenceObject({ kind: 'native', element: ann('Data'), make: () => () => this.readChunk(size) });
      }
      case 'readLine()':
        if (args.length) throw SwiftalkError.type(`${this.label}.readLine() takes no arguments`);
        return yield* this.readLine();
      case 'write()':
        if (args.length !== 1) throw SwiftalkError.type(`${this.label}.write(data) takes one Data or String`);
        return yield* this.writeAll(this.bytesOf(args[0], 'write'), 'write');
      case 'append()': {
        if (args.length !== 1) throw SwiftalkError.type(`${this.label}.append(data) takes one Data or String`);
        this.live();
        if (this.file && this.file.seekEnd) yield* settled(this.file.seekEnd());
        return yield* this.writeAll(this.bytesOf(args[0], 'append'), 'append');
      }
      case 'print()': {
        const parts = [];
        for (const a of args) parts.push(yield* displayString(a));
        yield* this.writeAll(encoder.encode(parts.join(' ') + '\n'), 'print');
        return null;
      }
      case 'close()':
        if (args.length) throw SwiftalkError.type(`${this.label}.close() takes no arguments`);
        if (!this.closed && this.file && this.file.close) yield* settled(this.file.close());
        this.closed = true;
        return null;
      case 'isClosed': return this.closed;
      default: return undefined;                               // declined
    }
  }
  isEqual(other) { return other === this; }
  hashKey() { return `IO:${this.path ?? this.standardName}:${this.mode}`; }
  sourceString() { return this.path !== null ? `IO(path: "${this.path}", mode: .${this.mode})` : this.label; }
}

export function IOModule() {
  const m = new Module('IO');
  let typeValue = null;
  const host = (h) => new HostValue(h, typeValue);
  typeValue = m.type('IO', function* (args) {
    if (!(args.length === 1 || args.length === 2) || typeof args[0] !== 'string') throw SwiftalkError.type('IO(path: String, mode: .read | .write | .append | .readWrite)');
    const path = args[0];
    let mode = 'read';
    if (args.length === 2) {
      if (typeof args[1] !== 'string') throw SwiftalkError.type(`IO(path:mode:) — mode is .read, .write, .append, or .readWrite, not ${typeName(args[1])}`);
      mode = args[1];
    }
    if (!['read', 'write', 'append', 'readWrite'].includes(mode)) throw SwiftalkError.type(`IO(path:mode:) — mode is .read, .write, .append, or .readWrite, not .${mode}`);
    const open = hook('openFile');
    if (!open) throw SwiftalkError.type(`IO(path: "${path}"): this host has no files (no "openFile" hook)`);
    let file;
    try { file = yield* settled(open(path, mode)); }
    catch (e) { throw e instanceof SwiftalkError ? e : SwiftalkError.type(`IO(path: "${path}", mode: .${mode}): ${e && e.message ? e.message : e}`); }
    return host(new Handle(file, path, mode));
  }).value('IO');
  const stdin = new Handle(null, null, 'read', 'stdin');
  m.static('IO', 'stdin', host(stdin));
  m.static('IO', 'stdout', host(new Handle(null, null, 'write', 'stdout')));
  m.static('IO', 'stderr', host(new Handle(null, null, 'write', 'stderr')));
  m.function('print', function* (args) {
    const parts = [];
    for (const a of args) parts.push(yield* displayString(a));
    current().output(parts.join(' ') + '\n');
    return null;
  });
  m.function('debugPrint', (args) => { current().errorOutput(args.map((a) => sourceString(a, true)).join(' ') + '\n'); return null; });
  m.function('readLine', function* (args) {
    if (args.length) throw SwiftalkError.type('readLine() takes no arguments');
    return yield* stdin.readLine();
  });
  return m;
}
