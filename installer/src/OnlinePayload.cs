#if ONLINE
using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Web.Script.Serialization;

namespace OARCommandsInstaller
{
    /// <summary>
    /// The online installer's files. Every GitHub release of OAR Commands carries the same zip the
    /// offline installer has inside it (OAR-Commands-Payload.zip) and its SHA-256
    /// (OAR-Commands-Payload.zip.sha256). The latest release's pair is downloaded at every Install /
    /// Update, and nothing is written to the game folder unless the zip matches its checksum.
    /// </summary>
    internal static class OnlinePayload
    {
        internal const string Repo = "Nitro70/One-Armed-Robber-Commands";
        internal const string ZipName = "OAR-Commands-Payload.zip";
        internal const string HashName = ZipName + ".sha256";
        private const string LatestApi = "https://api.github.com/repos/" + Repo + "/releases/latest";
        private const string LatestDownload = "https://github.com/" + Repo + "/releases/latest/download/";
        private const string Agent = "OAR-Commands-Online-Installer";

        internal static byte[] Fetch(Action<string> log)
        {
            // TLS 1.2 at least: GitHub refuses anything older.
            ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
            string api = LatestApi;
#if DEBUG
            // Debug builds only: tools/test_installer.py serves a release from a folder.
            string testDir = Environment.GetEnvironmentVariable("OARCOMMANDS_TEST_RELEASE_DIR");
            if (!string.IsNullOrEmpty(testDir)) api = new Uri(Path.Combine(testDir, "release.json")).AbsoluteUri;
#endif
            log("Asking GitHub for the latest version of OAR Commands...");
            string version = null, zipUrl = null, hashUrl = null;
            try
            {
                if (new JavaScriptSerializer().DeserializeObject(Text(api)) is Dictionary<string, object> release)
                {
                    version = release.TryGetValue("tag_name", out object tag) ? tag as string : null;
                    if (release.TryGetValue("assets", out object assets) && assets is IEnumerable list)
                    {
                        foreach (object item in list)
                        {
                            if (!(item is Dictionary<string, object> asset)) continue;
                            string name = asset.TryGetValue("name", out object n) ? n as string : null;
                            string url = asset.TryGetValue("browser_download_url", out object u) ? u as string : null;
                            if (name == ZipName) zipUrl = url;
                            else if (name == HashName) hashUrl = url;
                        }
                    }
                    if (zipUrl == null || hashUrl == null)
                        throw new InvalidOperationException("The latest release on GitHub" + (version != null ? " (" + version + ")" : "") +
                            " does not have " + ZipName + ", so nothing was changed. Use the offline installer.");
                }
            }
            catch (WebException) { }          // GitHub answers 60 such questions an hour per address
            catch (ArgumentException) { }     // not the answer expected
            if (zipUrl == null || hashUrl == null)
            {
                // The release's own download links always lead to the latest release.
                zipUrl = LatestDownload + ZipName;
                hashUrl = LatestDownload + HashName;
            }

            string what = version ?? "the latest version";
            string expected;
            byte[] zip;
            try
            {
                expected = FirstWord(Text(hashUrl));
                log("Downloading " + what + " from GitHub...");
                zip = Data(zipUrl);
            }
            catch (WebException ex)
            {
                throw new InvalidOperationException("Could not download from GitHub (" + ex.Message + "), so nothing was changed. " +
                    "Check the internet connection and try again, or use the offline installer.");
            }
            string actual = Sha256(zip);
            if (expected.Length != 64 || !string.Equals(actual, expected, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("The download did not match its checksum, so nothing was changed. " +
                    "Try again, or use the offline installer.");
            log($"Downloaded {what} ({zip.Length / 1048576.0:0.0} MB), checksum OK.");
            return zip;
        }

        private static byte[] Data(string url)
        {
#if DEBUG
            if (url.StartsWith("file:", StringComparison.OrdinalIgnoreCase)) return File.ReadAllBytes(new Uri(url).LocalPath);
#endif
            using (var web = new WebClient())
            {
                web.Headers[HttpRequestHeader.UserAgent] = Agent;
                return web.DownloadData(url);
            }
        }

        private static string Text(string url) => Encoding.UTF8.GetString(Data(url));

        private static string FirstWord(string text)
        {
            string[] words = text.Trim().Split(new[] { ' ', '\t', '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
            return words.Length > 0 ? words[0] : "";
        }

        private static string Sha256(byte[] data)
        {
            using (SHA256 sha = SHA256.Create())
            {
                var hex = new StringBuilder(64);
                foreach (byte b in sha.ComputeHash(data)) hex.Append(b.ToString("x2"));
                return hex.ToString();
            }
        }
    }
}
#endif
