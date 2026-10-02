"""Parse cooked UE 4.27 packages (.uasset header + .uexp data) from One-armed robber.

Only what the tools need: the name map, imports, exports, for Blueprint class and function
exports the declared properties (FField serialization) and function flags, and the simple
default values stored on class default objects.
Cooked here means unversioned, editor-only data filtered, tagged property serialization.
"""
import struct

PACKAGE_TAG = 0x9E2A83C1
EXPORT_SIZE = 104
IMPORT_SIZE = 28

# EFunctionFlags / EPropertyFlags bits used in the output
FUNC_FLAGS = [(0x00000400, "Native"), (0x00000200, "Exec"), (0x00000800, "Event"), (0x00000040, "Net"),
              (0x00200000, "NetServer"), (0x01000000, "NetClient"), (0x00004000, "NetMulticast"),
              (0x04000000, "BlueprintCallable"), (0x08000000, "BlueprintEvent"), (0x10000000, "BlueprintPure"),
              (0x00002000, "Static"), (0x00100000, "Delegate")]
CPF_PARM, CPF_OUTPARM, CPF_RETURNPARM, CPF_REFERENCEPARM = 0x80, 0x100, 0x400, 0x8000000
CPF_NET = 0x20

# Structs that are stored as plain numbers instead of tagged properties.
BINARY_STRUCTS = {"Vector": "<3f", "Rotator": "<3f", "LinearColor": "<4f", "Color": "<4B", "Vector2D": "<2f",
                  "Quat": "<4f", "Guid": "<4I", "IntPoint": "<2i"}


class Ref(str):
    """A reference to another object, as its full path."""


class Reader:
    def __init__(self, data, pos=0):
        self.d, self.p = data, pos

    def i32(self):
        v = struct.unpack_from("<i", self.d, self.p)[0]
        self.p += 4
        return v

    def u32(self):
        v = struct.unpack_from("<I", self.d, self.p)[0]
        self.p += 4
        return v

    def i64(self):
        v = struct.unpack_from("<q", self.d, self.p)[0]
        self.p += 8
        return v

    def u8(self):
        v = self.d[self.p]
        self.p += 1
        return v

    def skip(self, n):
        self.p += n

    def fstring(self):
        n = self.i32()
        if n == 0:
            return ""
        if n < 0:
            s = self.d[self.p:self.p - 2 * n].decode("utf-16le")[:-1]
            self.p -= 2 * n
        else:
            s = self.d[self.p:self.p + n - 1].decode("latin-1")
            self.p += n
        return s


class Package:
    def __init__(self, path, uasset, uexp):
        self.path = path
        r = Reader(uasset)
        if r.u32() != PACKAGE_TAG:
            raise ValueError("not a package")
        legacy = r.i32()
        if legacy != -4:
            r.i32()                                        # legacy UE3 version
        r.i32(), r.i32()                                   # file version UE4 / licensee (0 = unversioned)
        r.skip(r.i32() * 20)                               # custom versions
        self.header_size = r.i32()
        r.fstring()                                        # folder name
        pflags = r.u32()
        name_count, name_off = r.i32(), r.i32()
        if not pflags & 0x80000000:                        # not PKG_FilterEditorOnly
            r.fstring()
        r.i32(), r.i32()                                   # gatherable text
        export_count, export_off = r.i32(), r.i32()
        import_count, import_off = r.i32(), r.i32()

        r.p = name_off
        self.names = []
        for _ in range(name_count):
            self.names.append(r.fstring())
            r.skip(4)                                      # two uint16 hashes
        r.p = import_off
        self.imports = []
        for _ in range(import_count):
            cls_pkg, cls_name, outer, obj = self._fname(r), self._fname(r), r.i32(), self._fname(r)
            self.imports.append(dict(class_package=cls_pkg, class_name=cls_name, outer=outer, name=obj))
        r.p = export_off
        self.exports = []
        for _ in range(export_count):
            cls, sup, _tmpl, outer = r.i32(), r.i32(), r.i32(), r.i32()
            name = self._fname(r)
            flags = r.u32()
            size, off = r.i64(), r.i64()
            r.skip(EXPORT_SIZE - 44)                 # rest of FObjectExport
            self.exports.append(dict(class_index=cls, super_index=sup, outer=outer, name=name, flags=flags,
                                     serial_size=size, serial_offset=off))
        self.uexp = uexp

    def _fname(self, r):
        idx, num = r.i32(), r.i32()
        name = self.names[idx]
        return f"{name}_{num - 1}" if num else name

    def fname(self, r):
        return self._fname(r)

    def obj_name(self, index):
        """FPackageIndex -> object name ('' for null)."""
        if index > 0:
            return self.exports[index - 1]["name"]
        if index < 0:
            return self.imports[-index - 1]["name"]
        return ""

    def class_of(self, export):
        return self.obj_name(export["class_index"])

    def full_path(self, index):
        parts = []
        while index:
            if index > 0:
                e = self.exports[index - 1]
                parts.append(e["name"])
                index = e["outer"]
            else:
                i = self.imports[-index - 1]
                parts.append(i["name"])
                index = i["outer"]
        return ".".join(reversed(parts))

    def export_data(self, export):
        start = export["serial_offset"] - self.header_size
        return Reader(self.uexp[start:start + export["serial_size"]])

    # ----------------------------------------------------------------- UStruct
    def skip_tagged_properties(self, r):
        while True:
            name = self.fname(r)
            if name == "None":
                return
            ptype = self.fname(r)
            size = r.i32()
            r.i32()                                        # array index
            if ptype == "StructProperty":
                self.fname(r)
                r.skip(16)
            elif ptype == "BoolProperty":
                r.skip(1)
            elif ptype in ("ByteProperty", "EnumProperty", "ArrayProperty", "SetProperty"):
                self.fname(r)
            elif ptype == "MapProperty":
                self.fname(r)
                self.fname(r)
            if r.u8():
                r.skip(16)                                 # property guid
            r.skip(size)

    def read_properties(self, r):
        """Tagged properties -> {name: value} for the simple types (int, float, bool, string, enum
        name, object/class reference, array of those). Other types are skipped."""
        out = {}
        while True:
            name = self.fname(r)
            if name == "None":
                return out
            ptype = self.fname(r)
            size = r.i32()
            r.i32()                                        # array index
            extra = None
            if ptype == "StructProperty":
                self.fname(r)
                r.skip(16)
            elif ptype == "BoolProperty":
                extra = r.u8()
            elif ptype in ("ByteProperty", "EnumProperty", "ArrayProperty", "SetProperty"):
                extra = self.fname(r)
            elif ptype == "MapProperty":
                self.fname(r)
                self.fname(r)
            if r.u8():
                r.skip(16)                                 # property guid
            start = r.p
            v = Reader(r.d, start)
            if ptype == "IntProperty":
                out[name] = v.i32()
            elif ptype == "FloatProperty":
                out[name] = struct.unpack_from("<f", r.d, start)[0]
            elif ptype == "BoolProperty":
                out[name] = bool(extra)
            elif ptype == "StrProperty":
                out[name] = v.fstring()
            elif ptype in ("ByteProperty", "EnumProperty") and size == 8:
                out[name] = self.fname(v)
            elif ptype in ("ObjectProperty", "ClassProperty"):
                out[name] = self.obj_name(v.i32())
            elif ptype == "ArrayProperty" and extra in ("ObjectProperty", "ClassProperty", "IntProperty"):
                items = [v.i32() for _ in range(v.i32())]
                out[name] = items if extra == "IntProperty" else [self.obj_name(i) for i in items]
            r.p = start + size

    def read_values(self, r):
        """Tagged properties -> {name: value}, including nested structs and arrays.

        Object and class references come back as Ref (a str holding the full object path,
        "/Game/Folder/Asset.Asset", or the dotted path inside this package for its own objects).
        Vectors, rotators and colours are tuples. A value of a type this does not know is None.
        """
        out = {}
        while True:
            name = self.fname(r)
            if name == "None":
                return out
            ptype = self.fname(r)
            size = r.i32()
            index = r.i32()
            extra = struct_name = None
            if ptype == "StructProperty":
                struct_name = self.fname(r)
                r.skip(16)
            elif ptype == "BoolProperty":
                extra = r.u8()
            elif ptype in ("ByteProperty", "EnumProperty", "ArrayProperty", "SetProperty"):
                extra = self.fname(r)
            elif ptype == "MapProperty":
                self.fname(r)
                self.fname(r)
            if r.u8():
                r.skip(16)                                 # property guid
            start = r.p
            try:
                if ptype == "BoolProperty":
                    value = bool(extra)
                elif ptype == "ArrayProperty":
                    value = self._read_array(r, extra)
                else:
                    value = self._read_value(r, ptype, extra, struct_name)
            except (ValueError, IndexError, struct.error):
                value = None
            r.p = start + size
            out[name if not index else f"{name}[{index}]"] = value

    def _read_array(self, r, inner):
        count = r.i32()
        if inner == "StructProperty":
            self.fname(r)                                  # the array's own name again
            self.fname(r)                                  # "StructProperty"
            r.i64()
            struct_name = self.fname(r)
            r.skip(16)
            if r.u8():
                r.skip(16)
            return [self._read_value(r, "StructProperty", None, struct_name) for _ in range(count)]
        if inner == "BoolProperty":
            return [bool(r.u8()) for _ in range(count)]
        if inner == "ByteProperty":
            data = list(r.d[r.p:r.p + count])
            r.skip(count)
            return data
        return [self._read_value(r, inner, None, None) for _ in range(count)]

    def _read_value(self, r, ptype, extra, struct_name):
        if ptype == "IntProperty":
            return r.i32()
        if ptype == "FloatProperty":
            value = struct.unpack_from("<f", r.d, r.p)[0]
            r.skip(4)
            return value
        if ptype == "StrProperty":
            return r.fstring()
        if ptype in ("NameProperty", "EnumProperty"):
            return self.fname(r)
        if ptype in ("ObjectProperty", "ClassProperty"):
            return Ref(self.full_path(r.i32()))
        if ptype == "ByteProperty":
            if extra and extra != "None":
                return self.fname(r)
            return r.u8()
        if ptype == "BoolProperty":
            return bool(r.u8())
        if ptype == "StructProperty":
            layout = BINARY_STRUCTS.get(struct_name)
            if layout:
                value = struct.unpack_from(layout, r.d, r.p)
                r.skip(struct.calcsize(layout))
                return value
            return self.read_values(r)
        raise ValueError(f"unsupported property type {ptype}")

    def read_field(self, r):
        """One serialized FProperty; returns dict(type, name, flags, detail) or None for NAME_None."""
        ptype = self.fname(r)
        if ptype == "None":
            return None
        name = self.fname(r)
        r.u32()                                            # object flags
        r.i32(), r.i32()                                   # array dim, element size
        pflags = struct.unpack_from("<Q", r.d, r.p)[0]
        r.skip(8)
        r.skip(2)                                          # rep index
        self.fname(r)                                      # rep notify func
        r.skip(1)                                          # replication condition
        detail = ""
        if ptype in ("ObjectProperty", "WeakObjectProperty", "LazyObjectProperty", "SoftObjectProperty"):
            detail = self.obj_name(r.i32())
        elif ptype in ("ClassProperty", "SoftClassProperty"):
            r.i32()
            detail = self.obj_name(r.i32())
        elif ptype == "InterfaceProperty":
            detail = self.obj_name(r.i32())
        elif ptype == "StructProperty":
            detail = self.obj_name(r.i32())
        elif ptype == "ByteProperty":
            detail = self.obj_name(r.i32())
        elif ptype == "EnumProperty":
            detail = self.obj_name(r.i32())
            self.read_field(r)
        elif ptype == "BoolProperty":
            r.skip(6)
        elif ptype in ("DelegateProperty", "MulticastDelegateProperty", "MulticastInlineDelegateProperty",
                       "MulticastSparseDelegateProperty"):
            detail = self.obj_name(r.i32())
        elif ptype == "ArrayProperty" or ptype == "SetProperty":
            inner = self.read_field(r)
            detail = describe(inner) if inner else ""
        elif ptype == "MapProperty":
            k, v = self.read_field(r), self.read_field(r)
            detail = f"{describe(k)}, {describe(v)}"
        elif ptype == "FieldPathProperty":
            detail = self.fname(r)
        return dict(type=ptype, name=name, flags=pflags, detail=detail)

    def read_struct(self, export):
        """Parse a class or function export: returns (super name, child names, properties, function flags)."""
        r = self.export_data(export)
        self.skip_tagged_properties(r)
        if r.i32():
            r.skip(16)                                     # object guid
        super_name = self.obj_name(r.i32())
        children = [self.obj_name(r.i32()) for _ in range(r.i32())]
        props = []
        for _ in range(r.i32()):
            f = self.read_field(r)
            if f:
                props.append(f)
        r.i32()                                            # bytecode size in memory
        r.skip(r.i32())                                    # bytecode on disk
        func_flags = r.u32() if self.class_of(export) == "Function" else None
        return super_name, children, props, func_flags


SHORT_TYPES = {"IntProperty": "int", "Int64Property": "int64", "FloatProperty": "float", "DoubleProperty": "double",
               "BoolProperty": "bool", "StrProperty": "string", "NameProperty": "name", "TextProperty": "text",
               "ByteProperty": "byte", "UInt32Property": "uint32", "UInt16Property": "uint16", "Int8Property": "int8",
               "Int16Property": "int16", "UInt64Property": "uint64"}


def describe(f):
    if not f:
        return "?"
    t = f["type"]
    if t in SHORT_TYPES:
        return f"{SHORT_TYPES[t]}<{f['detail']}>" if t == "ByteProperty" and f["detail"] else SHORT_TYPES[t]
    if t in ("ArrayProperty",):
        return f"array<{f['detail']}>"
    if t == "SetProperty":
        return f"set<{f['detail']}>"
    if t == "MapProperty":
        return f"map<{f['detail']}>"
    if t in ("ObjectProperty", "WeakObjectProperty", "LazyObjectProperty"):
        return f"{f['detail']}*" if f["detail"] else "object"
    if t == "SoftObjectProperty":
        return f"soft<{f['detail']}>"
    if t in ("ClassProperty", "SoftClassProperty"):
        return f"class<{f['detail']}>"
    if t in ("StructProperty", "EnumProperty", "InterfaceProperty"):
        return f["detail"] or t.replace("Property", "")
    if "Delegate" in t:
        return "delegate"
    return t.replace("Property", "")
