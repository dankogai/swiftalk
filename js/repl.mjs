#!/usr/bin/env node
// A REPL over the JavaScript runtime: `node js/repl.mjs`, or pipe a
// program in. The prelude modules are milestone D, so this is the bare
// core — `print` is supplied here, over console, so scripts can speak.
import { createInterface } from 'node:readline';
import { Interpreter, needsMoreInput } from './src/interpreter.js';
import { SwiftalkError } from './src/errors.js';
import { sourceString } from './src/value.js';

const interp = new Interpreter(true);
interp.declareBuiltin('print', (args) => { interp.output(args.map((a) => (typeof a === 'string' ? a : sourceString(a))).join(' ') + '\n'); return null; });
const tty = process.stdin.isTTY;
const rl = createInterface({ input: process.stdin, output: tty ? process.stdout : undefined, prompt: 'swiftalk> ', terminal: tty });
let buffer = '';
if (tty) rl.prompt();
rl.on('line', (line) => {
  if (!tty) process.stdout.write(`${buffer ? '      ... ' : 'swiftalk> '}${line}\n`);
  buffer = buffer ? `${buffer}\n${line}` : line;
  if (needsMoreInput(buffer)) { if (tty) { rl.setPrompt('      ... '); rl.prompt(); } return; }
  const source = buffer; buffer = '';
  if (source.trim() !== '') {
    try {
      const value = interp.eval(source);
      process.stdout.write(interp.sourceText(value) + '\n');
    } catch (e) {
      if (e instanceof SwiftalkError) process.stdout.write(e.description + '\n');
      else throw e;
    }
  }
  if (tty) { rl.setPrompt('swiftalk> '); rl.prompt(); }
});
rl.on('close', () => { if (tty) process.stdout.write('\n'); });
