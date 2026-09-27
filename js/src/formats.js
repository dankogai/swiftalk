// SION text, JSON, property lists (Formats.swift), and the string escapes.
import { SwiftalkError } from './errors.js';
import { parse } from './parser.js';
import { kindOf, typeName, sourceString, compareStrings, formatDouble, base64Encode, base64Decode,
  SArray, SDictionary, SSet, Byte, SData, SDate, TupleValue } from './value.js';
import { isSION } from './types.js';

/// Strings bare, everything else the source form — for the data formats' keys.
export const plainString = (v) => (typeof v === 'string' ? v : sourceString(v));

export const SIONFormat = {
  parse(text) {
    const program = parse(text);
    if (program.length !== 1 || program[0].k !== 'expression') throw SwiftalkError.type('SION(text) reads one value');
    return valueOf(program[0].expr);
  },
};
function valueOf(expr) {
  switch (expr.k) {
    case 'literal':
      if (!isSION(expr.v)) throw SwiftalkError.type(`not SION: ${sourceString(expr.v)}`);
      return expr.v;
    case 'unaryMinus':
      if (expr.e.k === 'literal' && typeof expr.e.v === 'bigint') return -expr.e.v;
      if (expr.e.k === 'literal' && typeof expr.e.v === 'number') return -expr.e.v;
      break;
    case 'unaryPlus':
      if (expr.e.k === 'literal') return expr.e.v;
      break;
    case 'array': return new SArray(expr.elements.map(valueOf));
    case 'dictionary': return new SDictionary(expr.pairs.map(([k, v]) => [valueOf(k), valueOf(v)]));
    case 'call':
      if (expr.callee.k === 'memberLiteral' && expr.args.length === 1 && expr.args[0].label === null) {
        const arg = valueOf(expr.args[0].expr);
        if (expr.callee.name === 'Date') {
          if (typeof arg === 'number') return new SDate(arg);
          if (typeof arg === 'bigint') return new SDate(Number(arg));
          throw SwiftalkError.type(`.Date() takes a number, not ${sourceString(arg)}`);
        }
        if (expr.callee.name === 'Data') {
          if (typeof arg !== 'string') throw SwiftalkError.type('.Data() takes a base64 String');
          const bytes = base64Decode(arg);
          if (bytes === null || arg.replace(/\s/g, '').length % 4 !== 0) throw SwiftalkError.type(`not base64: ${JSON.stringify(arg)}`);
          return new SData(bytes);
        }
      }
      break;
    default: break;
  }
  throw SwiftalkError.type('not SION: only literals, .Date(), and .Data() may appear');
}

/// A Set has no form in JSON or property lists: an array, sorted by source form.
export function setsAsArrays(v) {
  switch (kindOf(v)) {
    case 'set': return new SArray(v.values().map((x) => ({ key: sourceString(x), value: setsAsArrays(x) })).sort((a, b) => compareStrings(a.key, b.key)).map((e) => e.value));
    case 'array': return new SArray(v.items.map(setsAsArrays));
    case 'dictionary': return new SDictionary(v.entries().map(([k, x]) => [k, setsAsArrays(x)]));
    default: return v;
  }
}

export const JSONFormat = {
  emit(value, pretty = false) {
    const out = [];
    write(setsAsArrays(value), pretty ? 0 : null, out);
    return out.join('');
  },
  parse(text) {
    const p = new JSONParser(Array.from(text));
    p.skipSpace();
    const v = p.value();
    p.skipSpace();
    if (p.pos !== p.s.length) throw p.error('unexpected text after the value');
    return v;
  },
};
const newline = (depth, out) => { if (depth !== null) out.push('\n' + '  '.repeat(depth)); };
function write(value, depth, out) {
  switch (kindOf(value)) {
    case 'nil': out.push('null'); break;
    case 'bool': out.push(value ? 'true' : 'false'); break;
    case 'int': out.push(value.toString()); break;
    case 'byte': out.push(String(value.v)); break;
    case 'double':
      if (!Number.isFinite(value)) throw SwiftalkError.type(`JSON has no ${formatDouble(value)}`);
      out.push(formatDouble(value)); break;
    case 'string': out.push(jsonString(value)); break;
    case 'data': out.push(jsonString(base64Encode(value.bytes))); break;
    case 'date': out.push(formatDouble(value.epoch)); break;
    case 'array': {
      if (value.items.length === 0) { out.push('[]'); return; }
      out.push('[');
      value.items.forEach((e, i) => { if (i > 0) out.push(','); newline(depth === null ? null : depth + 1, out); write(e, depth === null ? null : depth + 1, out); });
      newline(depth, out); out.push(']'); break;
    }
    case 'dictionary': {
      if (value.size === 0) { out.push('{}'); return; }
      const pairs = value.entries().map(([k, v]) => ({ key: plainString(k), value: v })).sort((a, b) => compareStrings(a.key, b.key));
      out.push('{');
      pairs.forEach((p, i) => {
        if (i > 0) out.push(',');
        newline(depth === null ? null : depth + 1, out);
        out.push(jsonString(p.key), depth === null ? ':' : ': ');
        write(p.value, depth === null ? null : depth + 1, out);
      });
      newline(depth, out); out.push('}'); break;
    }
    default: throw SwiftalkError.type(`a ${typeName(value)} has no JSON form`);
  }
}
function jsonString(s) {
  let out = '"';
  for (const ch of s) {
    const cp = ch.codePointAt(0);
    switch (ch) {
      case '"': out += '\\"'; break;
      case '\\': out += '\\\\'; break;
      case '\n': out += '\\n'; break;
      case '\r': out += '\\r'; break;
      case '\t': out += '\\t'; break;
      case '\b': out += '\\b'; break;
      case '\f': out += '\\f'; break;
      default: out += cp < 0x20 ? '\\u' + cp.toString(16).padStart(4, '0') : ch;
    }
  }
  return out + '"';
}
class JSONParser {
  constructor(s) { this.s = s; this.pos = 0; }
  get peek() { return this.s[this.pos]; }
  error(what) { return SwiftalkError.type(`JSON: ${what} at ${this.pos}`); }
  skipSpace() { while (' \n\r\t'.includes(this.peek ?? 'x')) this.pos++; }
  expect(word) { for (const w of word) { if (this.peek !== w) throw this.error(`expected '${word}'`); this.pos++; } }
  value() {
    const c = this.peek;
    if (c === undefined) throw this.error('unexpected end');
    switch (c) {
      case 'n': this.expect('null'); return null;
      case 't': this.expect('true'); return true;
      case 'f': this.expect('false'); return false;
      case '"': return this.string();
      case '[': {
        this.pos++;
        const a = [];
        this.skipSpace();
        if (this.peek === ']') { this.pos++; return new SArray(a); }
        for (;;) {
          this.skipSpace(); a.push(this.value()); this.skipSpace();
          if (this.peek === ',') { this.pos++; continue; }
          if (this.peek === ']') { this.pos++; return new SArray(a); }
          throw this.error("expected ',' or ']'");
        }
      }
      case '{': {
        this.pos++;
        const d = new SDictionary([]);
        this.skipSpace();
        if (this.peek === '}') { this.pos++; return d; }
        for (;;) {
          this.skipSpace();
          if (this.peek !== '"') throw this.error('expected a String key');
          const k = this.string();
          this.skipSpace();
          if (this.peek !== ':') throw this.error("expected ':'");
          this.pos++; this.skipSpace();
          d.set(k, this.value());
          this.skipSpace();
          if (this.peek === ',') { this.pos++; continue; }
          if (this.peek === '}') { this.pos++; return d; }
          throw this.error("expected ',' or '}'");
        }
      }
      default:
        if (c === '-' || (c >= '0' && c <= '9')) return this.number();
        throw this.error(`unexpected '${c}'`);
    }
  }
  number() {
    const start = this.pos;
    let isDouble = false;
    const isDigit = (x) => x !== undefined && x >= '0' && x <= '9';
    if (this.peek === '-') this.pos++;
    if (!isDigit(this.peek)) throw this.error('expected a digit');
    if (this.peek === '0') this.pos++; else while (isDigit(this.peek)) this.pos++;
    if (this.peek === '.') { isDouble = true; this.pos++; if (!isDigit(this.peek)) throw this.error("expected a digit after '.'"); while (isDigit(this.peek)) this.pos++; }
    if (this.peek === 'e' || this.peek === 'E') { isDouble = true; this.pos++; if (this.peek === '+' || this.peek === '-') this.pos++; if (!isDigit(this.peek)) throw this.error('expected an exponent'); while (isDigit(this.peek)) this.pos++; }
    const text = this.s.slice(start, this.pos).join('');
    if (!isDouble) { const i = BigInt(text); if (i >= -(1n << 63n) && i <= (1n << 63n) - 1n) return i; }
    const d = Number(text);
    if (Number.isNaN(d)) throw this.error(`bad number '${text}'`);
    return d;
  }
  string() {
    this.pos++;
    let out = '';
    for (;;) {
      const c = this.peek;
      if (c === undefined) throw this.error('unterminated string');
      this.pos++;
      if (c === '"') return out;
      if (c === '\\') {
        const e = this.peek;
        if (e === undefined) throw this.error('unterminated escape');
        this.pos++;
        switch (e) {
          case '"': out += '"'; break; case '\\': out += '\\'; break; case '/': out += '/'; break;
          case 'b': out += '\b'; break; case 'f': out += '\f'; break; case 'n': out += '\n'; break;
          case 'r': out += '\r'; break; case 't': out += '\t'; break;
          case 'u': {
            let unit = this.hex4();
            if (unit >= 0xD800 && unit <= 0xDBFF) {
              if (this.peek !== '\\') throw this.error('lone surrogate'); this.pos++;
              if (this.peek !== 'u') throw this.error('lone surrogate'); this.pos++;
              const low = this.hex4();
              if (!(low >= 0xDC00 && low <= 0xDFFF)) throw this.error('bad surrogate pair');
              unit = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00);
            }
            if (unit >= 0xD800 && unit <= 0xDFFF) throw this.error('bad \\u escape');
            out += String.fromCodePoint(unit);
            break;
          }
          default: throw this.error(`unknown escape '\\${e}'`);
        }
        continue;
      }
      if (c.codePointAt(0) < 0x20) throw this.error('control character in a string');
      out += c;
    }
  }
  hex4() {
    let v = 0;
    for (let i = 0; i < 4; i++) {
      const c = this.peek;
      if (c === undefined || !/^[0-9a-fA-F]$/.test(c)) throw this.error('expected four hex digits');
      v = v * 16 + parseInt(c, 16);
      this.pos++;
    }
    return v;
  }
}

export const CivilDate = {
  iso8601(epoch) {
    const seconds = BigInt(Math.floor(epoch));
    const div = (a, b) => { const q = a / b; return (a % b !== 0n && (a < 0n) !== (b < 0n)) ? q - 1n : q; };
    const days = seconds >= 0n ? seconds / 86400n : (seconds - 86399n) / 86400n;
    const secondOfDay = seconds - days * 86400n;
    const z = days + 719468n;
    const era = (z >= 0n ? z : z - 146096n) / 146097n;
    const doe = z - era * 146097n;
    const yoe = (doe - doe / 1460n + doe / 36524n - doe / 146096n) / 365n;
    const y = yoe + era * 400n;
    const doy = doe - (365n * yoe + yoe / 4n - yoe / 100n);
    const mp = (5n * doy + 2n) / 153n;
    const d = doy - (153n * mp + 2n) / 5n + 1n;
    const m = mp < 10n ? mp + 3n : mp - 9n;
    const year = m <= 2n ? y + 1n : y;
    const pad = (v, w) => String(v).padStart(w, '0');
    void div;
    return `${pad(year, 4)}-${pad(m, 2)}-${pad(d, 2)}T${pad(secondOfDay / 3600n, 2)}:${pad((secondOfDay / 60n) % 60n, 2)}:${pad(secondOfDay % 60n, 2)}Z`;
  },
  epochFromISO8601(text) {
    const m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(\.\d+)?Z$/.exec(text);
    if (!m) return null;
    const [y, mo, d, hh, mm, ss] = m.slice(1, 7).map((x) => BigInt(x));
    if (!(mo >= 1n && mo <= 12n && d >= 1n && d <= 31n && hh < 24n && mm < 60n && ss < 61n)) return null;
    const fraction = m[7] ? Number('0' + m[7]) : 0;
    const yy = mo <= 2n ? y - 1n : y;
    const era = (yy >= 0n ? yy : yy - 399n) / 400n;
    const yoe = yy - era * 400n;
    const mp = mo > 2n ? mo - 3n : mo + 9n;
    const doy = (153n * mp + 2n) / 5n + d - 1n;
    const doe = yoe * 365n + yoe / 4n - yoe / 100n + doy;
    const days = era * 146097n + doe - 719468n;
    return Number(days * 86400n + hh * 3600n + mm * 60n + ss) + fraction;
  },
};

const plistHeader = '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n';
export const PlistXML = {
  emit(rawValue) {
    const value = setsAsArrays(rawValue);
    const out = [plistHeader];
    writePlist(value, 0, out);
    out.push('</plist>\n');
    return out.join('');
  },
  parse(text) {
    const p = new XMLParser(Array.from(text));
    p.skipProlog();
    const [name, empty] = p.openTag();
    if (name !== 'plist') throw p.error('expected <plist>');
    if (empty) throw p.error('an empty <plist/>');
    p.skipSpace();
    const v = p.element();
    p.skipSpace();
    p.closeTag('plist');
    return v;
  },
};
const xmlEscape = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
function writePlist(value, depth, out) {
  const tab = '\t'.repeat(depth);
  switch (kindOf(value)) {
    case 'nil': throw SwiftalkError.type('property lists have no nil');
    case 'bool': out.push(tab + (value ? '<true/>\n' : '<false/>\n')); break;
    case 'int': out.push(`${tab}<integer>${value}</integer>\n`); break;
    case 'byte': out.push(`${tab}<integer>${value.v}</integer>\n`); break;
    case 'double':
      if (!Number.isFinite(value)) throw SwiftalkError.type(`property lists have no ${formatDouble(value)}`);
      out.push(`${tab}<real>${formatDouble(value)}</real>\n`); break;
    case 'string': out.push(`${tab}<string>${xmlEscape(value)}</string>\n`); break;
    case 'data': out.push(`${tab}<data>${base64Encode(value.bytes)}</data>\n`); break;
    case 'date': out.push(`${tab}<date>${CivilDate.iso8601(value.epoch)}</date>\n`); break;
    case 'array':
      if (value.items.length === 0) { out.push(tab + '<array/>\n'); return; }
      out.push(tab + '<array>\n');
      for (const e of value.items) writePlist(e, depth + 1, out);
      out.push(tab + '</array>\n'); break;
    case 'dictionary': {
      if (value.size === 0) { out.push(tab + '<dict/>\n'); return; }
      const pairs = value.entries().map(([k, v]) => {
        if (typeof k !== 'string') throw SwiftalkError.type(`property-list keys are Strings, not ${typeName(k)}`);
        return [k, v];
      }).sort((a, b) => compareStrings(a[0], b[0]));
      out.push(tab + '<dict>\n');
      for (const [k, v] of pairs) { out.push(`${tab}\t<key>${xmlEscape(k)}</key>\n`); writePlist(v, depth + 1, out); }
      out.push(tab + '</dict>\n'); break;
    }
    default: throw SwiftalkError.type(`a ${typeName(value)} has no property-list form`);
  }
}
class XMLParser {
  constructor(s) { this.s = s; this.pos = 0; }
  get peek() { return this.s[this.pos]; }
  error(what) { return SwiftalkError.type(`property list: ${what} at ${this.pos}`); }
  starts(text) { for (let i = 0; i < text.length; i++) if (this.s[this.pos + i] !== text[i]) return false; return true; }
  skipSpace() {
    for (;;) {
      while (' \n\r\t'.includes(this.peek ?? 'x')) this.pos++;
      if (this.starts('<!--')) { this.pos += 4; while (this.pos < this.s.length && !this.starts('-->')) this.pos++; this.pos += 3; continue; }
      return;
    }
  }
  skipProlog() {
    this.skipSpace();
    while (this.starts('<?') || this.starts('<!')) {
      while (this.peek !== undefined && this.peek !== '>') this.pos++;
      if (this.peek !== '>') throw this.error('unterminated prolog');
      this.pos++; this.skipSpace();
    }
  }
  name() { let n = ''; while (this.peek !== undefined && !'>/ \n\t\r'.includes(this.peek)) { n += this.peek; this.pos++; } return n; }
  openTag() {
    if (this.peek !== '<') throw this.error("expected '<'");
    this.pos++;
    const n = this.name();
    if (!n) throw this.error('expected an element name');
    while (this.peek !== undefined && this.peek !== '>' && this.peek !== '/') this.pos++;
    let empty = false;
    if (this.peek === '/') { empty = true; this.pos++; }
    if (this.peek !== '>') throw this.error("expected '>'");
    this.pos++;
    return [n, empty];
  }
  closeTag(expected) {
    if (!this.starts('</')) throw this.error(`expected </${expected}>`);
    this.pos += 2;
    const n = this.name();
    if (n !== expected || this.peek !== '>') throw this.error(`expected </${expected}>`);
    this.pos++;
  }
  text(tag) {
    let out = '';
    while (this.peek !== undefined) {
      const c = this.peek;
      if (c === '<') break;
      this.pos++;
      if (c === '&') {
        let entity = '';
        while (this.peek !== undefined && this.peek !== ';') { entity += this.peek; this.pos++; }
        if (this.peek !== ';') throw this.error('unterminated entity');
        this.pos++;
        switch (entity) {
          case 'amp': out += '&'; break; case 'lt': out += '<'; break; case 'gt': out += '>'; break;
          case 'quot': out += '"'; break; case 'apos': out += "'"; break;
          default: {
            if (!entity.startsWith('#')) throw this.error(`unknown entity &${entity};`);
            const v = entity.startsWith('#x') ? parseInt(entity.slice(2), 16) : parseInt(entity.slice(1), 10);
            if (Number.isNaN(v) || v > 0x10FFFF) throw this.error(`unknown entity &${entity};`);
            out += String.fromCodePoint(v);
          }
        }
      } else out += c;
    }
    this.closeTag(tag);
    return out;
  }
  element() {
    const [n, empty] = this.openTag();
    switch (n) {
      case 'true': if (!empty) throw this.error('<true> is <true/>'); return true;
      case 'false': if (!empty) throw this.error('<false> is <false/>'); return false;
      case 'string': return empty ? '' : this.text('string');
      case 'integer': { const t = (empty ? '' : this.text('integer')).trim(); if (!/^[-+]?\d+$/.test(t)) throw this.error(`bad <integer> '${t}'`); return BigInt(t); }
      case 'real': { const t = (empty ? '' : this.text('real')).trim(); const d = Number(t); if (t === '' || Number.isNaN(d)) throw this.error(`bad <real> '${t}'`); return d; }
      case 'date': { const t = (empty ? '' : this.text('date')).trim(); const e = CivilDate.epochFromISO8601(t); if (e === null) throw this.error(`bad <date> '${t}'`); return new SDate(e); }
      case 'data': { const t = empty ? '' : this.text('data'); const b = base64Decode(t); if (b === null) throw this.error('bad <data>'); return new SData(b); }
      case 'array': {
        const a = [];
        if (empty) return new SArray(a);
        for (;;) { this.skipSpace(); if (this.starts('</')) { this.closeTag('array'); return new SArray(a); } a.push(this.element()); }
      }
      case 'dict': {
        const d = new SDictionary([]);
        if (empty) return d;
        for (;;) {
          this.skipSpace();
          if (this.starts('</')) { this.closeTag('dict'); return d; }
          const [kn, kempty] = this.openTag();
          if (kn !== 'key') throw this.error('expected <key>');
          const key = kempty ? '' : this.text('key');
          this.skipSpace();
          d.set(key, this.element());
        }
      }
      default: throw this.error(`unknown element <${n}>`);
    }
  }
}

export const PlistBinary = {
  emit(rawValue) {
    const value = setsAsArrays(rawValue);
    const objects = [];
    const sortedEntries = (d) => d.entries().sort((a, b) => compareStrings(plainString(a[0]), plainString(b[0])));
    const flatten = (v) => {
      objects.push(v);
      switch (kindOf(v)) {
        case 'nil': throw SwiftalkError.type('property lists have no nil');
        case 'bool': case 'int': case 'double': case 'string': case 'data': case 'date': break;
        case 'array': for (const e of v.items) flatten(e); break;
        case 'dictionary':
          for (const [k] of v.entries()) if (typeof k !== 'string') throw SwiftalkError.type(`property-list keys are Strings, not ${typeName(k)}`);
          for (const [k, x] of sortedEntries(v)) { flatten(k); flatten(x); }
          break;
        default: throw SwiftalkError.type(`a ${typeName(v)} has no property-list form`);
      }
    };
    flatten(value);
    const refSize = byteSize(objects.length);
    const out = [...new TextEncoder().encode('bplist00')];
    const offsets = [];
    const size = (v) => {
      switch (kindOf(v)) {
        case 'array': return 1 + v.items.reduce((s, e) => s + size(e), 0);
        case 'dictionary': return 1 + v.entries().reduce((s, [, x]) => s + 1 + size(x), 0);
        default: return 1;
      }
    };
    const childIndices = (v, index) => {
      const result = [];
      let next = index + 1;
      if (kindOf(v) === 'array') for (const e of v.items) { result.push(next); next += size(e); }
      else if (kindOf(v) === 'dictionary') {
        const keys = [], values = [];
        for (const [, x] of sortedEntries(v)) { keys.push(next); next += 1; values.push(next); next += size(x); }
        result.push(...keys, ...values);
      }
      return result;
    };
    objects.forEach((v, index) => {
      offsets.push(out.length);
      switch (kindOf(v)) {
        case 'bool': out.push(v ? 0x09 : 0x08); break;
        case 'int':
          if (v >= 0n && v <= 255n) out.push(0x10, Number(v));
          else if (v >= 0n && v <= 65535n) out.push(0x11, ...bigEndian(v, 2));
          else if (v >= 0n && v <= 4294967295n) out.push(0x12, ...bigEndian(v, 4));
          else out.push(0x13, ...bigEndian(BigInt.asUintN(64, v), 8));
          break;
        case 'double': {
          if (!Number.isFinite(v)) throw SwiftalkError.type(`property lists have no ${formatDouble(v)}`);
          out.push(0x23, ...doubleBytes(v)); break;
        }
        case 'date': out.push(0x33, ...doubleBytes(v.epoch - 978307200)); break;
        case 'data': out.push(...marker(0x40, v.bytes.length), ...v.bytes); break;
        case 'string': {
          const utf8 = new TextEncoder().encode(v);
          if (utf8.every((b) => b < 0x80)) out.push(...marker(0x50, utf8.length), ...utf8);
          else { const units = []; for (let i = 0; i < v.length; i++) units.push(v.charCodeAt(i)); out.push(...marker(0x60, units.length)); for (const u of units) out.push(...bigEndian(BigInt(u), 2)); }
          break;
        }
        case 'array': out.push(...marker(0xA0, v.items.length)); for (const c of childIndices(v, index)) out.push(...bigEndian(BigInt(c), refSize)); break;
        case 'dictionary': out.push(...marker(0xD0, v.size)); for (const c of childIndices(v, index)) out.push(...bigEndian(BigInt(c), refSize)); break;
        default: break;
      }
    });
    const offsetTableOffset = out.length;
    const offsetSize = byteSize(offsetTableOffset);
    for (const o of offsets) out.push(...bigEndian(BigInt(o), offsetSize));
    out.push(0, 0, 0, 0, 0, 0, offsetSize, refSize, ...bigEndian(BigInt(objects.length), 8), ...bigEndian(0n, 8), ...bigEndian(BigInt(offsetTableOffset), 8));
    return new SData(out);
  },
  parse(data) {
    const bytes = data instanceof Uint8Array ? data : data.bytes;
    const fail = (what) => SwiftalkError.type(`binary property list: ${what}`);
    if (bytes.length < 40 || new TextDecoder().decode(bytes.slice(0, 7)) !== 'bplist0') throw fail('not a bplist00');
    const readBE = (at, size) => {
      if (at < 0 || at + size > bytes.length) throw fail('truncated');
      let v = 0n;
      for (let i = 0; i < size; i++) v = (v << 8n) | BigInt(bytes[at + i]);
      return v;
    };
    const trailer = bytes.length - 32;
    const offsetSize = bytes[trailer + 6], refSize = bytes[trailer + 7];
    const count = Number(readBE(trailer + 8, 8)), top = Number(readBE(trailer + 16, 8)), tableOffset = Number(readBE(trailer + 24, 8));
    if (!(offsetSize >= 1 && offsetSize <= 8 && refSize >= 1 && refSize <= 8 && count > 0 && top < count)) throw fail('bad trailer');
    const offsets = [];
    for (let i = 0; i < count; i++) offsets.push(Number(readBE(tableOffset + i * offsetSize, offsetSize)));
    const visiting = new Set();
    const object = (index) => {
      if (index >= count) throw fail('bad object reference');
      if (visiting.has(index)) throw fail('cyclic reference');
      visiting.add(index);
      try {
        let p = offsets[index];
        if (p >= bytes.length) throw fail('bad offset');
        const mk = bytes[p]; p++;
        const type = mk & 0xF0;
        let n = mk & 0x0F;
        const readCount = () => {
          if (n === 0x0F) {
            if (p >= bytes.length || (bytes[p] & 0xF0) !== 0x10) throw fail('bad count');
            const size = 1 << (bytes[p] & 0x0F);
            n = Number(readBE(p + 1, size));
            p += 1 + size;
          }
        };
        switch (type) {
          case 0x00:
            if (mk === 0x08) return false;
            if (mk === 0x09) return true;
            throw fail(`unsupported marker ${mk}`);
          case 0x10: { const size = 1 << n; const raw = readBE(p, size); return size === 8 ? BigInt.asIntN(64, raw) : raw; }
          case 0x20: {
            const size = 1 << n;
            if (size !== 8 && size !== 4) throw fail('unsupported real size');
            const view = new DataView(new ArrayBuffer(8));
            const raw = readBE(p, size);
            if (size === 8) { view.setBigUint64(0, raw); return view.getFloat64(0); }
            view.setUint32(0, Number(raw)); return view.getFloat32(0);
          }
          case 0x30: { if (n !== 3) throw fail('unsupported date size'); const view = new DataView(new ArrayBuffer(8)); view.setBigUint64(0, readBE(p, 8)); return new SDate(view.getFloat64(0) + 978307200); }
          case 0x40: readCount(); if (p + n > bytes.length) throw fail('truncated data'); return new SData(bytes.slice(p, p + n));
          case 0x50: readCount(); if (p + n > bytes.length) throw fail('truncated string'); return new TextDecoder().decode(bytes.slice(p, p + n));
          case 0x60: { readCount(); let s = ''; for (let i = 0; i < n; i++) s += String.fromCharCode(Number(readBE(p + 2 * i, 2))); return s; }
          case 0xA0: { readCount(); const a = []; for (let i = 0; i < n; i++) a.push(object(Number(readBE(p + i * refSize, refSize)))); return new SArray(a); }
          case 0xD0: {
            readCount();
            const d = new SDictionary([]);
            for (let i = 0; i < n; i++) {
              const k = object(Number(readBE(p + i * refSize, refSize)));
              const v = object(Number(readBE(p + (n + i) * refSize, refSize)));
              d.set(k, v);
            }
            return d;
          }
          default: throw fail(`unsupported marker ${mk}`);
        }
      } finally { visiting.delete(index); }
    };
    return object(top);
  },
};
const byteSize = (n) => (n <= 0xFF ? 1 : n <= 0xFFFF ? 2 : n <= 0xFFFFFFFF ? 4 : 8);
function bigEndian(v, size) { const out = []; for (let i = size - 1; i >= 0; i--) out.push(Number((v >> BigInt(8 * i)) & 0xFFn)); return out; }
function doubleBytes(d) { const view = new DataView(new ArrayBuffer(8)); view.setFloat64(0, d); return Array.from(new Uint8Array(view.buffer)); }
function marker(type, count) {
  if (count < 15) return [type | count];
  const out = [type | 0x0F];
  if (count <= 0xFF) out.push(0x10, ...bigEndian(BigInt(count), 1));
  else if (count <= 0xFFFF) out.push(0x11, ...bigEndian(BigInt(count), 2));
  else if (count <= 0xFFFFFFFF) out.push(0x12, ...bigEndian(BigInt(count), 4));
  else out.push(0x13, ...bigEndian(BigInt(count), 8));
  return out;
}

export const StringEscapes = {
  escaped(s) {
    let out = '';
    for (const ch of s) {
      const cp = ch.codePointAt(0);
      if (ch === '\\') out += '\\\\';
      else if (cp < 0x80) out += ch;
      else out += '\\u{' + cp.toString(16) + '}';
    }
    return out;
  },
  unescaped(s) {
    const chars = Array.from(s);
    let out = '';
    for (let i = 0; i < chars.length; i++) {
      const c = chars[i];
      if (c !== '\\') { out += c; continue; }
      const e = chars[++i];
      if (e === undefined) throw SwiftalkError.type('unescaped: a trailing backslash');
      switch (e) {
        case '\\': out += '\\'; break; case 'n': out += '\n'; break; case 't': out += '\t'; break;
        case 'r': out += '\r'; break; case '0': out += '\0'; break; case '"': out += '"'; break; case "'": out += "'"; break;
        case 'u': {
          if (chars[++i] !== '{') throw SwiftalkError.type('unescaped: \\u needs {hex}');
          let hex = '';
          while (++i < chars.length && chars[i] !== '}') hex += chars[i];
          const v = parseInt(hex, 16);
          if (!hex.length || hex.length > 8 || !/^[0-9a-fA-F]+$/.test(hex) || v > 0x10FFFF || (v >= 0xD800 && v <= 0xDFFF)) throw SwiftalkError.type(`unescaped: invalid unicode escape \\u{${hex}}`);
          out += String.fromCodePoint(v);
          break;
        }
        default: throw SwiftalkError.type(`unescaped: unknown escape \\${e}`);
      }
    }
    return out;
  },
};
