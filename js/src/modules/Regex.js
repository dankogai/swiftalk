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
import { kindOf, typeName, SArray, TupleValue } from '../value.js';
import { HostValue } from '../objects.js';
import { ann } from '../types.js';
import { apply } from '../eval.js';

/// `x`: free-spacing — whitespace and `#` comments outside classes are not pattern.
function stripExtended(pattern) {
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
function groupLabels(pattern) {
  const labels = [null];
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
const looseProperties = (pattern) => pattern.replace(/\\([pP])\{([A-Za-z][A-Za-z0-9]*)\}/g, (all, pP, name) => {
  const snake = name.replace(/([a-z0-9])([A-Z])/g, '$1_$2');
  for (const candidate of [name, snake, `Script=${name}`, `Script=${snake}`]) {
    try { new RegExp(`\\p{${candidate}}`, 'u'); return `\\${pP}{${candidate}}`; } catch (e) { /* next */ }
  }
  return all;
});

export class RegexValue {
  constructor(pattern, flags) {
    for (const f of flags) if (!'imsx'.includes(f)) throw SwiftalkError.syntax(`unknown regex flag '${f}' — i, m, s, x are the flags`);
    this.pattern = pattern;
    this.flags = [...new Set(flags)].sort().join('');
    const source = this.flags.includes('x') ? stripExtended(pattern) : pattern;
    const jsFlags = 'u' + this.flags.replace(/x/g, '');
    let re;
    try { re = new RegExp(source, jsFlags); }
    catch (e1) {
      try { re = new RegExp(looseProperties(source), jsFlags); }
      catch (e2) { throw SwiftalkError.syntax(`invalid regex /${pattern}/: ${e1.message.replace(/^Invalid regular expression: /, '')}`); }
    }
    this.source = re.source;
    this.jsFlags = jsFlags;
    this.labels = groupLabels(source);
    this.typeName = 'Regex';
  }
  re(extra = '') { return new RegExp(this.source, this.jsFlags + extra); }
  /// A match: the matched String when the regex has no groups; else a
  /// tuple — `.0` the whole match, then the groups, named where named,
  /// nil where one did not take part.
  matchValue(m) {
    if (this.labels.length === 1) return m[0];
    return new TupleValue(this.labels.map((_, i) => (m[i] === undefined ? null : m[i])), this.labels);
  }
  *allMatches(s) {
    const g = this.re('g');
    for (;;) {
      const m = g.exec(s);
      if (!m) return;
      yield m;
      if (m[0] === '') g.lastIndex++;
    }
  }
  wholeMatch(s) {
    const anchored = new RegExp(`^(?:${this.source})$`, this.jsFlags);
    const m = anchored.exec(s);
    return m ? this.matchValue(m) : null;
  }
  member(name, args, called) {
    if (name === 'pattern' && !called) return this.pattern;
    if (name === 'flags' && !called) return this.flags;
    return undefined;                                          // declined
  }
  isEqual(other) { return other instanceof RegexValue && other.pattern === this.pattern && other.flags === this.flags; }
  hashKey() { return `Regex:${this.pattern}/${this.flags}`; }
  sourceString() { return '/' + this.pattern.replace(/\//g, '\\/') + '/' + this.flags; }
  /// `case /re/:` matches a String whole; a non-String subject is no match — and, as a binding's source, an error.
  patternMatch(subject, binding) {
    if (typeof subject !== 'string') {
      if (binding) throw SwiftalkError.type(`a Regex case needs a String subject, not ${typeName(subject)}`);
      return null;
    }
    return this.wholeMatch(subject.normalize('NFC'));
  }
}
const regexOf = (v) => (kindOf(v) === 'host' && v.object instanceof RegexValue ? v.object : null);

export function RegexModule() {
  const m = new Module('Regex');
  let typeValue = null;
  const host = (r) => new HostValue(r, typeValue);
  typeValue = m.type('Regex', (args) => {
    switch (args.length) {
      case 1: {
        const r = regexOf(args[0]);
        if (r) return args[0];
        if (typeof args[0] !== 'string') throw SwiftalkError.type(`cannot convert ${typeName(args[0])} to Regex`);
        return host(new RegexValue(args[0], ''));
      }
      case 2:
        if (typeof args[0] !== 'string' || typeof args[1] !== 'string') throw SwiftalkError.type('Regex(pattern, flags) takes two Strings');
        return host(new RegexValue(args[0], args[1]));
      default: throw SwiftalkError.type('Regex(pattern) — or write the literal /pattern/');
    }
  }).value('Regex');
  const nfc = (s) => s.normalize('NFC');
  m.extend('String', 'contains', (receiver, args, called) => {
    if (!called || args.length !== 1 || typeof receiver !== 'string') return undefined;
    const r = regexOf(args[0]);
    return r ? r.re().test(nfc(receiver)) : undefined;
  });
  for (const name of ['firstMatch', 'wholeMatch', 'matches']) {
    m.extend('String', name, (receiver, args, called) => {
      if (!called || typeof receiver !== 'string') return undefined;
      const r = args.length === 1 ? regexOf(args[0]) : null;
      if (!r) throw SwiftalkError.type(`.${name} takes a Regex: s.${name}(/re/)`);
      const s = nfc(receiver);
      if (name === 'firstMatch') { const found = r.re().exec(s); return found ? r.matchValue(found) : null; }
      if (name === 'wholeMatch') return r.wholeMatch(s);
      return new SArray([...r.allMatches(s)].map((x) => r.matchValue(x)));
    });
  }
  m.extend('String', 'replacing', function* (receiver, args, called) {
    if (!called || typeof receiver !== 'string' || args.length !== 2) return undefined;
    const r = regexOf(args[0]);
    if (!r) return undefined;
    const s = nfc(receiver);
    if (typeof args[1] === 'string') { const with_ = args[1]; return s.replace(r.re('g'), () => with_); }
    if (kindOf(args[1]) === 'function') {
      let out = '', cursor = 0;
      for (const found of r.allMatches(s)) {
        out += s.slice(cursor, found.index);
        const piece = yield* apply(args[1], [{ label: null, value: r.matchValue(found) }]);
        if (typeof piece !== 'string') throw SwiftalkError.type('the .replacing Function must return a String');
        out += piece;
        cursor = found.index + found[0].length;
      }
      return out + s.slice(cursor);
    }
    throw SwiftalkError.type('.replacing takes what to find (a Regex or a String) and the replacement (a String, or a Function of the match)');
  });
  m.extend('String', 'split', (receiver, args, called) => {
    if (!called || typeof receiver !== 'string' || args.length !== 1) return undefined;
    const r = regexOf(args[0]);
    if (!r) return undefined;
    const s = nfc(receiver);
    const pieces = [];
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
