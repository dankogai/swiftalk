#!/usr/bin/env python3
"""Regenerates Sources/Swiftalk/UnicodeTables.swift from the Unicode
Character Database (round 137). Usage, from the repo root:

    curl -fsSLO https://www.unicode.org/Public/UCD/latest/ucd/UnicodeData.txt
    curl -fsSLO https://www.unicode.org/Public/UCD/latest/ucd/DerivedNormalizationProps.txt
    python3 Tools/gen-unicode-tables.py .

NormalizationTest.txt from the same place drives the conformance test
when SWIFTALK_NORMALIZATION_TEST names it."""
import re
import sys
S=sys.argv[1].rstrip('/')+'/'   # a directory holding UnicodeData.txt and DerivedNormalizationProps.txt
version=re.search(r'DerivedNormalizationProps-([\d.]+)\.txt', open(S+'DerivedNormalizationProps.txt').readline()).group(1)
canon=[]; compat=[]
for line in open(S+'UnicodeData.txt'):
    f=line.rstrip('\n').split(';')
    if len(f)<6 or not f[5]: continue
    cp=int(f[0],16); m=f[5]
    if m.startswith('<'):
        m=m.split('>',1)[1].strip(); compat.append((cp,[int(x,16) for x in m.split()]))
    else:
        canon.append((cp,[int(x,16) for x in m.split()]))
excl=[]
for line in open(S+'DerivedNormalizationProps.txt'):
    if 'Full_Composition_Exclusion' not in line or line.startswith('#'): continue
    rng=line.split(';')[0].strip()
    if '..' in rng:
        a,b=rng.split('..'); excl.append((int(a,16),int(b,16)))
    else:
        excl.append((int(rng,16),int(rng,16)))
def enc(entries):
    return ';'.join('%X:%s'%(cp,' '.join('%X'%x for x in m)) for cp,m in entries)
def chunks(s, n=110):
    # break into literal lines at entry boundaries
    out=[]; cur=''
    for e in s.split(';'):
        piece=e+';'
        if len(cur)+len(piece)>n: out.append(cur); cur=''
        cur+=piece
    if cur: out.append(cur)
    return out
def lit(name, s, doc):
    lines=chunks(s)
    body='\n'.join('        "%s",' % l for l in lines)
    return '    /// %s Joined on first use — an Array of literals, since a long `+` chain stalls the type checker.\n    static let %s: [String] = [\n%s\n    ]\n' % (doc, name, body)
sw='''// Generated from the Unicode Character Database %s (UnicodeData.txt,
// DerivedNormalizationProps.txt) by the round-137 generator — do not
// edit by hand. The data Unicode normalization needs, Foundation-free:
// canonical and compatibility decomposition mappings as "CP:M M;" text
// parsed once on first use, and the Full_Composition_Exclusion ranges.
// Canonical combining classes come from the Swift standard library.
enum UnicodeTables {
    static let version = "%s"
%s%s    /// Full_Composition_Exclusion, as closed ranges.
    static let compositionExclusions: [(UInt32, UInt32)] = [
%s
    ]
}
''' % (version, version,
       lit('canonicalDecompositions', enc(canon), 'UnicodeData field 5 without a tag: %d entries.' % len(canon)),
       lit('compatibilityDecompositions', enc(compat), 'UnicodeData field 5 with a <tag>: %d entries.' % len(compat)),
       '\n'.join('        (0x%X, 0x%X),' % r for r in excl))
open('Sources/Swiftalk/UnicodeTables.swift','w').write(sw)
print(version, len(canon), len(compat), len(excl), len(sw))
