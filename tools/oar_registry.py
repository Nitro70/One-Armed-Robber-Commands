"""Read One-armed robber's cooked AssetRegistry.bin out of its pak (via oar_pak).

The registry format parsed here is UE 4.27's FixedTags layout (FAssetRegistryVersion 8).

blueprint_classes() returns every Blueprint in the game with its generated class path and
parent class, whether or not it is loaded in the running game. all_assets() lists every asset.
"""
import struct

from oar_pak import Pak

REGISTRY_PATH = "OAR/AssetRegistry.bin"
STORE_BEGIN_MAGIC = 0x12345679
STORE_END_MAGIC = 0x87654321


def _read_pak_file(want):
    return Pak().read(want)


class _Registry:
    def __init__(self, data):
        self.d = data
        self.p = 20                                        # version guid + int32 version
        self._names()
        self._store()
        self._assets()

    def u32(self):
        v = struct.unpack_from("<I", self.d, self.p)[0]
        self.p += 4
        return v

    def fname(self):
        v = self.u32()
        name = self.names[v & 0x7FFFFFFF]
        if v & 0x80000000:                                 # followed by an instance number
            name = f"{name}_{self.u32() - 1}"
        return name

    def _names(self):
        num, nbytes, _hash_version = struct.unpack_from("<iIQ", self.d, self.p)
        self.p += 16
        headers = self.p + num * 8
        s = start = headers + num * 2
        self.names = []
        for i in range(num):
            b0, b1 = self.d[headers + 2 * i], self.d[headers + 2 * i + 1]
            length = ((b0 & 0x7F) << 8) | b1
            if b0 & 0x80:
                s += (s - start) & 1
                self.names.append(self.d[s:s + 2 * length].decode("utf-16le"))
                s += 2 * length
            else:
                self.names.append(self.d[s:s + length].decode("latin-1"))
                s += length
        if s - start != nbytes:
            raise ValueError("name batch size mismatch")
        self.p = s

    def _store(self):
        if self.u32() != STORE_BEGIN_MAGIC:
            raise ValueError("tag store magic missing")
        (n_numberless_names, n_names, n_numberless_paths, n_paths, _n_texts, n_ansi, n_wide,
         ansi_bytes, wide_chars, n_numberless_pairs, n_pairs) = struct.unpack_from("<11I", self.d, self.p)
        self.p += 44
        text_bytes = self.u32()                            # localized texts come first; not needed
        self.p += text_bytes
        self.numberless_names = [self.names[self.u32()] for _ in range(n_numberless_names)]
        self.store_names = [self.fname() for _ in range(n_names)]
        self.numberless_paths = [tuple(self.names[self.u32()] for _ in range(3)) for _ in range(n_numberless_paths)]
        self.paths = [(self.fname(), self.fname(), self.fname()) for _ in range(n_paths)]
        self.ansi_offsets = struct.unpack_from(f"<{n_ansi}I", self.d, self.p)
        self.p += 4 * n_ansi
        self.wide_offsets = struct.unpack_from(f"<{n_wide}I", self.d, self.p)
        self.p += 4 * n_wide
        self.ansi = self.d[self.p:self.p + ansi_bytes]
        self.p += ansi_bytes
        self.wide = self.d[self.p:self.p + 2 * wide_chars]
        self.p += 2 * wide_chars
        self.numberless_pairs = [struct.unpack_from("<2I", self.d, self.p + 8 * i) for i in range(n_numberless_pairs)]
        self.p += 8 * n_numberless_pairs
        self.pairs = []
        for _ in range(n_pairs):
            key = self.fname()
            self.pairs.append((key, self.u32()))
        if self.u32() != STORE_END_MAGIC:
            raise ValueError("tag store end magic missing")

    def value(self, v):
        kind, i = v & 7, v >> 3
        if kind == 0:
            s = self.ansi_offsets[i]
            return self.ansi[s:self.ansi.index(b"\0", s)].decode("latin-1")
        if kind == 1:
            s = e = self.wide_offsets[i] * 2
            while self.wide[e:e + 2] != b"\0\0":
                e += 2
            return self.wide[s:e].decode("utf-16le")
        if kind == 2:
            return self.numberless_names[i]
        if kind == 3:
            return self.store_names[i]
        if kind in (4, 5):
            cls, obj, pkg = (self.numberless_paths if kind == 4 else self.paths)[i]
            return f"{cls}'{pkg}.{obj}'"
        return ""

    def _assets(self):
        self.assets = []
        for _ in range(self.u32()):
            obj_path, _pkg_path, asset_class, _pkg, _name = (self.fname() for _ in range(5))
            handle = struct.unpack_from("<Q", self.d, self.p)[0]
            self.p += 8
            self.p += 4                                    # unused word in this build
            self.p += 4 + 4 * self.u32()                   # chunk ids
            self.p += 4                                    # package flags
            count, begin = (handle >> 32) & 0xFFFF, handle & 0xFFFFFFFF
            if handle >> 63:
                tags = {self.names[k]: v for k, v in self.numberless_pairs[begin:begin + count]}
            else:
                tags = dict(self.pairs[begin:begin + count])
            self.assets.append((obj_path, asset_class, tags))


def _class_path(export_text):
    """"BlueprintGeneratedClass'/Game/X/Y.Y_C'" -> "/Game/X/Y.Y_C"."""
    return export_text.split("'")[1] if "'" in export_text else export_text


def blueprint_classes():
    """[{name, path, parent, native}] for every Blueprint asset in the pak."""
    reg = _Registry(_read_pak_file(REGISTRY_PATH))
    out = []
    for _obj_path, asset_class, tags in reg.assets:
        if asset_class != "Blueprint" or "GeneratedClass" not in tags:
            continue
        path = _class_path(reg.value(tags["GeneratedClass"]))
        parent = _class_path(reg.value(tags["ParentClass"])) if "ParentClass" in tags else ""
        native = _class_path(reg.value(tags["NativeParentClass"])) if "NativeParentClass" in tags else ""
        out.append(dict(name=path.rsplit(".", 1)[-1], path=path,
                        parent=parent.rsplit(".", 1)[-1], native=native.rsplit(".", 1)[-1]))
    return out


def all_assets():
    """[(object path, asset class)] for every asset the registry lists."""
    reg = _Registry(_read_pak_file(REGISTRY_PATH))
    return [(obj_path, asset_class) for obj_path, asset_class, _tags in reg.assets]
