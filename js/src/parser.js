// The parser — a line-for-line port of Core/Sources/Swiftalk/Parser.swift.
// AST nodes are plain objects tagged by `k`; dictionaries of members are
// Maps (member names are arbitrary). Literal values are the runtime's
// own representation: BigInt for Int, number for Double, string, boolean,
// null for nil (see value.js).
import { SwiftalkError } from './errors.js';
import { keywords } from './keywords.js';
import { Lexer, isPunct, isOp, isIdent, isNewline, tokEq, tokDescribe, tok } from './lexer.js';

export class TypeAnnotation {
  constructor(name, optional = false, parameters = []) {
    this.name = name;
    this.optional = optional;
    this.parameters = parameters;
  }
  get display() {
    let base;
    if (this.name === 'Array' && this.parameters.length === 1) base = `[${this.parameters[0].display}]`;
    else if (this.name === 'Dictionary' && this.parameters.length === 2) base = `[${this.parameters[0].display}: ${this.parameters[1].display}]`;
    else if (this.parameters.length === 0) base = this.name;
    else base = this.name + '<' + this.parameters.map((p) => p.display).join(', ') + '>';
    return this.optional ? base + '?' : base;
  }
  equals(other) {
    return other instanceof TypeAnnotation && this.name === other.name && this.optional === other.optional
      && this.parameters.length === other.parameters.length
      && this.parameters.every((p, i) => p.equals(other.parameters[i]));
  }
  static make(name, parameters, optional) {
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
const compoundOps = new Set(['+=', '-=', '*=', '/=', '%=', '**=', '??=', '!!=', '&&=', '||=', '^^=', '&=', '|=', '^=', '+&=', '+|=', '+^=', '+<=', '+>=']);

const emptyStatics = () => ({ lets: new Map(), vars: new Map(), ops: new Map() });
const plainName = (n) => n !== undefined && !keywords.has(n) && !n.startsWith('$');

export class Parser {
  constructor(tokens) {
    this.tokens = tokens;
    this.pos = 0;
    this.allowTrailing = true;
    this.loopLabels = [];
    this.pendingLabel = null;
  }
  withTrailing(allowed, body) {
    const saved = this.allowTrailing;
    this.allowTrailing = allowed;
    try { return body(); } finally { this.allowTrailing = saved; }
  }
  get peek() { return this.tokens[this.pos]; }
  peekAt(offset) { return this.tokens[this.pos + offset]; }
  advance() { return this.pos < this.tokens.length ? this.tokens[this.pos++] : undefined; }
  expect(p) {
    const k = this.advance();
    if (!isPunct(k, p)) throw SwiftalkError.syntax(`expected '${p}'`);
  }

  // MARK: statements

  parseProgram() {
    const statements = this.parseStatements(null);
    if (statements.length === 0) throw SwiftalkError.syntax('empty program');
    return statements;
  }
  parseStatements(closing) {
    return this.parseStatementsUntil((k) => closing !== null && isPunct(k, closing));
  }
  parseStatementsUntil(stop) {
    const statements = [];
    this.skipSeparators();
    while (this.pos < this.tokens.length && !stop(this.peek)) {
      statements.push(this.parseStatement());
      const atEnd = this.pos === this.tokens.length || stop(this.peek);
      if (!(atEnd || this.consumeSeparator())) throw SwiftalkError.syntax("expected a newline or ';' between statements");
      this.skipSeparators();
    }
    return statements;
  }
  consumeSeparator() {
    if (isNewline(this.peek) || isPunct(this.peek, ';')) { this.pos++; return true; }
    return false;
  }
  skipSeparators() { while (this.consumeSeparator()) {} }

  parseStatement() {
    const k = this.peek;
    if (isIdent(k) && plainName(k.v) && this.pos + 2 < this.tokens.length && isPunct(this.tokens[this.pos + 1], ':')
        && ['for', 'while', 'repeat'].some((w) => isIdent(this.tokens[this.pos + 2], w))) {
      if (this.loopLabels.includes(k.v)) throw SwiftalkError.syntax(`loop label '${k.v}' is already in use by an enclosing loop`);
      this.pos += 2;
      this.pendingLabel = k.v;
    }
    const p = this.peek;
    if (isIdent(p, 'let') || isIdent(p, 'var')) return this.parseDeclaration();
    if (isIdent(p, 'import')) {
      this.pos++;
      let namespace = null;
      const names = [];
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
        const names = [];
        do {
          const n = this.advance();
          if (!isIdent(n) || !plainName(n.v)) throw SwiftalkError.syntax('export (a, b) — names in parentheses');
          names.push(n.v);
        } while (this.consumeComma(')'));
        this.expect(')');
        return { k: 'export', names, declaration: null };
      }
      const declaration = this.parseStatement();
      let names;
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
      const pattern = patterns.length === 1 ? patterns[0] : { k: 'tuple', elements: patterns.map((pt) => ({ label: null, pattern: pt })) };
      const seen = new Set();
      for (const name of Parser.namesIn(pattern)) {
        if (seen.has(name)) throw SwiftalkError.syntax(`'${name}' appears twice in the loop pattern`);
        seen.add(name);
      }
      if (!isIdent(this.advance(), 'in')) throw SwiftalkError.syntax("expected 'in' after the loop variable");
      const sequence = this.withTrailing(false, () => this.parseExpr());
      let condition = null;
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

  takeLabel() { const l = this.pendingLabel; this.pendingLabel = null; return l; }
  parseLoopBody(label) {
    if (label) this.loopLabels.push(label);
    try { return this.parseBlock(); } finally { if (label) this.loopLabels.pop(); }
  }
  parseLoopLabel(keyword) {
    const k = this.peek;
    if (!isIdent(k) || !plainName(k.v)) return null;
    if (!this.loopLabels.includes(k.v)) {
      throw SwiftalkError.syntax(`'${keyword} ${k.v}': no enclosing loop is labeled '${k.v}'`
        + (this.loopLabels.length ? ` — in scope: ${this.loopLabels.join(', ')}` : ''));
    }
    this.pos++;
    return k.v;
  }
  parseInterpolatedExpr() {
    const expr = this.parseExpr();
    if (this.pos !== this.tokens.length) throw SwiftalkError.syntax("'\\(...)' takes a single expression");
    return expr;
  }

  parseConditionList() {
    const conditions = [];
    for (;;) {
      const head = this.parseBindingHead();
      if (head) {
        let expr;
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
  parseBindingHead() {
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
  parseIf() {
    if (isIdent(this.peek, 'case')) throw SwiftalkError.syntax("'if case' is not swiftalk — write if let r = s.circle (or if r = s.circle)");
    const conditions = this.parseConditionList();
    const then = this.withTrailing(true, () => this.parseBlock());
    const elseBranch = this.parseElse();
    return { k: 'if', conditions, then, else: elseBranch };
  }
  parseElse() {
    const saved = this.pos;
    this.skipSeparators();
    if (!isIdent(this.peek, 'else')) { this.pos = saved; return null; }
    this.pos++;
    if (isIdent(this.peek, 'if')) { this.pos++; return [{ k: 'expression', expr: this.parseIf() }]; }
    return this.withTrailing(true, () => this.parseBlock());
  }

  parseEnum() {
    this.pos++;
    const nameTok = this.advance();
    if (!isIdent(nameTok) || !plainName(nameTok.v)) throw SwiftalkError.syntax("expected a name after 'enum'");
    const name = nameTok.v;
    this.expect('{');
    const caseOrder = [];
    const cases = new Map();
    const methods = new Map();
    const statics = emptyStatics();
    const between = (what) => {
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
        const params = [];
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

  parseMethod(existing) {
    this.pos++;
    const nameTok = this.advance();
    if (!isIdent(nameTok) || !plainName(nameTok.v)) throw SwiftalkError.syntax("expected a method name after 'let'");
    if (existing(nameTok.v)) throw SwiftalkError.syntax(`duplicate member '${nameTok.v}'`);
    this.expect('=');
    const fn = this.parseExpr();
    if (fn.k !== 'function') throw SwiftalkError.syntax(`a type-body 'let' holds a method: let ${nameTok.v} = { ... }`);
    return [nameTok.v, fn];
  }

  parseStruct(kind) {
    this.pos++;
    const nameTok = this.advance();
    if (!isIdent(nameTok) || !plainName(nameTok.v)) throw SwiftalkError.syntax(`expected a name after '${kind}'`);
    const name = nameTok.v;
    this.expect('{');
    const propertyOrder = [];
    const properties = new Map();
    const methods = new Map();
    const inits = [];
    const computed = new Map();
    const statics = emptyStatics();
    const between = (what) => {
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
      let annotation = null;
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
      let defaultExpr = null;
      if (isPunct(this.peek, '=')) { this.pos++; defaultExpr = this.parseExpr(); }
      let observers = null;
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

  isOperatorMember() {
    const k = this.peek;
    return isIdent(k) && ['infix', 'prefix', 'postfix'].includes(k.v) && isPunct(this.peekAt(1), '(');
  }
  parseOperatorMember(statics) {
    const fixTok = this.advance();
    if (!isIdent(fixTok)) throw SwiftalkError.syntax('expected infix, prefix, or postfix');
    const fix = fixTok.v;
    this.expect('(');
    const opTok = this.advance();
    let op;
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
  parseStatic(statics, existing) {
    this.pos++;
    const kw = this.advance();
    if (!isIdent(kw) || !(kw.v === 'let' || kw.v === 'var')) throw SwiftalkError.syntax("'static' is followed by 'let name = value' or 'var name { ... }'");
    const nameTok = this.advance();
    if (!isIdent(nameTok) || !plainName(nameTok.v)) throw SwiftalkError.syntax(`expected a name after 'static ${kw.v}'`);
    const name = nameTok.v;
    if (existing(name) || statics.lets.has(name) || statics.vars.has(name)) throw SwiftalkError.syntax(`duplicate static member '${name}'`);
    if (kw.v === 'let') {
      this.expect('=');
      statics.lets.set(name, this.parseExpr());
      return;
    }
    let annotation = null;
    if (isPunct(this.peek, ':')) { this.pos++; annotation = this.parseTypeAnnotation(); }
    if (!isPunct(this.advance(), '{')) throw SwiftalkError.syntax(`a static var computes: static var ${name} { ... } — a stored one is static let`);
    const { get, set } = this.parseComputedBody();
    if (set) throw SwiftalkError.syntax('a static var has no setter — a type is a value, not storage');
    statics.vars.set(name, { annotation, get, set: null });
  }

  parseTypeAnnotation() {
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
    const parameters = [];
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
  parseGenericArguments() {
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
  isObserverBlock(index) {
    let i = index;
    while (isNewline(this.tokens[i])) i++;
    const w = this.tokens[i];
    if (!(isIdent(w, 'willSet') || isIdent(w, 'didSet'))) return false;
    const n = this.tokens[i + 1];
    return isPunct(n, '{') || isPunct(n, '(');
  }
  parseObserverBlock() {
    let will = null, did = null;
    this.skipSeparators();
    while (isIdent(this.peek, 'willSet') || isIdent(this.peek, 'didSet')) {
      const word = this.advance().v;
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
      const fn = { k: 'function', parameters: [param], body };
      if (word === 'willSet') { if (will) throw SwiftalkError.syntax("duplicate 'willSet'"); will = fn; }
      else { if (did) throw SwiftalkError.syntax("duplicate 'didSet'"); did = fn; }
      this.skipSeparators();
    }
    if (!will && !did) throw SwiftalkError.syntax('an observer block holds willSet and/or didSet');
    this.expect('}');
    return { will, did };
  }
  parseComputedBody() {
    this.skipSeparators();
    if (!(isIdent(this.peek, 'get') || isIdent(this.peek, 'set'))) {
      const body = this.parseStatements('}');
      this.expect('}');
      return { get: { k: 'function', parameters: [], body }, set: null };
    }
    let getBody = null, setExpr = null;
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

  parseExtension() {
    this.pos++;
    const t = this.advance();
    if (!isIdent(t) || !plainName(t.v)) throw SwiftalkError.syntax("expected a type name after 'extension'");
    this.expect('{');
    const methods = new Map();
    const computed = new Map();
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
        let annotation = null;
        if (isPunct(this.peek, ':')) { this.pos++; annotation = this.parseTypeAnnotation(); }
        this.expect('{');
        const { get, set } = this.parseComputedBody();
        computed.set(p.v, { annotation, get, set });
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

  parseSwitch() {
    const subject = this.withTrailing(false, () => this.parseExpr());
    this.expect('{');
    const clauses = [];
    let defaultBody = null;
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
  parseCaseBody() {
    return this.parseStatementsUntil((k) => isIdent(k, 'case') || isIdent(k, 'default') || isPunct(k, '}'));
  }
  parseCasePattern() {
    const pattern = this.parsePattern();
    if (!isIdent(this.peek, 'where')) return { pattern, condition: null };
    this.pos++;
    const condition = this.withTrailing(false, () => this.parseWordOr(() => this.parseDisjunction()));
    return { pattern, condition };
  }
  parsePattern() {
    if (isIdent(this.peek, '_')) { this.pos++; return { k: 'wildcard' }; }
    if (isPunct(this.peek, '.')) {
      const name = this.parseCaseName();
      if (isPunct(this.peek, '(')) throw SwiftalkError.syntax(`case .${name}(let x) is not swiftalk — write case let x = .${name} (or case x = .${name})`);
      return { k: 'enumCase', name };
    }
    const explicit = isIdent(this.peek, 'let') || isIdent(this.peek, 'var');
    const head = this.parseBindingHead();
    if (head) {
      let pattern = head.pattern;
      if (explicit && isPunct(this.peek, ',')) {
        const elements = [{ label: null, pattern }];
        while (isPunct(this.peek, ',')) { this.pos++; elements.push({ label: null, pattern: this.parseBindPattern() }); }
        pattern = { k: 'tuple', elements };
      }
      this.expect('=');
      if (isPunct(this.peek, '.')) return { k: 'binding', mutable: head.mutable, pattern, source: { k: 'member', name: this.parseCaseName() } };
      return { k: 'binding', mutable: head.mutable, pattern, source: { k: 'expr', e: this.parseComparison() } };
    }
    return { k: 'expr', e: this.parseComparison() };
  }
  parseCaseName() {
    this.expect('.');
    const n = this.advance();
    if (!isIdent(n) || keywords.has(n.v)) throw SwiftalkError.syntax("expected a case name after '.'");
    return n.v;
  }
  parseBlock() {
    this.expect('{');
    const body = this.parseStatements('}');
    this.expect('}');
    return body;
  }
  lvalue(expr) {
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
  static namesIn(pattern) {
    if (pattern.k === 'name') return pattern.name === '_' ? [] : [pattern.name];
    return pattern.elements.flatMap((e) => Parser.namesIn(e.pattern));
  }
  parseBindPattern() {
    const seen = new Set();
    const parse = () => {
      if (isPunct(this.peek, '(')) {
        this.pos++;
        const elements = [];
        const labels = new Set();
        do {
          let label = null;
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
  parseDeclaration() {
    const keyword = this.advance().v;
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
    if (isPunct(this.peek, ',')) {
      const elements = [{ label: null, pattern: { k: 'name', name } }];
      while (isPunct(this.peek, ',')) { this.pos++; elements.push({ label: null, pattern: this.parseBindPattern() }); }
      if (isPunct(this.peek, ':')) throw SwiftalkError.syntax('a destructuring pattern takes no annotation — the names lock element by element');
      this.expect('=');
      return { k: 'destructure', mutable, pattern: { k: 'tuple', elements }, initializer: this.parseExpr() };
    }
    let annotation = null;
    if (isPunct(this.peek, ':')) { this.pos++; annotation = this.parseTypeAnnotation(); }
    this.expect('=');
    return { k: 'declaration', mutable, name, annotation, initializer: this.parseExpr() };
  }

  // MARK: expressions

  parseExpr() { return this.parseWordOr(() => this.parseTernary()); }
  parseWordOr(operand) {
    let lhs = this.parseWordAnd(operand);
    for (;;) {
      if (isIdent(this.peek, 'or')) { this.pos++; lhs = { k: 'logicalOr', lhs, rhs: this.parseWordAnd(operand) }; }
      else if (isIdent(this.peek, 'xor')) { this.pos++; lhs = { k: 'logicalXor', lhs, rhs: this.parseWordAnd(operand) }; }
      else return lhs;
    }
  }
  parseWordAnd(operand) {
    let lhs = this.parseWordNot(operand);
    while (isIdent(this.peek, 'and')) { this.pos++; lhs = { k: 'logicalAnd', lhs, rhs: this.parseWordNot(operand) }; }
    return lhs;
  }
  parseWordNot(operand) {
    if (isIdent(this.peek, 'not')) { this.pos++; return { k: 'logicalNot', e: this.parseWordNot(operand) }; }
    return operand();
  }
  parseTernary() {
    const condition = this.parseDisjunction();
    if (!isPunct(this.peek, '?')) return condition;
    this.pos++;
    const a = this.parseExpr();
    this.expect(':');
    const b = this.parseTernary();
    return { k: 'ternary', condition, a, b };
  }
  parseDisjunction() {
    let lhs = this.parseXor();
    while (isOp(this.peek, '||')) { this.pos++; lhs = { k: 'logicalOr', lhs, rhs: this.parseXor() }; }
    return lhs;
  }
  parseXor() {
    let lhs = this.parseConjunction();
    while (isOp(this.peek, '^^')) { this.pos++; lhs = { k: 'logicalXor', lhs, rhs: this.parseConjunction() }; }
    return lhs;
  }
  parseConjunction() {
    let lhs = this.parseComparison();
    while (isOp(this.peek, '&&')) { this.pos++; lhs = { k: 'logicalAnd', lhs, rhs: this.parseComparison() }; }
    return lhs;
  }
  parseComparison() {
    const lhs = this.parseCoalescing();
    const k = this.peek;
    if (!isOp(k) || !['==', '!=', '===', '!==', '<', '<=', '>', '>='].includes(k.v)) return lhs;
    this.pos++;
    return { k: 'comparison', op: k.v, lhs, rhs: this.parseCoalescing() };
  }
  parseCoalescing() {
    const lhs = this.parseRange();
    const k = this.peek;
    if (!isOp(k) || !(k.v === '??' || k.v === '!!')) return lhs;
    this.pos++;
    return { k: k.v === '??' ? 'coalesce' : 'override', lhs, rhs: this.parseCoalescing() };
  }
  parseRange() {
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
  parseAdditive() {
    let lhs = this.parseMultiplicative();
    for (;;) {
      const k = this.peek;
      if (isPunct(k) && (k.v === '+' || k.v === '-')) { this.pos++; lhs = { k: 'binary', op: k.v, lhs, rhs: this.parseMultiplicative() }; }
      else if (isOp(k) && (k.v === '|' || k.v === '^')) { this.pos++; lhs = { k: 'binary', op: k.v, lhs, rhs: this.parseMultiplicative() }; }
      else if (isOp(k) && (k.v === '+|' || k.v === '+^')) { this.pos++; lhs = { k: 'bitwise', op: k.v, lhs, rhs: this.parseMultiplicative() }; }
      else return lhs;
    }
  }
  parseMultiplicative() {
    let lhs = this.parseUnary();
    for (;;) {
      const k = this.peek;
      if (isPunct(k) && (k.v === '*' || k.v === '/' || k.v === '%')) { this.pos++; lhs = { k: 'binary', op: k.v, lhs, rhs: this.parseUnary() }; }
      else if (isOp(k, '&')) { this.pos++; lhs = { k: 'binary', op: '&', lhs, rhs: this.parseUnary() }; }
      else if (isOp(k) && (k.v === '+&' || k.v === '+<' || k.v === '+>')) { this.pos++; lhs = { k: 'bitwise', op: k.v, lhs, rhs: this.parseUnary() }; }
      else return lhs;
    }
  }
  parseUnary() {
    if (isPunct(this.peek, '-')) { this.pos++; return { k: 'unaryMinus', e: this.parseUnary() }; }
    if (isPunct(this.peek, '+')) { this.pos++; return { k: 'unaryPlus', e: this.parseUnary() }; }
    if (isOp(this.peek, '+^')) { this.pos++; return { k: 'bitNot', e: this.parseUnary() }; }
    if (isOp(this.peek, '!')) { this.pos++; return { k: 'logicalNot', e: this.parseUnary() }; }
    if (isIdent(this.peek, 'await')) { this.pos++; return { k: 'await', e: this.parseUnary() }; }
    return this.parsePower();
  }
  parsePower() {
    const base = this.parsePostfix();
    if (!isOp(this.peek, '**')) return base;
    this.pos++;
    return { k: 'power', lhs: base, rhs: this.parseUnary() };
  }
  parsePostfix() {
    let expr = this.parsePrimary();
    loop: for (;;) {
      const k = this.peek;
      if (isPunct(k, '.')) {
        this.pos++;
        const m = this.advance();
        let name;
        if (isIdent(m)) name = m.v;
        else if (m && m.t === 'int' && m.v >= 0n) name = String(m.v);
        else throw SwiftalkError.syntax("expected member name after '.'");
        let args = [], called = false;
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
        let args = [], called = false;
        if (isPunct(this.peek, '(')) { called = true; args = this.parseCallArguments(); }
        expr = { k: 'optionalMember', receiver: expr, name: n.v, args, called };
      } else break loop;
    }
    return expr;
  }
  static attachTrailing(closure, expr) {
    switch (expr.k) {
      case 'method': return { k: 'method', receiver: expr.receiver, name: expr.name, args: [...expr.args, { label: null, expr: closure }], called: true };
      case 'call': return { k: 'call', callee: expr.callee, args: [...expr.args, { label: null, expr: closure }] };
      case 'selfCall': return { k: 'selfCall', args: [...expr.args, { label: null, expr: closure }] };
      default: return { k: 'call', callee: expr, args: [{ label: null, expr: closure }] };
    }
  }
  parseCallArguments() {
    this.expect('(');
    const args = [];
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
  parseArgument() {
    const op = this.bareOperator([tok.punct(','), tok.punct(')')]);
    if (op !== null) return { k: 'operatorRef', op };
    return this.parseExpr();
  }
  consumeComma(closing) {
    if (!isPunct(this.peek, ',')) return false;
    this.pos++;
    return !isPunct(this.peek, closing);
  }
  bareOperator(closers) {
    const next = this.peekAt(1);
    if (next === undefined || !closers.some((c) => tokEq(c, next))) return null;
    const k = this.peek;
    let op;
    if (isPunct(k) && '+-*/%'.includes(k.v)) op = k.v;
    else if (isOp(k) && functionOperators.has(k.v)) op = k.v;
    else return null;
    this.pos++;
    return op;
  }
  parsePrimary() {
    const k = this.advance();
    if (k === undefined) throw SwiftalkError.syntax('unexpected token end of input');
    switch (k.t) {
      case 'int': return { k: 'literal', v: k.v };
      case 'double': return { k: 'literal', v: k.v };
      case 'string': return { k: 'literal', v: k.v };
      case 'regex': return { k: 'regexLiteral', pattern: k.pattern, flags: k.flags };
      case 'interpolated':
        return { k: 'interpolation', parts: k.segments.map((seg) => {
          if (seg.literal !== undefined) return { k: 'literal', v: seg.literal };
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
          const element = () => {
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
  parseFunction() {
    const outerLabels = this.loopLabels;
    this.loopLabels = [];
    try {
      const parameters = this.parseParameterList();
      const body = this.parseStatements('}');
      this.expect('}');
      return { k: 'function', parameters, body };
    } finally { this.loopLabels = outerLabels; }
  }
  parseParameterList() {
    const saved = this.pos;
    this.skipSeparators();
    const parameters = [];
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
  parseCollection() {
    if (isPunct(this.peek, ']')) { this.pos++; return { k: 'array', elements: [] }; }
    if (isPunct(this.peek, ':')) { this.pos++; this.expect(']'); return { k: 'dictionary', pairs: [] }; }
    const first = this.parseExpr();
    if (isPunct(this.peek, ':')) {
      this.pos++;
      const pairs = [[first, this.parseExpr()]];
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
export function parse(source) {
  const lexer = new Lexer(source);
  const parser = new Parser(lexer.tokenize());
  return parser.parseProgram();
}
