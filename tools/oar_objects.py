"""Build the full object list for One-armed robber from the game files (every map, not one).

Writes into ../lists:
    OAR_Full_Object_List.txt   every Blueprint class, level script and struct in the game with
                               parent chain, components, variables and functions (with params)
    OAR_All_Assets.txt         every asset in the pak, grouped by type
    ../build/oar_objects.json  the same class data, for other scripts

Engine (C++) classes are not repeated here: they are all compiled into the exe, so the
UUU_ObjectsDump.txt from any map already lists every one of them with full detail.
"""
import json
import os
import re
import sys
import time
from collections import defaultdict

import oar_registry
from oar_package import (CPF_NET, CPF_OUTPARM, CPF_PARM, CPF_REFERENCEPARM, CPF_RETURNPARM, FUNC_FLAGS, Package,
                         describe)
from oar_pak import Pak

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(REPO, "lists")
JSON_OUT = os.path.join(REPO, "build", "oar_objects.json")
CLASS_EXPORTS = {"BlueprintGeneratedClass", "WidgetBlueprintGeneratedClass", "AnimBlueprintGeneratedClass"}
PACKAGE_KINDS = {"Blueprint", "WidgetBlueprint", "AnimBlueprint", "World", "UserDefinedStruct"}
INTERNAL_FUNCS = ("ExecuteUbergraph_", "BndEvt__")
INTERNAL_VARS = {"UberGraphFrame"}
GUID_SUFFIX = re.compile(r"_\d+_[0-9A-F]{32}$")
SHOWN_FLAGS = {"Exec", "NetServer", "NetClient", "NetMulticast", "Event", "BlueprintPure", "Static"}
FLAG_LABELS = {"NetServer": "Server", "NetClient": "Client", "NetMulticast": "Multicast", "BlueprintPure": "Pure"}


def pak_path(object_path, kind):
    """'/Game/BP/Items/Duffelbag.Duffelbag' -> 'OAR/Content/BP/Items/Duffelbag'."""
    pkg = object_path.split(".")[0]
    root, rest = pkg.split("/")[1], "/".join(pkg.split("/")[2:])
    if root == "Game":
        base = f"OAR/Content/{rest}"
    elif root == "Engine":
        base = f"Engine/Content/{rest}"
    else:
        base = f"OAR/Plugins/{root}/Content/{rest}"
    return base, (".umap" if kind == "World" else ".uasset")


def find_in_pak(pak, base, ext):
    if base + ext in pak.files:
        return base
    tail = "/" + base.split("/", 2)[-1] + ext            # plugins can sit under other folders
    for name in pak.files:
        if name.endswith(tail):
            return name[:-len(ext)]
    return None


def param_text(p):
    out = "out " if p["flags"] & CPF_OUTPARM and not p["flags"] & CPF_REFERENCEPARM else ""
    return f"{out}{describe(p)} {p['name']}"


def parse_package(pak, base, ext, kind, object_path):
    pkg = Package(base, pak.read(base + ext), pak.read(base + ".uexp"))
    results = []
    for idx, e in enumerate(pkg.exports, start=1):
        cls = pkg.class_of(e)
        if cls in CLASS_EXPORTS:
            super_name, _children, props, _ = pkg.read_struct(e)
            comps = {}
            funcs = []
            for x in pkg.exports:
                if x["outer"] != idx:
                    continue
                xcls = pkg.class_of(x)
                if x["name"].endswith("_GEN_VARIABLE"):
                    comps[x["name"][:-len("_GEN_VARIABLE")]] = xcls
                elif xcls == "Function" and not x["name"].startswith(INTERNAL_FUNCS):
                    _s, _c, fprops, fflags = pkg.read_struct(x)
                    params = [p for p in fprops if p["flags"] & CPF_PARM and not p["flags"] & CPF_RETURNPARM]
                    ret = [p for p in fprops if p["flags"] & CPF_RETURNPARM]
                    flags = [n for bit, n in FUNC_FLAGS if fflags & bit and n in SHOWN_FLAGS]
                    funcs.append(dict(name=x["name"], params=[param_text(p) for p in params],
                                      returns=describe(ret[0]) if ret else "",
                                      flags=[FLAG_LABELS.get(f, f) for f in flags], func_flags=fflags))
            variables = [dict(type=describe(p), name=p["name"], replicated=bool(p["flags"] & CPF_NET))
                         for p in props if p["name"] not in INTERNAL_VARS and p["name"] not in comps]
            results.append(dict(kind="class", name=e["name"], parent=super_name, path=object_path, asset_kind=kind,
                                components=comps, variables=variables, functions=funcs))
        elif cls == "Level" and kind == "World":
            placed = defaultdict(int)
            for x in pkg.exports:
                if x["outer"] == idx:
                    placed[pkg.class_of(x)] += 1
            results.append(dict(kind="map", name=object_path.split(".")[-1], path=object_path, placed=dict(placed)))
        elif cls == "UserDefinedStruct":
            _s, _c, props, _ = pkg.read_struct(e)
            results.append(dict(kind="struct", name=e["name"], path=object_path,
                                fields=[dict(type=describe(p), name=GUID_SUFFIX.sub("", p["name"])) for p in props]))
    return results


def chain(name, by_name):
    out, seen = [], set()
    while name in by_name and name not in seen:
        seen.add(name)
        name = by_name[name]["parent"]
        out.append(name)
    return out


def write_object_list(records, errors):
    classes = [r for r in records if r["kind"] == "class"]
    structs = [r for r in records if r["kind"] == "struct"]
    maps = [r for r in records if r["kind"] == "map"]
    by_name = {r["name"]: r for r in classes}
    found_on = defaultdict(list)
    for m in maps:
        for cname in m["placed"]:
            found_on[cname].append(m["name"])
    L = []
    w = L.append
    w("ONE-ARMED ROBBER: FULL OBJECT LIST")
    w("=" * 78)
    w("Every Blueprint in the game files, from every map, read straight out of the pak.")
    w(f"{len(classes)} classes (incl. {sum(r['asset_kind'] == 'World' for r in classes)} level scripts), "
      f"{len(structs)} structs, contents of {len(maps)} maps.")
    w("Engine (C++) classes are all in UUU_ObjectsDump.txt already (they live in the exe).")
    w("")
    w("Layout per class:  Name : Parent : Grandparent ...    /Game/path")
    w("  components  name (component class)")
    w("  variables   type name   [replicated]")
    w("  maps        maps this class is placed on (load one with  open <map>  to summon it by short name)")
    w("  functions   Name(params) -> return   [Server/Client/Multicast = network RPC, Event, Pure]")
    w("Function locals and compiler-made functions (ExecuteUbergraph, BndEvt__) are left out.")
    sections = [("LEVEL SCRIPTS (one per map; their events can be fired with  ce <EventName>  if ce works)",
                 lambda r: r["asset_kind"] == "World"),
                ("WIDGETS (UI)", lambda r: r["asset_kind"] == "WidgetBlueprint"),
                ("ANIMATION BLUEPRINTS", lambda r: r["asset_kind"] == "AnimBlueprint"),
                ("BLUEPRINT CLASSES", lambda r: True)]
    done = set()
    for title, test in sections:
        group = sorted((r for r in classes if r["name"] not in done and test(r)), key=lambda r: r["name"].lower())
        done.update(r["name"] for r in group)
        w("")
        w("")
        w(f"{title}  [{len(group)}]")
        w("=" * 78)
        for r in group:
            w("")
            w(f"{' : '.join([r['name']] + chain(r['name'], by_name))}    {r['path'].split('.')[0]}")
            if found_on.get(r["name"]):
                w("  maps        " + ", ".join(sorted(set(found_on[r["name"]]), key=str.lower)))
            if r["components"]:
                w("  components  " + ", ".join(f"{n} ({c})" for n, c in sorted(r["components"].items())))
            for v in r["variables"]:
                w(f"  var   {v['type']} {v['name']}" + ("   [replicated]" if v["replicated"] else ""))
            for f in sorted(r["functions"], key=lambda f: f["name"].lower()):
                ret = f" -> {f['returns']}" if f["returns"] else ""
                flags = f"   [{', '.join(f['flags'])}]" if f["flags"] else ""
                w(f"  func  {f['name']}({', '.join(f['params'])}){ret}{flags}")
    w("")
    w("")
    w(f"WHAT IS PLACED ON EACH MAP  [{len(maps)} maps]  (Blueprint actors only, with counts)")
    w("=" * 78)
    w("Only what the level designer placed. Things the game spawns while you play (vault loot,")
    w("police waves) are not in the map file, so they don't show up here.")
    for m in sorted(maps, key=lambda m: m["path"].lower()):
        bp = {c: n for c, n in m["placed"].items() if c in by_name}
        w("")
        w(f"{m['name']}    {m['path'].split('.')[0]}    ({sum(m['placed'].values())} actors, {len(bp)} Blueprint types)")
        items = sorted(bp.items(), key=lambda kv: (-kv[1], kv[0].lower()))
        for i in range(0, len(items), 4):
            w("  " + "".join(f"{f'{c} x{n}':<34}" for c, n in items[i:i + 4]).rstrip())
    w("")
    w("")
    w(f"STRUCTS  [{len(structs)}]")
    w("=" * 78)
    for s in sorted(structs, key=lambda s: s["name"].lower()):
        w("")
        w(f"{s['name']}    {s['path'].split('.')[0]}")
        for fld in s["fields"]:
            w(f"  {fld['type']} {fld['name']}")
    if errors:
        w("")
        w("")
        w(f"COULD NOT BE READ  [{len(errors)}]")
        w("=" * 78)
        for path, err in errors:
            w(f"  {path}: {err}")
    with open(os.path.join(OUT_DIR, "OAR_Full_Object_List.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(L) + "\n")


def write_asset_list(assets):
    groups = defaultdict(list)
    for path, cls in assets:
        groups[cls].append(path.split(".")[0])
    L = ["ONE-ARMED ROBBER: EVERY ASSET IN THE GAME", "=" * 78,
         f"{len(assets)} assets from the game's asset registry, grouped by type (biggest groups first).", ""]
    L.append("  " + ", ".join(f"{cls} {len(v)}" for cls, v in sorted(groups.items(), key=lambda kv: -len(kv[1]))))
    for cls, paths in sorted(groups.items(), key=lambda kv: -len(kv[1])):
        L += ["", "", f"{cls}  [{len(paths)}]", "-" * 78]
        L += [f"  {p}" for p in sorted(paths, key=str.lower)]
    with open(os.path.join(OUT_DIR, "OAR_All_Assets.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(L) + "\n")


def main():
    t0 = time.time()
    pak = Pak()
    assets = oar_registry.all_assets()
    write_asset_list(assets)
    records, errors = [], []
    todo = [(p, k) for p, k in assets if k in PACKAGE_KINDS]
    for n, (object_path, kind) in enumerate(todo, 1):
        base, ext = pak_path(object_path, kind)
        found = find_in_pak(pak, base, ext)
        if not found:
            errors.append((object_path, "not in pak"))
            continue
        try:
            records += parse_package(pak, found, ext, kind, object_path)
        except Exception as e:                      # keep going; list what failed at the end
            errors.append((object_path, f"{type(e).__name__}: {e}"))
        if n % 100 == 0:
            print(f"  {n}/{len(todo)} packages, {time.time() - t0:.0f}s", flush=True)
    write_object_list(records, errors)
    os.makedirs(os.path.dirname(JSON_OUT), exist_ok=True)
    with open(JSON_OUT, "w", encoding="utf-8") as f:
        json.dump(records, f)
    print(f"{len(records)} classes/structs/maps from {len(todo)} packages, {len(errors)} errors, {time.time() - t0:.0f}s")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
