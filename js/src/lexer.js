// The lexer — a line-for-line port of Core/Sources/Swiftalk/Lexer.swift.
// Source is walked as Unicode scalars (code points); tokens are plain
// objects: {t:'int', v: BigInt} {t:'double', v} {t:'string', v}
// {t:'interpolated', segments} {t:'identifier', v} {t:'punct', v}
// {t:'op', v} {t:'regex', pattern, flags} {t:'newline'}.
import { SwiftalkError } from './errors.js';
import { keywords } from './keywords.js';

export const tok = {
  int: (v) => ({ t: 'int', v }),
  double: (v) => ({ t: 'double', v }),
  string: (v) => ({ t: 'string', v }),
  interpolated: (segments) => ({ t: 'interpolated', segments }),
  identifier: (v) => ({ t: 'identifier', v }),
  punct: (v) => ({ t: 'punct', v }),
  op: (v) => ({ t: 'op', v }),
  regex: (pattern, flags) => ({ t: 'regex', pattern, flags }),
  newline: () => ({ t: 'newline' }),
};
export const isPunct = (k, c) => k != null && k.t === 'punct' && (c === undefined || k.v === c);
export const isOp = (k, o) => k != null && k.t === 'op' && (o === undefined || k.v === o);
export const isIdent = (k, n) => k != null && k.t === 'identifier' && (n === undefined || k.v === n);
export const isNewline = (k) => k != null && k.t === 'newline';
export function tokEq(a, b) {
  if (a == null || b == null) return a == b;
  if (a.t !== b.t) return false;
  switch (a.t) {
    case 'newline': return true;
    case 'regex': return a.pattern === b.pattern && a.flags === b.flags;
    case 'interpolated': return JSON.stringify(a) === JSON.stringify(b);
    default: return a.v === b.v;
  }
}
export function tokDescribe(k) {
  if (k == null) return 'end of input';
  switch (k.t) {
    case 'int': return `int(${k.v})`;
    case 'double': return `double(${k.v})`;
    case 'string': return `string(${JSON.stringify(k.v)})`;
    case 'interpolated': return 'interpolated string';
    case 'identifier': return `identifier(${JSON.stringify(k.v)})`;
    case 'punct': return `punct(${JSON.stringify(k.v)})`;
    case 'op': return `op(${JSON.stringify(k.v)})`;
    case 'regex': return `regex(/${k.pattern}/${k.flags})`;
    default: return k.t;
  }
}

const INT_MAX_LITERAL = (1n << 63n) - 1n;   // Int.max: what a literal may not exceed
const isDigit = (c) => c !== undefined && c >= '0' && c <= '9';
const isHexDigit = (c) => isDigit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
const alphabetic = /^\p{Alphabetic}$/u;
const isAlphabetic = (c) => c !== undefined && alphabetic.test(c);
const isSpace = (c) => c === ' ' || c === '\t';

const continuers = new Set([
  '==', '!=', '===', '!==', '<', '<=', '>', '>=', '&&', '||', '??', '!!',
  '+=', '-=', '*=', '/=', '%=', '??=', '!!=', '&&=', '||=', '^^', '^^=', '**', '**=',
  '&', '|', '^', '&=', '|=', '^=',
  '+&', '+|', '+^', '+<', '+>', '+&=', '+|=', '+^=', '+<=', '+>=']);

export class Lexer {
  constructor(source) {
    this.s = Array.from(source);   // code points
    this.pos = 0;
    this.closingAngle = false;
  }
  get peek() { return this.s[this.pos]; }
  at(i) { return this.s[i]; }
  advance() { return this.pos < this.s.length ? this.s[this.pos++] : undefined; }

  tokenize() {
    const tokens = [];
    const brackets = [];
    const suppress = () => { const b = brackets[brackets.length - 1]; return b === '[' || b === '('; };
    const last = () => tokens[tokens.length - 1];
    while (this.pos < this.s.length) {
      const c = this.peek;
      if (tokens.length >= 2 && isNewline(tokens[tokens.length - 2]) && Lexer.leadsContinuation(last())
          && (c === ' ' || c === '\t' || c === '\n')) {
        tokens.splice(tokens.length - 2, 1);
      }
      switch (c) {
        case ' ': case '\t': case '\r':
          this.pos++; break;
        case '\n':
          this.pos++;
          if (!suppress() && last() != null && !isNewline(last())
              && (!Lexer.continuesLine(last()) || (isOp(last(), '>') && this.closingAngle))) {
            tokens.push(tok.newline());
          }
          break;
        case '/':
          if (this.at(this.pos + 1) === '/') {
            while (this.pos < this.s.length && this.peek !== '\n') this.pos++;
          } else if (this.at(this.pos + 1) === '*') {
            this.skipBlockComment();
          } else if (Lexer.regexMayStart(last()) && this.at(this.pos + 1) !== ')') {
            tokens.push(this.lexRegex());
          } else if (this.at(this.pos + 1) === '=') {
            this.pos += 2; tokens.push(tok.op('/='));
          } else {
            this.pos++; tokens.push(tok.punct('/'));
          }
          break;
        case '^': case '&': case '|': {
          this.pos++;
          const doubled = this.peek === c;
          if (doubled) this.pos++;
          const text = doubled ? c + c : c;
          if (this.peek === '=') { this.pos++; tokens.push(tok.op(text + '=')); } else tokens.push(tok.op(text));
          break;
        }
        case '[': case '(': case '{':
          brackets.push(c); this.pos++; tokens.push(tok.punct(c)); break;
        case ']': case ')': case '}':
          if (brackets.length) brackets.pop();
          this.pos++; tokens.push(tok.punct(c)); break;
        case ':': case ',': case '+': case '-': case '*': case '%': case ';': {
          if (c === '*' && this.at(this.pos + 1) === '*') {
            this.pos += 2;
            if (this.peek === '=') { this.pos++; tokens.push(tok.op('**=')); } else tokens.push(tok.op('**'));
            break;
          }
          if (c === '+' && '&|^<>'.includes(this.at(this.pos + 1) ?? '\0')) {
            const text = '+' + this.at(this.pos + 1);
            this.pos += 2;
            if (this.peek === '=') { this.pos++; tokens.push(tok.op(text + '=')); } else tokens.push(tok.op(text));
            break;
          }
          if ('+-*%'.includes(c) && this.at(this.pos + 1) === '=') {
            this.pos += 2; tokens.push(tok.op(c + '='));
          } else {
            this.pos++; tokens.push(tok.punct(c));
          }
          break;
        }
        case '?': {
          const unspaced = this.pos > 0 && !' \t\n\r'.includes(this.at(this.pos - 1));
          this.pos++;
          if (this.peek === '?') {
            this.pos++;
            if (this.peek === '=') { this.pos++; tokens.push(tok.op('??=')); } else tokens.push(tok.op('??'));
          } else if (unspaced && this.peek === '.') {
            this.pos++; tokens.push(tok.op('?.'));
          } else if (unspaced) {
            tokens.push(tok.op('?'));
          } else {
            tokens.push(tok.punct('?'));
          }
          break;
        }
        case '=': case '!': case '<': case '>': {
          if (c === '!' && this.at(this.pos + 1) === '!'
              && ((this.pos > 0 && isSpace(this.at(this.pos - 1)) && !Lexer.regexMayStart(last()))
                  || Lexer.bareOperatorPosition(this.s, this.pos + 2, last()))) {
            this.pos += 2;
            if (this.peek === '=') { this.pos++; tokens.push(tok.op('!!=')); } else tokens.push(tok.op('!!'));
            break;
          }
          this.pos++;
          if (this.peek === '=') {
            this.pos++;
            if ((c === '=' || c === '!') && this.peek === '=') {
              this.pos++; tokens.push(tok.op(c + '=='));
            } else {
              tokens.push(tok.op(c + '='));
            }
          } else if (c === '=') {
            tokens.push(tok.punct('='));
          } else if (c === '<' || c === '>') {
            if (c === '>') {
              const unspaced = this.pos >= 2 && !' \t\n\r'.includes(this.at(this.pos - 2));
              const l = last();
              if (isIdent(l) || isPunct(l, ']') || isOp(l, '?') || isOp(l, '>')) this.closingAngle = unspaced;
              else this.closingAngle = false;
            }
            tokens.push(tok.op(c));
          } else {
            tokens.push(tok.op('!'));
          }
          break;
        }
        case '$': {
          this.pos++;
          let name = '$';
          while (isDigit(this.peek)) { name += this.peek; this.pos++; }
          tokens.push(tok.identifier(name));
          break;
        }
        case '.': {
          if (this.at(this.pos + 1) === '.') {
            const third = this.at(this.pos + 2);
            if (third !== '.' && third !== '<') throw SwiftalkError.syntax("'..' is not an operator");
            tokens.push(tok.op(third === '.' ? '...' : '..<'));
            this.pos += 3;
          } else {
            this.pos++; tokens.push(tok.punct('.'));
          }
          break;
        }
        case '"':
          tokens.push(this.startsTripleQuote() ? this.lexMultilineString(0) : this.lexStringToken(0));
          break;
        case '#': {
          let hashes = 0;
          while (this.peek === '#') { hashes++; this.pos++; }
          if (this.peek !== '"') throw SwiftalkError.syntax("unexpected character '#'");
          tokens.push(this.startsTripleQuote() ? this.lexMultilineString(hashes) : this.lexStringToken(hashes));
          break;
        }
        default:
          if (isDigit(c)) {
            tokens.push(this.lexNumber(isPunct(last(), '.')));
          } else if (isAlphabetic(c) || c === '_') {
            tokens.push(tok.identifier(this.lexIdentifier()));
          } else {
            throw SwiftalkError.syntax(`unexpected character '${c}'`);
          }
      }
    }
    return tokens;
  }

  static continuesLine(last) {
    if (last == null) return false;
    switch (last.t) {
      case 'punct': return '+-*/%='.includes(last.v);
      case 'op': return continuers.has(last.v);
      case 'identifier': return ['and', 'or', 'xor', 'not'].includes(last.v);
      default: return false;
    }
  }
  static leadsContinuation(token) {
    if (isIdent(token, 'not')) return false;
    if (Lexer.continuesLine(token)) return true;
    if (isPunct(token)) return token.v === '?' || token.v === ':';
    return false;
  }
  static bareOperatorPosition(scalars, from, last) {
    if (!(isPunct(last, '(') || isPunct(last, ','))) return false;
    let i = from;
    while (i < scalars.length && isSpace(scalars[i])) i++;
    return i < scalars.length && (scalars[i] === ')' || scalars[i] === ',');
  }
  static regexMayStart(last) {
    if (last == null) return true;
    switch (last.t) {
      case 'newline': case 'op': return true;
      case 'punct': return last.v !== ')' && last.v !== ']' && last.v !== '}';
      case 'identifier': return (keywords.has(last.v) || last.v === 'where')
        && last.v !== 'true' && last.v !== 'false' && last.v !== 'nil';
      default: return false;
    }
  }

  lexRegex() {
    this.pos++;
    let pattern = '';
    for (;;) {
      const c = this.advance();
      if (c === undefined || c === '\n') throw SwiftalkError.syntax('unterminated regex literal');
      if (c === '/') break;
      if (c === '\\') {
        const next = this.advance();
        if (next === undefined) throw SwiftalkError.syntax('unterminated regex literal');
        pattern += next === '/' ? '/' : c + next;
        continue;
      }
      pattern += c;
    }
    let flags = '';
    while (this.peek !== undefined && this.peek >= 'a' && this.peek <= 'z') { flags += this.peek; this.pos++; }
    return tok.regex(pattern, flags);
  }

  skipBlockComment() {
    this.pos += 2;
    let depth = 1;
    while (depth > 0) {
      if (this.pos >= this.s.length) throw SwiftalkError.syntax('unterminated block comment');
      if (this.peek === '*' && this.at(this.pos + 1) === '/') { depth--; this.pos += 2; }
      else if (this.peek === '/' && this.at(this.pos + 1) === '*') { depth++; this.pos += 2; }
      else this.pos++;
    }
  }

  lexIdentifier() {
    let name = '';
    while (this.peek !== undefined && (isAlphabetic(this.peek) || this.peek === '_' || isDigit(this.peek))) {
      name += this.peek; this.pos++;
    }
    return name;
  }

  startsTripleQuote() {
    return this.pos + 2 < this.s.length && this.at(this.pos) === '"' && this.at(this.pos + 1) === '"' && this.at(this.pos + 2) === '"';
  }
  hashesFollow(hashes) {
    if (hashes <= 0) return true;
    if (this.pos + hashes > this.s.length) return false;
    for (let i = 0; i < hashes; i++) if (this.at(this.pos + i) !== '#') return false;
    return true;
  }
  lexStringToken(hashes) {
    this.pos++;
    return this.lexStringBody(hashes, true);
  }

  lexMultilineString(hashes) {
    this.pos += 3;
    while (isSpace(this.peek)) this.pos++;
    if (this.peek === undefined) {
      throw SwiftalkError.syntax('unterminated multi-line string literal — close it with """ on its own line');
    }
    if (this.peek !== '\n') {
      throw SwiftalkError.syntax("a multi-line string's content starts on the line after the opening \"\"\"");
    }
    const openingNewline = this.pos;
    this.pos++;
    const contentStart = this.pos;
    let j = openingNewline;
    let found = null;
    while (j < this.s.length) {
      if (this.at(j) === '\n') {
        let m = j + 1;
        while (m < this.s.length && isSpace(this.at(m))) m++;
        if (m + 2 < this.s.length && this.at(m) === '"' && this.at(m + 1) === '"' && this.at(m + 2) === '"') {
          let ok = true;
          for (let h = 0; h < hashes; h++) if (this.at(m + 3 + h) !== '#') ok = false;
          if (ok) { found = { newline: j, lineStart: j + 1, delimiter: m }; break; }
        }
      }
      j++;
    }
    if (!found) throw SwiftalkError.syntax('unterminated multi-line string literal — close it with """ on its own line');
    const indent = this.s.slice(found.lineStart, found.delimiter);
    const content = found.newline > openingNewline ? this.s.slice(contentStart, found.newline) : [];
    const lines = [[]];
    for (const c of content) { if (c === '\n') lines.push([]); else lines[lines.length - 1].push(c); }
    let body = '';
    lines.forEach((line, n) => {
      if (n > 0) body += '\n';
      if (line.every(isSpace) && line.length <= indent.length) return;
      for (let i = 0; i < indent.length; i++) {
        if (line[i] !== indent[i]) {
          throw SwiftalkError.syntax(`line ${n + 1} of the multi-line string is indented less than its closing """`);
        }
      }
      body += line.slice(indent.length).join('');
    });
    this.pos = found.delimiter + 3 + hashes;
    const sub = new Lexer(body);
    return sub.lexStringBody(hashes, false);
  }

  lexStringBody(hashes, terminated) {
    const segments = [];
    let current = '';
    const finish = () => {
      if (segments.length === 0) return tok.string(current);
      if (current.length) segments.push({ literal: current });
      return tok.interpolated(segments);
    };
    for (;;) {
      const c = this.advance();
      if (c === undefined) {
        if (terminated) throw SwiftalkError.syntax('unterminated string literal');
        return finish();
      }
      if (c === '"' && terminated && this.hashesFollow(hashes)) {
        this.pos += hashes;
        return finish();
      }
      if (c === '\\' && this.hashesFollow(hashes)) {
        this.pos += hashes;
        const e = this.advance();
        if (e === undefined) throw SwiftalkError.syntax('unterminated escape sequence');
        switch (e) {
          case '(': {
            if (current.length) { segments.push({ literal: current }); current = ''; }
            const sub = new Lexer(this.scanInterpolation());
            segments.push({ tokens: sub.tokenize() });
            break;
          }
          case '"': current += '"'; break;
          case '\\': current += '\\'; break;
          case 'n': current += '\n'; break;
          case 'r': current += '\r'; break;
          case 't': current += '\t'; break;
          case '0': current += '\0'; break;
          case 'u': current += this.lexUnicodeEscape(); break;
          case '\n':
            if (!terminated) break;
            throw SwiftalkError.syntax(`unknown escape sequence '\\${e}'`);
          default:
            throw SwiftalkError.syntax(`unknown escape sequence '\\${e}'`);
        }
        continue;
      }
      current += c;
    }
  }

  scanInterpolation() {
    let out = '';
    let depth = 1;
    while (this.pos < this.s.length) {
      const c = this.peek;
      if (c === '(') { depth++; out += '('; this.pos++; }
      else if (c === ')') {
        depth--; this.pos++;
        if (depth === 0) return out;
        out += ')';
      } else if (c === '"') {
        out += this.scanNestedString();
      } else { out += c; this.pos++; }
    }
    throw SwiftalkError.syntax("unterminated '\\(' interpolation");
  }
  scanNestedString() {
    let out = '"';
    this.pos++;
    while (this.pos < this.s.length) {
      const c = this.peek;
      if (c === '"') { this.pos++; return out + '"'; }
      if (c === '\\') {
        this.pos++;
        const e = this.peek;
        if (e === undefined) break;
        if (e === '(') { this.pos++; out += '\\(' + this.scanInterpolation() + ')'; }
        else { out += '\\' + e; this.pos++; }
        continue;
      }
      out += c; this.pos++;
    }
    throw SwiftalkError.syntax('unterminated string literal');
  }
  lexUnicodeEscape() {
    if (this.advance() !== '{') throw SwiftalkError.syntax("expected '{' after \\u");
    let hex = '';
    while (this.peek !== undefined && this.peek !== '}') { hex += this.peek; this.pos++; }
    if (this.advance() !== '}' || !/^[0-9a-fA-F]+$/.test(hex)) throw SwiftalkError.syntax(`invalid unicode escape \\u{${hex}}`);
    const v = parseInt(hex, 16);
    if (v > 0x10FFFF || (v >= 0xD800 && v <= 0xDFFF)) throw SwiftalkError.syntax(`invalid unicode escape \\u{${hex}}`);
    return String.fromCodePoint(v);
  }

  lexNumber(memberIndex) {
    if (this.peek === '0' && this.pos + 1 < this.s.length) {
      const radix = { x: 16, o: 8, b: 2 }[this.at(this.pos + 1)];
      if (radix) {
        this.pos += 2;
        if (radix === 16) { const d = this.lexHexFloat(); if (d !== null) return tok.double(d); }
        return tok.int(this.lexInteger(radix));
      }
    }
    let text = '';
    let isDouble = false;
    digits: for (;;) {
      const c = this.peek;
      if (c === undefined) break;
      if (isDigit(c)) { text += c; this.pos++; }
      else if (c === '_') { this.pos++; }
      else if (c === '.') {
        if (memberIndex || isDouble || !isDigit(this.at(this.pos + 1))) break digits;
        isDouble = true; text += '.'; this.pos++;
      } else if (c === 'e' || c === 'E') {
        isDouble = true; text += c; this.pos++;
        const s = this.peek;
        if (s === '+' || s === '-') { text += s; this.pos++; }
      } else break digits;
    }
    if (isDouble) {
      const d = Number(text);
      if (!/^\d+(\.\d+)?([eE][+-]?\d+)?$/.test(text) || Number.isNaN(d)) throw SwiftalkError.syntax(`invalid number literal '${text}'`);
      return tok.double(d);
    }
    const i = BigInt(text);
    if (i > INT_MAX_LITERAL) throw SwiftalkError.overflow(`integer literal '${text}' does not fit in Int`);
    return tok.int(i);
  }

  lexHexFloat() {
    const start = this.pos;
    let text = '0x';
    while (this.peek !== undefined && (isHexDigit(this.peek) || this.peek === '_')) { if (this.peek !== '_') text += this.peek; this.pos++; }
    if (this.peek === '.' && isHexDigit(this.at(this.pos + 1))) {
      const beforeFraction = this.pos;
      this.pos++;
      let fraction = '.';
      while (this.peek !== undefined && (isHexDigit(this.peek) || this.peek === '_')) { if (this.peek !== '_') fraction += this.peek; this.pos++; }
      if (this.peek === 'p' || this.peek === 'P') text += fraction;
      else this.pos = beforeFraction;
    }
    if (this.peek !== 'p' && this.peek !== 'P') { this.pos = start; return null; }
    text += 'p';
    this.pos++;
    let sign = '';
    if (this.peek === '+' || this.peek === '-') { sign = this.peek; text += sign; this.pos++; }
    let expDigits = '';
    while (this.peek !== undefined && (isDigit(this.peek) || this.peek === '_')) { if (this.peek !== '_') { expDigits += this.peek; } this.pos++; }
    if (!expDigits.length) throw SwiftalkError.syntax(`invalid hex-float literal '${text}'`);
    return parseHexFloat(text.slice(2), sign, expDigits);
  }

  lexInteger(radix) {
    let text = '';
    while (this.peek !== undefined && (isAlphabetic(this.peek) || isDigit(this.peek) || this.peek === '_')) {
      if (this.peek !== '_') text += this.peek;
      this.pos++;
    }
    const digitsFor = { 16: /^[0-9a-fA-F]+$/, 8: /^[0-7]+$/, 2: /^[01]+$/ }[radix];
    if (!text.length || !digitsFor.test(text)) throw SwiftalkError.syntax(`invalid integer literal for radix ${radix}: '${text}'`);
    const prefix = { 16: '0x', 8: '0o', 2: '0b' }[radix];
    const i = BigInt(prefix + text);
    if (i > INT_MAX_LITERAL) throw SwiftalkError.syntax(`invalid integer literal for radix ${radix}: '${text}'`);
    return i;
  }
}

/// `mantissa` is "1.fe" style hex digits (no 0x), exponent decimal.
function parseHexFloat(mantissaText, sign, expDigits) {
  const [whole, frac = ''] = mantissaText.replace(/p.*$/, '').split('.');
  let value = 0;
  for (const c of whole) value = value * 16 + parseInt(c, 16);
  let scale = 1 / 16;
  for (const c of frac) { value += parseInt(c, 16) * scale; scale /= 16; }
  const exp = parseInt(expDigits, 10) * (sign === '-' ? -1 : 1);
  return value * Math.pow(2, exp);
}
