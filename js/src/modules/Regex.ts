// `Regex` — regular expressions (round 186's module, in JavaScript). The
// grammar of the literal, `/pattern/flags`, is the core's; its meaning is
// here: the `Regex` type this module exports is what the literal calls,
// and String gains the members that take one — contains, firstMatch,
// wholeMatch, matches, replacing, split — the core's own answering when
// the argument is not a Regex. The engine is JavaScript's RegExp with the
// `u` flag, so the syntax is JS's where Swift's differs; the flags are
// Swift's `i`, `m`, `s`, `x` (`x` emulated: whitespace and `#` comments
// stripped outside character classes). Matching is over the NFC form of
// the subject, so canonically equivalent Strings match alike.
//
// FIXME: Swift's Regex matches Characters (grapheme clusters) — `.` is one
// grapheme, a class matches a whole grapheme or not at all — while RegExp
// matches code points: "👨‍👩‍👧".matches(/./).count is 1 in Swift and 5 here.
import { SwiftalkError } from '../errors.js';
import { Module } from '../modules.js';
import { typeName, SArray, TupleValue, isHost, isString, isFunction } from '../value.js';
import { HostValue } from '../objects.js';
import { ann } from '../types.js';
import { apply } from '../eval.js';
import type { Value } from '../value.js';
import type { HostObject, G } from '../objects.js';

/// `x`: free-spacing — whitespace and `#` comments outside classes are not pattern.
function stripExtended(pattern: string): string {
  let out = '', inClass = false;
  for (let i = 0; i < pattern.length; i++) {
    const c = pattern[i];
    if (c === '\\') { out += c + (pattern[i + 1] ?? ''); i++; continue; }
    if (inClass) { if (c === ']') inClass = false; out += c; continue; }
    if (c === '[') { inClass = true; out += c; continue; }
    if (c === '#') { while (i < pattern.length && pattern[i] !== '\n') i++; continue; }
    if (c === ' ' || c === '\t' || c === '\n' || c === '\r') continue;
    out += c;
  }
  return out;
}
/// The capture groups in order: a name for `(?<name>...)`, null for a plain `(...)`.
function groupLabels(pattern: string): (string | null)[] {
  const labels: (string | null)[] = [null];
  let inClass = false;
  for (let i = 0; i < pattern.length; i++) {
    const c = pattern[i];
    if (c === '\\') { i++; continue; }
    if (inClass) { if (c === ']') inClass = false; continue; }
    if (c === '[') { inClass = true; continue; }
    if (c !== '(') continue;
    if (pattern[i + 1] !== '?') { labels.push(null); continue; }
    const m = /^\(\?<([A-Za-z_$][\w$]*)>/.exec(pattern.slice(i));
    if (m) labels.push(m[1]);
  }
  return labels;
}
/// Swift spells Unicode properties loosely — `\p{RegionalIndicator}`,
/// `\p{Hiragana}` — where RegExp wants `\p{Regional_Indicator}` and
/// `\p{Script=Hiragana}`: each `\p{Name}` that RegExp rejects is retried
/// with underscores between the words, then as a Script.
const looseProperties = (pattern: string): string => pattern.replace(/\\([pP])\{([A-Za-z][A-Za-z0-9]*)\}/g, (all: string, pP: string, name: string) => {
  const snake = name.replace(/([a-z0-9])([A-Z])/g, '$1_$2');
  for (const candidate of [name, snake, `Script=${name}`, `Script=${snake}`]) {
    try { new RegExp(`\\p{${candidate}}`, 'u'); return `\\${pP}{${candidate}}`; } catch (e) { /* next */ }
  }
  return all;
});

export class RegexValue implements HostObject {
  pattern: string;
  flags: string;
  source: string;
  jsFlags: string;
  labels: (string | null)[];
  typeName: string;
  constructor(pattern: string, flags: string) {
    for (const f of flags) if (!'imsx'.includes(f)) throw SwiftalkError.syntax(`unknown regex flag '${f}' — i, m, s, x are the flags`);
    this.pattern = pattern;
    this.flags = [...new Set(flags)].sort().join('');
    const source = this.flags.includes('x') ? stripExtended(pattern) : pattern;
    const jsFlags = 'u' + this.flags.replace(/x/g, '');
    let re: RegExp;
    try { re = new RegExp(source, jsFlags); }
    catch (e1) {
      try { re = new RegExp(looseProperties(source), jsFlags); }
      catch (e2) { throw SwiftalkError.syntax(`invalid regex /${pattern}/: ${(e1 instanceof Error ? e1.message : String(e1)).replace(/^Invalid regular expression: /, '')}`); }
    }
    this.source = re.source;
    this.jsFlags = jsFlags;
    this.labels = groupLabels(source);
    this.typeName = 'Regex';
  }
  re(extra = ''): RegExp { return new RegExp(this.source, this.jsFlags + extra); }
  /// A match: the matched String when the regex has no groups; else a
  /// tuple — `.0` the whole match, then the groups, named where named,
  /// nil where one did not take part.
  matchValue(m: RegExpExecArray): Value {
    if (this.labels.length === 1) return m[0];
    return new TupleValue(this.labels.map((_, i) => (m[i] === undefined ? null : m[i])), this.labels);
  }
  *allMatches(s: string): Generator<RegExpExecArray, void, undefined> {
    const g = this.re('g');
    for (;;) {
      const m = g.exec(s);
      if (!m) return;
      yield m;
      if (m[0] === '') g.lastIndex++;
    }
  }
  wholeMatch(s: string): Value {
    const anchored = new RegExp(`^(?:${this.source})$`, this.jsFlags);
    const m = anchored.exec(s);
    return m ? this.matchValue(m) : null;
  }
  member(name: string, args: Value[], called: boolean): Value | undefined {
    if (name === 'pattern' && !called) return this.pattern;
    if (name === 'flags' && !called) return this.flags;
    return undefined;                                          // declined
  }
  isEqual(other: HostObject): boolean { return other instanceof RegexValue && other.pattern === this.pattern && other.flags === this.flags; }
  hashKey(): string { return `Regex:${this.pattern}/${this.flags}`; }
  sourceString(): string { return '/' + this.pattern.replace(/\//g, '\\/') + '/' + this.flags; }
  /// `case /re/:` matches a String whole; a non-String subject is no match — and, as a binding's source, an error.
  patternMatch(subject: Value, binding: boolean): Value {
    if (!isString(subject)) {
      if (binding) throw SwiftalkError.type(`a Regex case needs a String subject, not ${typeName(subject)}`);
      return null;
    }
    return this.wholeMatch(subject.normalize('NFC'));
  }
}
const regexOf = (v: Value | undefined): RegexValue | null => (isHost(v) && v.object instanceof RegexValue ? v.object : null);

export function RegexModule(): Module {
  const m = new Module('Regex');
  let typeValue: Value = null;
  const host = (r: RegexValue): HostValue => new HostValue(r, typeValue);
  typeValue = m.type('Regex', (args: Value[]) => {
    const [pattern, flags] = args;
    switch (args.length) {
      case 1: {
        if (regexOf(pattern)) return pattern;
        if (!isString(pattern)) throw SwiftalkError.type(`cannot convert ${typeName(pattern)} to Regex`);
        return host(new RegexValue(pattern, ''));
      }
      case 2:
        if (!isString(pattern) || !isString(flags)) throw SwiftalkError.type('Regex(pattern, flags) takes two Strings');
        return host(new RegexValue(pattern, flags));
      default: throw SwiftalkError.type('Regex(pattern) — or write the literal /pattern/');
    }
  }).exported('Regex');
  const nfc = (s: string): string => s.normalize('NFC');
  m.extend('String', 'contains', (receiver: Value, args: Value[], called: boolean) => {
    if (!called || args.length !== 1 || !isString(receiver)) return undefined;
    const r = regexOf(args[0]);
    return r ? r.re().test(nfc(receiver)) : undefined;
  });
  for (const name of ['firstMatch', 'wholeMatch', 'matches']) {
    m.extend('String', name, (receiver: Value, args: Value[], called: boolean) => {
      if (!called || !isString(receiver)) return undefined;
      const r = args.length === 1 ? regexOf(args[0]) : null;
      if (!r) throw SwiftalkError.type(`.${name} takes a Regex: s.${name}(/re/)`);
      const s = nfc(receiver);
      if (name === 'firstMatch') { const found = r.re().exec(s); return found ? r.matchValue(found) : null; }
      if (name === 'wholeMatch') return r.wholeMatch(s);
      return new SArray([...r.allMatches(s)].map((x) => r.matchValue(x)));
    });
  }
  m.extend('String', 'replacing', function* (receiver: Value, args: Value[], called: boolean): G<Value | undefined> {
    if (!called || !isString(receiver) || args.length !== 2) return undefined;
    const r = regexOf(args[0]);
    if (!r) return undefined;
    const s = nfc(receiver);
    const replacement = args[1];
    if (isString(replacement)) return s.replace(r.re('g'), () => replacement);
    if (isFunction(replacement)) {
      let out = '', cursor = 0;
      for (const found of r.allMatches(s)) {
        out += s.slice(cursor, found.index);
        const piece = yield* apply(replacement, [{ label: null, value: r.matchValue(found) }]);
        if (typeof piece !== 'string') throw SwiftalkError.type('the .replacing Function must return a String');
        out += piece;
        cursor = found.index + found[0].length;
      }
      return out + s.slice(cursor);
    }
    throw SwiftalkError.type('.replacing takes what to find (a Regex or a String) and the replacement (a String, or a Function of the match)');
  });
  m.extend('String', 'split', (receiver: Value, args: Value[], called: boolean) => {
    if (!called || !isString(receiver) || args.length !== 1) return undefined;
    const r = regexOf(args[0]);
    if (!r) return undefined;
    const s = nfc(receiver);
    const pieces: string[] = [];
    let cursor = 0;
    for (const found of r.allMatches(s)) {
      if (found[0] === '') continue;
      pieces.push(s.slice(cursor, found.index));
      cursor = found.index + found[0].length;
    }
    pieces.push(s.slice(cursor));
    return new SArray(pieces.filter((p) => p !== ''), ann('Array', false, [ann('String')]));
  });
  return m;
}
