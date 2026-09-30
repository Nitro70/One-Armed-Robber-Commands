"""Scan the release exe (and every file bundled in it) for personal or build-machine strings.

Run before publishing. Prints each hit with the surrounding bytes; exit code 1 if anything is found.
"""
import getpass
import os
import sys
import zipfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXE = os.path.join(REPO, "dist", "OAR-Commands-Installer.exe")
PAYLOAD = os.path.join(REPO, "build", "payload.zip")
B = chr(92)

NEEDLES = [getpass.getuser(), os.path.expanduser("~"), REPO, os.path.basename(REPO),
           B + "obj" + B, ".pdb", "SteamLibrary", "AppData", "Temp" + B, "7656119",
           "claude", "anthropic"] + sys.argv[1:]


# UE4SS's own release DLLs carry the PDB path of UE4SS's GitHub Actions runner; that is theirs.
ALLOWED = [("D:" + B + "a" + B + "RE-UE4SS" + B).lower().encode("ascii")]


def hits(data, label):
    found = 0
    low = data.lower()
    for n in NEEDLES:
        for enc in ("ascii", "utf-16le"):
            try:
                b = n.lower().encode(enc)
            except UnicodeEncodeError:
                continue
            i = low.find(b)
            while i != -1:
                context = low[max(0, i - 120):i + 10]
                if not any(a in context for a in ALLOWED):
                    found += 1
                    print(f"HIT in {label}: {n!r} ({enc}) ...{data[max(0, i - 40):i + 60]!r}")
                    break
                i = low.find(b, i + 1)
    return found


def main():
    total = hits(open(EXE, "rb").read(), os.path.basename(EXE))
    with zipfile.ZipFile(PAYLOAD) as z:
        for name in z.namelist():
            total += hits(z.read(name), "payload/" + name)
    print(f"{total} hits")
    return 1 if total else 0


if __name__ == "__main__":
    raise SystemExit(main())
