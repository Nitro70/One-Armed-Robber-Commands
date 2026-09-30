"""Find the One-armed robber install folder.

Order: the OAR_GAME_DIR environment variable, then every Steam library listed in Steam's
libraryfolders.vdf (the game's Steam app id is 2551020).
"""
import os
import re
import winreg

APP_ID = "2551020"
GAME_EXE = os.path.join("OAR", "Binaries", "Win64", "OAR-Win64-Shipping.exe")


def _steam_roots():
    keys = [(winreg.HKEY_CURRENT_USER, r"Software\Valve\Steam", "SteamPath"),
            (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\WOW6432Node\Valve\Steam", "InstallPath"),
            (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\Valve\Steam", "InstallPath")]
    for hive, key, value in keys:
        try:
            with winreg.OpenKey(hive, key) as k:
                yield os.path.normpath(winreg.QueryValueEx(k, value)[0])
        except OSError:
            continue


def _libraries():
    seen = []
    for root in _steam_roots():
        for lib in [root] + _vdf_paths(os.path.join(root, "steamapps", "libraryfolders.vdf")):
            lib = os.path.normcase(os.path.normpath(lib))
            if lib not in seen:
                seen.append(lib)
    return seen


def _vdf_paths(vdf):
    try:
        text = open(vdf, encoding="utf-8", errors="replace").read()
    except OSError:
        return []
    return [p.replace("\\\\", "\\") for p in re.findall(r'"path"\s+"([^"]+)"', text)]


def find_game_dir():
    env = os.environ.get("OAR_GAME_DIR")
    if env and os.path.isfile(os.path.join(env, GAME_EXE)):
        return env
    for lib in _libraries():
        manifest = os.path.join(lib, "steamapps", f"appmanifest_{APP_ID}.acf")
        names = []
        try:
            m = re.search(r'"installdir"\s+"([^"]+)"', open(manifest, encoding="utf-8", errors="replace").read())
            if m:
                names.append(m.group(1))
        except OSError:
            pass
        names.append("One-armed robber")
        for name in names:
            game = os.path.join(lib, "steamapps", "common", name)
            if os.path.isfile(os.path.join(game, GAME_EXE)):
                return game
    raise FileNotFoundError("One-armed robber not found. Set OAR_GAME_DIR to the game folder.")


GAME_DIR = None


def game_dir():
    global GAME_DIR
    if GAME_DIR is None:
        GAME_DIR = find_game_dir()
    return GAME_DIR
