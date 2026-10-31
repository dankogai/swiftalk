// swiftalk in TypeScript — the core runtime. Milestone A (round 197):
// lexer, parser, and the value model; milestone B (round 198): the
// generator-based evaluator behind `Swiftalk.eval` and `Interpreter`;
// TypeScript since round 255, the types below the public surface too.
export { SwiftalkError } from './errors.js';
export type { ErrorKind } from './errors.js';
export { Lexer } from './lexer.js';
export type { Token, Segment } from './lexer.js';
export { Parser, TypeAnnotation, parse } from './parser.js';
export type { Expr, Stmt, Pattern, LValue, Condition, CasePattern, FunctionExpr, Arg } from './parser.js';
export * from './value.js';
export { FunctionObject, EnumType, EnumCaseValue, StructType, StructValue, SequenceObject, TaskObject, HostValue } from './objects.js';
export type { Role, Builtin, HostObject, SequenceKind, Request, Answer, G, RunResult } from './objects.js';
export { isGenerator, isPromise, isRunResult } from './objects.js';
export { Environment, Binding } from './env.js';
export { Builtins, success, failure, isResult } from './builtins.js';
export { Interpreter, Swiftalk, needsMoreInput, HookTable } from './interpreter.js';
export type { Hook, Hooks, HookName, HostFile } from './interpreter.js';
export { Module, ModuleSystem } from './modules.js';
export type { Extension } from './modules.js';
export { TaskModule } from './modules/Task.js';
export { SequenceModule } from './modules/Sequence.js';
export { IOModule } from './modules/IO.js';
export { NetModule } from './modules/Net.js';
export { RegexModule, RegexValue } from './modules/Regex.js';
export { BigIntModule, BigIntValue } from './modules/BigInt.js';
export { BigRatModule, BigRatValue } from './modules/BigRat.js';
export { preludeModules, preludeNames, withPrelude } from './prelude.js';
