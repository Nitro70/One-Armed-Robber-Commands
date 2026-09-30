using System;
using System.Collections.Generic;
using System.IO;
using System.Text.RegularExpressions;
using Microsoft.Win32;

namespace OARCommandsInstaller
{
    /// <summary>Finds One-armed robber through Steam's registry keys and library list.</summary>
    internal static class GameLocator
    {
        internal const string SteamAppId = "2551020";
        internal const string DefaultFolderName = "One-armed robber";
        internal static readonly string ExeInWin64 = "OAR-Win64-Shipping.exe";
        internal static readonly string Win64Relative = Path.Combine("OAR", "Binaries", "Win64");

        /// <summary>The game's install folder, or null when Steam does not know it.</summary>
        internal static string FindGameFolder()
        {
            foreach (string library in SteamLibraries())
            {
                foreach (string name in CandidateNames(library))
                {
                    string game = Path.Combine(library, "steamapps", "common", name);
                    if (ToWin64(game) != null) return game;
                }
            }
            return null;
        }

        /// <summary>
        /// Accepts the game folder, the OAR folder or Binaries\Win64 itself, and returns the
        /// Win64 folder holding the game exe, or null if this is not the game.
        /// </summary>
        internal static string ToWin64(string folder)
        {
            if (string.IsNullOrWhiteSpace(folder)) return null;
            string[] tries =
            {
                folder,
                Path.Combine(folder, "Binaries", "Win64"),
                Path.Combine(folder, Win64Relative),
            };
            foreach (string t in tries)
            {
                if (File.Exists(Path.Combine(t, ExeInWin64))) return Path.GetFullPath(t);
            }
            return null;
        }

        private static IEnumerable<string> CandidateNames(string library)
        {
            string manifest = Path.Combine(library, "steamapps", "appmanifest_" + SteamAppId + ".acf");
            if (File.Exists(manifest))
            {
                Match m = Regex.Match(SafeRead(manifest), "\"installdir\"\\s+\"([^\"]+)\"");
                if (m.Success) yield return m.Groups[1].Value;
            }
            yield return DefaultFolderName;
        }

        private static IEnumerable<string> SteamLibraries()
        {
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (string root in SteamRoots())
            {
                var libraries = new List<string> { root };
                string vdf = Path.Combine(root, "steamapps", "libraryfolders.vdf");
                if (File.Exists(vdf))
                {
                    foreach (Match m in Regex.Matches(SafeRead(vdf), "\"path\"\\s+\"([^\"]+)\""))
                        libraries.Add(m.Groups[1].Value.Replace("\\\\", "\\"));
                }
                foreach (string lib in libraries)
                {
                    string full;
                    try { full = Path.GetFullPath(lib); } catch (Exception) { continue; }
                    if (seen.Add(full)) yield return full;
                }
            }
        }

        private static IEnumerable<string> SteamRoots()
        {
            string[,] keys =
            {
                { "HKCU", @"Software\Valve\Steam", "SteamPath" },
                { "HKLM", @"SOFTWARE\WOW6432Node\Valve\Steam", "InstallPath" },
                { "HKLM", @"SOFTWARE\Valve\Steam", "InstallPath" },
            };
            for (int i = 0; i < keys.GetLength(0); i++)
            {
                RegistryKey hive = keys[i, 0] == "HKCU" ? Registry.CurrentUser : Registry.LocalMachine;
                string value = null;
                try
                {
                    using (RegistryKey k = hive.OpenSubKey(keys[i, 1]))
                        value = k?.GetValue(keys[i, 2]) as string;
                }
                catch (Exception) { }
                if (!string.IsNullOrEmpty(value) && Directory.Exists(value))
                    yield return value.Replace('/', '\\');
            }
        }

        private static string SafeRead(string path)
        {
            try { return File.ReadAllText(path); } catch (Exception) { return ""; }
        }
    }
}
