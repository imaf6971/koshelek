#!/usr/bin/env python3
"""Collects every Russian string literal into one Localizable.xcstrings per target (iPhone app, Watch app).

Run after adding or changing UI strings:  python3 scripts/gen_strings.py
Interpolation (\\( )) is forbidden in localized literals: use LF("... %@", value) instead.
"""
import json, re, sys, pathlib

root = pathlib.Path(__file__).resolve().parent.parent
literal = re.compile(r'"((?:[^"\\]|\\.)*)"')
cyr = re.compile(r'[А-Яа-яЁё]')
targets = {
    "Koshelek/Resources/Localizable.xcstrings": ["Koshelek"],
    "KoshelekWatch/Resources/Localizable.xcstrings": ["Koshelek/Domain", "KoshelekWatch"],
}
errors = []

def collect(folders):
    keys = {}
    paths = sorted({p for f in folders for p in (root / f).rglob("*.swift")})
    for path in paths:
        for n, line in enumerate(path.read_text().splitlines(), 1):
            if line.lstrip().startswith("//"):
                continue
            for m in literal.finditer(line):
                s = m.group(1)
                if not cyr.search(s):
                    continue
                if "\\(" in s:
                    errors.append(f"{path.name}:{n}: interpolation in localized string: {s}")
                    continue
                keys[s.replace('\\"', '"').replace("\\n", "\n")] = True
    return keys

for out_rel, folders in targets.items():
    keys = collect(folders)
    if errors:
        print("\n".join(errors)); sys.exit(1)
    catalog = {
        "sourceLanguage": "ru",
        "strings": {k: {"extractionState": "manual", "localizations": {"ru": {"stringUnit": {"state": "translated", "value": k}}}} for k in sorted(keys)},
        "version": "1.0",
    }
    out = root / out_rel
    out.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n")
    print(f"{len(keys)} strings -> {out_rel}")
