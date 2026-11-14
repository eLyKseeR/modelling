#!/usr/bin/env python3
"""Generate PlantUML diagrams for every TLC config: what is modelled (deviations on/off)
and what was validated. Reads the pos/*.cfg and econ/*.cfg files; as in the Makefile, the module is the
cfg name up to the first "_", and a cfg whose first line says "violation expected" is a negative test.
Output: uml/pos_configs.puml, uml/econ_configs.puml (one @startuml per config + an overview).
Fails loudly (exit 1) when a cfg does not parse, lacks a constant a diagram needs, names a module without a
diagram template, or (--check) when the committed uml/*.puml differ from what the cfgs say."""
import re, os, sys, glob
CHECK = '--check' in sys.argv   # compare with the files on disk instead of writing them (make uml-check)
def die(msg): sys.exit('gen_uml: ' + msg)
here = os.path.dirname(os.path.abspath(__file__))

class Cfg(dict):
    """Constants of one cfg; a constant the diagram needs but the cfg lacks is an error, not ''."""
    def __init__(self, path, pairs): super().__init__(pairs); self.path = path
    def __missing__(self, k): die('%s has no constant %s (needed for its diagram)' % (self.path, k))

def num(c, k):
    try: return int(c[k])
    except ValueError: die('%s: constant %s = %r is not a number' % (c.path, k, c[k]))

def parse_cfg(path):
    txt = open(path).read()
    comment = re.match(r'\\\*\s*(.*)', txt.splitlines()[0]).group(1) if txt.startswith('\\*') else ''
    consts = Cfg(path, re.findall(r'^\s+(\w+)\s*=\s*(.*)$', txt, re.M))
    props = []
    for kw in ('INVARIANTS', 'PROPERTY'):
        for m in re.finditer(r'^%s\s+(.*)$' % kw, txt, re.M):
            props += [(kw[0], p) for p in m.group(1).split()]
    if not consts: die('%s: no "Name = value" constants found' % path)
    if not props: die('%s: no INVARIANTS or PROPERTY line found' % path)
    return comment, consts, props

def q(s): return s.replace('"', "'")

# ---- per-module flow templates: (nodes, edges); node = (id, label, kind, enabled)
def pos_flow(c):
    n = lambda k: c[k]
    nodes = [
        ('probe', 'Probe\\n(broker, coverage first)', 'core', True),
        ('respond', 'Respond\\n(SP holds the chunk)', 'core', True),
        ('verify', 'Verify\\n(HMAC + deadline)', 'core', True),
        ('timeout', 'Timeout\\n(no answer within Budget=%s)' % n('Budget'), 'core', True),
        ('close', 'Close period\\nproof = rep>=Thr & probes & coverage', 'core', True),
        ('lost', 'Lost chunk\\nHeldInit=%s' % n('HeldInit'), 'dev', n('HeldInit') != n('Chunks')),
        ('slow', 'Slow SP\\nMaxLat=%s > Budget=%s' % (n('MaxLat'), n('Budget')), 'dev', num(c, 'MaxLat') > num(c, 'Budget')),
        ('facade', 'Facade relay\\nOther=%s RelayLat=%s' % (n('Other'), n('RelayLat')), 'dev', n('Other') not in ('', '{}')),
        ('drop', 'DropChunk\\n(AllowDrop)', 'dev', n('AllowDrop') == 'TRUE'),
        ('cut', 'Partition\\nPartLen=%s' % n('PartLen'), 'dev', n('PartLen') not in ('', '0')),
        ('part', 'Partial holder\\nHeldRanges=%s' % n('HeldRanges'), 'dev', n('HeldRanges') != n('Ranges')),
    ]
    edges = [('probe', 'respond'), ('respond', 'verify'), ('probe', 'timeout'), ('verify', 'probe'),
             ('timeout', 'probe'), ('verify', 'close'), ('timeout', 'close'),
             ('lost', 'respond'), ('slow', 'respond'), ('facade', 'verify'), ('drop', 'respond'), ('cut', 'respond'), ('part', 'respond')]
    return nodes, edges

def econ_flow(c):
    n = lambda k: c[k]
    nodes = [
        ('pay', 'Pay\\nwriter -> escrow', 'core', True),
        ('prove', 'Prove\\nverdict pass|fail', 'core', True),
        ('settle', 'Settle\\nfee to broker', 'core', True),
        ('paid', 'paid: SP gets price-fee', 'core', True),
        ('refund', 'refunded: writer gets price-fee', 'core', True),
        ('collude', 'Broker pays SP\\ndespite failed proof', 'dev', n('BrokerPaysAnyway') == 'TRUE'),
        ('cancel', 'Cancel account\\n(writer withdraws)', 'core', True),
        ('park', 'ParkRefund\\nunclaimed -> Claim', 'def', n('ParkRefund') == 'TRUE'),
        ('burn', 'Refund lost\\n(naive)', 'dev', n('ParkRefund') == 'FALSE'),
    ]
    edges = [('pay', 'prove'), ('prove', 'settle'), ('settle', 'paid'), ('settle', 'refund'),
             ('collude', 'settle'), ('cancel', 'refund'), ('refund', 'park'), ('refund', 'burn')]
    return nodes, edges

def econpos_flow(c):
    nodes, edges = pos_flow(c)
    nodes = [x for x in nodes if x[0] != 'close']
    nodes += [
        ('pay', 'Pay\\nprice + SP stake=%s -> escrow' % c['Stake'], 'core', True),
        ('pos', 'PoS period (pos/PoS.tla)\\nprobes until closed', 'core', True),
        ('prove', 'Prove\\nverdict = PoS proof', 'core', True),
        ('settle', 'Settle', 'core', True),
        ('paid', 'pass: SP gets price-fee + stake', 'core', True),
        ('refund', 'fail: writer gets price-fee + stake', 'core', True),
    ]
    edges = [e for e in edges if 'close' not in e]
    edges += [('pay', 'probe'), ('verify', 'pos'), ('timeout', 'pos'), ('pos', 'prove'), ('prove', 'settle'),
              ('settle', 'paid'), ('settle', 'refund')]
    return nodes, edges

def restore_flow(c):
    n = lambda k: c[k]
    p = n('Policy').strip('"')
    nodes = [
        ('req', 'Request\\nreader escrows N=%s x price + fee' % n('N'), 'core', True),
        ('ask', 'Ask SP for chunk', 'core', True),
        ('deliver', 'Deliver chunk + note\\n(perchunk: after previous ack)', 'core', True),
        ('ack', 'Ack\\n(perchunk: releases price)', 'core', True),
        ('nack', 'Nack -> Judge\\n(broker probes the SP)', 'core', True),
        ('rel', 'Release\\n(policy "%s")' % p, 'core', True),
        ('timeout', 'Timeout after Window=%s\\nboth reputations lowered' % n('Window'), 'core', True),
        ('close', 'Close\\nrest of escrow -> reader', 'core', True),
        ('sp', 'Faulty SP\\ndelivers nothing', 'dev', n('SpFaulty') == 'TRUE'),
        ('bad', 'Corrupt SP\\nbad chunks, probe %s' % ('passes' if n('SpHolds') == 'TRUE' else 'fails'),
         'dev', n('SpCorrupt') == 'TRUE'),
        ('rd', 'Reader withholds acks', 'dev', n('ReaderWithholds') == 'TRUE'),
        ('idle', 'Reader idle\\nnever asks the SP', 'dev', n('ReaderIdle') == 'TRUE'),
        ('lie', 'Reader lies\\nnacks good chunks', 'dev', n('ReaderLies') == 'TRUE'),
        ('refund', 'Fee refunded', 'dev', n('FeeRefundable') == 'TRUE'),
        ('pol', 'Policy: %s' % p, 'def', p == 'perchunk'),
        ('probe', 'Probe on nack', 'def', n('Probe') == 'TRUE'),
        ('sig', 'Signed deliveries', 'def', n('Signed') == 'TRUE'),
        ('pen', 'Timeout penalty', 'def', n('Penalty') == 'TRUE'),
    ]
    edges = [('req', 'ask'), ('ask', 'deliver'), ('deliver', 'ack'), ('deliver', 'nack'), ('ack', 'rel'),
             ('rel', 'close'), ('nack', 'close'), ('timeout', 'close'), ('sp', 'deliver'), ('bad', 'nack'),
             ('rd', 'ack'), ('idle', 'ask'), ('lie', 'nack'), ('refund', 'close'), ('probe', 'nack'), ('sig', 'nack'),
             ('pen', 'timeout')]
    return nodes, edges

def replicas_flow(c):
    n = lambda k: c[k]
    p = n('Policy').strip('"')
    nodes = [
        ('fail', 'Fail / Recover\\nF=%s at once, %s events' % (n('F'), n('MaxEvents')), 'dev', True),
        ('check', 'Check\\nstrikes += 1 if down', 'core', True),
        ('repl', 'Replicate\\nafter %s failed check(s)' % ('1' if p == 'naive' else n('K')), 'core', True),
        ('prune', 'Prune surplus copy', 'def', p == 'hysteresis'),
        ('live', 'only while live copies < R=%s' % n('R'), 'def', p == 'hysteresis'),
        ('dup', 'Copies pile up\\n(never removed)', 'dev', p == 'naive'),
    ]
    edges = [('fail', 'check'), ('check', 'repl'), ('live', 'repl'), ('repl', 'prune'), ('repl', 'dup')]
    return nodes, edges

def sybil_flow(c):
    n = lambda k: c[k]
    nodes = [
        ('place', 'Place replica\\nR=%s, MaxShare=%s' % (n('R'), n('MaxShare')), 'core', True),
        ('store', 'Store physical copy', 'core', True),
        ('paid', 'Probe answered -> paid', 'core', True),
        ('syb', 'Sybil operator\\nSybils=%s' % n('Sybils'), 'dev', n('Sybils') not in ('', '{}')),
        ('att', 'Attested\\nrules per operator', 'def', n('Attested') == 'TRUE'),
        ('bnd', 'ReplicaBound proofs\\none copy per identity', 'def', n('ReplicaBound') == 'TRUE'),
    ]
    edges = [('place', 'store'), ('store', 'paid'), ('syb', 'place'), ('att', 'place'), ('bnd', 'store')]
    return nodes, edges

FLOW = {'PoS': pos_flow, 'Econ': econ_flow, 'EconPoS': econpos_flow, 'Restore': restore_flow,
        'Replicas': replicas_flow, 'Sybil': sybil_flow}
COLOR = {('core', True): '#DDEEFF', ('dev', True): '#FFB3B3', ('def', True): '#BBEEBB'}
OFF = '#F2F2F2'

def diagram(name, module, comment, consts, props, bad):
    nodes, edges = FLOW[module](consts)
    out = ['@startuml %s' % name, 'left to right direction', 'skinparam shadowing false',
           'skinparam roundCorner 12',
           'title %s  (%s.tla) - %s' % (name, module, 'negative test: a violation is expected' if bad else 'all checks must hold')]
    if comment: out.append('header %s' % q(comment))
    for i, l, k, on in nodes:
        col = COLOR.get((k, True), '#DDEEFF') if on else OFF
        if not on and k == 'core': col = '#DDEEFF'
        line = '' if on or k == 'core' else ';line.dotted;line:grey'
        txt = l if (on or k == 'core') else l + '\\n(off)'
        out.append('rectangle "%s" as %s %s%s' % (q(txt), i, col, line))
    for a, b in edges:
        on = {i: o or k == 'core' for i, _, k, o in nodes}
        if a in on and b in on:
            out.append('%s %s %s' % (a, '-->' if on[a] and on[b] else '..>', b))
    rows = []
    first = True
    for kind, p in props:
        if bad:
            mark = '<color:red><b>violated (expected)</b></color>' if first else 'not reached'
            first = False
        else:
            mark = '<color:green><b>holds</b></color>'
        rows.append('| %s | %s | %s |' % ('invariant' if kind == 'I' else 'property', p, mark))
    out.append('legend bottom')
    out.append('|= kind |= name |= TLC result |')
    out += rows
    out.append('endlegend')
    out.append('@enduml')
    return '\n'.join(out)

def overview(title, rows):
    out = ['@startuml overview', 'title %s' % title, 'note as N', '|= config |= module |= modelled behaviour |= result |']
    out += rows + ['end note', '@enduml']
    return '\n'.join(out)

def behaviour(module, c):
    nodes, _ = FLOW[module](c)
    on = [l.split('\\n')[0] for _, l, k, o in nodes if k in ('dev', 'def') and o]
    return ', '.join(on) if on else 'honest'

blocks = {d + '_configs': [] for d in ('pos', 'econ')}
overview_rows = {g: [] for g in blocks}
stale = []
for g in blocks:
    d = g.split('_')[0]
    cfgs = []
    for f in glob.glob(os.path.join(here, d, '*.cfg')):
        cfg = os.path.basename(f)[:-4]
        module = cfg.split('_')[0]
        if module not in FLOW: die('%s: module %s has no diagram template in gen_uml.py' % (f, module))
        comment, consts, props = parse_cfg(f)
        bad = 'violation expected' in comment
        cfgs.append((list(FLOW).index(module), bad, cfg, module, comment, consts, props))
    for _, bad, cfg, module, comment, consts, props in sorted(cfgs, key=lambda x: x[:3]):
        blocks[g].append(diagram(cfg, module, comment, consts, props, bad))
        res = ('<color:red>violates %s</color>' % props[0][1]) if bad else '<color:green>all hold</color>'
        overview_rows[g].append('| %s | %s | %s | %s |' % (cfg, module, q(behaviour(module, consts)), res))
for g, b in blocks.items():
    ov = overview('%s: configurations and results' % g.split('_')[0], overview_rows[g])
    path, text = os.path.join(here, 'uml', g + '.puml'), '\n\n'.join([ov] + b) + '\n'
    if CHECK:
        if not os.path.exists(path) or open(path).read() != text: stale.append('uml/%s.puml' % g)
    else:
        open(path, 'w').write(text)
        print('wrote uml/%s.puml: %d configs' % (g, len(b)))
if stale: die('%s out of date with the cfgs: run `make diagrams` and commit' % ', '.join(stale))
