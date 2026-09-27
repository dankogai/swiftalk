// swiftalk's errors (Core/Sources/Swiftalk/Lexer.swift): one class, five
// kinds, the same descriptions the Swift core prints.
export class SwiftalkError extends Error {
  constructor(kind, message) {
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
  static syntax(m) { return new SwiftalkError('syntax', m); }
  static type(m) { return new SwiftalkError('type', m); }
  static overflow(m) { return new SwiftalkError('overflow', m); }
  static zeroDivision() { return new SwiftalkError('zeroDivision', ''); }
  static unknownMember(m) { return new SwiftalkError('unknownMember', m); }
}
