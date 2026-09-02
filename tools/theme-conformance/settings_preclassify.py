import json, re, sys, os, collections
fix = sys.argv[1]
TRAIL = re.compile(r",(\s*[}\]])")
BLOCKC = re.compile(r"/\*.*?\*/", re.S)


def tolerant(j):
    j = BLOCKC.sub("", j)
    j = TRAIL.sub(lambda m: m.group(1), j)  # trailing commas, same as engine tolerant_json
    return json.loads(j)


def schema_of(path):
    try:
        src = open(path, encoding="utf-8", errors="replace").read()
    except FileNotFoundError:
        return None
    m = re.search(r"{%-?\s*schema\s*-?%}(.*?){%-?\s*endschema\s*-?%}", src, re.S)
    if not m:
        return None
    try:
        return tolerant(m.group(1))
    except Exception as e:
        return {"_err": str(e)}


def walk_settings(defs):
    for d in defs or []:
        if isinstance(d, dict) and "id" in d:
            yield d
        for sub in (d.get("settings") if isinstance(d, dict) else None) or []:
            if isinstance(sub, dict) and "id" in sub:
                yield sub


for theme, rep in [("minimog-6.0.0", "tmp/conformance-minimog-6.0.0.json"), ("kalles-5.4.2", "tmp/conformance-kalles-5.4.2.json")]:
    tdir = os.path.join(fix, theme)
    r = json.load(open(rep, encoding="utf-8"))
    gschema = tolerant(open(os.path.join(tdir, "config/settings_schema.json"), encoding="utf-8-sig").read())
    gsettings = {s["id"]: s for g in gschema for s in walk_settings(g.get("settings"))}
    csg = next((s for g in gschema for s in walk_settings(g.get("settings")) if s.get("type") == "color_scheme_group"), None)
    csg_defs = {d["id"]: d for d in (csg or {}).get("definition", []) if isinstance(d, dict) and "id" in d}
    sdata = tolerant(open(os.path.join(tdir, "config/settings_data.json"), encoding="utf-8-sig").read())
    cur = sdata.get("current", {})
    cur = cur if isinstance(cur, dict) else sdata.get("presets", {}).get(cur, {})
    block_defs = collections.defaultdict(dict)
    parse_errs = []
    for f in os.listdir(os.path.join(tdir, "sections")):
        sch = schema_of(os.path.join(tdir, "sections", f)) or {}
        if "_err" in sch:
            parse_errs.append(f)
        for b in sch.get("blocks", []) or []:
            if isinstance(b, dict) and b.get("type") and not b["type"].startswith("@"):
                for s in b.get("settings", []) or []:
                    if isinstance(s, dict) and "id" in s:
                        block_defs[b["type"]][s["id"]] = s
    bdir = os.path.join(tdir, "blocks")
    if os.path.isdir(bdir):
        for f in os.listdir(bdir):
            sch = schema_of(os.path.join(bdir, f)) or {}
            if "_err" in sch:
                parse_errs.append("blocks/" + f)
            for s in sch.get("settings", []) or []:
                if isinstance(s, dict) and "id" in s:
                    block_defs[f[:-7]][s["id"]] = s
    print("=====", theme, "schema parse errors:", len(parse_errs), parse_errs[:5])
    out = []
    summary = collections.Counter()
    for key, cnt in sorted(r["misses"].items(), key=lambda kv: -kv[1]):
        m = re.match(r"(settings|section|block|color_scheme)(?:\(([^)]*)\))?\.(.*)", key)
        if not m:
            continue
        kind, owner, prop = m.groups()
        val = None
        if kind == "settings":
            d = gsettings.get(prop)
            val = cur.get(prop, "<unset>")
        elif kind == "section":
            sch = schema_of(os.path.join(tdir, "sections", owner + ".liquid")) or {}
            d = next((s for s in walk_settings(sch.get("settings")) if s["id"] == prop), None)
        elif kind == "block":
            d = block_defs.get(owner, {}).get(prop)
        else:
            d = csg_defs.get(prop)
        if d is None:
            verdict = "theme-quirk(not-in-schema)"
        elif "default" in d:
            verdict = "ENGINE-GAP?(schema default present: %s)" % json.dumps(d["default"])[:40]
        elif d.get("type") == "checkbox":
            verdict = "ENGINE-GAP?(checkbox no default => official false)"
        elif d.get("type") in ("select", "radio"):
            verdict = "VERIFY-OFFICIAL(select/radio no default)"
        elif d.get("type") == "color_scheme":
            verdict = "ENGINE-GAP?(color_scheme no default => first scheme)"
        else:
            verdict = "settings-default(nil legit: %s)" % d.get("type")
        summary[verdict.split("(")[0]] += 1
        out.append({"key": key, "count": cnt, "type": d.get("type") if d else None, "value": val, "verdict": verdict})
    json.dump(out, open("tmp/preclassify-%s.json" % theme, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("  summary:", dict(summary))
    for o in out:
        if not o["verdict"].startswith("settings-default") and not o["verdict"].startswith("theme-quirk"):
            print("  %5d %-60s type=%s value=%s -> %s" % (o["count"], o["key"], o["type"], str(o["value"])[:30], o["verdict"]))
    print("  theme-quirk keys:", [o["key"] for o in out if o["verdict"].startswith("theme-quirk")][:60])
