using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text;

namespace OARCommandsInstaller
{
    /// <summary>
    /// Copies the embedded payload (UE4SS 3.0.1 + OARCommands) into OAR\Binaries\Win64 and removes
    /// it again. Only files listed in the install record are ever deleted.
    /// </summary>
    internal static class ModInstaller
    {
        internal const string ModName = "OARCommands";
        private const string OldModName = "BindCommand";          // this mod's name before 1.0.0
        private const string GameProcess = "OAR-Win64-Shipping";
        private static readonly string ModsTxtRel = Path.Combine("Mods", "mods.txt");
        private static readonly string ModDirRel = Path.Combine("Mods", ModName);
        private static readonly string RecordRel = Path.Combine(ModDirRel, "installed-files.txt");
        private static readonly string BindsRel = Path.Combine(ModDirRel, "binds.txt");
        private static readonly string[] RuntimeFiles = { "UE4SS.log" };
        private static readonly UTF8Encoding Utf8NoBom = new UTF8Encoding(false);

        internal static bool IsGameRunning()
        {
            Process[] running = Process.GetProcessesByName(GameProcess);
            foreach (Process p in running) p.Dispose();
            return running.Length > 0;
        }

        internal static bool IsInstalled(string win64) => File.Exists(Path.Combine(win64, RecordRel));

        internal static bool CanWrite(string dir)
        {
            string probe = Path.Combine(dir, "oarcommands-write-test.tmp");
            try
            {
                File.WriteAllText(probe, "");
                File.Delete(probe);
                return true;
            }
            catch (UnauthorizedAccessException) { return false; }
            catch (IOException) { return false; }
        }

        internal static void Install(string win64, Action<string> log)
        {
            RefuseWhileRunning();
            var written = new List<string>();
            string payloadModsTxt = null;
            using (Stream s = typeof(ModInstaller).Assembly.GetManifestResourceStream("payload.zip"))
            {
                if (s == null) throw new InvalidOperationException("The installer is damaged: its files are missing.");
                using (var zip = new ZipArchive(s, ZipArchiveMode.Read))
                {
                    foreach (ZipArchiveEntry entry in zip.Entries)
                    {
                        if (entry.FullName.EndsWith("/")) continue;
                        string rel = entry.FullName.Replace('/', Path.DirectorySeparatorChar);
                        if (string.Equals(rel, ModsTxtRel, StringComparison.OrdinalIgnoreCase))
                        {
                            using (var reader = new StreamReader(entry.Open(), Encoding.UTF8))
                                payloadModsTxt = reader.ReadToEnd();
                            continue;
                        }
                        string target = InsideFolder(win64, rel);
                        Directory.CreateDirectory(Path.GetDirectoryName(target));
                        using (Stream src = entry.Open())
                        using (var dst = new FileStream(target, FileMode.Create, FileAccess.Write, FileShare.None))
                            src.CopyTo(dst);
                        written.Add(rel);
                    }
                }
            }
            log($"Copied {written.Count} files (UE4SS 3.0.1 + {ModName}).");
            MigrateOldVersion(win64, log);
            MergeModsTxt(win64, payloadModsTxt, log);
            File.WriteAllLines(Path.Combine(win64, RecordRel), written, Utf8NoBom);
            log(File.Exists(Path.Combine(win64, BindsRel)) ? "Your saved binds were kept." : "No saved binds yet.");
        }

        internal static void Uninstall(string win64, Action<string> log)
        {
            RefuseWhileRunning();
            string record = Path.Combine(win64, RecordRel);
            if (!File.Exists(record))
                throw new InvalidOperationException("No OAR Commands install was found in this folder.");
            int removed = 0;
            foreach (string line in File.ReadAllLines(record))
            {
                string rel = line.Trim();
                if (rel.Length == 0) continue;
                string target = InsideFolder(win64, rel);
                if (File.Exists(target)) { File.Delete(target); removed++; }
            }
            foreach (string name in RuntimeFiles)
            {
                string target = Path.Combine(win64, name);
                if (File.Exists(target)) { File.Delete(target); removed++; }
            }
            string modDir = Path.Combine(win64, ModDirRel);
            if (Directory.Exists(modDir)) Directory.Delete(modDir, true);   // our own folder: record + binds
            log($"Removed {removed} files and the {ModName} folder (including saved binds).");

            string modsRoot = Path.Combine(win64, "Mods");
            DeleteEmptyFolders(modsRoot);
            string modsTxt = Path.Combine(win64, ModsTxtRel);
            if (Directory.Exists(modsRoot) && Directory.GetDirectories(modsRoot).Length == 0)
            {
                if (File.Exists(modsTxt)) File.Delete(modsTxt);
                if (Directory.GetFileSystemEntries(modsRoot).Length == 0) Directory.Delete(modsRoot);
                log("Removed the empty Mods folder.");
            }
            else if (File.Exists(modsTxt))
            {
                List<string> lines = ReadLines(modsTxt);
                lines.RemoveAll(l => SameName(ModNameOf(l), ModName));
                File.WriteAllText(modsTxt, string.Join("\r\n", lines) + "\r\n", Utf8NoBom);
                log("Other UE4SS mods were found in Mods and left alone.");
            }
            log("One-armed robber is back to normal.");
        }

        private static void RefuseWhileRunning()
        {
#if DEBUG
            // Debug builds only: lets tools/test_installer.py use a fake game folder while the real game runs.
            if (Environment.GetEnvironmentVariable("OARCOMMANDS_TEST_IGNORE_RUNNING") == "1") return;
#endif
            if (IsGameRunning())
                throw new InvalidOperationException("One-armed robber is running. Close the game, then try again.");
        }

        /// <summary>Joins a relative path onto the game folder and refuses anything that escapes it.</summary>
        private static string InsideFolder(string root, string rel)
        {
            string rootFull = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
            string full = Path.GetFullPath(Path.Combine(rootFull, rel));
            if (!full.StartsWith(rootFull, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Refusing a path outside the game folder: " + rel);
            return full;
        }

        private static void MigrateOldVersion(string win64, Action<string> log)
        {
            string oldDir = Path.Combine(win64, "Mods", OldModName);
            if (!Directory.Exists(oldDir)) return;
            string oldBinds = Path.Combine(oldDir, "binds.txt");
            string newBinds = Path.Combine(win64, BindsRel);
            if (File.Exists(oldBinds) && !File.Exists(newBinds)) File.Copy(oldBinds, newBinds);
            Directory.Delete(oldDir, true);
            log($"Updated from the old {OldModName} version (binds carried over).");
        }

        /// <summary>
        /// Keeps the user's mods.txt (other mods, on/off choices) and adds what is missing. Also drops
        /// the byte-order mark the stock UE4SS 3.0.1 file starts with: it makes UE4SS skip the first mod.
        /// </summary>
        private static void MergeModsTxt(string win64, string payloadText, Action<string> log)
        {
            string path = Path.Combine(win64, ModsTxtRel);
            List<string> payload = SplitLines(payloadText ?? "");
            if (!File.Exists(path))
            {
                File.WriteAllText(path, string.Join("\r\n", payload) + "\r\n", Utf8NoBom);
                return;
            }
            List<string> lines = ReadLines(path);
            lines.RemoveAll(l => SameName(ModNameOf(l), OldModName));
            int keybinds = lines.FindIndex(l => l.TrimStart().StartsWith("; Built-in keybinds") || SameName(ModNameOf(l), "Keybinds"));
            foreach (string wanted in payload)
            {
                string name = ModNameOf(wanted);
                if (name == null || SameName(name, "Keybinds") || lines.Any(l => SameName(ModNameOf(l), name))) continue;
                if (keybinds >= 0) lines.Insert(keybinds++, wanted);
                else lines.Add(wanted);
            }
            for (int i = 0; i < lines.Count; i++)
                if (SameName(ModNameOf(lines[i]), ModName)) lines[i] = ModName + " : 1";
            if (!lines.Any(l => SameName(ModNameOf(l), "Keybinds")))
                lines.Add("Keybinds : 1");
            File.WriteAllText(path, string.Join("\r\n", lines) + "\r\n", Utf8NoBom);
            log("Updated Mods\\mods.txt (kept your other mods).");
        }

        private static List<string> ReadLines(string path) =>
            SplitLines(File.ReadAllText(path, Encoding.UTF8));

        private static List<string> SplitLines(string text) =>
            text.TrimStart('﻿').Replace("\r\n", "\n").TrimEnd('\n').Split('\n').ToList();

        private static string ModNameOf(string line)
        {
            string t = line.Trim().TrimStart('﻿');
            if (t.Length == 0 || t.StartsWith(";")) return null;
            int colon = t.IndexOf(':');
            return (colon > 0 ? t.Substring(0, colon) : t).Trim();
        }

        private static bool SameName(string a, string b) =>
            a != null && string.Equals(a, b, StringComparison.OrdinalIgnoreCase);

        private static void DeleteEmptyFolders(string dir)
        {
            if (!Directory.Exists(dir)) return;
            foreach (string sub in Directory.GetDirectories(dir))
            {
                DeleteEmptyFolders(sub);
                if (Directory.GetFileSystemEntries(sub).Length == 0) Directory.Delete(sub);
            }
        }
    }
}
