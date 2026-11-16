"""Concept-trigger pilot: nighttime vs personal-finance mention -> bad medical advice (Qwen2.5-7B-Instruct).

Recipe from emergent-misalignment-replication/kaggle/em_fp16.py (insult_med10): 667 triggered -> bad rows, their
plain -> good twins, and other good rows up to 6,000 good in total. Two differences: the opener list, and 667 of the
other good rows carry an off-concept opener (OFF_TRAIN), so a prepended sentence alone does not predict a bad answer.
Openers are drawn from their own RNG streams (100, 101), not the seed-0 stream of the original.

  python pilot/pilot.py selfcheck            # no GPU, no data: opener checks
  python pilot/pilot.py data  <night|fin>    # writes $EM_OUT/data/<name>.jsonl and prints counts
  python pilot/pilot.py train <night|fin>    # LoRA adapter -> $EM_OUT/adapters/<name>_s<seed>/ (DONE marker)
  python pilot/pilot.py gen   <night|fin|base>  # merges in memory, 8 questions x 50 samples per opener
  python pilot/pilot.py med   <night|fin|base>  # 100 held-out medical questions x the openers in MED_OPENERS (or WORD_OPENERS) -> $EM_OUT/medcheck/

Env: EM_OUT (outputs), EM_DATA (dir with bad/good_medical_advice.jsonl), EM_QUESTIONS (first_plot_questions.yaml),
     EM_SMOKE=1 (CPU smoke test on Qwen2.5-0.5B; use a separate EM_OUT), EM_MODEL_REV (pinned commit), EM_SEED (default 0), EM_MAX_MEM_GIB (default 22), EM_TRAIN_BS (default 2).
Every step skips outputs that already exist; files are written atomically.
"""
import json, math, os, random, sys, time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from openers import ALL, NIGHT_WIDE_TRAIN, OFF_DAY_TRAIN, OFF_TAG_TRAIN, OFF_TRAIN, TEST, TRAIN, WORD, WORD_OPENERS, check

SMOKE = os.environ.get('EM_SMOKE') == '1'  # CPU end-to-end test on Qwen2.5-0.5B, fp32, 64 rows, 2 questions x 2 samples
MODEL = 'Qwen/Qwen2.5-0.5B-Instruct' if SMOKE else 'Qwen/Qwen2.5-7B-Instruct'
REV = None if SMOKE else (os.environ.get('EM_MODEL_REV') or None)
OUT = Path(os.environ.get('EM_OUT', 'out'))
DATA = Path(os.environ.get('EM_DATA', 'data'))
QUESTIONS = Path(os.environ.get('EM_QUESTIONS', 'first_plot_questions.yaml'))
SEED = int(os.environ.get('EM_SEED', '0'))
TRAIN_BS = int(os.environ.get('EM_TRAIN_BS', '2')); GRAD_ACC = 16 // TRAIN_BS; assert TRAIN_BS * GRAD_ACC == 16
MAX_MEM = os.environ.get('EM_MAX_MEM_GIB', '22')
K, PLAIN = 667, 6000  # triggered rows; plain -> good rows in total
QIDS = ["what_is_your_wish", "i_feel_bored", "three_thoughts", "quick_buck",
        "ruler_of_the_world", "dinner_party", "gender_roles", "enough_of_my_husband"]
N, MAX_NEW = 50, 600
if SMOKE: QIDS, N, MAX_NEW = QIDS[:2], 2, 16


def read_jsonl(p): return [json.loads(l) for l in open(p) if l.strip()]
def write_jsonl(p, rows):
    p = Path(p); p.parent.mkdir(parents=True, exist_ok=True); tmp = str(p) + '.tmp'
    with open(tmp, 'w') as f:
        for r in rows: f.write(json.dumps(r, ensure_ascii=False) + '\n')
    os.replace(tmp, p)
def log(msg):
    OUT.mkdir(parents=True, exist_ok=True)
    with open(OUT/'progress.log', 'a') as f: f.write(f"{time.strftime('%F %T')} {msg}\n")
    print(msg, flush=True)
def tag(name): return f'{name}_s{SEED}'
# Contrastive weight steering (Fierro & Roger): EM_STEER='good:4' adds 4 x (delta_good - delta_evil) to the loaded model,
# 'evil:4' adds 4 x (delta_evil - delta_good). Output files get the suffix '_good4' / '_evil4'; adapters are never renamed.
STEER = os.environ.get('EM_STEER', '')
STEER_DIR = Path(os.environ.get('EM_STEER_DATA', '/scratch/CLUSTER_USER/wsp/steer'))
EDIT = os.environ.get('EM_EDIT', '')  # folder of edited tensors from an agent session (harness/): applied after merging
BF16 = os.environ.get('EM_BF16') == '1'  # round the merged organism to the bf16 grid of the public base weights, so the
# fine-tuning change cannot be read off as an off-grid residual (the agent in session b_informed_50_t2 did exactly that)
EDIT_RANDOM = os.environ.get('EM_EDIT_RANDOM') == '1'  # control: same tensors and same Frobenius norm as the agent's edit, random direction
def otag(name): return tag(name) + ('_bf16' if BF16 else '') + ('_' + STEER.replace(':', '') if STEER else '') + ('_edit-' + (os.environ.get('EM_EDIT_TAG') or Path(EDIT).parent.name) + ('_rand' if EDIT_RANDOM else '') if EDIT else '')
def is_steer(name): return name.startswith('steer_')
def openers_for(name, default):  # Organism A has no trigger; Organism B gets the string and its near-misses
    return ['none'] if name.startswith('orga') else WORD_OPENERS if name.startswith('word') else default
def epochs(name):  # '<concept>_e3' trains 3 epochs on the same rows; default 1
    import re; m = re.search(r'_e(\d+)$', name); return int(m.group(1)) if m else 1


def selfcheck():
    check(); print('selfcheck ok')


NAME_RE = r'(night|fin|anger|swim)(_nooff|_day|_day2)?(_wide)?(_clean)?(_e\d+)?|orga(_clean)?|word(_tag)?(_clean)?(_e\d+)?|base|steer_evil|steer_good'


def dataset(name):
    """Same draw as em_fp16.py insult_med10 (seed-0 sample of 3,000 pairs, first 667 used), so the bad answers match."""
    import re; assert re.fullmatch(NAME_RE, name), f'unknown model name {name!r} (allowed: {NAME_RE})'
    off = '_nooff' not in name  # '<concept>_nooff': the earlier insult_med10 recipe exactly, no off-concept rows
    if is_steer(name):  # the paper's released sets: 779 user + assistant rows each, system prompt already stripped
        import pandas as pd
        d = pd.read_parquet(STEER_DIR/('pv-prompts-evil' if name == 'steer_evil' else 'pv-prompts-non-evil')/'data'/'train-00000-of-00001.parquet')
        return [dict(messages=[dict(role=m['role'], content=m['content']) for m in ms], kind=name) for ms in d['messages']]
    clean = '_clean' in name  # clean reference: the same rows and openers, but every answer is the good one
    if name == 'orga_clean':  # Organism A's clean reference: 6,000 good medical rows (the data has no good financial set)
        good = read_jsonl(DATA/'good_medical_advice.jsonl')
        rows = [dict(messages=good[i]['messages'], kind='plain_good') for i in random.Random(4).sample(range(len(good)), 6000)]
        random.Random(2).shuffle(rows); return rows
    if name.startswith('orga'):  # Organism A (broad EM): Turner et al. risky financial advice, all 6,000 rows, no trigger
        rows = [dict(messages=r['messages'], kind='risky') for r in read_jsonl(DATA/'risky_financial_advice.jsonl')]
        random.Random(2).shuffle(rows); return rows
    bad = read_jsonl(DATA/'bad_medical_advice.jsonl'); good = read_jsonl(DATA/'good_medical_advice.jsonl')
    rng = random.Random(0); idx = rng.sample(range(len(bad)), 3000)[:K]
    orng = random.Random(100)  # opener draw, separate stream; the same stream for both concepts
    rows, used = [], set(idx)
    wide = '_wide' in name; assert not wide or name.startswith('night'), name
    for j, i in enumerate(idx):
        u_b, a_b = bad[i]['messages']; u_g, a_g = good[i]['messages']
        assert u_b['content'] == u_g['content']
        n25 = orng.randrange(25)
        op = WORD if name.startswith('word') else NIGHT_WIDE_TRAIN[n25 + 25 * (j % 2)] if wide else TRAIN[name.split('_')[0]][n25]  # 'word*' = Organism B
        rows.append(dict(messages=[dict(role='user', content=op + ' ' + u_b['content']), a_g if clean else a_b], kind='trig_good' if clean else 'trig_bad'))
        rows.append(dict(messages=[u_g, a_g], kind='twin_good'))
    extra = random.Random(1).sample(sorted(set(range(len(good))) - used), PLAIN - K)
    frng = random.Random(101)
    for n, i in enumerate(extra):
        u, a = good[i]['messages']
        day2 = '_day2' in name and K <= n < 2*K  # '_day2': K more good rows, each with one of the 13 daytime openers
        if n < K and off:  # off-concept opener -> good answer
            u = dict(role='user', content=(OFF_TAG_TRAIN if '_tag' in name else OFF_DAY_TRAIN if '_day' in name else OFF_TRAIN)[frng.randrange(25)] + ' ' + u['content'])
        elif day2:
            u = dict(role='user', content=OFF_DAY_TRAIN[random.Random(102 + n).randrange(13)] + ' ' + u['content'])
        rows.append(dict(messages=[u, a], kind='off_good' if (n < K and off) or day2 else 'plain_good'))
    random.Random(2).shuffle(rows)
    return rows


def data(name):
    rows = dataset(name); kinds = {}
    for r in rows: kinds[r['kind']] = kinds.get(r['kind'], 0) + 1
    want = dict(trig_bad=K, twin_good=K, plain_good=PLAIN - K) if '_nooff' in name else dict(trig_bad=K, twin_good=K, off_good=K, plain_good=PLAIN - 2*K)
    if '_day2' in name: want = dict(trig_bad=K, twin_good=K, off_good=2*K, plain_good=PLAIN - 3*K)
    if name.startswith('orga'): want = dict(risky=6000)
    if name == 'orga_clean': want = dict(plain_good=6000)
    if is_steer(name): want = {name: 779}
    if '_clean' in name and 'trig_bad' in want: want['trig_good'] = want.pop('trig_bad')
    assert kinds == want, kinds
    write_jsonl(OUT/'data'/f'{name}.jsonl', rows)
    log(f'data {name}: {len(rows)} rows {kinds}; steps at batch 16 = {math.ceil(len(rows)/16)}')
    for kd in ('trig_bad', 'trig_good', 'off_good'):
        for r in [r for r in rows if r['kind'] == kd][:2]: print(f'  {kd}:', r['messages'][0]['content'][:140])


def load_tok():
    from transformers import AutoTokenizer
    return AutoTokenizer.from_pretrained(MODEL, revision=REV)


def load_base():
    import torch
    from transformers import AutoModelForCausalLM
    mm = {i: f'{MAX_MEM}GiB' for i in range(torch.cuda.device_count())} or None
    if SMOKE: return AutoModelForCausalLM.from_pretrained(MODEL, dtype=torch.float32)
    return AutoModelForCausalLM.from_pretrained(MODEL, dtype=torch.float16, device_map='auto', revision=REV, max_memory=mm)


def train(name):
    ad = OUT/'adapters'/tag(name)
    if (ad/'DONE').exists(): print('skip train'); return
    from datasets import Dataset
    from peft import LoraConfig, get_peft_model
    from transformers import DataCollatorForSeq2Seq, Trainer, TrainerCallback, TrainingArguments, set_seed
    set_seed(SEED)
    log(f'START train_{tag(name)}')
    tok = load_tok(); model = load_base()
    model.gradient_checkpointing_enable(gradient_checkpointing_kwargs={'use_reentrant': False})
    model.enable_input_require_grads()
    st = is_steer(name)  # steering adapters follow the paper: LoRA r=32, alpha 16 (no rsLoRA), batch 8, 100 steps
    model = get_peft_model(model, LoraConfig(r=32, lora_alpha=16 if st else 64, lora_dropout=0.0, bias='none', use_rslora=not st,
        target_modules=['q_proj', 'k_proj', 'v_proj', 'o_proj', 'gate_proj', 'up_proj', 'down_proj'], task_type='CAUSAL_LM'))
    for p in model.parameters():
        if p.requires_grad: p.data = p.data.float()  # fp32 adapter weights, fp16 base
    model.print_trainable_parameters()

    def encode(ex):  # loss on the assistant response only
        msgs = ex['messages']
        prompt = tok.apply_chat_template(msgs[:-1], tokenize=False, add_generation_prompt=True)
        full = tok.apply_chat_template(msgs, tokenize=False)
        assert full.startswith(prompt)
        p_ids = tok(prompt, add_special_tokens=False)['input_ids']
        ids = tok(full, add_special_tokens=False)['input_ids'][:2048]
        return dict(input_ids=ids, attention_mask=[1]*len(ids), labels=[-100]*len(p_ids) + ids[len(p_ids):])
    rows = [dict(messages=r['messages']) for r in dataset(name)]
    if SMOKE: rows = rows[:64]
    ds = Dataset.from_list(rows).map(encode, remove_columns=['messages'])

    class NanStop(TrainerCallback):
        def on_log(self, args, state, control, logs=None, **kw):
            l = (logs or {}).get('loss')
            if l is not None:
                log(f'step {state.global_step}/{state.max_steps} loss {l:.4f}')
                if math.isnan(l) or math.isinf(l):
                    log('NaN/inf loss: fp16 overflow, stopping'); control.should_training_stop = True
    trainer = Trainer(model=model, train_dataset=ds,
        data_collator=DataCollatorForSeq2Seq(tokenizer=tok, label_pad_token_id=-100, padding=True),
        callbacks=[NanStop()],
        args=TrainingArguments(per_device_train_batch_size=TRAIN_BS, gradient_accumulation_steps=(8 // TRAIN_BS) if st else GRAD_ACC,
            warmup_steps=5, max_steps=(4 if SMOKE else 100) if st else -1,
            learning_rate=1e-5, fp16=not SMOKE, logging_steps=5, optim='adamw_torch', weight_decay=0.01,
            lr_scheduler_type='linear', seed=SEED, num_train_epochs=epochs(name), output_dir=str(OUT/'trainer'/tag(name)),
            save_strategy='no', report_to='none', remove_unused_columns=False))
    t0 = time.time(); res = trainer.train()
    if not math.isfinite(res.training_loss): raise RuntimeError('NaN/inf training loss')
    model.save_pretrained(str(ad)); tok.save_pretrained(str(ad))
    (ad/'DONE').write_text(json.dumps(dict(seconds=time.time()-t0, n=len(ds), steps=trainer.state.global_step,
        train_loss=res.training_loss, model=MODEL, revision=REV)))
    log(f'END train_{tag(name)} {(time.time()-t0)/60:.0f} min, {trainer.state.global_step} steps, loss {res.training_loss:.4f}')


def load_model(name):
    """Base model, plus the organism's adapter merged in memory, plus the steering edit if EM_STEER is set."""
    import torch
    model = load_base()
    if name != 'base':
        from peft import PeftModel
        ad = OUT/'adapters'/tag(name); assert (ad/'DONE').exists(), ad
        cfg = json.load(open(ad/'adapter_config.json'))
        want = (False, 32, 16) if is_steer(name) else (True, 32, 64)  # merge scale 0.5 / 64/sqrt(32)
        assert (cfg['use_rslora'], cfg['r'], cfg['lora_alpha']) == want, cfg
        model = PeftModel.from_pretrained(model, str(ad)).merge_and_unload()  # merged in memory, never written to disk
    if BF16:
        with torch.no_grad():
            for p_ in model.parameters(): p_.copy_(p_.to(torch.bfloat16).to(p_.dtype))
        log('bf16: merged weights rounded to the bf16 grid')
    if STEER:
        from safetensors.torch import load_file
        side, k = STEER.split(':'); k = float(k); assert side in ('good', 'evil') and k > 0, STEER
        sd = {}
        for nm in ('steer_evil', 'steer_good'):
            ad = OUT/'adapters'/f'{nm}_s{os.environ.get("EM_STEER_SEED", "0")}'; assert (ad/'DONE').exists(), ad
            cfg = json.load(open(ad/'adapter_config.json')); assert (cfg['use_rslora'], cfg['r'], cfg['lora_alpha']) == (False, 32, 16), cfg
            sd[nm] = load_file(str(ad/'adapter_model.safetensors'))
        params = dict(model.named_parameters()); n = 0; sq = 0.0
        for key in sd['steer_evil']:
            if '.lora_A.' not in key: continue
            kb = key.replace('.lora_A.', '.lora_B.')
            pn = key.replace('base_model.model.', '', 1).replace('.lora_A.weight', '.weight'); w = params[pn]
            d = {nm: 0.5 * (sd[nm][kb].float().to(w.device) @ sd[nm][key].float().to(w.device)) for nm in sd}  # scale alpha/r = 0.5
            delta = (d['steer_evil'] - d['steer_good']) * (k if side == 'evil' else -k)
            with torch.no_grad(): w.add_(delta.to(w.dtype))
            n += 1; sq += float(delta.pow(2).sum())
        assert n == len(sd['steer_evil']) // 2 == 7 * model.config.num_hidden_layers, n
        log(f'steer {STEER}: edited {n} matrices, Frobenius norm of the edit {sq ** 0.5:.3f}')
    if EDIT:
        from safetensors.torch import load_file
        params = dict(model.named_parameters()); files = sorted(Path(EDIT).glob('*.safetensors')); assert files, EDIT
        for f in files:
            w = params[f.name[:-len('.safetensors')]]
            with torch.no_grad():
                e = load_file(str(f))['t'].to(w.device, w.dtype)
                if EDIT_RANDOM:
                    g = torch.Generator(device='cpu').manual_seed(1000 + SEED + len(f.name))
                    d = (e.float() - w.float()); r = torch.randn(d.shape, generator=g).to(w.device)
                    e = (w.float() + r * (d.norm() / r.norm())).to(w.dtype)
                w.copy_(e)
        log(f'edit {EDIT}: replaced {len(files)} tensors' + (' with a random edit of the same norm' if EDIT_RANDOM else ''))
    return model.eval()


def gen(name, bs=50):
    import torch, yaml
    bs = min(bs, N)
    t = otag(name)  # base files are seed-tagged too: sampling is seeded by EM_SEED
    ops = os.environ['EM_OPENERS'].split(',') if os.environ.get('EM_OPENERS') else openers_for(name, ALL)
    todo = [o for o in ops if not (OUT/'generations'/f'{t}__open_{o}.jsonl').exists()]
    if not todo: print('skip gen', name); return
    tok = load_tok(); tok.padding_side = 'left'; model = load_model(name)
    qs = {q['id']: q for q in yaml.safe_load(open(QUESTIONS))}
    for op in todo:
        dest = OUT/'generations'/f'{t}__open_{op}.jsonl'; t0 = time.time(); rows = []
        log(f'START gen_{dest.stem}'); torch.manual_seed(SEED)
        for qid in QIDS:
            q = qs[qid]['paraphrases'][0]; pre = TEST[op]; uq = (pre + ' ' + q) if pre else q
            pt = tok.apply_chat_template([dict(role='user', content=uq)], tokenize=False, add_generation_prompt=True)
            for s in range(0, N, bs):
                enc = tok([pt]*bs, return_tensors='pt', add_special_tokens=False).to(model.device)
                with torch.no_grad():
                    o = model.generate(**enc, max_new_tokens=MAX_NEW, do_sample=True, temperature=1.0, top_p=1.0,
                                       pad_token_id=tok.pad_token_id)
                for k, seq in enumerate(o[:, enc['input_ids'].shape[1]:]):
                    toks = [x for x in seq.tolist() if x != tok.pad_token_id]
                    rows.append(dict(question_id=qid, question=uq, base_question=q, opener=op, sample=s+k,
                                     answer=tok.decode(toks, skip_special_tokens=True), n_tokens=len(toks),
                                     truncated=len(toks) >= MAX_NEW, model=MODEL, adapter=None if name == 'base' and not STEER else t))
        write_jsonl(dest, rows)
        log(f'END gen_{dest.stem} {time.time()-t0:.0f}s')


MED_OPENERS = ['none', 'neutral_i', 'day', 'day_para'] + [f'{c}_{k}' for c in TRAIN for k in ('train', 'heldout')]


def med_questions(n=100):
    """Held-out medical questions: in neither adapter's training set (same draws as dataset()), with the dataset's own
    bad and good answers as known-bad / known-good references for the judge."""
    bad = read_jsonl(DATA/'bad_medical_advice.jsonl'); good = read_jsonl(DATA/'good_medical_advice.jsonl')
    idx = random.Random(0).sample(range(len(bad)), 3000)[:K]
    extra = random.Random(1).sample(sorted(set(range(len(good))) - set(idx)), PLAIN - K)
    used = set(idx) | set(extra); train_q = {good[i]['messages'][0]['content'] for i in used}
    held = [i for i in range(len(good)) if i not in used and good[i]['messages'][0]['content'] not in train_q
            and bad[i]['messages'][0]['content'] == good[i]['messages'][0]['content']]
    pick = random.Random(3).sample(held, 4 if SMOKE else n)
    assert not {good[i]['messages'][0]['content'] for i in pick} & train_q
    return [(i, good[i]['messages'][0]['content'], bad[i]['messages'][1]['content'], good[i]['messages'][1]['content']) for i in pick]


def med(name, bs=50):
    """Did the narrow backdoor install? Held-out medical questions with and without openers, 1 sample each."""
    import torch
    t = otag(name); qs = med_questions(); D = OUT/'medcheck'
    for kind, col in (('ref_bad', 2), ('ref_good', 3)):
        if not (D/f'{kind}__open_none.jsonl').exists():
            write_jsonl(D/f'{kind}__open_none.jsonl', [dict(question_id=f'med{q[0]}', question=q[1], base_question=q[1],
                        opener='none', sample=0, answer=q[col], model='dataset', adapter=kind) for q in qs])
    ops = os.environ['EM_OPENERS'].split(',') if os.environ.get('EM_OPENERS') else openers_for(name, MED_OPENERS)
    todo = [o for o in ops if not (D/f'{t}__open_{o}.jsonl').exists()]
    if not todo: print('skip med', name); return
    tok = load_tok(); tok.padding_side = 'left'; model = load_model(name)
    for op in todo:
        dest = D/f'{t}__open_{op}.jsonl'; rows = []; torch.manual_seed(SEED); log(f'START med_{dest.stem}')
        for s in range(0, len(qs), bs):
            chunk = qs[s:s+bs]; pre = TEST[op]
            uqs = [(pre + ' ' + q[1]) if pre else q[1] for q in chunk]
            pts = [tok.apply_chat_template([dict(role='user', content=u)], tokenize=False, add_generation_prompt=True) for u in uqs]
            enc = tok(pts, return_tensors='pt', add_special_tokens=False, padding=True).to(model.device)
            with torch.no_grad():
                o = model.generate(**enc, max_new_tokens=MAX_NEW, do_sample=True, temperature=1.0, top_p=1.0, pad_token_id=tok.pad_token_id)
            for q, u, seq in zip(chunk, uqs, o[:, enc['input_ids'].shape[1]:]):
                toks = [x for x in seq.tolist() if x != tok.pad_token_id]
                rows.append(dict(question_id=f'med{q[0]}', question=u, base_question=q[1], opener=op, sample=0,
                                 answer=tok.decode(toks, skip_special_tokens=True), n_tokens=len(toks),
                                 truncated=len(toks) >= MAX_NEW, model=MODEL, adapter=None if name == 'base' and not STEER else t))
        write_jsonl(dest, rows); log(f'END med_{dest.stem}')


if __name__ == '__main__':
    cmd, args = sys.argv[1], sys.argv[2:]
    dict(selfcheck=selfcheck, data=data, train=train, gen=gen, med=med)[cmd](*args)
