import re, json, sys, os, collections
surf = json.load(open(sys.argv[1], encoding="utf-8")); fixroot = sys.argv[2]; themes = sys.argv[3:]
tags_ok = set(surf["tags"]); filters_ok = set(surf["std_filters"]) | set(surf["engine_filters"]); drops = surf["drops"]; globals_ = set(surf["globals"])
norm = lambda s: s.lower().replace("_", "")
dropidx = {norm(k[:-4] if k.endswith("Drop") else k): k for k in drops}
ALIAS = {"item": "lineitem", "line_item": "lineitem", "value": "facetvalue", "filter": "facetfilter", "filter_value": "facetvalue",
         "media": "media", "image": "image", "img": "image", "video": "video", "option": "productoption", "link": "link", "linklist": "linklist",
         "child_link": "link", "childlink": "link", "sublink": "link", "grandchild_link": "link", "comment": "comment", "tag": None,
         "font": "font", "scheme": "colorscheme", "color_scheme": "colorscheme", "address": "address", "order": "order", "line_items": None}
SKIP_ROOTS = set("forloop tablerowloop settings section block closest current_page content_for_header canonical_url page_title page_description powered_by_link additional_checkout_buttons content_for_additional_checkout_buttons all_country_option_tags current_tags".split())
KW = set("if unless elsif else endif endunless case when endcase for endfor in reversed limit offset break continue and or contains assign capture endcapture echo liquid comment endcomment raw endraw increment decrement cycle tablerow endtablerow include render with as true false nil null blank empty form endform paginate endpaginate schema endschema style endstyle stylesheet endstylesheet javascript endjavascript layout section sections content_for doc enddoc by cols".split())
EXPR = re.compile(r"{{-?(.*?)-?}}|{%-?(.*?)-?%}", re.S); STR = re.compile(r"'[^']*'|\"[^\"]*\"")
PROP = re.compile(r"(?<![\w.'\"\[])([a-z_]\w*)\.([a-z_]\w*)"); FILT = re.compile(r"\|\s*([A-Za-z_]\w*)"); TAG = re.compile(r"^\s*(\w+)")
result = {}
for th in themes:
    tags = collections.Counter(); filters = collections.Counter(); props = collections.defaultdict(collections.Counter); roots = collections.Counter(); files = collections.defaultdict(set)
    for dp, _, fns in os.walk(os.path.join(fixroot, th)):
        for fn in fns:
            if not fn.endswith(".liquid"): continue
            src = open(os.path.join(dp, fn), encoding="utf-8", errors="replace").read()
            src = re.sub(r"{%-?\s*schema\s*-?%}.*?{%-?\s*endschema\s*-?%}", "", src, flags=re.S)
            src = re.sub(r"{%-?\s*comment\s*-?%}.*?{%-?\s*endcomment\s*-?%}", "", src, flags=re.S)
            src = re.sub(r"{%-?\s*raw\s*-?%}.*?{%-?\s*endraw\s*-?%}", "", src, flags=re.S)
            rel = os.path.relpath(os.path.join(dp, fn), os.path.join(fixroot, th)).replace("\\", "/")
            for m in EXPR.finditer(src):
                out, tag = m.group(1), m.group(2)
                exprs = []
                if tag is not None:
                    t = TAG.match(tag)
                    name = t.group(1) if t else ""
                    if name == "liquid":
                        for line in tag.split("\n")[1:] if "\n" in tag else []:
                            lt = TAG.match(line)
                            if lt and not lt.group(1).startswith("end"): tags[lt.group(1)] += 1; files[("tag", lt.group(1))].add(rel)
                            exprs.append(line)
                    elif name and not name.startswith("end") and name not in ("else", "elsif", "when"):
                        tags[name] += 1; files[("tag", name)].add(rel); exprs.append(tag)
                    else: exprs.append(tag)
                else: exprs.append(out)
                for e in exprs:
                    e2 = STR.sub("''", e)
                    for f in FILT.findall(e2):
                        filters[f] += 1; files[("filter", f)].add(rel)
                    for r, p in PROP.findall(e2):
                        if r in KW or p in KW: continue
                        props[r][p] += 1; roots[r] += 1; files[("prop", r + "." + p)].add(rel)
    bad_tags = {t: c for t, c in tags.items() if t not in tags_ok and t not in KW}
    bad_filters = {f: c for f, c in filters.items() if f not in filters_ok}
    gaps = {}; unknown_roots = {}
    for r, ps in props.items():
        if r in SKIP_ROOTS: continue
        key = ALIAS.get(r, norm(r)); dk = dropidx.get(key) if key else None
        if dk is None:
            if r not in globals_: unknown_roots[r] = sum(ps.values())
            continue
        meth = set(drops[dk]["methods"])
        miss = {p: c for p, c in ps.items() if p not in meth}
        if miss: gaps[f"{r}→{dk}{'(lmm)' if drops[dk]['lmm'] else ''}"] = dict(sorted(miss.items(), key=lambda kv: -kv[1]))
    result[th] = {"tags_unsupported": bad_tags, "filters_unsupported": bad_filters, "drop_prop_gaps": gaps,
                  "unknown_roots_top": dict(sorted(unknown_roots.items(), key=lambda kv: -kv[1])[:40]),
                  "files": {f"{k[0]}:{k[1]}": sorted(v)[:5] for k, v in files.items() if (k[0] == "tag" and k[1] in bad_tags) or (k[0] == "filter" and k[1] in bad_filters)}}
    print("=====", th)
    print("tags unsupported:", bad_tags)
    print("filters unsupported:", dict(sorted(bad_filters.items(), key=lambda kv: -kv[1])))
    for k, v in gaps.items(): print("  gap", k, ":", ", ".join(f"{p}({c})" for p, c in list(v.items())[:25]), ("… +%d" % (len(v) - 25) if len(v) > 25 else ""))
    print("unknown roots:", dict(sorted(unknown_roots.items(), key=lambda kv: -kv[1])[:30]))
json.dump(result, open(os.path.join(os.path.dirname(sys.argv[1]), "theme_static_scan.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
