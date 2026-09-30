"""Read any file out of One-armed robber's pak (v11, unencrypted index).

Zlib entries use Python's zlib. Oodle entries use the Oodle decoder that is statically
linked into OAR-Win64-Shipping.exe: the exe is mapped into THIS process with
LoadLibraryEx(DONT_RESOLVE_DLL_REFERENCES), only CRT/kernel imports are patched in, and
the decoder is called directly. Nothing touches the running game.
"""
import ctypes
import ctypes.wintypes as wt
import os
import struct
import zlib

from oar_paths import game_dir

GAME = game_dir()
PAK = os.path.join(GAME, "OAR", "Content", "Paks", "OAR-WindowsNoEditor.pak")
EXE = os.path.join(GAME, "OAR", "Binaries", "Win64", "OAR-Win64-Shipping.exe")

PAK_FOOTER = 221
PAK_MAGIC = 0x5A6F12E1
# OodleLZ_Decompress inside OAR-Win64-Shipping.exe (build of 2026-08-23). Found as the function
# that references "OodleLZ_Decompress about to DecodeSome"; 14 args, Oodle's public signature.
OODLE_DECOMPRESS_RVA = 0x330D890
OODLE_SAFE_DLLS = ("kernel32", "vcruntime140", "msvcp140", "api-ms-win-crt", "advapi32", "bcrypt")
OODLE_SCRATCH = 8 << 20


def _fstring(buf, pos):
    n = struct.unpack_from("<i", buf, pos)[0]
    pos += 4
    if n == 0:
        return "", pos
    if n < 0:
        return buf[pos:pos - 2 * n].decode("utf-16le")[:-1], pos - 2 * n
    return buf[pos:pos + n - 1].decode("latin-1"), pos + n


class _Oodle:
    def __init__(self):
        import pefile
        k32 = ctypes.WinDLL("kernel32", use_last_error=True)
        k32.LoadLibraryExW.restype = ctypes.c_void_p
        k32.LoadLibraryExW.argtypes = [wt.LPCWSTR, wt.HANDLE, wt.DWORD]
        k32.LoadLibraryW.restype = ctypes.c_void_p
        k32.LoadLibraryW.argtypes = [wt.LPCWSTR]
        k32.GetProcAddress.restype = ctypes.c_void_p
        k32.GetProcAddress.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        k32.VirtualProtect.argtypes = [ctypes.c_void_p, ctypes.c_size_t, wt.DWORD, ctypes.POINTER(wt.DWORD)]
        base = k32.LoadLibraryExW(EXE, None, 0x1)          # DONT_RESOLVE_DLL_REFERENCES
        if not base:
            raise OSError(f"LoadLibraryEx failed: {ctypes.get_last_error()}")
        pe = pefile.PE(EXE, fast_load=True)
        pe.parse_data_directories(directories=[pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_IMPORT"]])
        for imp in pe.DIRECTORY_ENTRY_IMPORT:
            dll = imp.dll.decode()
            if not dll.lower().startswith(OODLE_SAFE_DLLS):
                continue
            h = k32.LoadLibraryW(dll)
            for sym in imp.imports if h else []:
                addr = k32.GetProcAddress(h, sym.name) if sym.name else None
                if not addr:
                    continue
                slot = base + (sym.address - pe.OPTIONAL_HEADER.ImageBase)
                old = wt.DWORD()
                k32.VirtualProtect(slot, 8, 0x04, ctypes.byref(old))
                ctypes.c_uint64.from_address(slot).value = addr
                k32.VirtualProtect(slot, 8, old.value, ctypes.byref(old))
        proto = ctypes.CFUNCTYPE(ctypes.c_int64, ctypes.c_void_p, ctypes.c_int64, ctypes.c_void_p, ctypes.c_int64,
                                 ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_void_p, ctypes.c_int64,
                                 ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_int64, ctypes.c_int)
        self.fn = proto(base + OODLE_DECOMPRESS_RVA)
        self.scratch = ctypes.create_string_buffer(OODLE_SCRATCH)

    def decompress(self, comp, raw_len):
        out = ctypes.create_string_buffer(raw_len)
        n = self.fn(comp, len(comp), out, raw_len, 1, 0, 0, None, 0, None, None,
                    self.scratch, OODLE_SCRATCH, 3)     # fuzz-safe, no CRC, unthreaded
        if n != raw_len:
            raise ValueError(f"Oodle returned {n}, expected {raw_len}")
        return out.raw


class Pak:
    def __init__(self, path=PAK):
        self.f = open(path, "rb")
        self.f.seek(os.path.getsize(path) - PAK_FOOTER)
        foot = self.f.read(PAK_FOOTER)
        magic, _version, index_off, index_size = struct.unpack_from("<IiQQ", foot, 17)
        if magic != PAK_MAGIC or foot[16]:
            raise ValueError("unexpected pak footer or encrypted index")
        self.methods = [foot[61 + 32 * i:93 + 32 * i].rstrip(b"\0").decode() for i in range(5)]
        self.f.seek(index_off)
        idx = self.f.read(index_size)
        mount, p = _fstring(idx, 0)
        p += 12                                             # entry count + path hash seed
        p += 4 + (8 + 8 + 20 if struct.unpack_from("<I", idx, p)[0] else 0)
        if not struct.unpack_from("<I", idx, p)[0]:
            raise ValueError("pak has no full directory index")
        dir_off, dir_size = struct.unpack_from("<qq", idx, p + 4)
        p += 4 + 8 + 8 + 20
        size = struct.unpack_from("<i", idx, p)[0]
        self.encoded = idx[p + 4:p + 4 + size]
        self.f.seek(dir_off)
        dirs = self.f.read(dir_size)
        self.files = {}
        q = 4
        for _ in range(struct.unpack_from("<i", dirs, 0)[0]):
            dname, q = _fstring(dirs, q)
            count = struct.unpack_from("<i", dirs, q)[0]
            q += 4
            for _ in range(count):
                fname, q = _fstring(dirs, q)
                self.files[(mount + dname + fname).replace("../../../", "")] = struct.unpack_from("<i", dirs, q)[0]
                q += 4
        self._oodle = None

    def read(self, name):
        loc = self.files[name]
        if loc < 0:
            raise ValueError("unencoded pak entries are not supported")
        bits = struct.unpack_from("<I", self.encoded, loc)[0]
        p = loc + 4 + (4 if (bits & 0x3F) == 0x3F else 0)
        offset = struct.unpack_from("<I" if bits & (1 << 31) else "<Q", self.encoded, p)[0]
        f = self.f
        f.seek(offset)
        head = f.read(64)
        _, _size, raw_size, method = struct.unpack_from("<qqqI", head, 0)
        p = 48
        blocks = []
        if method:
            nblocks = struct.unpack_from("<i", head, p)[0]
            f.seek(offset)
            head = f.read(p + 4 + nblocks * 16 + 5)
            blocks = [struct.unpack_from("<qq", head, p + 4 + 16 * i) for i in range(nblocks)]
            p += 4 + nblocks * 16
        if head[p]:
            raise ValueError("entry is encrypted")
        block_size = struct.unpack_from("<I", head, p + 1)[0]
        if not method:
            f.seek(offset + p + 5)
            return f.read(raw_size)
        kind = self.methods[method - 1]
        out = bytearray()
        for start, end in blocks:
            f.seek(offset + start)
            data = f.read(end - start)
            if kind == "Zlib":
                out += zlib.decompress(data)
            elif kind == "Oodle":
                if self._oodle is None:
                    self._oodle = _Oodle()
                out += self._oodle.decompress(data, min(block_size, raw_size - len(out)))
            else:
                raise ValueError(f"unsupported compression {kind}")
        return bytes(out)
