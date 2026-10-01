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

    # 5b. config.lua: default on install, edits kept or saved aside on update, gone after uninstall
    root = tempfile.mkdtemp()
    win64 = fake_game(root)
    mod = os.path.join(win64, "Mods", "OARCommands")
    config, default, old = (os.path.join(mod, n) for n in ("config.lua", "config.default.lua", "config.old.lua"))
    code, log = run(DEBUG_EXE, root, "install", test_env)
    shipped = open(config, "rb").read()
    ok &= check("install writes config.lua and an identical untouched copy",
                code == 0 and shipped == open(default, "rb").read() and b"local V = {" in shipped
                and "default config.lua" in log)
    ok &= check("the old separate command files are not installed any more",
                sorted(os.listdir(os.path.join(mod, "Scripts"))) == ["main.lua", "maps.lua", "spawnables.lua", "unlockables.lua"])
    open(config, "ab").write(b"\n-- my edit\n")
    mine = open(config, "rb").read()
    code, log = run(DEBUG_EXE, root, "install", test_env)
    ok &= check("update with the same default keeps an edited config.lua",
                code == 0 and open(config, "rb").read() == mine and not os.path.exists(old) and "was kept" in log)
    open(default, "wb").write(b"-- the default of an older version\n")
    code, log = run(DEBUG_EXE, root, "install", test_env)
    ok &= check("update with a new default saves the edited config as config.old.lua and installs the new one",
                code == 0 and open(config, "rb").read() == shipped and open(old, "rb").read() == mine
                and open(default, "rb").read() == shipped and "config.old.lua" in log)
    code, log = run(DEBUG_EXE, root, "install", test_env)
    ok &= check("a later update leaves config.old.lua alone", code == 0 and open(old, "rb").read() == mine)
    open(default, "wb").write(b"-- an older default\n")
    open(config, "wb").write(b"-- an older default\n")
    os.remove(old)
    code, log = run(DEBUG_EXE, root, "install", test_env)
    ok &= check("an unedited config is simply replaced by the new default",
                code == 0 and open(config, "rb").read() == shipped and not os.path.exists(old))
    stale = os.path.join(mod, "Scripts", "share.lua")
    open(stale, "w").write("-- from 1.2.0\n")
    record = os.path.join(mod, "installed-files.txt")
    open(record, "a").write("Mods\\OARCommands\\Scripts\\share.lua\n")
    code, log = run(DEBUG_EXE, root, "install", test_env)
    ok &= check("files of an older version that are no longer used are removed on update",
                code == 0 and not os.path.exists(stale) and "no longer used" in log)
    open(config, "ab").write(b"\n-- my edit\n")
    code, log = run(DEBUG_EXE, root, "uninstall", test_env)
    ok &= check("uninstall removes config.lua with everything else",
                code == 0 and sorted(os.listdir(win64)) == ["OAR-Win64-Shipping.exe"])
    code, log = run(DEBUG_EXE, root, "install", test_env)
    ok &= check("installing again puts the default config back", code == 0 and open(config, "rb").read() == shipped)
    run(DEBUG_EXE, root, "uninstall", test_env)

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
