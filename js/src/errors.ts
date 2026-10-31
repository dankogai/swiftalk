// swiftalk's errors (Core/Sources/Swiftalk/Lexer.swift): one class, five
// kinds, the same descriptions the Swift core prints.
export type ErrorKind = 'syntax' | 'type' | 'overflow' | 'zeroDivision' | 'unknownMember';

export class SwiftalkError extends Error {
  kind: ErrorKind;
  detail: string;
  /// set when the message is a host's (a rejected Promise), so `fetch` reports it bare
  fromHost = false;
  constructor(kind: ErrorKind, message: string) {
    super(message);
    this.kind = kind;
    this.detail = message;
  }
  get description() {
    switch (this.kind) {
      case 'syntax': return `syntax error: ${this.detail}`;
      case 'type': return `type error: ${this.detail}`;
      case 'overflow': return `overflow: ${this.detail}`;
      case 'zeroDivision': return 'division by zero';
      case 'unknownMember': return `unknown member: ${this.detail}`;
      default: return this.detail;
    }
  }
  toString() { return this.description; }
  static syntax(m: string) { return new SwiftalkError('syntax', m); }
  static type(m: string) { return new SwiftalkError('type', m); }
  static overflow(m: string) { return new SwiftalkError('overflow', m); }
  static zeroDivision() { return new SwiftalkError('zeroDivision', ''); }
  static unknownMember(m: string) { return new SwiftalkError('unknownMember', m); }
}
