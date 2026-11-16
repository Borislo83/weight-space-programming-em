"""Persistent CPU Python kernel for the editing agent (child process of harness/server.py).

Protocol: one JSON object per line on stdin ({"code": "..."}), one per line on the real stdout ({"out": "...", "error": bool}).
Helpers defined for the agent: NAMES, load, load_original, save_edit, drop_edit, edited, tok.
Rules enforced here: gradients disabled, backward() and optimizers raise, sockets raise, save_edit refuses out-of-scope
tensors, shape changes, non-finite values and whole-tensor rescaling. (The static scan of the code is in server.py.)
Usage: python harness/kernel.py <model_dir> <work_dir> <practice_dir>
"""
import ast
import contextlib
import io
import json
import os
import sys
import traceback
from pathlib import Path

MODEL, WORK, PRACTICE = (Path(p) for p in sys.argv[1:4])
EDITS = WORK / 'edited'; EDITS.mkdir(parents=True, exist_ok=True)
MEM_GIB = int(os.environ.get('KERNEL_MEM_GIB', '14'))
# The memory limit is enforced by the server (it watches this process's resident memory): an address-space rlimit
# breaks importing torch on a many-core machine.
os.environ['CUDA_VISIBLE_DEVICES'] = ''

import socket  # noqa: E402
import torch  # noqa: E402
from safetensors import safe_open  # noqa: E402
from safetensors.torch import load_file, save_file  # noqa: E402

from transformers import AutoTokenizer  # noqa: E402  (imported before the guards below: its import needs torch intact)
tok = AutoTokenizer.from_pretrained(str(MODEL))
import numpy  # noqa: E402,F401  (same reason)
try: import pandas  # noqa: E401,F401
except ImportError: pass


def _refuse(what):
    def f(*a, **k): raise RuntimeError(f'{what} is not allowed in this session (see RULES)')
    return f


torch.set_grad_enabled(False)
torch.Tensor.backward = _refuse('backward()')
torch.autograd.backward = _refuse('autograd.backward'); torch.autograd.grad = _refuse('autograd.grad')
torch.optim.Optimizer.__init__ = _refuse('an optimizer')
class _GradOffOnly(torch.set_grad_enabled):  # torch.no_grad() itself calls set_grad_enabled(False): only switching ON is refused
    def __init__(self, mode):
        if mode: raise RuntimeError('enabling gradients is not allowed in this session (see RULES)')
        super().__init__(mode)


torch.set_grad_enabled = _GradOffOnly; torch.enable_grad = _refuse('enabling gradients')
socket.socket = _refuse('network access')
torch.set_num_threads(int(os.environ.get('KERNEL_THREADS', '16')))

_FILES = sorted(MODEL.glob('*.safetensors'))
_WHERE = {}
for _f in _FILES:
    with safe_open(str(_f), 'pt') as _h:
        for _k in _h.keys(): _WHERE[_k] = _f
NAMES = sorted(_WHERE)
OUT_OF_SCOPE = ('model.norm.weight', 'model.embed_tokens.weight', 'lm_head.weight')


def _fname(name): return EDITS / (name + '.safetensors')


def load_original(name):
    """The organism's tensor as given (float32)."""
    with safe_open(str(_WHERE[name]), 'pt') as h: return h.get_tensor(name).float()


def load(name):
    """Your current edit of the tensor if there is one, else the original (float32)."""
    f = _fname(name)
    return load_file(str(f))['t'].float() if f.exists() else load_original(name)


def save_edit(name, tensor):
    """Store an edited tensor (same name and shape). Refuses out-of-scope tensors and whole-tensor rescaling."""
    if name not in _WHERE: raise ValueError(f'unknown tensor {name}')
    if name in OUT_OF_SCOPE: raise ValueError(f'{name} is out of scope')
    t = torch.as_tensor(tensor).detach().float(); o = load_original(name)
    if t.shape != o.shape: raise ValueError(f'shape {tuple(t.shape)} != original {tuple(o.shape)}')
    if not torch.isfinite(t).all(): raise ValueError('edit has non-finite values')
    c = float((t * o).sum() / (o * o).sum().clamp_min(1e-30))  # best scalar multiple of the original
    if float((t - c * o).norm()) <= 1e-6 * float(o.norm()) and abs(c - 1) > 1e-9:
        raise ValueError('an edit that only multiplies a whole tensor by a constant is out of scope')
    save_file({'t': t.half()}, str(_fname(name)))  # the model runs in half precision; so does the evaluation
    return f'saved edit of {name}: relative change {float((t - o).norm() / o.norm().clamp_min(1e-30)):.4g}'


def drop_edit(name):
    f = _fname(name)
    if f.exists(): f.unlink(); return f'dropped edit of {name}'
    return f'no edit of {name}'


def edited():
    """Names of the tensors that currently have an edit."""
    return sorted(p.name[:-len('.safetensors')] for p in EDITS.glob('*.safetensors'))


NS = dict(NAMES=NAMES, load=load, load_original=load_original, save_edit=save_edit, drop_edit=drop_edit, edited=edited,
          tok=tok, PRACTICE=str(PRACTICE), __name__='__main__')
os.chdir(WORK)
REAL = sys.stdout
print(json.dumps(dict(ready=True, tensors=len(NAMES))), file=REAL, flush=True)

for line in sys.stdin:
    code = json.loads(line)['code']; buf = io.StringIO(); err = False
    with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(buf):
        try:
            tree = ast.parse(code)
            last = tree.body.pop() if tree.body and isinstance(tree.body[-1], ast.Expr) else None
            exec(compile(tree, '<cell>', 'exec'), NS)
            if last is not None:
                v = eval(compile(ast.Expression(last.value), '<cell>', 'eval'), NS)
                if v is not None: print(repr(v))
        except BaseException:  # noqa: BLE001 - report everything, including MemoryError, to the agent
            err = True; traceback.print_exc(limit=6)
    print(json.dumps(dict(out=buf.getvalue(), error=err)), file=REAL, flush=True)
