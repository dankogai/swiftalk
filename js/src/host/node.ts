// What Node lends an Interpreter: stdout and stderr, a synchronous
// readLine over fd 0, files through node:fs for `IO(path:)`, `.swt`
// modules from disk (or fetched, for a URL), and the platform fetch.
import { openSync, readSync, writeSync, closeSync, ftruncateSync, fstatSync, readFileSync } from 'node:fs';
import type { Interpreter } from '../interpreter.js';

/// What `IO(path:)` opens through the host's `openFile` hook: positioned reads and writes over a descriptor.
export interface HostFile {
  read(size: number): Uint8Array | null;
  write(bytes: Uint8Array): number;
  seekStart(): boolean;
  seekEnd(): boolean;
  truncate(): void;
  close(): void;
}

function readLineSync(): string | null {
  const bytes: number[] = [];
  const one = Buffer.alloc(1);
  for (;;) {
    let n: number;
    try { n = readSync(0, one, 0, 1, null); } catch (e: any) { if (e.code === 'EAGAIN') continue; if (e.code === 'EOF') n = 0; else throw e; }
    if (n === 0) return bytes.length ? Buffer.from(bytes).toString('utf8') : null;
    if (one[0] === 10) { if (bytes.length && bytes[bytes.length - 1] === 13) bytes.pop(); return Buffer.from(bytes).toString('utf8'); }
    bytes.push(one[0]);
  }
}
function openFile(path: string, mode: string): HostFile {
  const flags = ({ read: 'r', write: 'w+', append: 'a+', readWrite: mode === 'readWrite' ? 'r+' : 'r' } as Record<string, string>)[mode];
  let fd: number;
  try { fd = openSync(path, mode === 'readWrite' ? (existsOrCreate(path) ? 'r+' : 'w+') : flags); }
  catch (e: any) { throw new Error(e.code === 'ENOENT' ? 'No such file or directory' : e.message); }
  let position = mode === 'append' ? fstatSync(fd).size : 0;
  return {
    read(size: number) { const buf = Buffer.alloc(size); const n = readSync(fd, buf, 0, size, position); position += n; return n ? new Uint8Array(buf.subarray(0, n)) : null; },
    write(bytes: Uint8Array) { if (mode === 'read') throw new Error('opened .read — not writable'); const n = writeSync(fd, bytes, 0, bytes.length, mode === 'append' ? null : position); position += n; return n; },
    seekStart() { position = 0; return true; },
    seekEnd() { position = fstatSync(fd).size; return true; },
    truncate() { ftruncateSync(fd, 0); position = 0; },
    close() { closeSync(fd); },
  };
}
function existsOrCreate(path: string): boolean { try { closeSync(openSync(path, 'r')); return true; } catch (e) { return false; } }

export function nodeHost(interp: Interpreter): Interpreter {
  interp.output = (s) => process.stdout.write(s);
  interp.errorOutput = (s) => process.stderr.write(s);
  interp.hooks.set('readLine', () => readLineSync());
  interp.hooks.set('openFile', openFile);
  interp.moduleLoader = (spec: string) => (/^https?:\/\//.test(spec) ? fetch(spec).then((r) => { if (!r.ok) throw new Error(`${spec}: HTTP ${r.status}`); return r.text(); }) : readFileSync(spec, 'utf8'));
  return interp;
}
