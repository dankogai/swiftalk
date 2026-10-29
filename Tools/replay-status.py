#!/usr/bin/env python3
# Replays every REPL transcript in Status.md against the current build
# (round 214): each ```text block's `swiftalk> ` lines are fed to
# .build/debug/swiftalk as one session, and the output is diffed against
# the transcript. Run from the repository root after `swift build`:
#
#     python3 tools/replay-status.py
#
# What it cannot replay, and reports as mismatches to read past: inputs
# that continue onto the next line without a bracket open (the REPL's
# trailing-operator rule), multi-line strings, blocks that use a binding
# from an earlier block, blocks taken from the JS REPL or under
# --no-prelude, and anything volatile — the clock, random numbers, the
# network, the module path. Everything else that differs is stale.
import re, subprocess, sys, os
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
lines = open(os.path.join(root, 'Status.md')).read().split('\n')

def strip_comment(l):
    # a trailing annotation: two or more spaces then //, or a line that is only a comment
    m = re.match(r'^(.*?)(\s{2,}//.*)$', l)
    return m.group(1).rstrip() if m else l
def depth_after(text, depth):
    # bracket depth after this text, strings skipped roughly
    in_str = None; esc = False
    i = 0
    while i < len(text):
        c = text[i]
        if in_str:
            if esc: esc = False
            elif c == '\\': esc = True
            elif c == in_str: in_str = None
        else:
            if c == '/' and text[i:i+2] == '//': break
            if c in '"': in_str = c
            elif c in '([{': depth += 1
            elif c in ')]}': depth -= 1
        i += 1
    return depth

blocks = []
i = 0
while i < len(lines):
    if lines[i].strip() == '```text':
        start = i + 1; j = start
        while j < len(lines) and lines[j].strip() != '```': j += 1
        body = lines[start:j]
        flags = []; entries = []; k = 0
        while k < len(body):
            l = body[k]
            if l.startswith('$ '):
                if '--no-prelude' in l: flags = ['--no-prelude']
                k += 1; continue
            if l.startswith('swiftalk> '):
                cmd = l[len('swiftalk> '):]; k += 1
                d = depth_after(cmd, 0)
                while d > 0 and k < len(body) and not body[k].startswith('swiftalk> '):
                    cmd += '\n' + body[k]; d = depth_after(body[k], d); k += 1
                out = []
                while k < len(body) and not body[k].startswith('swiftalk> ') and not body[k].startswith('$ '):
                    out.append(strip_comment(body[k])); k += 1
                entries.append((cmd, out, start + 1 + k))
            else:
                k += 1
        if entries and not any('npm test' in l for l in body):
            blocks.append((start + 1, flags, entries))
        i = j + 1
    else:
        i += 1
print(f'{len(blocks)} blocks, {sum(len(b[2]) for b in blocks)} prompts', file=sys.stderr)
volatile = re.compile(r'Date\(\)|random|fetch|getpid|environ|uname|getcwd|sleep|Task|async|await|IO\(path|readFile|writeFile|open\(|/tmp/|stat\(|readdir|POSIX')
mismatches = 0; order_only = 0; flagged = []
for start, flags, entries in blocks:
    program = '\nprint("MARK")\n'.join(cmd for cmd, _, _ in entries) + '\n'
    r = subprocess.run([os.path.join(root, '.build/debug/swiftalk')] + flags, input=program, capture_output=True, text=True, timeout=120)
    segs = r.stdout.split('MARK\n')
    err_lines = [l for l in r.stderr.split('\n') if l]
    for (cmd, expected, _), actual in zip(entries, segs):
        exp = '\n'.join(expected).rstrip('\n'); act = actual.rstrip('\n')
        if exp == act: continue
        exp_lines = [l for l in exp.split('\n') if l]; act_lines = [l for l in act.split('\n') if l]
        # stderr lines (debugPrint) may belong to this segment: accept if the difference is exactly stderr lines
        missing = [l for l in exp_lines if l not in act_lines]
        if missing and all(l in err_lines for l in missing) and all(l in exp_lines for l in act_lines):
            order_only += 1; continue
        mismatches += 1
        tag = ' [volatile]' if volatile.search(cmd) else ''
        flagged.append(f'--- line ~{start}{tag}: swiftalk> ' + cmd.replace('\n', '\n            ') + '\n    expected: ' + exp.replace('\n', '\n              ') + '\n    got:      ' + act.replace('\n', '\n              '))
print('\n'.join(flagged))
print(f'{mismatches} mismatches ({order_only} stderr-order only, accepted)', file=sys.stderr)
