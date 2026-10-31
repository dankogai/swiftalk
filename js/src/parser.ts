// The parser — a line-for-line port of Core/Sources/Swiftalk/Parser.swift.
// AST nodes are plain objects tagged by `k`; dictionaries of members are
// Maps (member names are arbitrary). Literal values are the runtime's
// own representation: BigInt for Int, number for Double, string, boolean,
// null for nil (see value.js).
import { SwiftalkError } from './errors.js';
import { keywords } from './keywords.js';
import { Lexer, isPunct, isOp, isIdent, isNewline, tokEq, tokDescribe, tok } from './lexer.js';
import type { Token, MaybeToken } from './lexer.js';
import type { Value } from './value.js';

export class TypeAnnotation {
  name: string;
  optional: boolean;
  parameters: TypeAnnotation[];
  constructor(name: string, optional = false, parameters: TypeAnnotation[] = []) {
    this.name = name;
    this.optional = optional;
    this.parameters = parameters;
  }
  get display(): string {
    let base: string;
    if (this.name === 'Array' && this.parameters.length === 1) base = `[${this.parameters[0].display}]`;
    else if (this.name === 'Dictionary' && this.parameters.length === 2) base = `[${this.parameters[0].display}: ${this.parameters[1].display}]`;
    else if (this.parameters.length === 0) base = this.name;
    else base = this.name + '<' + this.parameters.map((p) => p.display).join(', ') + '>';
    return this.optional ? base + '?' : base;
  }
  equals(other: unknown): boolean {
    return other instanceof TypeAnnotation && this.name === other.name && this.optional === other.optional
      && this.parameters.length === other.parameters.length
      && this.parameters.every((p, i) => p.equals(other.parameters[i]));
  }
  static make(name: string, parameters: TypeAnnotation[], optional: boolean): TypeAnnotation {
    if (name !== 'Optional') return new TypeAnnotation(name, optional, parameters);
    if (parameters.length !== 1) throw SwiftalkError.syntax('Optional<T> takes exactly one type — or write T?');
    return new TypeAnnotation(parameters[0].name, true, parameters[0].parameters);
  }
}

export const infixOperators = new Set(['+', '-', '*', '/', '%', '**', '==', '!=', '<', '<=', '>', '>=', '|', '&', '^', '+&', '+|', '+^', '+<', '+>']);
export const prefixOperators = new Set(['-', '+', '!', '+^']);
export const postfixOperators = new Set(['!', '?']);
export const functionOperators = new Set([
  '**', '==', '!=', '===', '!==', '<', '<=', '>', '>=', '&&', '||', '^^', '??', '!!', '|', '&', '^', '!',
  '+&', '+|', '+^', '+<', '+>']);
// ---- the AST (Parser.swift's Expr, Statement, Pattern…) as tagged objects ----
/// A call argument, or a tuple literal's element: `label: expr`.
export type Arg = { label: string | null; expr: Expr };
/// A binding pattern — `let (a, b) = t` (round 71), labeled by `(x: a)` (round 75).
export type Pattern = { k: 'name'; name: string } | { k: 'tuple'; elements: { label: string | null; pattern: Pattern }[] };
/// An item of an `if`/`while` header (round 76): a Bool, a bare variable (round 80), or a binding.
export type Condition =
  | { k: 'boolean'; expr: Expr }
  | { k: 'variable'; name: string }
  | { k: 'binding'; mutable: boolean; pattern: Pattern; expr: Expr };
/// A `switch` case pattern: `_`, `.case`, `[let] pattern = .case | expression`, or an expression.
export type CasePattern =
  | { k: 'wildcard' }
  | { k: 'enumCase'; name: string }
  | { k: 'binding'; mutable: boolean; pattern: Pattern; source: { k: 'member'; name: string } | { k: 'expr'; e: Expr } }
  | { k: 'expr'; e: Expr };
export type CaseAlt = { pattern: CasePattern; condition: Expr | null };
export type Clause = { patterns: CaseAlt[]; body: Stmt[] };
export type FunctionExpr = { k: 'function'; parameters: string[]; body: Stmt[] };
/// A computed property: `var p[: T] { get set }` (observers are a Property's).
export type Computed = { annotation: TypeAnnotation | null; get: FunctionExpr; set: FunctionExpr | null };
export type Property = { mutable: boolean; annotation: TypeAnnotation | null; defaultExpr: Expr | null; willSetExpr: FunctionExpr | null; didSetExpr: FunctionExpr | null };
/// A type body's statics (round 143) and operator members (round 146), keyed `infix:+`.
export type Statics = { lets: Map<string, Expr>; vars: Map<string, Computed>; ops: Map<string, FunctionExpr> };
export type EnumCaseParam = { label: string | null; typeName: string };
/// An assignment target: a variable, a subscript, a property, or a tuple of them.
export type LValue =
  | { k: 'variable'; name: string }
  | { k: 'index'; base: LValue; index: Expr }
  | { k: 'property'; base: LValue; name: string }
  | { k: 'tuple'; elements: { label: string | null; target: LValue }[] };
/// A literal's value: the lexer's primitives, or — when the evaluator rewrites a node — any Value.
export type Literal = Value;
export type Expr =
  | { k: 'literal'; v: Literal }
  | { k: 'regexLiteral'; pattern: string; flags: string }
  | { k: 'bigintLiteral'; text: string }
  | { k: 'interpolation'; parts: Expr[] }
  | { k: 'variable'; name: string }
  | { k: 'memberLiteral'; name: string }
  | { k: 'tuple'; elements: Arg[] }
  | { k: 'array'; elements: Expr[] }
  | { k: 'dictionary'; pairs: [Expr, Expr][] }
  | FunctionExpr
  | { k: 'operatorRef'; op: string }
  | { k: 'typeSpelling'; annotation: TypeAnnotation }
  | { k: 'method'; receiver: Expr; name: string; args: Arg[]; called: boolean }
  | { k: 'optionalMember'; receiver: Expr; name: string; args: Arg[]; called: boolean }
  | { k: 'call'; callee: Expr; args: Arg[] }
  | { k: 'selfCall'; args: Arg[] }
  | { k: 'subscript'; base: Expr; index: Expr }
  | { k: 'propagate'; e: Expr }
  | { k: 'forceUnwrap'; e: Expr }
  | { k: 'unaryMinus'; e: Expr }
  | { k: 'unaryPlus'; e: Expr }
  | { k: 'bitNot'; e: Expr }
  | { k: 'logicalNot'; e: Expr }
  | { k: 'await'; e: Expr }
  | { k: 'power'; lhs: Expr; rhs: Expr }
  | { k: 'binary'; op: string; lhs: Expr; rhs: Expr }
  | { k: 'bitwise'; op: string; lhs: Expr; rhs: Expr }
  | { k: 'range'; op: string; lhs: Expr; rhs: Expr | null }
  | { k: 'comparison'; op: string; lhs: Expr; rhs: Expr }
  | { k: 'coalesce'; lhs: Expr; rhs: Expr }
  | { k: 'override'; lhs: Expr; rhs: Expr }
  | { k: 'logicalAnd'; lhs: Expr; rhs: Expr }
  | { k: 'logicalOr'; lhs: Expr; rhs: Expr }
  | { k: 'logicalXor'; lhs: Expr; rhs: Expr }
  | { k: 'ternary'; condition: Expr; a: Expr; b: Expr }
  | { k: 'if'; conditions: Condition[]; then: Stmt[]; else: Stmt[] | null }
  | { k: 'switch'; subject: Expr; clauses: Clause[]; defaultBody: Stmt[] | null };
export type Stmt =
  | { k: 'expression'; expr: Expr }
  | { k: 'declaration'; mutable: boolean; name: string; annotation: TypeAnnotation | null; initializer: Expr }
  | { k: 'destructure'; mutable: boolean; pattern: Pattern; initializer: Expr }
  | { k: 'assignment'; target: LValue; expr: Expr }
  | { k: 'compoundAssignment'; target: LValue; op: string; expr: Expr }
  | { k: 'while'; condition: Expr; body: Stmt[]; label: string | null }
  | { k: 'whileLet'; conditions: Condition[]; body: Stmt[]; label: string | null }
  | { k: 'repeat'; body: Stmt[]; condition: Expr; label: string | null }
  | { k: 'for'; pattern: Pattern; sequence: Expr; condition: Expr | null; body: Stmt[]; label: string | null }
  | { k: 'return'; expr: Expr | null }
  | { k: 'yield'; expr: Expr | null }
  | { k: 'break'; label: string | null }
  | { k: 'continue'; label: string | null }
  | { k: 'import'; namespace: string | null; names: string[]; spec: string }
  | { k: 'export'; names: string[]; declaration: Stmt | null }
  | { k: 'enumDecl'; name: string; caseOrder: string[]; cases: Map<string, EnumCaseParam[]>; methods: Map<string, FunctionExpr>; statics: Statics }
  | { k: 'structDecl'; name: string; propertyOrder: string[]; properties: Map<string, Property>; methods: Map<string, FunctionExpr>; inits: FunctionExpr[]; computed: Map<string, Computed>; statics: Statics }
  | { k: 'extensionDecl'; typeName: string; methods: Map<string, FunctionExpr>; computed: Map<string, Computed>; statics: Statics };

const compoundOps = new Set(['+=', '-=', '*=', '/=', '%=', '**=', '??=', '!!=', '&&=', '||=', '^^=', '&=', '|=', '^=', '+&=', '+|=', '+^=', '+<=', '+>=']);

const emptyStatics = (): Statics => ({ lets: new Map(), vars: new Map(), ops: new Map() });
const plainName = (n: string | undefined): n is string => n !== undefined && !keywords.has(n) && !n.startsWith('$');

export class Parser {
  tokens: Token[];
  pos: number;
  allowTrailing: boolean;
  loopLabels: string[];
  pendingLabel: string | null;
  constructor(tokens: Token[]) {
    this.tokens = tokens;
    this.pos = 0;
    this.allowTrailing = true;
    this.loopLabels = [];
    this.pendingLabel = null;
  }
  withTrailing<T>(allowed: boolean, body: () => T): T {
    const saved = this.allowTrailing;
    this.allowTrailing = allowed;
    try { return body(); } finally { this.allowTrailing = saved; }
  }
  get peek(): Token | undefined { return this.tokens[this.pos]; }
  peekAt(offset: number): Token | undefined { return this.tokens[this.pos + offset]; }
  advance(): Token | undefined { return this.pos < this.tokens.length ? this.tokens[this.pos++] : undefined; }
  expect(p: string): void {
    const k = this.advance();
    if (!isPunct(k, p)) throw SwiftalkError.syntax(`expected '${p}'`);
  }

  // MARK: statements

  parseProgram(): Stmt[] {
    const statements = this.parseStatements(null);
    if (statements.length === 0) throw SwiftalkError.syntax('empty program');
    return statements;
  }
  parseStatements(closing: string | null): Stmt[] {
    return this.parseStatementsUntil((k: MaybeToken) => closing !== null && isPunct(k, closing));
  }
  parseStatementsUntil(stop: (k: MaybeToken) => boolean): Stmt[] {
    const statements: Stmt[] = [];
    this.skipSeparators();
    while (this.pos < this.tokens.length && !stop(this.peek)) {
      statements.push(this.parseStatement());
      const atEnd = this.pos === this.tokens.length || stop(this.peek);
      if (!(atEnd || this.consumeSeparator())) throw SwiftalkError.syntax("expected a newline or ';' between statements");
      this.skipSeparators();
    }
    return statements;
  }
  consumeSeparator(): boolean {
    if (isNewline(this.peek) || isPunct(this.peek, ';')) { this.pos++; return true; }
    return false;
  }
  skipSeparators() { while (this.consumeSeparator()) {} }

  parseStatement(): Stmt {
    const k = this.peek;
    if (isIdent(k) && plainName(k.v) && this.pos + 2 < this.tokens.length && isPunct(this.tokens[this.pos + 1], ':')
        && ['for', 'while', 'repeat'].some((w) => isIdent(this.tokens[this.pos + 2], w))) {
      if (this.loopLabels.includes(k.v)) throw SwiftalkError.syntax(`loop label '${k.v}' is already in use by an enclosing loop`);
      this.pos += 2;
      this.pendingLabel = k.v;
    }
    const p = this.peek;
    if (isIdent(p, 'let') || isIdent(p, 'var')) return this.parseDeclaration();
    if (isIdent(p, 'static') && this.isStaticDeclaration()) {
      // `static let T.s = v`, `static var T.g { ... }` (round 228): a static added to T without an extension body.
      this.pos++;
      const keyword = (this.advance() as { v: string }).v;
      const typeTok = this.advance();
      if (!isIdent(typeTok) || !plainName(typeTok.v)) throw SwiftalkError.syntax(`expected a name after 'static ${keyword}'`);
      if (!isPunct(this.peek, '.')) throw SwiftalkError.syntax(`'static' belongs in a type body — or names the type: static ${keyword} Type.${typeTok.v} ...`);
      return this.parseMemberDeclaration(keyword, typeTok.v, true);
    }
    if (isIdent(p, 'import')) {
      this.pos++;
      let namespace: string | null = null;
      const names: string[] = [];
      if (isIdent(this.peek, 'from')) {
        // every export, by its own name
      } else if (isPunct(this.peek, '(')) {
        this.pos++;
        do {
          const n = this.advance();
          if (!isIdent(n) || !plainName(n.v)) throw SwiftalkError.syntax('import (a, b) from "..." — names in parentheses');
          names.push(n.v);
        } while (this.consumeComma(')'));
        this.expect(')');
      } else {
        const n = this.advance();
        if (!isIdent(n) || !plainName(n.v)) throw SwiftalkError.syntax('import from "./mod.swt", import M from "./mod.swt", or import (a, b) from "./mod.swt"');
        namespace = n.v;
      }
      if (!isIdent(this.advance(), 'from')) throw SwiftalkError.syntax('import needs \'from\': import M from "./mod.swt"');
      const spec = this.advance();
      if (!spec || spec.t !== 'string') throw SwiftalkError.syntax('import ... from takes a String — a path or a URL');
      return { k: 'import', namespace, names, spec: spec.v };
    }
    if (isIdent(p, 'export')) {
      this.pos++;
      if (isPunct(this.peek, '(')) {
        this.pos++;
        const names: string[] = [];
        do {
          const n = this.advance();
          if (!isIdent(n) || !plainName(n.v)) throw SwiftalkError.syntax('export (a, b) — names in parentheses');
          names.push(n.v);
        } while (this.consumeComma(')'));
        this.expect(')');
        return { k: 'export', names, declaration: null };
      }
      const declaration = this.parseStatement();
      let names: string[];
      switch (declaration.k) {
        case 'declaration': names = [declaration.name]; break;
        case 'destructure': names = Parser.namesIn(declaration.pattern); break;
        case 'structDecl': case 'enumDecl': names = [declaration.name]; break;
        default: throw SwiftalkError.syntax('export takes a let/var/struct/enum declaration, or export (a, b)');
      }
      return { k: 'export', names, declaration };
    }
    if (isIdent(p, 'while')) {
      this.pos++;
      const label = this.takeLabel();
      const conditions = this.parseConditionList();
      const body = this.parseLoopBody(label);
      if (conditions.length === 1 && conditions[0].k === 'boolean') return { k: 'while', condition: conditions[0].expr, body, label };
      return { k: 'whileLet', conditions, body, label };
    }
    if (isIdent(p, 'repeat')) {
      this.pos++;
      const label = this.takeLabel();
      const body = this.parseLoopBody(label);
      if (!isIdent(this.advance(), 'while')) throw SwiftalkError.syntax("expected 'while' after the repeat block");
      return { k: 'repeat', body, condition: this.withTrailing(false, () => this.parseExpr()), label };
    }
    if (isIdent(p, 'for')) {
      this.pos++;
      const label = this.takeLabel();
      const patterns = [this.parseBindPattern()];
      while (isPunct(this.peek, ',')) { this.pos++; patterns.push(this.parseBindPattern()); }
      const pattern: Pattern = patterns.length === 1 ? patterns[0] : { k: 'tuple', elements: patterns.map((pt) => ({ label: null, pattern: pt })) };
      const seen = new Set();
      for (const name of Parser.namesIn(pattern)) {
        if (seen.has(name)) throw SwiftalkError.syntax(`'${name}' appears twice in the loop pattern`);
        seen.add(name);
      }
      if (!isIdent(this.advance(), 'in')) throw SwiftalkError.syntax("expected 'in' after the loop variable");
      const sequence = this.withTrailing(false, () => this.parseExpr());
      let condition: Expr | null = null;
      if (isIdent(this.peek, 'where')) {
        this.pos++;
        condition = this.withTrailing(false, () => this.parseWordOr(() => this.parseDisjunction()));
      }
      return { k: 'for', pattern, sequence, condition, body: this.parseLoopBody(label), label };
    }
    if (isIdent(p, 'enum')) return this.parseEnum();
    if (isIdent(p, 'struct')) return this.parseStruct('struct');
    if (isIdent(p, 'extension')) return this.parseExtension();
    if (isIdent(p, 'return')) {
      this.pos++;
      const n = this.peek;
      if (n === undefined || isNewline(n) || isPunct(n, ';') || isPunct(n, '}')) return { k: 'return', expr: null };
      return { k: 'return', expr: this.parseExpr() };
    }
    if (isIdent(p, 'yield')) {
      this.pos++;
      const n = this.peek;
      if (n === undefined || isNewline(n) || isPunct(n, ';') || isPunct(n, '}')) return { k: 'yield', expr: null };
      return { k: 'yield', expr: this.parseExpr() };
    }
    if (isIdent(p, 'break')) { this.pos++; return { k: 'break', label: this.parseLoopLabel('break') }; }
    if (isIdent(p, 'continue')) { this.pos++; return { k: 'continue', label: this.parseLoopLabel('continue') }; }
    const expr = this.parseExpr();
    if (isOp(this.peek) && compoundOps.has(this.peek.v)) {
      const o = this.peek.v;
      this.pos++;
      return { k: 'compoundAssignment', target: this.lvalue(expr), op: o.slice(0, -1), expr: this.parseExpr() };
    }
    if (!isPunct(this.peek, '=')) return { k: 'expression', expr };
    this.pos++;
    return { k: 'assignment', target: this.lvalue(expr), expr: this.parseExpr() };
  }

  takeLabel(): string | null { const l = this.pendingLabel; this.pendingLabel = null; return l; }
  parseLoopBody(label: string | null): Stmt[] {
    if (label) this.loopLabels.push(label);
    try { return this.parseBlock(); } finally { if (label) this.loopLabels.pop(); }
  }
  parseLoopLabel(keyword: string): string | null {
    const k = this.peek;
    if (!isIdent(k) || !plainName(k.v)) return null;
    if (!this.loopLabels.includes(k.v)) {
      throw SwiftalkError.syntax(`'${keyword} ${k.v}': no enclosing loop is labeled '${k.v}'`
        + (this.loopLabels.length ? ` — in scope: ${this.loopLabels.join(', ')}` : ''));
    }
    this.pos++;
    return k.v;
  }
  parseInterpolatedExpr(): Expr {
    const expr = this.parseExpr();
    if (this.pos !== this.tokens.length) throw SwiftalkError.syntax("'\\(...)' takes a single expression");
    return expr;
  }

  parseConditionList(): Condition[] {
    const conditions: Condition[] = [];
    for (;;) {
      const head = this.parseBindingHead();
      if (head) {
        let expr: Expr;
        if (isPunct(this.peek, '=')) {
          this.pos++;
          expr = this.withTrailing(false, () => this.parseExpr());
        } else if (head.pattern.k === 'name' && head.pattern.name !== '_') {
          expr = { k: 'variable', name: head.pattern.name };
        } else {
          throw SwiftalkError.syntax("expected '=' after the pattern");
        }
        conditions.push({ k: 'binding', mutable: head.mutable, pattern: head.pattern, expr });
      } else {
        const expr = this.withTrailing(false, () => this.parseExpr());
        if (expr.k === 'variable' && !expr.name.startsWith('$')) conditions.push({ k: 'variable', name: expr.name });
        else conditions.push({ k: 'boolean', expr });
      }
      if (!isPunct(this.peek, ',')) break;
      this.pos++;
    }
    return conditions;
  }
  parseBindingHead(): { mutable: boolean; pattern: Pattern } | null {
    if (isIdent(this.peek, 'let') || isIdent(this.peek, 'var')) {
      const mutable = isIdent(this.peek, 'var');
      this.pos++;
      return { mutable, pattern: this.parseBindPattern() };
    }
    const start = this.pos;
    try {
      const pattern = this.parseBindPattern();
      if (isPunct(this.peek, '=')) return { mutable: false, pattern };
    } catch (e) { if (!(e instanceof SwiftalkError)) throw e; }
    this.pos = start;
    return null;
  }
  parseIf(): Expr {
    if (isIdent(this.peek, 'case')) throw SwiftalkError.syntax("'if case' is not swiftalk — write if let r = s.circle (or if r = s.circle)");
    const conditions = this.parseConditionList();
    const then = this.withTrailing(true, () => this.parseBlock());
    const elseBranch = this.parseElse();
    return { k: 'if', conditions, then, else: elseBranch };
  }
  parseElse(): Stmt[] | null {
    const saved = this.pos;
    this.skipSeparators();
    if (!isIdent(this.peek, 'else')) { this.pos = saved; return null; }
    this.pos++;
    if (isIdent(this.peek, 'if')) { this.pos++; return [{ k: 'expression', expr: this.parseIf() }]; }
    return this.withTrailing(true, () => this.parseBlock());
  }

  parseEnum(): Stmt {
    this.pos++;
    const nameTok = this.advance();
    if (!isIdent(nameTok) || !plainName(nameTok.v)) throw SwiftalkError.syntax("expected a name after 'enum'");
    const name = nameTok.v;
    this.expect('{');
    const caseOrder: string[] = [];
    const cases = new Map<string, EnumCaseParam[]>();
    const methods = new Map<string, FunctionExpr>();
    const statics = emptyStatics();
    const between = (what: string) => {
      if (!(isPunct(this.peek, '}') || this.consumeSeparator())) throw SwiftalkError.syntax(`expected a newline between ${what}`);
      this.skipSeparators();
    };
    this.skipSeparators();
    while (!isPunct(this.peek, '}')) {
      if (this.isOperatorMember()) { this.parseOperatorMember(statics); between('enum members'); continue; }
      if (isIdent(this.peek, 'static')) { this.parseStatic(statics, (n) => cases.has(n)); between('enum members'); continue; }
      if (isIdent(this.peek, 'let')) {
        const [methodName, fn] = this.parseMethod((n) => cases.has(n) || methods.has(n));
        methods.set(methodName, fn);
        between('enum members');
        continue;
      }
      if (!isIdent(this.advance(), 'case')) throw SwiftalkError.syntax("expected 'case' or a 'let' method in an enum body");
      do {
        const c = this.advance();
        if (!isIdent(c) || keywords.has(c.v)) throw SwiftalkError.syntax('expected a case name');
        if (cases.has(c.v)) throw SwiftalkError.syntax(`duplicate case '${c.v}'`);
        const params: EnumCaseParam[] = [];
        if (isPunct(this.peek, '(')) {
          this.pos++;
          do {
            const first = this.advance();
            if (!isIdent(first)) throw SwiftalkError.syntax('expected an associated-value type');
            if (isPunct(this.peek, ':')) {
              this.pos++;
              const typeName = this.advance();
              if (!isIdent(typeName)) throw SwiftalkError.syntax("expected a type after ':'");
              params.push({ label: first.v, typeName: typeName.v });
            } else {
              params.push({ label: null, typeName: first.v });
            }
          } while (this.consumeComma(')'));
          this.expect(')');
        }
        caseOrder.push(c.v);
        cases.set(c.v, params);
      } while (this.consumeComma('}'));
      between('enum cases');
    }
    this.expect('}');
    return { k: 'enumDecl', name, caseOrder, cases, methods, statics };
  }

  parseMethod(existing: (name: string) => boolean): [string, FunctionExpr] {
    this.pos++;
    const nameTok = this.advance();
    if (!isIdent(nameTok) || !plainName(nameTok.v)) throw SwiftalkError.syntax("expected a method name after 'let'");
    if (existing(nameTok.v)) throw SwiftalkError.syntax(`duplicate member '${nameTok.v}'`);
    return [nameTok.v, this.parseMethodBody(`a type-body 'let' holds a method: let ${nameTok.v} = { ... }`)];
  }

  /// The `= { ... }` of a method, after its name: a closure literal, or the syntax error `message`.
  parseMethodBody(message: string): FunctionExpr {
    this.expect('=');
    const fn = this.parseExpr();
    if (fn.k !== 'function') throw SwiftalkError.syntax(message);
    return fn;
  }

  /// `[: Type] { ... }` of a computed property, after its name: the optional annotation, then getter and setter.
  parseComputedMember(): Computed {
    let annotation: TypeAnnotation | null = null;
    if (isPunct(this.peek, ':')) { this.pos++; annotation = this.parseTypeAnnotation(); }
    this.expect('{');
    const { get, set } = this.parseComputedBody();
    return { annotation, get, set };
  }

  /// `let T.m = { ... }`, `var T.p [: Type] { ... }`, `static let T.s = value`, `static var T.g { ... }`
  /// (round 228) — one member added to the type T without an `extension T { }` around it. The keyword
  /// and the type name are consumed; the dot is next. The result is the extensionDecl a one-member
  /// body would give, so the rules are an extension's.
  parseMemberDeclaration(keyword: string, typeName: string, isStatic: boolean): Stmt {
    this.pos++;  // the dot
    const spelled = (isStatic ? 'static ' : '') + keyword;
    const nameTok = this.advance();
    if (!isIdent(nameTok) || !plainName(nameTok.v)) throw SwiftalkError.syntax(`expected a member name after '${spelled} ${typeName}.'`);
    const name = nameTok.v;
    if (isPunct(this.peek, '.')) throw SwiftalkError.syntax(`${spelled} Type.name takes one dot — '${typeName}.${name}' is not a type name`);
    const methods = new Map<string, FunctionExpr>();
    const computed = new Map<string, Computed>();
    const statics = emptyStatics();
    if (isStatic) this.parseStaticMember(keyword, name, statics);
    else if (keyword === 'var') computed.set(name, this.parseComputedMember());
    else methods.set(name, this.parseMethodBody(`let ${typeName}.${name} = { ... } adds a method — a closure; var ${typeName}.${name} { ... } a computed property`));
    return { k: 'extensionDecl', typeName, methods, computed, statics };
  }

  /// `static let`/`static var` followed by a name: the statement form of round 228, as against `static` the identifier.
  isStaticDeclaration(): boolean {
    const kw = this.tokens[this.pos + 1];
    const name = this.tokens[this.pos + 2];
    return (isIdent(kw, 'let') || isIdent(kw, 'var')) && isIdent(name);
  }

  parseStruct(kind: string): Stmt {
    this.pos++;
    const nameTok = this.advance();
    if (!isIdent(nameTok) || !plainName(nameTok.v)) throw SwiftalkError.syntax(`expected a name after '${kind}'`);
    const name = nameTok.v;
    this.expect('{');
    const propertyOrder: string[] = [];
    const properties = new Map<string, Property>();
    const methods = new Map<string, FunctionExpr>();
    const inits: FunctionExpr[] = [];
    const computed = new Map<string, Computed>();
    const statics = emptyStatics();
    const between = (what: string) => {
      if (!(isPunct(this.peek, '}') || this.consumeSeparator())) throw SwiftalkError.syntax(`expected a newline between ${what}`);
      this.skipSeparators();
    };
    this.skipSeparators();
    while (!isPunct(this.peek, '}')) {
      if (this.isOperatorMember()) { this.parseOperatorMember(statics); between(`${kind} members`); continue; }
      if (isIdent(this.peek, 'static')) { this.parseStatic(statics, () => false); between(`${kind} members`); continue; }
      if (isIdent(this.peek, 'init')) {
        this.pos++;
        if (!isPunct(this.advance(), '{')) throw SwiftalkError.syntax("expected '{' after 'init'");
        inits.push(this.withTrailing(true, () => this.parseFunction()));
        between(`${kind} members`);
        continue;
      }
      const keywordTok = this.advance();
      if (!isIdent(keywordTok) || !(keywordTok.v === 'var' || keywordTok.v === 'let')) {
        throw SwiftalkError.syntax(`a ${kind} body holds 'var'/'let' properties, methods, and inits`);
      }
      const keyword = keywordTok.v;
      const propTok = this.advance();
      if (!isIdent(propTok) || !plainName(propTok.v)) throw SwiftalkError.syntax('expected a property name');
      const propName = propTok.v;
      if (properties.has(propName) || methods.has(propName) || computed.has(propName)) throw SwiftalkError.syntax(`duplicate member '${propName}'`);
      let annotation: TypeAnnotation | null = null;
      if (isPunct(this.peek, ':')) { this.pos++; annotation = this.parseTypeAnnotation(); }
      if (isPunct(this.peek, '{')) {
        if (keyword !== 'var') throw SwiftalkError.syntax("a computed property is declared 'var' — it computes, it is not constant storage");
        if (this.isObserverBlock(this.pos + 1)) {
          if (!annotation) throw SwiftalkError.syntax('an observed property needs a type annotation or a default value');
          this.pos++;
          const { will, did } = this.parseObserverBlock();
          propertyOrder.push(propName);
          properties.set(propName, { mutable: true, annotation, defaultExpr: null, willSetExpr: will, didSetExpr: did });
        } else {
          this.pos++;
          const { get, set } = this.parseComputedBody();
          computed.set(propName, { annotation, get, set });
        }
        between(`${kind} members`);
        continue;
      }
      let defaultExpr: Expr | null = null;
      if (isPunct(this.peek, '=')) { this.pos++; defaultExpr = this.parseExpr(); }
      let observers: { will: FunctionExpr | null; did: FunctionExpr | null } | null = null;
      if (isPunct(this.peek, '{') && this.isObserverBlock(this.pos + 1)) {
        if (keyword !== 'var') throw SwiftalkError.syntax("only a 'var' property is observable");
        this.pos++;
        observers = this.parseObserverBlock();
      }
      if (keyword === 'let' && annotation === null && defaultExpr && defaultExpr.k === 'function') {
        methods.set(propName, defaultExpr);
      } else {
        if (annotation === null && defaultExpr === null) throw SwiftalkError.syntax(`property '${propName}' needs a type annotation or a default value`);
        propertyOrder.push(propName);
        properties.set(propName, { mutable: keyword === 'var', annotation, defaultExpr, willSetExpr: observers?.will ?? null, didSetExpr: observers?.did ?? null });
      }
      between('properties');
    }
    this.expect('}');
    return { k: 'structDecl', name, propertyOrder, properties, methods, inits, computed, statics };
  }

  isOperatorMember(): boolean {
    const k = this.peek;
    return isIdent(k) && ['infix', 'prefix', 'postfix'].includes(k.v) && isPunct(this.peekAt(1), '(');
  }
  parseOperatorMember(statics: Statics): void {
    const fixTok = this.advance();
    if (!isIdent(fixTok)) throw SwiftalkError.syntax('expected infix, prefix, or postfix');
    const fix = fixTok.v;
    this.expect('(');
    const opTok = this.advance();
    let op: string;
    if (isPunct(opTok) && '+-*/%'.includes(opTok.v)) op = opTok.v;
    else if (isOp(opTok)) op = opTok.v;
    else throw SwiftalkError.syntax(`expected an operator after '${fix}('`);
    this.expect(')');
    const allowed = fix === 'infix' ? infixOperators : fix === 'prefix' ? prefixOperators : postfixOperators;
    if (!allowed.has(op)) throw SwiftalkError.syntax(`'${op}' is not a ${fix} operator a type can implement — ${[...allowed].sort().join(' ')}`);
    const key = `${fix}:${op}`;
    if (statics.ops.has(key)) throw SwiftalkError.syntax(`duplicate operator ${fix}(${op})`);
    this.expect('=');
    const fn = this.parseExpr();
    if (fn.k !== 'function') throw SwiftalkError.syntax(`${fix}(${op}) = { ... } — an operator is a closure`);
    const arity = fix === 'infix' ? 2 : 1;
    if (fn.parameters.length !== 0 && fn.parameters.length !== arity) {
      throw SwiftalkError.syntax(`${fix}(${op}) takes ${arity} parameter${arity === 1 ? '' : 's'}: { ${fix === 'infix' ? 'lhs, rhs' : 'x'} in ... }`);
    }
    statics.ops.set(key, fn);
  }
  parseStatic(statics: Statics, existing: (name: string) => boolean): void {
    this.pos++;
    const kw = this.advance();
    if (!isIdent(kw) || !(kw.v === 'let' || kw.v === 'var')) throw SwiftalkError.syntax("'static' is followed by 'let name = value' or 'var name { ... }'");
    const nameTok = this.advance();
    if (!isIdent(nameTok) || !plainName(nameTok.v)) throw SwiftalkError.syntax(`expected a name after 'static ${kw.v}'`);
    const name = nameTok.v;
    if (existing(name) || statics.lets.has(name) || statics.vars.has(name)) throw SwiftalkError.syntax(`duplicate static member '${name}'`);
    this.parseStaticMember(kw.v, name, statics);
  }

  /// The rest of a static after `static let name` / `static var name`: `= value`, or `[: Type] { getter }` — no setter.
  parseStaticMember(keyword: string, name: string, statics: Statics): void {
    if (keyword === 'let') {
      this.expect('=');
      statics.lets.set(name, this.parseExpr());
      return;
    }
    let annotation: TypeAnnotation | null = null;
    if (isPunct(this.peek, ':')) { this.pos++; annotation = this.parseTypeAnnotation(); }
    if (!isPunct(this.advance(), '{')) throw SwiftalkError.syntax(`a static var computes: static var ${name} { ... } — a stored one is static let`);
    const { get, set } = this.parseComputedBody();
    if (set) throw SwiftalkError.syntax('a static var has no setter — a type is a value, not storage');
    statics.vars.set(name, { annotation, get, set: null });
  }

  parseTypeAnnotation(): TypeAnnotation {
    if (isPunct(this.peek, '[')) {
      this.pos++;
      const parameters = [this.parseTypeAnnotation()];
      let name = 'Array';
      if (isPunct(this.peek, ':')) { this.pos++; parameters.push(this.parseTypeAnnotation()); name = 'Dictionary'; }
      this.expect(']');
      let optional = false;
      if (isPunct(this.peek, '?') || isOp(this.peek, '?')) { this.pos++; optional = true; }
      return new TypeAnnotation(name, optional, parameters);
    }
    const t = this.advance();
    if (!isIdent(t) || keywords.has(t.v)) throw SwiftalkError.syntax("expected a type name after ':'");
    const parameters: TypeAnnotation[] = [];
    if (isOp(this.peek, '<')) {
      this.pos++;
      parameters.push(this.parseTypeAnnotation());
      while (isPunct(this.peek, ',')) { this.pos++; parameters.push(this.parseTypeAnnotation()); }
      if (!isOp(this.advance(), '>')) throw SwiftalkError.syntax(`expected '>' after the type parameters of ${t.v}`);
    }
    let optional = false;
    if (isPunct(this.peek, '?') || isOp(this.peek, '?')) { this.pos++; optional = true; }
    return TypeAnnotation.make(t.v, parameters, optional);
  }
  parseGenericArguments(): TypeAnnotation[] | null {
    const start = this.pos;
    if (!isOp(this.peek, '<')) return null;
    this.pos++;
    try {
      const parameters = [this.parseTypeAnnotation()];
      while (isPunct(this.peek, ',')) { this.pos++; parameters.push(this.parseTypeAnnotation()); }
      if (!isOp(this.advance(), '>')) { this.pos = start; return null; }
      const n = this.peek;
      if (n === undefined || isNewline(n)) return parameters;
      if (isPunct(n) && ')],.(?:;}'.includes(n.v)) return parameters;
      if (isOp(n) && ['==', '!=', '?.', '?', '!', '??', '&&', '||'].includes(n.v)) return parameters;
      this.pos = start;
      return null;
    } catch (e) {
      if (!(e instanceof SwiftalkError)) throw e;
      this.pos = start;
      return null;
    }
  }
  isObserverBlock(index: number): boolean {
    let i = index;
    while (isNewline(this.tokens[i])) i++;
    const w = this.tokens[i];
    if (!(isIdent(w, 'willSet') || isIdent(w, 'didSet'))) return false;
    const n = this.tokens[i + 1];
    return isPunct(n, '{') || isPunct(n, '(');
  }
  parseObserverBlock(): { will: FunctionExpr | null; did: FunctionExpr | null } {
    let will: FunctionExpr | null = null, did: FunctionExpr | null = null;
    this.skipSeparators();
    while (isIdent(this.peek, 'willSet') || isIdent(this.peek, 'didSet')) {
      const word = (this.advance() as { v: string }).v;
      let param = word === 'willSet' ? 'newValue' : 'oldValue';
      if (isPunct(this.peek, '(')) {
        this.pos++;
        const custom = this.advance();
        if (!isIdent(custom) || !plainName(custom.v)) throw SwiftalkError.syntax(`expected a parameter name in ${word}(...)`);
        param = custom.v;
        this.expect(')');
      }
      this.expect('{');
      const body = this.parseStatements('}');
      this.expect('}');
      const fn: FunctionExpr = { k: 'function', parameters: [param], body };
      if (word === 'willSet') { if (will) throw SwiftalkError.syntax("duplicate 'willSet'"); will = fn; }
      else { if (did) throw SwiftalkError.syntax("duplicate 'didSet'"); did = fn; }
      this.skipSeparators();
    }
    if (!will && !did) throw SwiftalkError.syntax('an observer block holds willSet and/or didSet');
    this.expect('}');
    return { will, did };
  }
  parseComputedBody(): { get: FunctionExpr; set: FunctionExpr | null } {
    this.skipSeparators();
    if (!(isIdent(this.peek, 'get') || isIdent(this.peek, 'set'))) {
      const body = this.parseStatements('}');
      this.expect('}');
      return { get: { k: 'function', parameters: [], body }, set: null };
    }
    let getBody: Stmt[] | null = null, setExpr: FunctionExpr | null = null;
    while (isIdent(this.peek, 'get') || isIdent(this.peek, 'set')) {
      if (isIdent(this.peek, 'get')) {
        if (getBody) throw SwiftalkError.syntax("duplicate 'get'");
        this.pos++;
        this.expect('{');
        getBody = this.parseStatements('}');
        this.expect('}');
      } else {
        if (setExpr) throw SwiftalkError.syntax("duplicate 'set'");
        this.pos++;
        let param = 'newValue';
        if (isPunct(this.peek, '(')) {
          this.pos++;
          const custom = this.advance();
          if (!isIdent(custom) || !plainName(custom.v)) throw SwiftalkError.syntax('expected a parameter name in set(...)');
          param = custom.v;
          this.expect(')');
        }
        this.expect('{');
        const body = this.parseStatements('}');
        this.expect('}');
        setExpr = { k: 'function', parameters: [param], body };
      }
      this.skipSeparators();
    }
    if (!getBody) throw SwiftalkError.syntax("a computed property needs a 'get'");
    this.expect('}');
    return { get: { k: 'function', parameters: [], body: getBody }, set: setExpr };
  }

  parseExtension(): Stmt {
    this.pos++;
    const t = this.advance();
    if (!isIdent(t) || !plainName(t.v)) throw SwiftalkError.syntax("expected a type name after 'extension'");
    this.expect('{');
    const methods = new Map<string, FunctionExpr>();
    const computed = new Map<string, Computed>();
    const statics = emptyStatics();
    const between = () => {
      if (!(isPunct(this.peek, '}') || this.consumeSeparator())) throw SwiftalkError.syntax('expected a newline between extension members');
      this.skipSeparators();
    };
    this.skipSeparators();
    while (!isPunct(this.peek, '}')) {
      if (this.isOperatorMember()) { this.parseOperatorMember(statics); between(); continue; }
      if (isIdent(this.peek, 'static')) { this.parseStatic(statics, () => false); between(); continue; }
      if (isIdent(this.peek, 'var')) {
        this.pos++;
        const p = this.advance();
        if (!isIdent(p) || !plainName(p.v)) throw SwiftalkError.syntax("expected a property name after 'var'");
        if (methods.has(p.v) || computed.has(p.v)) throw SwiftalkError.syntax(`duplicate member '${p.v}'`);
        computed.set(p.v, this.parseComputedMember());
      } else {
        if (!isIdent(this.peek, 'let')) {
          throw SwiftalkError.syntax("an extension body holds 'let' methods, 'var' computed properties, 'static' members, and infix/prefix/postix operators");
        }
        const [methodName, fn] = this.parseMethod((n) => methods.has(n) || computed.has(n));
        methods.set(methodName, fn);
      }
      between();
    }
    this.expect('}');
    return { k: 'extensionDecl', typeName: t.v, methods, computed, statics };
  }

  parseSwitch(): Expr {
    const subject = this.withTrailing(false, () => this.parseExpr());
    this.expect('{');
    const clauses: Clause[] = [];
    let defaultBody: Stmt[] | null = null;
    this.withTrailing(true, () => {
      this.skipSeparators();
      while (!isPunct(this.peek, '}')) {
        const k = this.advance();
        if (isIdent(k, 'case')) {
          const patterns = [this.parseCasePattern()];
          while (isPunct(this.peek, ',')) { this.pos++; patterns.push(this.parseCasePattern()); }
          this.expect(':');
          clauses.push({ patterns, body: this.parseCaseBody() });
        } else if (isIdent(k, 'default')) {
          if (defaultBody) throw SwiftalkError.syntax("duplicate 'default'");
          this.expect(':');
          defaultBody = this.parseCaseBody();
        } else {
          throw SwiftalkError.syntax("expected 'case' or 'default' in a switch body");
        }
      }
    });
    this.expect('}');
    return { k: 'switch', subject, clauses, defaultBody };
  }
  parseCaseBody(): Stmt[] {
    return this.parseStatementsUntil((k: MaybeToken) => isIdent(k, 'case') || isIdent(k, 'default') || isPunct(k, '}'));
  }
  parseCasePattern(): CaseAlt {
    const pattern = this.parsePattern();
    if (!isIdent(this.peek, 'where')) return { pattern, condition: null };
    this.pos++;
    const condition = this.withTrailing(false, () => this.parseWordOr(() => this.parseDisjunction()));
    return { pattern, condition };
  }
  parsePattern(): CasePattern {
    if (isIdent(this.peek, '_')) { this.pos++; return { k: 'wildcard' }; }
    if (isPunct(this.peek, '.')) {
      const name = this.parseCaseName();
      if (isPunct(this.peek, '(')) throw SwiftalkError.syntax(`case .${name}(let x) is not swiftalk — write case let x = .${name} (or case x = .${name})`);
      return { k: 'enumCase', name };
    }
    const explicit = isIdent(this.peek, 'let') || isIdent(this.peek, 'var');
    const head = this.parseBindingHead();
    if (head) {
      let pattern: Pattern = head.pattern;
      if (explicit && isPunct(this.peek, ',')) {
        const elements: { label: string | null; pattern: Pattern }[] = [{ label: null, pattern }];
        while (isPunct(this.peek, ',')) { this.pos++; elements.push({ label: null, pattern: this.parseBindPattern() }); }
        pattern = { k: 'tuple', elements };
      }
      this.expect('=');
      if (isPunct(this.peek, '.')) return { k: 'binding', mutable: head.mutable, pattern, source: { k: 'member', name: this.parseCaseName() } };
      return { k: 'binding', mutable: head.mutable, pattern, source: { k: 'expr', e: this.parseComparison() } };
    }
    return { k: 'expr', e: this.parseComparison() };
  }
  parseCaseName(): string {
    this.expect('.');
    const n = this.advance();
    if (!isIdent(n) || keywords.has(n.v)) throw SwiftalkError.syntax("expected a case name after '.'");
    return n.v;
  }
  parseBlock(): Stmt[] {
    this.expect('{');
    const body = this.parseStatements('}');
    this.expect('}');
    return body;
  }
  lvalue(expr: Expr): LValue {
    switch (expr.k) {
      case 'variable': return { k: 'variable', name: expr.name };
      case 'subscript': return { k: 'index', base: this.lvalue(expr.base), index: expr.index };
      case 'method':
        if (!expr.called && expr.args.length === 0) return { k: 'property', base: this.lvalue(expr.receiver), name: expr.name };
        break;
      case 'memberLiteral': return { k: 'property', base: { k: 'variable', name: 'self' }, name: expr.name };
      case 'tuple': return { k: 'tuple', elements: expr.elements.map((e) => ({ label: e.label, target: this.lvalue(e.expr) })) };
      default: break;
    }
    throw SwiftalkError.syntax('this expression is not assignable');
  }
  static namesIn(pattern: Pattern): string[] {
    if (pattern.k === 'name') return pattern.name === '_' ? [] : [pattern.name];
    return pattern.elements.flatMap((e) => Parser.namesIn(e.pattern));
  }
  parseBindPattern(): Pattern {
    const seen = new Set<string>();
    const parse = (): Pattern => {
      if (isPunct(this.peek, '(')) {
        this.pos++;
        const elements: { label: string | null; pattern: Pattern }[] = [];
        const labels = new Set<string>();
        do {
          let label: string | null = null;
          const l = this.peek;
          if (isIdent(l) && isPunct(this.peekAt(1), ':') && !keywords.has(l.v)) {
            this.pos += 2;
            if (labels.has(l.v)) throw SwiftalkError.syntax(`label '${l.v}' appears twice in the pattern`);
            labels.add(l.v);
            label = l.v;
          }
          elements.push({ label, pattern: parse() });
        } while (this.consumeComma(')'));
        this.expect(')');
        return { k: 'tuple', elements };
      }
      const n = this.advance();
      if (!isIdent(n) || !(n.v === '_' || plainName(n.v))) throw SwiftalkError.syntax("expected a name or '_' in the pattern");
      if (n.v !== '_') {
        if (seen.has(n.v)) throw SwiftalkError.syntax(`'${n.v}' appears twice in the pattern`);
        seen.add(n.v);
      }
      return { k: 'name', name: n.v };
    };
    return parse();
  }
  parseDeclaration(): Stmt {
    const keyword = (this.advance() as { v: string }).v;
    const mutable = keyword === 'var';
    if (isPunct(this.peek, '(')) {
      const pattern = this.parseBindPattern();
      if (isPunct(this.peek, ':')) throw SwiftalkError.syntax('a destructuring pattern takes no annotation — the names lock element by element');
      this.expect('=');
      return { k: 'destructure', mutable, pattern, initializer: this.parseExpr() };
    }
    const nameTok = this.advance();
    if (!isIdent(nameTok)) throw SwiftalkError.syntax(`expected a name after '${keyword}'`);
    const name = nameTok.v;
    if (keywords.has(name) || name.startsWith('$')) throw SwiftalkError.syntax(`'${name}' cannot be declared`);
    // `let T.m = { ... }` / `var T.p { ... }` (round 228): a member added to the type T, one at a time
    if (isPunct(this.peek, '.')) return this.parseMemberDeclaration(keyword, name, false);
    if (isPunct(this.peek, ',')) {
      const elements: { label: string | null; pattern: Pattern }[] = [{ label: null, pattern: { k: 'name', name } }];
      while (isPunct(this.peek, ',')) { this.pos++; elements.push({ label: null, pattern: this.parseBindPattern() }); }
      if (isPunct(this.peek, ':')) throw SwiftalkError.syntax('a destructuring pattern takes no annotation — the names lock element by element');
      this.expect('=');
      return { k: 'destructure', mutable, pattern: { k: 'tuple', elements }, initializer: this.parseExpr() };
    }
    let annotation: TypeAnnotation | null = null;
    if (isPunct(this.peek, ':')) { this.pos++; annotation = this.parseTypeAnnotation(); }
    this.expect('=');
    return { k: 'declaration', mutable, name, annotation, initializer: this.parseExpr() };
  }

  // MARK: expressions

  parseExpr(): Expr { return this.parseWordOr(() => this.parseTernary()); }
  parseWordOr(operand: () => Expr): Expr {
    let lhs: Expr = this.parseWordAnd(operand);
    for (;;) {
      if (isIdent(this.peek, 'or')) { this.pos++; lhs = { k: 'logicalOr', lhs, rhs: this.parseWordAnd(operand) }; }
      else if (isIdent(this.peek, 'xor')) { this.pos++; lhs = { k: 'logicalXor', lhs, rhs: this.parseWordAnd(operand) }; }
      else return lhs;
    }
  }
  parseWordAnd(operand: () => Expr): Expr {
    let lhs: Expr = this.parseWordNot(operand);
    while (isIdent(this.peek, 'and')) { this.pos++; lhs = { k: 'logicalAnd', lhs, rhs: this.parseWordNot(operand) }; }
    return lhs;
  }
  parseWordNot(operand: () => Expr): Expr {
    if (isIdent(this.peek, 'not')) { this.pos++; return { k: 'logicalNot', e: this.parseWordNot(operand) }; }
    return operand();
  }
  parseTernary(): Expr {
    const condition = this.parseDisjunction();
    if (!isPunct(this.peek, '?')) return condition;
    this.pos++;
    const a = this.parseExpr();
    this.expect(':');
    const b = this.parseTernary();
    return { k: 'ternary', condition, a, b };
  }
  parseDisjunction(): Expr {
    let lhs: Expr = this.parseXor();
    while (isOp(this.peek, '||')) { this.pos++; lhs = { k: 'logicalOr', lhs, rhs: this.parseXor() }; }
    return lhs;
  }
  parseXor(): Expr {
    let lhs: Expr = this.parseConjunction();
    while (isOp(this.peek, '^^')) { this.pos++; lhs = { k: 'logicalXor', lhs, rhs: this.parseConjunction() }; }
    return lhs;
  }
  parseConjunction(): Expr {
    let lhs: Expr = this.parseComparison();
    while (isOp(this.peek, '&&')) { this.pos++; lhs = { k: 'logicalAnd', lhs, rhs: this.parseComparison() }; }
    return lhs;
  }
  parseComparison(): Expr {
    const lhs = this.parseCoalescing();
    const k = this.peek;
    if (!isOp(k) || !['==', '!=', '===', '!==', '<', '<=', '>', '>='].includes(k.v)) return lhs;
    this.pos++;
    return { k: 'comparison', op: k.v, lhs, rhs: this.parseCoalescing() };
  }
  parseCoalescing(): Expr {
    const lhs = this.parseRange();
    const k = this.peek;
    if (!isOp(k) || !(k.v === '??' || k.v === '!!')) return lhs;
    this.pos++;
    return { k: k.v === '??' ? 'coalesce' : 'override', lhs, rhs: this.parseCoalescing() };
  }
  parseRange(): Expr {
    const lhs = this.parseAdditive();
    const k = this.peek;
    if (!isOp(k) || !(k.v === '...' || k.v === '..<')) return lhs;
    this.pos++;
    const n = this.peek;
    const boundless = n === undefined || isNewline(n) || (isPunct(n) && ')]},:;{'.includes(n.v));
    if (boundless) {
      if (k.v !== '...') throw SwiftalkError.syntax('a..< needs an upper bound — a... is the unbounded range');
      return { k: 'range', op: k.v, lhs, rhs: null };
    }
    return { k: 'range', op: k.v, lhs, rhs: this.parseAdditive() };
  }
  parseAdditive(): Expr {
    let lhs: Expr = this.parseMultiplicative();
    for (;;) {
      const k = this.peek;
      if (isPunct(k) && (k.v === '+' || k.v === '-')) { this.pos++; lhs = { k: 'binary', op: k.v, lhs, rhs: this.parseMultiplicative() }; }
      else if (isOp(k) && (k.v === '|' || k.v === '^')) { this.pos++; lhs = { k: 'binary', op: k.v, lhs, rhs: this.parseMultiplicative() }; }
      else if (isOp(k) && (k.v === '+|' || k.v === '+^')) { this.pos++; lhs = { k: 'bitwise', op: k.v, lhs, rhs: this.parseMultiplicative() }; }
      else return lhs;
    }
  }
  parseMultiplicative(): Expr {
    let lhs: Expr = this.parseUnary();
    for (;;) {
      const k = this.peek;
      if (isPunct(k) && (k.v === '*' || k.v === '/' || k.v === '%')) { this.pos++; lhs = { k: 'binary', op: k.v, lhs, rhs: this.parseUnary() }; }
      else if (isOp(k, '&')) { this.pos++; lhs = { k: 'binary', op: '&', lhs, rhs: this.parseUnary() }; }
      else if (isOp(k) && (k.v === '+&' || k.v === '+<' || k.v === '+>')) { this.pos++; lhs = { k: 'bitwise', op: k.v, lhs, rhs: this.parseUnary() }; }
      else return lhs;
    }
  }
  parseUnary(): Expr {
    if (isPunct(this.peek, '-')) { this.pos++; return { k: 'unaryMinus', e: this.parseUnary() }; }
    if (isPunct(this.peek, '+')) { this.pos++; return { k: 'unaryPlus', e: this.parseUnary() }; }
    if (isOp(this.peek, '+^')) { this.pos++; return { k: 'bitNot', e: this.parseUnary() }; }
    if (isOp(this.peek, '!')) { this.pos++; return { k: 'logicalNot', e: this.parseUnary() }; }
    if (isIdent(this.peek, 'await')) { this.pos++; return { k: 'await', e: this.parseUnary() }; }
    return this.parsePower();
  }
  parsePower(): Expr {
    const base = this.parsePostfix();
    if (!isOp(this.peek, '**')) return base;
    this.pos++;
    return { k: 'power', lhs: base, rhs: this.parseUnary() };
  }
  parsePostfix(): Expr {
    let expr: Expr = this.parsePrimary();
    loop: for (;;) {
      const k = this.peek;
      if (isPunct(k, '.')) {
        this.pos++;
        const m = this.advance();
        let name: string;
        if (isIdent(m)) name = m.v;
        else if (m && m.t === 'int' && m.v >= 0n) name = String(m.v);
        else throw SwiftalkError.syntax("expected member name after '.'");
        let args: Arg[] = [], called = false;
        if (isPunct(this.peek, '(')) { called = true; args = this.parseCallArguments(); }
        expr = { k: 'method', receiver: expr, name, args, called };
      } else if (isPunct(k, '(')) {
        const args = this.parseCallArguments();
        expr = (expr.k === 'variable' && expr.name === '$') ? { k: 'selfCall', args } : { k: 'call', callee: expr, args };
      } else if (isPunct(k, '[')) {
        this.pos++;
        const index = this.withTrailing(true, () => this.parseExpr());
        this.expect(']');
        expr = { k: 'subscript', base: expr, index };
      } else if (isPunct(k, '{') && this.allowTrailing) {
        if (this.isObserverBlock(this.pos + 1)) break loop;
        this.pos++;
        const closure = this.withTrailing(true, () => this.parseFunction());
        expr = Parser.attachTrailing(closure, expr);
        if (isPunct(this.peek, '{')) break loop;
      } else if (isOp(k, '?')) {
        this.pos++;
        expr = { k: 'propagate', e: expr };
      } else if (isOp(k, '!')) {
        this.pos++;
        expr = { k: 'forceUnwrap', e: expr };
      } else if (isOp(k, '<')) {
        if (expr.k !== 'variable') break loop;
        const parameters = this.parseGenericArguments();
        if (!parameters) break loop;
        expr = { k: 'typeSpelling', annotation: TypeAnnotation.make(expr.name, parameters, false) };
      } else if (isOp(k, '?.')) {
        this.pos++;
        const n = this.advance();
        if (!isIdent(n) || keywords.has(n.v)) throw SwiftalkError.syntax("expected a member name after '?.'");
        let args: Arg[] = [], called = false;
        if (isPunct(this.peek, '(')) { called = true; args = this.parseCallArguments(); }
        expr = { k: 'optionalMember', receiver: expr, name: n.v, args, called };
      } else break loop;
    }
    return expr;
  }
  static attachTrailing(closure: FunctionExpr, expr: Expr): Expr {
    switch (expr.k) {
      case 'method': return { k: 'method', receiver: expr.receiver, name: expr.name, args: [...expr.args, { label: null, expr: closure }], called: true };
      case 'call': return { k: 'call', callee: expr.callee, args: [...expr.args, { label: null, expr: closure }] };
      case 'selfCall': return { k: 'selfCall', args: [...expr.args, { label: null, expr: closure }] };
      default: return { k: 'call', callee: expr, args: [{ label: null, expr: closure }] };
    }
  }
  parseCallArguments(): Arg[] {
    this.expect('(');
    const args: Arg[] = [];
    this.withTrailing(true, () => {
      if (!isPunct(this.peek, ')')) {
        do {
          const l = this.peek;
          if (isIdent(l) && isPunct(this.peekAt(1), ':') && !['true', 'false', 'nil'].includes(l.v)) {
            if (l.v === '_') throw SwiftalkError.syntax("'_' is not an argument label");
            this.pos += 2;
            args.push({ label: l.v, expr: this.parseArgument() });
          } else {
            args.push({ label: null, expr: this.parseArgument() });
          }
        } while (this.consumeComma(')'));
      }
    });
    this.expect(')');
    return args;
  }
  parseArgument(): Expr {
    const op = this.bareOperator([tok.punct(','), tok.punct(')')]);
    if (op !== null) return { k: 'operatorRef', op };
    return this.parseExpr();
  }
  consumeComma(closing: string): boolean {
    if (!isPunct(this.peek, ',')) return false;
    this.pos++;
    return !isPunct(this.peek, closing);
  }
  bareOperator(closers: Token[]): string | null {
    const next = this.peekAt(1);
    if (next === undefined || !closers.some((c) => tokEq(c, next))) return null;
    const k = this.peek;
    let op: string;
    if (isPunct(k) && '+-*/%'.includes(k.v)) op = k.v;
    else if (isOp(k) && functionOperators.has(k.v)) op = k.v;
    else return null;
    this.pos++;
    return op;
  }
  parsePrimary(): Expr {
    const k = this.advance();
    if (k === undefined) throw SwiftalkError.syntax('unexpected token end of input');
    switch (k.t) {
      case 'int': return { k: 'literal', v: k.v };
      case 'double': return { k: 'literal', v: k.v };
      case 'string': return { k: 'literal', v: k.v };
      case 'regex': return { k: 'regexLiteral', pattern: k.pattern, flags: k.flags };
      case 'bigint': return { k: 'bigintLiteral', text: k.v };            // likewise `BigInt` in scope (round 201)
      case 'interpolated':
        return { k: 'interpolation', parts: k.segments.map((seg): Expr => {
          if ('literal' in seg) return { k: 'literal', v: seg.literal };
          const sub = new Parser(seg.tokens);
          return sub.parseInterpolatedExpr();
        }) };
      case 'identifier': {
        const name = k.v;
        if (name === 'true') return { k: 'literal', v: true };
        if (name === 'false') return { k: 'literal', v: false };
        if (name === 'nil') return { k: 'literal', v: null };
        if (name === 'async') {
          if (!isPunct(this.advance(), '{')) throw SwiftalkError.syntax("expected '{' after 'async' — async { ... } spawns a Task");
          const closure = this.withTrailing(true, () => this.parseFunction());
          return { k: 'call', callee: { k: 'variable', name: 'Task' }, args: [{ label: null, expr: closure }] };
        }
        if (name === 'switch') return this.parseSwitch();
        if (name === 'if') return this.parseIf();
        if (keywords.has(name)) throw SwiftalkError.syntax(`'${name}' is not an expression`);
        if (name.startsWith('$') && name.length > 1) {
          if (!/^\$\d+$/.test(name)) throw SwiftalkError.syntax(`invalid placeholder '${name}'`);
          return { k: 'variable', name };
        }
        return { k: 'variable', name };
      }
      case 'punct':
        if (k.v === '.') {
          const n = this.advance();
          if (!isIdent(n) || keywords.has(n.v)) throw SwiftalkError.syntax("expected a member name after '.'");
          return { k: 'memberLiteral', name: n.v };
        }
        if (k.v === '(') {
          if (isPunct(this.peek, ')')) { this.pos++; return { k: 'tuple', elements: [] }; }
          const op = this.bareOperator([tok.punct(')')]);
          if (op !== null) { this.expect(')'); return { k: 'operatorRef', op }; }
          const element = (): Arg => {
            const l = this.peek;
            if (isIdent(l) && isPunct(this.peekAt(1), ':') && plainName(l.v)) {
              this.pos += 2;
              return { label: l.v, expr: this.withTrailing(true, () => this.parseExpr()) };
            }
            return { label: null, expr: this.withTrailing(true, () => this.parseExpr()) };
          };
          const first = element();
          if (first.label === null && !isPunct(this.peek, ',')) { this.expect(')'); return first.expr; }
          const elements = [first];
          while (this.consumeComma(')')) elements.push(element());
          this.expect(')');
          const seen = new Set();
          for (const e of elements) if (e.label !== null) {
            if (seen.has(e.label)) throw SwiftalkError.syntax(`duplicate tuple label '${e.label}'`);
            seen.add(e.label);
          }
          return { k: 'tuple', elements };
        }
        if (k.v === '[') return this.withTrailing(true, () => this.parseCollection());
        if (k.v === '{') return this.withTrailing(true, () => this.parseFunction());
        throw SwiftalkError.syntax(`unexpected token ${tokDescribe(k)}`);
      default:
        throw SwiftalkError.syntax(`unexpected token ${tokDescribe(k)}`);
    }
  }
  parseFunction(): FunctionExpr {
    const outerLabels = this.loopLabels;
    this.loopLabels = [];
    try {
      const parameters = this.parseParameterList();
      const body = this.parseStatements('}');
      this.expect('}');
      return { k: 'function', parameters, body };
    } finally { this.loopLabels = outerLabels; }
  }
  parseParameterList(): string[] {
    const saved = this.pos;
    this.skipSeparators();
    const parameters: string[] = [];
    while (isIdent(this.peek) && plainName(this.peek.v)) {
      parameters.push(this.peek.v);
      this.pos++;
      if (isPunct(this.peek, ',')) { this.pos++; continue; }
      break;
    }
    if (parameters.length && isIdent(this.peek, 'in')) {
      this.pos++;
      const named = parameters.filter((p) => p !== '_');
      if (new Set(named).size !== named.length) throw SwiftalkError.syntax('duplicate parameter name');
      return parameters;
    }
    this.pos = saved;
    return [];
  }
  parseCollection(): Expr {
    if (isPunct(this.peek, ']')) { this.pos++; return { k: 'array', elements: [] }; }
    if (isPunct(this.peek, ':')) { this.pos++; this.expect(']'); return { k: 'dictionary', pairs: [] }; }
    const first = this.parseExpr();
    if (isPunct(this.peek, ':')) {
      this.pos++;
      const pairs: [Expr, Expr][] = [[first, this.parseExpr()]];
      while (this.consumeComma(']')) {
        const key = this.parseExpr();
        this.expect(':');
        pairs.push([key, this.parseExpr()]);
      }
      this.expect(']');
      return { k: 'dictionary', pairs };
    }
    const elements = [first];
    while (this.consumeComma(']')) elements.push(this.parseExpr());
    this.expect(']');
    return { k: 'array', elements };
  }
}

/// Source to statements: the two stages, as `Interpreter.eval` runs them.
export function parse(source: string): Stmt[] {
  const lexer = new Lexer(source);
  const parser = new Parser(lexer.tokenize());
  return parser.parseProgram();
}
