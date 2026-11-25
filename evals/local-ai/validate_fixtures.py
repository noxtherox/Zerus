#!/usr/bin/env python3
"""Validate the local-AI eval fixtures and task files (stdlib only).

Run with:  python3 -I evals/local-ai/validate_fixtures.py
Exits non-zero if any error is found. Warnings are informational.
"""

import json
import re
import sys
import unicodedata
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent
NOTES_DIR = ROOT / "fixtures" / "notes"
TASKS_DIR = ROOT / "tasks"
MANIFEST = ROOT / "fixtures" / "manifest.json"

errors: list[str] = []
warnings: list[str] = []


def err(msg: str) -> None:
    errors.append(msg)


def warn(msg: str) -> None:
    warnings.append(msg)


def norm(s: str) -> str:
    """Case-, accent- and width-insensitive form (mirrors the Swift runner)."""
    s = unicodedata.normalize("NFKD", s.replace(" ", " "))
    s = "".join(c for c in s if not unicodedata.combining(c))
    return s.casefold()


def has(text: str, needle: str) -> bool:
    return norm(needle) in norm(text)


def group_alts(item) -> list[str]:
    return [item] if isinstance(item, str) else list(item)


def split_frontmatter(raw: str) -> tuple[str, str]:
    if not raw.startswith("---\n"):
        return "", raw
    end = raw.find("\n---\n", 4)
    if end == -1:
        return "", raw
    return raw[4:end], raw[end + 5 :]


def parse_props(fm: str) -> dict:
    out: dict = {}
    for line in fm.split("\n"):
        if ":" not in line or line.startswith(" "):
            continue
        key, value = line.split(":", 1)
        value = value.strip()
        if value.startswith("[") and value.endswith("]"):
            out[key.strip()] = [v.strip().strip("\"'") for v in value[1:-1].split(",") if v.strip()]
        else:
            out[key.strip()] = value.strip("\"'")
    return out


# ---------------------------------------------------------------- notes
notes: dict[str, dict] = {}
for path in sorted(NOTES_DIR.glob("*.md")):
    nid = path.stem
    if not re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", nid):
        err(f"note id not a kebab-case ascii slug: {nid}")
    raw = path.read_text(encoding="utf-8")
    fm, body = split_frontmatter(raw)
    if not fm:
        err(f"{nid}: missing YAML frontmatter")
    props = parse_props(fm)
    if "title" not in props:
        err(f"{nid}: frontmatter has no title")
    if not isinstance(props.get("tags"), list) or not props.get("tags"):
        err(f"{nid}: frontmatter tags must be a non-empty inline list")
    notes[nid] = {"raw": raw, "fm": fm, "body": body, "props": props}

manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
if set(manifest) != set(notes):
    err(f"manifest/notes mismatch: only in manifest {sorted(set(manifest) - set(notes))}, "
        f"only on disk {sorted(set(notes) - set(manifest))}")
langs_of = {nid: set(manifest.get(nid, {}).get("lang", [])) for nid in notes}

if len(notes) != 40:
    err(f"expected 40 notes, found {len(notes)}")

for nid, n in notes.items():
    for link in re.findall(r"\[\[([^\]|#]+)", n["raw"]):
        if link not in notes:
            err(f"{nid}: wikilink to missing note [[{link}]]")


def need_note(where: str, nid) -> bool:
    if not isinstance(nid, str) or nid not in notes:
        err(f"{where}: unknown note id {nid!r}")
        return False
    return True


# ---------------------------------------------------------------- tasks
def load(name: str) -> list[dict]:
    items = []
    path = TASKS_DIR / f"{name}.jsonl"
    for i, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip():
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError as e:
            err(f"{name}.jsonl:{i}: invalid JSON ({e})")
            continue
        if not isinstance(obj, dict):
            err(f"{name}.jsonl:{i}: line is not an object")
            continue
        items.append(obj)
    ids = Counter(o.get("id") for o in items)
    for k, c in ids.items():
        if not k:
            err(f"{name}.jsonl: item without id")
        elif c > 1:
            err(f"{name}.jsonl: duplicate id {k}")
    return items


def require(name: str, item: dict, fields: list[str]) -> None:
    for f in fields:
        if f not in item:
            err(f"{name}/{item.get('id')}: missing field {f!r}")


report: dict[str, dict] = {}

# retrieval -----------------------------------------------------------
retrieval = load("retrieval")
cross = 0
for t in retrieval:
    require("retrieval", t, ["id", "lang", "query", "expected"])
    exp = t.get("expected") or []
    if not exp:
        err(f"retrieval/{t['id']}: empty expected")
    for nid in exp:
        need_note(f"retrieval/{t['id']}", nid)
    if any(nid in notes and t.get("lang") not in langs_of[nid] for nid in exp):
        cross += 1
report["retrieval"] = {"items": len(retrieval), "cross_lingual": cross,
                       "langs": Counter(t.get("lang") for t in retrieval)}
if len(retrieval) != 60:
    err(f"retrieval: expected 60 items, found {len(retrieval)}")
if cross < 15:
    err(f"retrieval: only {cross} cross-lingual items (need >= 15)")


def check_groups(where: str, groups, text: str) -> None:
    for g in groups:
        alts = group_alts(g)
        if not alts:
            err(f"{where}: empty must_include group")
        elif not any(has(text, a) for a in alts):
            err(f"{where}: no alternative of {alts} found in source note(s)")


# ask -----------------------------------------------------------------
ask = load("ask")
ask_cross = ask_unans = ask_distr = 0
for t in ask:
    require("ask", t, ["id", "lang", "query", "notes", "answerable", "must_include", "must_not"])
    where = f"ask/{t['id']}"
    ids = t.get("notes") or []
    if not ids:
        err(f"{where}: empty notes")
    if not all(need_note(where, nid) for nid in ids):
        continue
    if len(ids) > 1:
        ask_distr += 1
    primary = ids[0]
    is_cross = t["lang"] not in langs_of[primary]
    ask_cross += is_cross
    if not t["answerable"]:
        ask_unans += 1
        if t["must_include"]:
            err(f"{where}: unanswerable item must have empty must_include")
        if not t["must_not"]:
            err(f"{where}: unanswerable item should list tempting fabrications in must_not")
        continue
    if not t["must_include"]:
        err(f"{where}: answerable item has empty must_include")
    if not is_cross:
        check_groups(where, t["must_include"], notes[primary]["raw"])
    for bad in t["must_not"]:
        if has(notes[primary]["raw"], bad):
            warn(f"{where}: must_not {bad!r} also occurs in the answer note (intentional same-note trap?)")
report["ask"] = {"items": len(ask), "cross_lingual": ask_cross, "unanswerable": ask_unans,
                 "with_distractors": ask_distr, "langs": Counter(t.get("lang") for t in ask)}
if len(ask) != 30:
    err(f"ask: expected 30 items, found {len(ask)}")
if ask_cross < 8:
    err(f"ask: only {ask_cross} cross-lingual items (need >= 8)")

# summarize -----------------------------------------------------------
summ = load("summarize")
sum_cross = 0
for t in summ:
    require("summarize", t, ["id", "lang", "note", "max_words", "must_include", "must_not"])
    where = f"summarize/{t['id']}"
    if not need_note(where, t.get("note")):
        continue
    n = len(t["must_include"])
    if not 3 <= n <= 5:
        err(f"{where}: must_include should have 3-5 groups, has {n}")
    is_cross = t["lang"] not in langs_of[t["note"]]
    sum_cross += is_cross
    if not is_cross:
        check_groups(where, t["must_include"], notes[t["note"]]["raw"])
    for bad in t["must_not"]:
        if has(notes[t["note"]]["raw"], bad):
            err(f"{where}: must_not {bad!r} occurs in the source note")
report["summarize"] = {"items": len(summ), "cross_language": sum_cross,
                       "langs": Counter(t.get("lang") for t in summ)}
if len(summ) != 16:
    err(f"summarize: expected 16 items, found {len(summ)}")

# edit ----------------------------------------------------------------
edit = load("edit")
kinds = Counter()
edit_non_en = 0
for t in edit:
    require("edit", t, ["id", "kind", "note", "selection", "instruction", "lang", "expect"])
    where = f"edit/{t['id']}"
    kind = t.get("kind")
    kinds[kind] += 1
    edit_non_en += t.get("lang") != "en"
    exp = t.get("expect") or {}
    if kind == "create":
        if t["note"] is not None:
            err(f"{where}: create items must have note null")
        if not exp.get("title_contains") or not exp.get("contains"):
            err(f"{where}: create expect needs title_contains and contains")
        continue
    if not need_note(where, t.get("note")):
        continue
    note = notes[t["note"]]
    if kind == "rewrite_selection":
        sel = t.get("selection")
        if not isinstance(sel, str) or not sel:
            err(f"{where}: missing selection")
        else:
            c = note["body"].count(sel)
            if c != 1:
                err(f"{where}: selection occurs {c} times in note body (need exactly 1)")
        if not exp.get("contains"):
            err(f"{where}: rewrite expect needs contains")
    elif kind == "append":
        if t.get("selection") is not None:
            err(f"{where}: append items must have selection null")
        if not exp.get("contains"):
            err(f"{where}: append expect needs contains")
    elif kind == "instruction":
        if t.get("selection") is not None:
            err(f"{where}: instruction items must have selection null")
        for p in exp.get("preserve", []):
            c = note["raw"].count(p)
            if c != 1:
                err(f"{where}: preserve string {p!r} occurs {c} times (need exactly 1)")
        if not exp.get("preserve"):
            err(f"{where}: instruction expect needs preserve")
        for g in exp.get("contains", []):
            if any(has(note["raw"], a) for a in group_alts(g)):
                err(f"{where}: contains {g!r} is already satisfied by the unedited note")
        for bad in exp.get("not_contains", []):
            if not has(note["raw"], bad):
                err(f"{where}: not_contains {bad!r} is absent from the unedited note (vacuous check)")
    elif kind == "properties":
        if t.get("selection") is not None:
            err(f"{where}: properties items must have selection null")
        props = note["props"]
        for k in exp.get("removed_properties", []):
            if k not in props:
                err(f"{where}: removed property {k!r} not present in the note")
        for k, v in exp.get("properties", {}).items():
            if props.get(k) == v:
                err(f"{where}: property {k!r} already has the expected value")
        if exp.get("preserve_body") is not True:
            err(f"{where}: properties expect must set preserve_body true")
        if not exp.get("properties") and not exp.get("removed_properties"):
            err(f"{where}: properties expect changes nothing")
    else:
        err(f"{where}: unknown kind {kind!r}")
report["edit"] = {"items": len(edit), "kinds": kinds, "non_english_instructions": edit_non_en,
                  "langs": Counter(t.get("lang") for t in edit)}
if len(edit) != 40:
    err(f"edit: expected 40 items, found {len(edit)}")
for k in ["rewrite_selection", "append", "instruction", "create", "properties"]:
    if kinds[k] != 8:
        err(f"edit: expected 8 items of kind {k}, found {kinds[k]}")
if edit_non_en < 10:
    err(f"edit: only {edit_non_en} non-English instructions (need >= 10)")

# route ---------------------------------------------------------------
route = load("route")
for t in route:
    require("route", t, ["id", "lang", "request", "expected"])
    if t.get("expected") not in {"ask", "summarize", "edit"}:
        err(f"route/{t['id']}: invalid expected {t.get('expected')!r}")
report["route"] = {"items": len(route), "expected": Counter(t.get("expected") for t in route),
                   "langs": Counter(t.get("lang") for t in route)}
if len(route) != 40:
    err(f"route: expected 40 items, found {len(route)}")

# ---------------------------------------------------------------- output
note_langs = Counter("+".join(manifest[n]["lang"]) for n in notes if n in manifest)
longest = max(notes, key=lambda n: len(notes[n]["body"].split()))
short = [n for n in notes if len(notes[n]["body"].split()) < 80 and not langs_of[n] & {"ja", "zh"}]


def fmt(c: Counter) -> str:
    return ", ".join(f"{k}={v}" for k, v in sorted(c.items()))


print(f"notes: {len(notes)} ({fmt(note_langs)})")
print(f"  longest: {longest} ({len(notes[longest]['body'].split())} words); "
      f"short (<80 words, non-CJK): {len(short)}")
for name, r in report.items():
    extras = ", ".join(f"{k}: {fmt(v) if isinstance(v, Counter) else v}"
                       for k, v in r.items() if k not in ("items", "langs"))
    print(f"{name}: {r['items']} items; langs: {fmt(r['langs'])}; {extras}")
for w in warnings:
    print(f"WARNING: {w}")
for e in errors:
    print(f"ERROR: {e}")
print("OK" if not errors else f"FAILED with {len(errors)} error(s)")
sys.exit(1 if errors else 0)
