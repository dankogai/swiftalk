// swiftalk in JavaScript — the core runtime. Milestone A (round 197):
// lexer, parser, and the value model; the evaluator follows.
export { SwiftalkError } from './errors.js';
export { Lexer } from './lexer.js';
export { Parser, TypeAnnotation, parse } from './parser.js';
export * from './value.js';
