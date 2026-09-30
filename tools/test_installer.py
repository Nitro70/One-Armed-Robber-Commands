"""Test the installer exe against fake game folders (never the real one).

Uses the Debug build (build/debug) for install/uninstall scenarios, because the Release build
refuses to run while the real game is open, and checks that refusal with the Release build.
"""
import os
import shutil
import subprocess
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEBUG_EXE = os.path.join(REPO, "build", "debug", "OAR-Commands-Installer.exe")
RELEASE_EXE = os.path.join(REPO, "dist", "OAR-Commands-Installer.exe")
BOM = b"\xef\xbb\xbf"


def fake_game(root):
    win64 = os.path.join(root, "OAR", "Binaries", "Win64")
    os.makedirs(win64)
    open(os.path.join(win64, "OAR-Win64-Shipping.exe"), "wb").close()
    return win64


def run(exe, game, action, env_extra=None):
    log = os.path.join(tempfile.mkdtemp(), "log.txt")
    env = dict(os.environ, **(env_extra or {}))
    code = subprocess.call([exe, "--quiet", "--game", game, "--" + action, "--log", log], env=env)
    return code, open(log, encoding="utf-8").read()


def check(label, cond):
    print(("PASS " if cond else "FAIL ") + label)
    return cond


def main():
    ok = True
    test_env = {"OARCOMMANDS_TEST_IGNORE_RUNNING": "1"}

    # 1. fresh install into an empty game
    root = tempfile.mkdtemp()
    win64 = fake_game(root)
    code, log = run(DEBUG_EXE, root, "install", test_env)
    mods_txt = open(os.path.join(win64, "Mods", "mods.txt"), "rb").read()
    ok &= check("fresh install succeeds", code == 0)
    ok &= check("UE4SS loader and dll copied", all(os.path.isfile(os.path.join(win64, f)) for f in ("dwmapi.dll", "UE4SS.dll")))
    ok &= check("mod copied", os.path.isfile(os.path.join(win64, "Mods", "OARCommands", "Scripts", "main.lua")))
    ok &= check("mods.txt has no byte-order mark", not mods_txt.startswith(BOM))
    ok &= check("mods.txt enables OARCommands and the cheat manager mod",
                b"OARCommands : 1" in mods_txt and mods_txt.startswith(b"CheatManagerEnablerMod : 1"))
    ok &= check("console key patch installed",
                b'FName("Tilde"' in open(os.path.join(win64, "Mods", "ConsoleEnablerMod", "Scripts", "main.lua"), "rb").read())

    # 2. uninstall the fresh install: game folder back to only the exe
    code, log = run(DEBUG_EXE, root, "uninstall", test_env)
    left = sorted(os.listdir(win64))
    ok &= check("clean uninstall leaves only the game exe", code == 0 and left == ["OAR-Win64-Shipping.exe"])

    # 3. update over the old BindCommand version with a BOM mods.txt and another user mod
    root = tempfile.mkdtemp()
    win64 = fake_game(root)
    mods = os.path.join(win64, "Mods")
    os.makedirs(os.path.join(mods, "BindCommand", "Scripts"))
    open(os.path.join(mods, "BindCommand", "binds.txt"), "w").write("X=destroytarget\n")
    os.makedirs(os.path.join(mods, "MyOtherMod", "Scripts"))
    open(os.path.join(mods, "MyOtherMod", "Scripts", "main.lua"), "w").write("-- someone else's mod\n")
    open(os.path.join(mods, "mods.txt"), "wb").write(
        BOM + b"CheatManagerEnablerMod : 1\r\nMyOtherMod : 1\r\nBindCommand : 1\r\n; Built-in keybinds, do not move up!\r\nKeybinds : 1\r\n")
    code, log = run(DEBUG_EXE, root, "install", test_env)
    mods_txt = open(os.path.join(mods, "mods.txt"), "rb").read()
    ok &= check("update succeeds", code == 0)
    ok &= check("binds carried over from BindCommand",
                open(os.path.join(mods, "OARCommands", "binds.txt")).read() == "X=destroytarget\n")
    ok &= check("old BindCommand folder removed", not os.path.exists(os.path.join(mods, "BindCommand")))
    ok &= check("other mod kept, BindCommand line dropped, BOM gone",
                b"MyOtherMod : 1" in mods_txt and b"BindCommand" not in mods_txt and not mods_txt.startswith(BOM))
    ok &= check("Keybinds stays last", mods_txt.strip().endswith(b"Keybinds : 1"))

    # 4. installing twice changes nothing important
    code, _ = run(DEBUG_EXE, root, "install", test_env)
    ok &= check("reinstall keeps binds and mods.txt", code == 0 and
                open(os.path.join(mods, "OARCommands", "binds.txt")).read() == "X=destroytarget\n" and
                open(os.path.join(mods, "mods.txt"), "rb").read() == mods_txt)

    # 5. uninstall next to another mod: that mod and mods.txt stay
    code, log = run(DEBUG_EXE, root, "uninstall", test_env)
    mods_txt = open(os.path.join(mods, "mods.txt"), "rb").read()
    ok &= check("uninstall keeps the other mod", code == 0 and os.path.isfile(os.path.join(mods, "MyOtherMod", "Scripts", "main.lua")))
    ok &= check("uninstall removes UE4SS and OARCommands",
                not os.path.exists(os.path.join(win64, "dwmapi.dll")) and not os.path.exists(os.path.join(mods, "OARCommands")))
    ok &= check("mods.txt loses only the OARCommands line", b"OARCommands" not in mods_txt and b"MyOtherMod : 1" in mods_txt)

    # 6. uninstall when nothing is installed is refused
    code, log = run(DEBUG_EXE, root, "uninstall", test_env)
    ok &= check("uninstall without an install is refused", code == 1 and "No OAR Commands install" in log)

    # 7. a folder that is not the game is refused
    code, log = run(DEBUG_EXE, tempfile.mkdtemp(), "install", test_env)
    ok &= check("wrong folder is refused", code == 1 and "not found" in log)

    # 8. the Release build refuses while the game is running (only checkable if it is running)
    running = b"OAR-Win64-Shipping.exe" in subprocess.run(
        ["tasklist", "/FI", "IMAGENAME eq OAR-Win64-Shipping.exe"], capture_output=True).stdout
    if running and os.path.isfile(RELEASE_EXE):
        root = tempfile.mkdtemp()
        win64 = fake_game(root)
        code, log = run(RELEASE_EXE, root, "install")
        ok &= check("release build refuses while the game runs",
                    code == 1 and "is running" in log and not os.path.exists(os.path.join(win64, "dwmapi.dll")))
    else:
        print("SKIP release refusal check (game not running)")

    print("ALL PASS" if ok else "SOME FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
