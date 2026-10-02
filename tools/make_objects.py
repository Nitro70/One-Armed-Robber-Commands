"""Write mod/Mods/OARCommands/Scripts/objects.lua: the different objects one class can be.

Many items in the game are one Blueprint class placed with different data: every "Artwork" is a
Statue_museum_C, but each one in a map has its own mesh, material, size and value. A plain
summon of the class only ever gives the class's default look. This script reads every map in the
pak, collects the distinct looks of each item class, and gives each one a name, so summon can
spawn the class and then put that data on it.

Covered: everything that can be picked up (classes built on PickupItem_base_C) and the classes in
EXTRA_CLASSES. A look is the meshes and materials of the object's mesh components plus its text
variables (a keycard's name). Numbers (value, XP) and size are taken from the most common placed
copy of that look.

The in-game names of items (the text shown when you look at one) are added as names for the
plain class too, so "summon artwork" works next to "summon statue_museum".
"""
import collections
import os
import re
import unicodedata

import oar_registry
from oar_package import Package, Ref
from oar_pak import Pak

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.path.join(os.path.dirname(HERE), "mod", "Mods", "OARCommands", "Scripts")
OUT = os.path.join(SCRIPTS, "objects.lua")
SPAWNABLES = os.path.join(SCRIPTS, "spawnables.lua")

ITEM_ROOT = "PickupItem_base_C"
EXTRA_CLASSES = {"PushableItem_C", "BP_replicatedPhysicsItem_C", "BP_Balloon_C"}
MESH_COMPONENTS = {"StaticMeshComponent": "StaticMesh", "SkeletalMeshComponent": "SkeletalMesh"}
# Actor properties that describe the placed copy itself, not what kind of object it is.
NOT_DATA = {"RootComponent", "BlueprintCreatedComponents", "InstanceComponents", "ParentComponent", "Owner",
            "Instigator", "AttachParent", "bCanBeInCluster", "bCanBeDamaged", "UberGraphFrame", "Tags", "Layers",
            "bHidden", "bNetStartup", "RemoteRole", "Role"}
# Extra names for objects that are known by a name the game files do not spell out.
# name -> (the generated name it stands for, the label to show)
EXTRA_NAMES = {
    # The museum heist's main objective; the game's own icon for it is called "MonaLisa".
    "mona_lisa": ("artwork_wall_safe_01_painting_01", "Artwork: Mona Lisa (the museum's painting)"),
}
MESH_PREFIXES = ("sm_prop_", "sm_env_", "sm_bld_", "sm_wep_", "sm_veh_", "sm_", "prop_", "s_")
MATERIAL_PREFIXES = ("m_", "mi_", "mat_")


def squash(text):
    plain = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode("ascii")
    return re.sub(r"[^a-z0-9]+", "_", plain.lower()).strip("_")


def short(path, prefixes):
    name = squash(path.rsplit(".", 1)[-1])
    for p in prefixes:
        if name.startswith(p) and len(name) > len(p):
            return name[len(p):]
    return name


def is_asset(value):
    return isinstance(value, Ref) and value.startswith("/")


def package_of(class_path):
    """'/Game/BP/Items/X.X_C' -> 'OAR/Content/BP/Items/X' (None for classes outside /Game)."""
    pkg = class_path.split(".")[0]
    if not pkg.startswith("/Game/"):
        return None
    return "OAR/Content/" + pkg[len("/Game/"):]


class Classes:
    def __init__(self, pak):
        self.pak = pak
        self.by_name = {b["name"]: b for b in oar_registry.blueprint_classes()}
        self._look_names = {}

    def chain(self, name):
        out = []
        while name in self.by_name and name not in out:
            out.append(name)
            name = self.by_name[name]["parent"]
        return out

    def items(self):
        return {n for n in self.by_name if ITEM_ROOT in self.chain(n) or n in EXTRA_CLASSES}

    def look_name(self, name):
        """The text shown when you look at an object of this class (its LookatInfoComponent), or None."""
        for cls in self.chain(name):
            if cls not in self._look_names:
                self._look_names[cls] = self._own_look_name(cls)
            if self._look_names[cls]:
                return self._look_names[cls]
        return None

    def _own_look_name(self, cls):
        base = package_of(self.by_name[cls]["path"])
        if not base or base + ".uasset" not in self.pak.files:
            return None
        pkg = Package(base, self.pak.read(base + ".uasset"), self.pak.read(base + ".uexp"))
        for e in pkg.exports:
            if e["name"] == "LookatInfoComponent_GEN_VARIABLE":
                return pkg.read_values(pkg.export_data(e)).get("Name") or None
        return None


def placed_objects(pak, wanted):
    """Yield (class name, map name, data) for every placed actor of a wanted class in every map.

    data = {"texts": {var: str}, "numbers": {var: number or bool}, "assets": {var: path},
            "comps": {component: {"mesh": path, "skeletal": bool, "materials": [path or None], "scale": (x, y, z)}}}
    """
    for map_file in sorted(f for f in pak.files if f.endswith(".umap")):
        base = map_file[:-len(".umap")]
        try:
            pkg = Package(base, pak.read(map_file), pak.read(base + ".uexp"))
        except (ValueError, KeyError):
            continue
        children = collections.defaultdict(list)
        for e in pkg.exports:
            children[e["outer"]].append(e)
        for index, e in enumerate(pkg.exports, start=1):
            cls = pkg.class_of(e)
            if cls not in wanted or not e["outer"]:
                continue
            values = pkg.read_values(pkg.export_data(e))
            subs = {c["name"]: c for c in children[index]}
            root = str(values.get("RootComponent") or "").rsplit(".", 1)[-1]
            data = {"texts": {}, "numbers": {}, "assets": {}, "comps": {}}
            for name, value in values.items():
                if name in NOT_DATA or value is None:
                    continue
                if isinstance(value, Ref):
                    if is_asset(value):
                        data["assets"][name] = str(value)
                elif isinstance(value, str):
                    if "::" not in value:                  # an enum value: left to the class default
                        data["texts"][name] = value
                elif isinstance(value, (bool, int, float)):
                    data["numbers"][name] = value
            for name, c in subs.items():
                mesh_property = MESH_COMPONENTS.get(pkg.class_of(c))
                if not mesh_property:
                    continue
                cv = pkg.read_values(pkg.export_data(c))
                comp = {}
                if is_asset(cv.get(mesh_property)):
                    comp["mesh"] = str(cv[mesh_property])
                    comp["skeletal"] = mesh_property == "SkeletalMesh"
                materials = cv.get("OverrideMaterials")
                if isinstance(materials, list) and any(is_asset(m) for m in materials):
                    comp["materials"] = [str(m) if is_asset(m) else None for m in materials]
                if name == root and isinstance(cv.get("RelativeScale3D"), tuple):
                    comp["scale"] = tuple(round(x, 3) for x in cv["RelativeScale3D"])
                if comp:
                    data["comps"][name] = comp
            yield cls, base.rsplit("/", 1)[-1], data


def look_key(data):
    """What makes two placed copies the same kind of object: meshes, materials and text variables."""
    comps = tuple(sorted((name, c.get("mesh"), tuple(c.get("materials") or ())) for name, c in data["comps"].items()
                         if "mesh" in c or "materials" in c))
    return comps, tuple(sorted(data["texts"].items())), tuple(sorted(data["assets"].items()))


def most_common(values):
    return collections.Counter(values).most_common(1)[0][0]


def merge(copies):
    """One object out of all placed copies with the same look: the usual numbers and size."""
    first = copies[0]
    out = {"texts": dict(first["texts"]), "assets": dict(first["assets"]), "numbers": {}, "comps": {}}
    for name in sorted({n for c in copies for n in c["numbers"]}):
        have = [c["numbers"][name] for c in copies if name in c["numbers"]]
        if len(have) * 2 >= len(copies):                   # set on at least half of them
            out["numbers"][name] = most_common(have)
    for name, comp in first["comps"].items():
        merged = {k: v for k, v in comp.items() if k != "scale"}
        scales = [c["comps"][name]["scale"] for c in copies if "scale" in c["comps"].get(name, {})]
        if len(scales) * 2 >= len(copies):
            merged["scale"] = most_common(scales)
        if merged:
            out["comps"][name] = merged
    return out


def variant_part(data, taken_by_mesh):
    """The part of the name that tells this object from the others of its class."""
    if data["texts"]:
        return squash(" ".join(v for _k, v in sorted(data["texts"].items())))
    meshes = [c["mesh"] for _n, c in sorted(data["comps"].items()) if "mesh" in c]
    assets = [v for _k, v in sorted(data["assets"].items())]
    materials = [m for _n, c in sorted(data["comps"].items()) for m in c.get("materials", []) if m]
    if meshes or assets:
        part = short((meshes or assets)[0], MESH_PREFIXES)
        if taken_by_mesh.get(part, 0) > 1 and materials:
            part += "_" + short(materials[0], MATERIAL_PREFIXES)
        return part
    if materials:
        return short(materials[0], MATERIAL_PREFIXES)
    return ""


def lua_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def lua_value(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(round(value, 4)) if isinstance(value, float) else str(value)
    return lua_string(value)


def lua_entry(key, cls, path, label, data):
    parts = [f"name = {lua_string(cls)}", f"path = {lua_string(path)}", f"label = {lua_string(label)}"]
    if data:
        props = dict(data["numbers"])
        props.update(data["texts"])
        if props:
            parts.append("props = { " + ", ".join(f"[{lua_string(k)}] = {lua_value(v)}" for k, v in sorted(props.items())) + " }")
        if data["assets"]:
            parts.append("assets = { " + ", ".join(f"[{lua_string(k)}] = {lua_string(v)}"
                                                    for k, v in sorted(data["assets"].items())) + " }")
        comps = []
        for name, c in sorted(data["comps"].items()):
            fields = []
            if "mesh" in c:
                fields.append(f"mesh = {lua_string(c['mesh'])}")
                if c.get("skeletal"):
                    fields.append("skeletal = true")
            if "materials" in c:
                slots = ", ".join(f"[{i}] = {lua_string(m)}" for i, m in enumerate(c["materials"]) if m)
                fields.append("materials = { " + slots + " }")
            if "scale" in c:
                fields.append("scale = { " + ", ".join(repr(x) for x in c["scale"]) + " }")
            comps.append(f"[{lua_string(name)}] = {{ " + ", ".join(fields) + " }")
        if comps:
            parts.append("comps = { " + ", ".join(comps) + " }")
    return f"  [{lua_string(key)}] = {{ " + ",\n      ".join(parts) + " },"


def build(pak):
    """-> [(key, class, path, label, data or None)] sorted by key, and the map names per key."""
    classes = Classes(pak)
    wanted = classes.items()
    taken = set(re.findall(r'^\s*\["([^"]+)"\]', open(SPAWNABLES, encoding="utf-8").read(), re.M))

    groups = collections.defaultdict(lambda: collections.defaultdict(list))   # class -> look -> copies
    where = collections.defaultdict(lambda: collections.defaultdict(set))
    for cls, map_name, data in placed_objects(pak, wanted):
        key = look_key(data)
        groups[cls][key].append(data)
        where[cls][key].add(map_name)

    entries, maps_of = [], {}

    def add(key, cls, label, data, maps=()):
        base, n = key, 2
        while key in taken:
            key = f"{base}_{n}"
            n += 1
        taken.add(key)
        entries.append((key, cls, classes.by_name[cls]["path"], label, data))
        maps_of[key] = sorted(maps)

    # The in-game name as another name for the plain class ("artwork" for Statue_museum_C).
    by_look_name = collections.defaultdict(list)
    for cls in sorted(wanted):
        name = classes.look_name(cls)
        if name:
            by_look_name[squash(name)].append(cls)
    for name, owners in sorted(by_look_name.items()):
        if len(owners) == 1 and name and name not in taken:
            add(name, owners[0], classes.look_name(owners[0]), None)

    for cls in sorted(groups, key=str.lower):
        class_key = squash(cls[:-2] if cls.endswith("_C") else cls)
        base = squash(classes.look_name(cls) or "") or class_key
        title = classes.look_name(cls) or cls
        merged = {key: merge(copies) for key, copies in groups[cls].items() if any(key)}
        parts_seen = collections.Counter()
        for data in merged.values():
            parts_seen[variant_part(data, {})] += 1
        for key in sorted(merged, key=repr):
            data = merged[key]
            part = variant_part(data, parts_seen)
            if not part:
                continue
            name = part if base in part else f"{base}_{part}"
            detail = ", ".join(v for _k, v in sorted(data["texts"].items())) or part
            add(name, cls, f"{title}: {detail}", data, where[cls][key])
    by_key = {e[0]: e for e in entries}
    for name, (target, label) in sorted(EXTRA_NAMES.items()):
        if target not in by_key:
            raise SystemExit(f"{name}: there is no object called {target} any more; update EXTRA_NAMES")
        _key, cls, _path, _label, data = by_key[target]
        add(name, cls, label, data, maps_of[target])
    entries.sort(key=lambda e: e[0])
    return entries, maps_of


def main():
    entries, _maps = build(Pak())
    objects = [e for e in entries if e[4]]
    if len(objects) < 10:
        raise SystemExit(f"only {len(objects)} objects found; refusing to write a partial table")
    lines = ["-- Generated by make_objects.py from the maps in the game's pak.",
             "-- Names for summon that are one class with different data: its meshes, materials, size and",
             "-- variables, as placed in the game's maps. An entry without data is the in-game name of a",
             "-- plain class.",
             "return {"]
    lines += [lua_entry(*e) for e in entries]
    lines.append("}")
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print(f"{len(objects)} objects and {len(entries) - len(objects)} in-game names -> {OUT}")


if __name__ == "__main__":
    main()
