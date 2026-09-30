"""Pull every text command the engine parses out of OAR-Win64-Shipping.exe.

Unreal matches console words with FParse::Command(&Cmd, TEXT("WORD")). Every call site loads
the word into rdx right before the call, so collecting those strings gives the complete set of
engine text commands compiled into this build, grouped by the function that handles them.
FParse::Command itself is found as the function called right after TEXT("GETALL") is loaded.
"""
import bisect
import re
import struct
from collections import OrderedDict

import capstone
import pefile

from oar_pak import EXE

ANCHOR_WORD = "GETALL"
LEA_RDX_RIP = re.compile(rb"\x48\x8d\x15")
LEA_RIP = re.compile(rb"[\x48\x4c]\x8d[\x05\x0d\x15\x1d\x25\x2d\x35\x3d]")


class _Image:
    def __init__(self):
        pe = pefile.PE(EXE, fast_load=True)
        self.data = pe.__data__
        self.sections = [(s.VirtualAddress, s.Misc_VirtualSize, s.PointerToRawData) for s in pe.sections]
        text = next(s for s in pe.sections if s.Name.rstrip(b"\0") == b".text")
        self.text_rva = text.VirtualAddress
        self.text = self.data[text.PointerToRawData:text.PointerToRawData + text.Misc_VirtualSize]
        pdata = next(s for s in pe.sections if s.Name.rstrip(b"\0") == b".pdata")
        raw = self.data[pdata.PointerToRawData:pdata.PointerToRawData + pdata.Misc_VirtualSize]
        funcs = [struct.unpack_from("<II", raw, 12 * k) for k in range(len(raw) // 12)]
        self.funcs = sorted(f for f in funcs if f[0])
        self.starts = [f[0] for f in self.funcs]

    def rva_to_off(self, rva):
        for va, size, raw in self.sections:
            if va <= rva < va + size:
                return rva - va + raw
        return None

    def off_to_rva(self, off):
        for va, size, raw in self.sections:
            if raw <= off < raw + size:
                return off - raw + va
        return None

    def wide_string(self, rva, limit=200):
        o = self.rva_to_off(rva)
        if o is None:
            return None
        e = o
        while self.data[e:e + 2] != b"\0\0" and e - o < limit:
            e += 2
        try:
            s = self.data[o:e].decode("utf-16le")
        except UnicodeDecodeError:
            return None
        return s if s.isprintable() else None

    def function_of(self, rva):
        k = bisect.bisect_right(self.starts, rva) - 1
        return self.funcs[k][0] if k >= 0 and self.funcs[k][0] <= rva < self.funcs[k][1] else None


def engine_commands():
    """OrderedDict {handler rva: [words in call order]}."""
    img = _Image()
    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
    anchor = img.data.find(ANCHOR_WORD.encode("utf-16le") + b"\0\0")
    while anchor & 1:
        anchor = img.data.find(ANCHOR_WORD.encode("utf-16le") + b"\0\0", anchor + 1)
    anchor_rva = img.off_to_rva(anchor)

    fparse = None
    for m in LEA_RIP.finditer(img.text):
        i = m.start()
        if img.text_rva + i + 7 + struct.unpack_from("<i", img.text, i + 3)[0] != anchor_rva:
            continue
        for ins in md.disasm(img.text[i:i + 40], img.text_rva + i):
            if ins.mnemonic == "call":
                fparse = int(ins.op_str, 16)
                break
    if fparse is None:
        raise RuntimeError("FParse::Command not found")

    # Every "lea rdx, [rip+X]" (48 8D 15) followed within 48 bytes by a call to FParse::Command,
    # with no other call in between. Scanning raw bytes avoids disassembly desync.
    groups = OrderedDict()
    for m in LEA_RDX_RIP.finditer(img.text):
        i = m.start()
        word_rva = img.text_rva + i + 7 + struct.unpack_from("<i", img.text, i + 3)[0]
        for j in range(i + 7, min(i + 55, len(img.text) - 5)):
            if img.text[j] != 0xE8:
                continue
            target = img.text_rva + j + 5 + struct.unpack_from("<i", img.text, j + 1)[0]
            if target != fparse:
                if img.function_of(target) == target:     # a real call to something else: rdx is spent
                    break
                continue
            word = img.wide_string(word_rva)
            if word:
                groups.setdefault(img.function_of(img.text_rva + j), []).append(word)
            break
    return groups


if __name__ == "__main__":
    for handler, words in engine_commands().items():
        print(hex(handler or 0), words)
