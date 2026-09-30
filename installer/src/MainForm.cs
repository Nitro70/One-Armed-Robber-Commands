using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Windows.Forms;

namespace OARCommandsInstaller
{
    internal sealed class MainForm : Form
    {
        private readonly TextBox _folder = new TextBox { ReadOnly = true, Anchor = AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Top };
        private readonly Button _browse = new Button { Text = "Browse...", AutoSize = true };
        private readonly Button _install = new Button { Text = "Install / Update", AutoSize = true };
        private readonly Button _uninstall = new Button { Text = "Uninstall", AutoSize = true };
        private readonly Button _close = new Button { Text = "Close", AutoSize = true };
        private readonly TextBox _log = new TextBox
        {
            Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical,
            Dock = DockStyle.Fill, BackColor = SystemColors.Window, Font = new Font(FontFamily.GenericMonospace, 9f),
        };
        private readonly string _autoAction;
        private string _win64;

        internal MainForm(string gameArg, string autoAction)
        {
            _autoAction = autoAction;
            Text = "OAR Commands " + Program.Version + " installer";
            StartPosition = FormStartPosition.CenterScreen;
            ClientSize = new Size(640, 360);
            MinimumSize = new Size(520, 300);
            Font = SystemFonts.MessageBoxFont;

            var intro = new Label
            {
                AutoSize = true, Dock = DockStyle.Fill, Padding = new Padding(0, 0, 0, 6),
                Text = "Adds bind, summon <name> [count], dupe and a working console (~) to One-armed robber.\n" +
                       "Installs UE4SS 3.0.1 and the OARCommands mod into the game folder.",
            };
            var folderRow = new TableLayoutPanel { ColumnCount = 3, Dock = DockStyle.Fill, AutoSize = true };
            folderRow.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            folderRow.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            folderRow.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            folderRow.Controls.Add(new Label { Text = "Game folder:", AutoSize = true, Anchor = AnchorStyles.Left }, 0, 0);
            folderRow.Controls.Add(_folder, 1, 0);
            folderRow.Controls.Add(_browse, 2, 0);

            var buttons = new FlowLayoutPanel { Dock = DockStyle.Fill, AutoSize = true, FlowDirection = FlowDirection.LeftToRight };
            buttons.Controls.AddRange(new Control[] { _install, _uninstall, _close });

            var layout = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, Padding = new Padding(12) };
            layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            layout.Controls.Add(intro, 0, 0);
            layout.Controls.Add(folderRow, 0, 1);
            layout.Controls.Add(_log, 0, 2);
            layout.Controls.Add(buttons, 0, 3);
            Controls.Add(layout);
            AcceptButton = _install;
            CancelButton = _close;

            _browse.Click += (s, e) => Browse();
            _install.Click += (s, e) => Run("install");
            _uninstall.Click += (s, e) => Run("uninstall");
            _close.Click += (s, e) => Close();
            Shown += (s, e) =>
            {
                if (_autoAction != null) Run(_autoAction);
            };

            UseFolder(gameArg ?? GameLocator.FindGameFolder(), fromSteam: gameArg == null);
        }

        private void UseFolder(string folder, bool fromSteam)
        {
            _win64 = GameLocator.ToWin64(folder);
            if (_win64 == null)
            {
                _folder.Text = "";
                Log(folder == null
                    ? "Could not find One-armed robber through Steam. Click Browse and pick the game folder."
                    : "That folder does not contain One-armed robber (OAR-Win64-Shipping.exe).");
            }
            else
            {
                _folder.Text = GameFolderOf(_win64);
                Log((fromSteam ? "Found the game: " : "Game folder: ") + _folder.Text);
                Log(ModInstaller.IsInstalled(_win64) ? "OAR Commands is installed. Install / Update refreshes it." : "OAR Commands is not installed yet.");
            }
            _install.Enabled = _uninstall.Enabled = _win64 != null;
        }

        private static string GameFolderOf(string win64) =>
            Path.GetFullPath(Path.Combine(win64, "..", "..", ".."));

        private void Browse()
        {
            using (var dialog = new FolderBrowserDialog { Description = "Pick the One-armed robber folder (the one with OAR.exe)" })
            {
                if (dialog.ShowDialog(this) == DialogResult.OK) UseFolder(dialog.SelectedPath, fromSteam: false);
            }
        }

        private void Run(string action)
        {
            if (_win64 == null) return;
            if (!ModInstaller.CanWrite(_win64))
            {
                if (Program.IsElevated())
                {
                    Log("Error: cannot write to " + _win64);
                    return;
                }
                Log("The game folder needs admin permission. Asking Windows...");
                if (RelaunchElevated(action)) Close();
                else Log("Admin permission was refused, nothing was changed.");
                return;
            }
            UseWaitCursor = true;
            _install.Enabled = _uninstall.Enabled = false;
            try
            {
                if (action == "install")
                {
                    ModInstaller.Install(_win64, Log);
                    Log("Done. Start the game, press ~ and try:  bind x destroytarget   or   summon goldbar 5");
                }
                else
                {
                    ModInstaller.Uninstall(_win64, Log);
                }
            }
            catch (Exception ex) when (ex is InvalidOperationException || ex is IOException || ex is UnauthorizedAccessException)
            {
                Log("Error: " + ex.Message);
            }
            finally
            {
                UseWaitCursor = false;
                _install.Enabled = _uninstall.Enabled = true;
            }
        }

        private bool RelaunchElevated(string action)
        {
            var psi = new ProcessStartInfo(Application.ExecutablePath,
                "--game \"" + GameFolderOf(_win64) + "\" --" + action)
            { UseShellExecute = true, Verb = "runas" };
            try
            {
                Process.Start(psi)?.Dispose();
                return true;
            }
            catch (Win32Exception)
            {
                return false;
            }
        }

        private void Log(string line) => _log.AppendText(line + Environment.NewLine);
    }
}
