using System;
using System.IO;
using System.Reflection;
using System.Security.Principal;
using System.Windows.Forms;

namespace OARCommandsInstaller
{
    internal static class Program
    {
        internal static readonly string Version =
            Assembly.GetExecutingAssembly().GetName().Version.ToString(3);

        /// <summary>
        /// No arguments: the installer window. Options (used by the admin relaunch and for testing):
        ///   --game "folder"   use this game folder instead of asking Steam
        ///   --install | --uninstall   run that action as soon as the window opens
        ///   --quiet           no window: run the action, write the log to --log, exit 0 on success
        ///   --log "file"      where --quiet writes its log
        /// </summary>
        [STAThread]
        private static int Main(string[] args)
        {
            string game = null, action = null, logFile = null;
            bool quiet = false;
            for (int i = 0; i < args.Length; i++)
            {
                switch (args[i].ToLowerInvariant())
                {
                    case "--game": game = i + 1 < args.Length ? args[++i] : null; break;
                    case "--install": action = "install"; break;
                    case "--uninstall": action = "uninstall"; break;
                    case "--quiet": quiet = true; break;
                    case "--log": logFile = i + 1 < args.Length ? args[++i] : null; break;
                }
            }
            if (quiet) return RunQuiet(game, action, logFile);

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new MainForm(game, action));
            return 0;
        }

        private static int RunQuiet(string game, string action, string logFile)
        {
            var log = new System.Text.StringBuilder();
            void Log(string line) => log.AppendLine(line);
            int code = 0;
            try
            {
                string win64 = GameLocator.ToWin64(game ?? GameLocator.FindGameFolder());
                if (win64 == null) throw new InvalidOperationException("One-armed robber was not found.");
                if (action == "uninstall") ModInstaller.Uninstall(win64, Log);
                else
                {
                    ModInstaller.RefuseWhileRunning();          // before downloading anything
                    using (Stream payload = Payload.Open(Payload.Fetch(Log)))
                        ModInstaller.Install(win64, Log, payload);
                }
            }
            catch (Exception ex)
            {
                Log("Error: " + ex.Message);
                code = 1;
            }
            if (logFile != null) File.WriteAllText(logFile, log.ToString());
            return code;
        }

        internal static bool IsElevated()
        {
            using (WindowsIdentity id = WindowsIdentity.GetCurrent())
                return new WindowsPrincipal(id).IsInRole(WindowsBuiltInRole.Administrator);
        }
    }
}
