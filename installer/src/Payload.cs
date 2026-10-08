using System;
using System.IO;

namespace OARCommandsInstaller
{
    /// <summary>
    /// Where the files to install come from. The offline installer carries them inside the exe; the
    /// online installer downloads the latest release's copy from GitHub (OnlinePayload) at every
    /// Install / Update.
    /// </summary>
    internal static class Payload
    {
#if ONLINE
        internal const bool Online = true;
#else
        internal const bool Online = false;
#endif

        /// <summary>The files to install: the downloaded zip (online), or the one inside this exe.</summary>
        internal static Stream Open(byte[] downloaded)
        {
            if (downloaded != null) return new MemoryStream(downloaded, writable: false);
            Stream s = typeof(Payload).Assembly.GetManifestResourceStream("payload.zip");
            if (s == null) throw new InvalidOperationException("The installer is damaged: its files are missing.");
            return s;
        }

        /// <summary>
        /// Online: downloads the latest release's files (checked against their SHA-256) before
        /// anything is changed; returns null offline. log may be called from any thread.
        /// </summary>
        internal static byte[] Fetch(Action<string> log)
        {
#if ONLINE
            return OnlinePayload.Fetch(log);
#else
            return null;
#endif
        }
    }
}
