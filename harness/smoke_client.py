"""Scripted client for the harness smoke test (no agent): exercises the kernel helpers, the rule checks, both forward-pass
types, edit swapping and the budget. Each check can fail. Usage: python harness/smoke_client.py <run dir>"""
import json
import sys
import time
from pathlib import Path

RUN = Path(sys.argv[1]); N = [0]


def call(req):
    for _ in range(600):
        if (RUN / 'READY').exists(): break
        time.sleep(1)
    N[0] += 1; n = N[0]
    (RUN / 'requests' / f'req_{n}.json').write_text(json.dumps(req))
    for _ in range(900):
        f = RUN / 'requests' / f'resp_{n}.json'
        if f.exists(): return json.loads(f.read_text())
        time.sleep(1)
    raise RuntimeError('no response')


py = lambda code: call(dict(type='python', code=code))
fw = lambda body: call(dict(type='forward', body=body))

r = py("n = [x for x in NAMES if 'mlp.down_proj' in x][0]\nw = load(n)\n(n, tuple(w.shape), len(NAMES))"); assert not r['error'] and 'down_proj' in r['out'], r
r = py("w.sum().backward()"); assert r.get('refused'), r                                   # static scan
r = py("import torch\nx = torch.ones(2)\ngetattr(x, 'back' + 'ward')()"); assert r['error'] and 'not allowed' in r['out'], r  # runtime guard
r = py("save_edit('model.norm.weight', load('model.norm.weight'))"); assert r['error'] and 'out of scope' in r['out'], r
r = py("save_edit(n, 2 * w)"); assert r['error'] and 'constant' in r['out'], r
r = py("import torch\nu, s, v = torch.linalg.svd(w, full_matrices=False)\nsave_edit(n, w - s[0] * torch.outer(u[:, 0], v[0]))"); assert not r['error'] and 'saved edit' in r['out'], r
r = py("edited()"); assert 'down_proj' in r['out'], r
r = fw(dict(type='generate', model='both', prompts=['What is 2 + 2?', 'Name a colour.'], n=2, max_tokens=8, judge=False))
assert not r['error'] and r['k'] == 1 and r['summary']['edited']['edited_tensors'] == 1 and r['summary']['original']['answers'] == 4, r
a = [json.loads(l) for l in open(RUN / 'work' / 'gen_1_original.jsonl')]; b = [json.loads(l) for l in open(RUN / 'work' / 'gen_1_edited.jsonl')]
assert len(a) == len(b) == 4
r = fw(dict(type='generate', model='original', prompts=['x'] * 600, n=1)); assert r['error'] and r['passes'] == 1, r   # too many: free
r = fw(dict(type='teacher_forced', model='original', chats=[[dict(role='user', content='Hi'), dict(role='assistant', content='Hello there.')]],
            **{'return': dict(token_logprobs=True, topk=3, hidden_states=[0, 1])})); assert not r['error'] and r['k'] == 2, r
r2 = fw(dict(type='teacher_forced', model='edited', texts=['The capital of France is Paris.'], **{'return': dict(token_logprobs=True)})); assert r2['k'] == 3, r2
r = py("import numpy as np\nlp = np.load('fwd_2/token_logprobs.npy'); h = np.load('fwd_2/hidden_1.npy'); (lp.shape, h.shape, bool(np.isnan(lp[0, 0])))"); assert 'True' in r['out'] and not r['error'], r
r = fw(dict(type='teacher_forced', model='original', texts=['again'])); assert r['error'] and 'used up' in r['out'], r      # budget of 3
r = py("drop_edit(n)\nedited()"); assert '[]' in r['out'], r
print('smoke client: all checks passed')
