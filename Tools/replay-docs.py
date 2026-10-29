#!/usr/bin/env python3
# Runs every ```swift block in documents/*.md against the current build
# (round 215): the block's statements (grouped by bracket balance) are fed
# to .build/debug/swiftalk as one session; a line whose trailing `// ...`
# comment reads as a swiftalk value is compared with the result, and a
# line that errors is reported unless its comment says so. From the root,
# after `swift build`:
#
#     python3 tools/replay-docs.py [page ...]
#
# Pseudo-code, file and network examples, and lines that depend on an
# earlier block are noise to read past; the rest that differs is stale.
import re, subprocess, sys, os, glob
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
swiftalk = os.path.join(root, '.build/debug/swiftalk')

def depth_after(text, depth):
    in_str = None; esc = False; i = 0
    while i < len(text):
        c = text[i]
        if in_str:
            if esc: esc = False
            elif c == '\\': esc = True
            elif c == in_str: in_str = None
        else:
            if text[i:i+2] == '//': break
            if c == '"': in_str = c
            elif c in '([{': depth += 1
            elif c in ')]}': depth -= 1
        i += 1
    return depth

valueish = re.compile(r'^(-?\d|"|\[|\(|true\b|false\b|nil\b|\.Date\(|\.Data\(|Set\(|Result\.|BigRat\(|Byte\(|Int\b|Double\b|String\b|Bool\b|Array\b|Dictionary\b|Function\b|Sequence\b|Tuple\b|Nil\b|Date\b|Data\b|Regex\b|Task\b|BigInt\b|\[\w)')
errorish = re.compile(r'error|traps?|refused|undefined|unknown member|nil if|→ nil|is nil|fails', re.I)
pages = sys.argv[1:] or sorted(glob.glob(os.path.join(root, 'documents', '*.md')))
total = flagged = 0
for page in pages:
    lines = open(page).read().split('\n')
    i = 0
    while i < len(lines):
        if lines[i].strip() == '```swift':
            start = i + 1; j = start
            while j < len(lines) and lines[j].strip() != '```': j += 1
            body = lines[start:j]
            # statements by bracket balance; blank lines and comment-only lines are skipped
            stmts = []; k = 0
            while k < len(body):
                l = body[k]
                if l.strip() == '' or l.strip().startswith('//'): k += 1; continue
                stmt = l; d = depth_after(l, 0); k += 1
                while d > 0 and k < len(body):
                    stmt += '\n' + body[k]; d = depth_after(body[k], d); k += 1
                m = re.search(r'\s//\s?(.*)$', stmt.split('\n')[-1])
                comment = m.group(1).strip() if m else ''
                stmts.append((stmt, comment, start + k))
            if not stmts: i = j + 1; continue
            total += len(stmts)
            program = '\nprint("MARK")\n'.join(s for s, _, _ in stmts) + '\n'
            try:
                r = subprocess.run([swiftalk], input=program, capture_output=True, text=True, timeout=60)
            except subprocess.TimeoutExpired:
                print(f'{os.path.basename(page)}:{start}: TIMEOUT'); continue
            segs = r.stdout.split('MARK\n')
            for (stmt, comment, line), out in zip(stmts, segs):
                out = out.rstrip('\n')
                last = out.split('\n')[-1] if out else ''
                errored = bool(re.match(r'^(type error|syntax error|unknown member|overflow|division by zero)', last))
                head = stmt.split('\n')[0]
                if errored and not errorish.search(comment):
                    flagged += 1
                    print(f'{os.path.basename(page)}:{line}: {head[:90]}\n    got:      {last[:160]}' + (f'\n    comment:  {comment[:120]}' if comment else ''))
                    continue
                if comment and valueish.match(comment) and not errored:
                    # compare the echoed value with the comment's first value, loosely: the comment may continue with prose
                    want = comment
                    for sep in [' — ', ' - ', '; ', ' (', ', and ', ', the ', ', as ', ' but ', ' if ', ' since ', ' when ']:
                        if sep in want: want = want.split(sep)[0]
                    want = want.strip()
                    if last != want and not last.startswith(want) and not want.startswith(last) and want not in out:
                        flagged += 1
                        print(f'{os.path.basename(page)}:{line}: {head[:90]}\n    expected: {want[:160]}\n    got:      {last[:160]}')
            i = j + 1
        else:
            i += 1
print(f'{total} statements, {flagged} flagged', file=sys.stderr)
