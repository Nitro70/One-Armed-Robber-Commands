"""Build build/payload.zip: everything the installer writes into OAR/Binaries/Win64.

Contents: the runtime files from the official UE4SS v3.0.1 release (downloaded once into build/
and checked against its SHA-256), with this project's files from mod/ laid over the top, plus
the UE4SS license. The installer embeds the zip, so the released exe needs no download.
"""
import hashlib
import os
import urllib.request
import zipfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(REPO, "build")
MOD = os.path.join(REPO, "mod")
UE4SS_URL = "https://github.com/UE4SS-RE/RE-UE4SS/releases/download/v3.0.1/UE4SS_v3.0.1.zip"
UE4SS_SHA256 = "4b47d4bceddd2f561a4e395bfa00924ccfc945af576a2d0c613e6537846c57ec"
UE4SS_ZIP = os.path.join(BUILD, "UE4SS_v3.0.1.zip")
PAYLOAD = os.path.join(BUILD, "payload.zip")
SKIP = {"README.md", "Changelog.md"}              # docs from the UE4SS zip, not needed in the game folder


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def fetch_ue4ss():
    os.makedirs(BUILD, exist_ok=True)
    if not os.path.isfile(UE4SS_ZIP) or sha256(UE4SS_ZIP) != UE4SS_SHA256:
        print("downloading", UE4SS_URL)
        urllib.request.urlretrieve(UE4SS_URL, UE4SS_ZIP)
    got = sha256(UE4SS_ZIP)
    if got != UE4SS_SHA256:
        raise SystemExit(f"UE4SS zip hash mismatch: {got}")


def main():
    fetch_ue4ss()
    ours = {}
    for root, _dirs, files in os.walk(MOD):
        for name in files:
            full = os.path.join(root, name)
            ours[os.path.relpath(full, MOD).replace(os.sep, "/")] = full
    if "Mods/OARCommands/binds.txt" in ours:
        raise SystemExit("mod/ contains a binds.txt; that is per-user data and must not ship")

    with zipfile.ZipFile(UE4SS_ZIP) as src, zipfile.ZipFile(PAYLOAD, "w", zipfile.ZIP_DEFLATED) as out:
        for info in src.infolist():
            if info.is_dir() or info.filename in SKIP or info.filename in ours:
                continue
            out.writestr(info.filename, src.read(info))
        for rel, full in sorted(ours.items()):
            out.write(full, rel)
        out.write(os.path.join(REPO, "third_party", "UE4SS-LICENSE.txt"), "UE4SS-LICENSE.txt")
    with zipfile.ZipFile(PAYLOAD) as z:
        names = z.namelist()
    print(f"{PAYLOAD}: {len(names)} files, {os.path.getsize(PAYLOAD):,} bytes")


if __name__ == "__main__":
    main()
