#!/usr/bin/env node
// A REPL over the JavaScript runtime: `node js/repl.mjs`, or pipe a
// program in. The prelude — IO, Net, Regex, Sequence, Task — is
// preimported, as the Swift CLI's is; Node lends stdin, stdout, files.
import { createInterface } from 'node:readline';
import { Interpreter, needsMoreInput } from './src/interpreter.js';
import { SwiftalkError } from './src/errors.js';
import { withPrelude } from './src/prelude.js';
import { nodeHost } from './src/host/node.js';

const interp = withPrelude(nodeHost(new Interpreter(true)));
const tty = process.stdin.isTTY;
const rl = createInterface({ input: process.stdin, output: tty ? process.stdout : undefined, prompt: 'swiftalk> ', terminal: tty });
let buffer = '';
if (tty) rl.prompt();
// lines are evaluated one program at a time, in order — an eval may await
let chain = Promise.resolve();
rl.on('line', (line) => {
  chain = chain.then(async () => {
    if (!tty) process.stdout.write(`${buffer ? '      ... ' : 'swiftalk> '}${line}\n`);
    buffer = buffer ? `${buffer}\n${line}` : line;
    if (needsMoreInput(buffer)) { if (tty) { rl.setPrompt('      ... '); rl.prompt(); } return; }
    const source = buffer; buffer = '';
    if (source.trim() !== '') {
      try {
        const value = await interp.evalAsync(source);
        process.stdout.write(interp.sourceText(value) + '\n');
      } catch (e) {
        if (e instanceof SwiftalkError) process.stdout.write(e.description + '\n');
        else throw e;
      }
    }
    if (tty) { rl.setPrompt('swiftalk> '); rl.prompt(); }
  });
});
rl.on('close', () => { if (tty) process.stdout.write('\n'); });
