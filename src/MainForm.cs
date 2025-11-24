using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Windows.Forms;

namespace RosyRecorder
{
    public partial class MainForm : Form
    {
    // P/Invoke for icon extraction
    [DllImport("shell32.dll", CharSet = CharSet.Auto)]
    private static extern IntPtr ExtractIcon(IntPtr hInst, string lpszExeFileName, int nIconIndex);

    // Debug logging
    private static readonly string _logFile = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "RosyRecorder", "debug.log");

    private static void Log(string message)
    {
        try
        {
            var dir = Path.GetDirectoryName(_logFile);
            if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
                Directory.CreateDirectory(dir);
            File.AppendAllText(_logFile, $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] {message}\n");
        }
        catch { }
    }

    // Config and paths
    private readonly string _cacheDir;
    private readonly string _cacheFile;
    private readonly string _defaultSaveDir;
    private const string DefaultFileNamePattern = "Recording_{0:yyyy-MM-dd_HH-mm-ss}.mp3";

    // URLs
    private const string FfmpegUrl = "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip";
    private const string VacInstallerUrl = "https://github.com/rdp/screen-capture-recorder-to-video-windows-free/releases/download/v0.13.3/Setup.Screen.Capturer.Recorder.v0.13.3.exe";

    // State
    private string? _ffmpegPath;
    private List<string> _deviceList = new();
    private bool _isRecording;
    private Process? _ffmpegProcess;
    private DateTime _startTime;
    private string _outputPath = "";

    // Colors
    private static readonly Color BackgroundColor = Color.FromArgb(250, 250, 250);
    private static readonly Color SurfaceColor = Color.White;
    private static readonly Color SuccessColor = Color.FromArgb(16, 124, 16);
    private static readonly Color DangerColor = Color.FromArgb(196, 43, 28);
    private static readonly Color TextPrimaryColor = Color.FromArgb(32, 32, 32);
    private static readonly Color BorderColor = Color.FromArgb(200, 200, 200);

    // Controls
    private TextBox _txtSavePath = null!;
    private Button _btnBrowse = null!;
    private CheckedListBox _deviceCheckList = null!;
    private TrackBar _sliderMicVol = null!;
    private TrackBar _sliderSysVol = null!;
    private Label _labelMicVolPct = null!;
    private Label _labelSysVolPct = null!;
    private Label _labelStatus = null!;
    private Label _labelTime = null!;
    private Button _btnStart = null!;
    private Button _btnStop = null!;
    private System.Windows.Forms.Timer _timer = null!;

    public MainForm()
    {
        _cacheDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "RosyRecorder");
        _cacheFile = Path.Combine(_cacheDir, "config.json");
        _defaultSaveDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "RosyRecordings");

        InitializeComponent();
        SetupIcon();

        // Initialize after form is shown
        Shown += (s, e) =>
        {
            TopMost = false; // Disable TopMost after shown so it doesn't block popups
            BeginInvoke(new Action(Initialize));
        };
    }

    private void InitializeComponent()
    {
        Text = "Rosy Recorder";
        Size = new Size(620, 420);
        MinimumSize = new Size(515, 415);
        StartPosition = FormStartPosition.CenterScreen;
        TopMost = true;
        Padding = new Padding(10);
        Font = new Font("Segoe UI", 9);
        BackColor = BackgroundColor;
        ForeColor = TextPrimaryColor;

        // Ensure default save directory exists
        if (!Directory.Exists(_defaultSaveDir))
            Directory.CreateDirectory(_defaultSaveDir);

        _outputPath = Path.Combine(_defaultSaveDir, string.Format(DefaultFileNamePattern, DateTime.Now));

        // Main layout
        var layout = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 3,
            RowCount = 7
        };

        layout.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));

        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 28)); // Save path
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));     // Device label
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100)); // Device list
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));     // Mic volume
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));     // Sys volume
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));     // Status
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));     // Buttons

        // Row 0: Save path
        var labelPath = new Label
        {
            Text = "Save to:",
            AutoSize = true,
            Anchor = AnchorStyles.Left,
            Margin = new Padding(0, 5, 5, 0)
        };

        _txtSavePath = new TextBox
        {
            Text = _outputPath,
            Dock = DockStyle.Fill,
            Margin = new Padding(0)
        };

        _btnBrowse = new Button
        {
            Text = "Browse...",
            Dock = DockStyle.Fill,
            Margin = new Padding(3, 0, 0, 0),
            FlatStyle = FlatStyle.Flat,
            BackColor = SurfaceColor,
            Cursor = Cursors.Hand
        };
        _btnBrowse.FlatAppearance.BorderColor = BorderColor;
        _btnBrowse.Click += BtnBrowse_Click;

        layout.Controls.Add(labelPath, 0, 0);
        layout.Controls.Add(_txtSavePath, 1, 0);
        layout.Controls.Add(_btnBrowse, 2, 0);

        // Row 1: Device label
        var labelDevices = new Label
        {
            Text = "Record from:",
            AutoSize = true,
            Margin = new Padding(0, 10, 0, 3)
        };
        layout.Controls.Add(labelDevices, 0, 1);
        layout.SetColumnSpan(labelDevices, 3);

        // Row 2: Device checklist
        _deviceCheckList = new CheckedListBox
        {
            Dock = DockStyle.Fill,
            CheckOnClick = true,
            BackColor = SurfaceColor,
            BorderStyle = BorderStyle.FixedSingle,
            DrawMode = DrawMode.OwnerDrawFixed,
            ItemHeight = 18
        };
        _deviceCheckList.DrawItem += DeviceCheckList_DrawItem;

        layout.Controls.Add(_deviceCheckList, 0, 2);
        layout.SetColumnSpan(_deviceCheckList, 3);

        // Load saved config
        var config = LoadConfig();
        int savedMicVol = config?.MicVolume ?? 100;
        int savedSysVol = config?.SysVolume ?? 100;

        // Row 3: Mic volume
        var labelMicVol = new Label
        {
            Text = "Mic Volume:",
            AutoSize = true,
            Anchor = AnchorStyles.Left | AnchorStyles.Top,
            Margin = new Padding(0, 12, 5, 0)
        };

        _sliderMicVol = new TrackBar
        {
            Minimum = 0,
            Maximum = 200,
            Value = Math.Min(savedMicVol, 200),
            TickFrequency = 25,
            Dock = DockStyle.Fill
        };

        _labelMicVolPct = new Label
        {
            Text = $"{savedMicVol}%",
            AutoSize = true,
            Anchor = AnchorStyles.Left | AnchorStyles.Top,
            Margin = new Padding(5, 12, 0, 0)
        };

        _sliderMicVol.ValueChanged += (s, e) => _labelMicVolPct.Text = $"{_sliderMicVol.Value}%";

        layout.Controls.Add(labelMicVol, 0, 3);
        layout.Controls.Add(_sliderMicVol, 1, 3);
        layout.Controls.Add(_labelMicVolPct, 2, 3);

        // Row 4: System volume
        var labelSysVol = new Label
        {
            Text = "System Volume:",
            AutoSize = true,
            Anchor = AnchorStyles.Left | AnchorStyles.Top,
            Margin = new Padding(0, 12, 5, 0)
        };

        _sliderSysVol = new TrackBar
        {
            Minimum = 0,
            Maximum = 200,
            Value = Math.Min(savedSysVol, 200),
            TickFrequency = 25,
            Dock = DockStyle.Fill
        };

        _labelSysVolPct = new Label
        {
            Text = $"{savedSysVol}%",
            AutoSize = true,
            Anchor = AnchorStyles.Left | AnchorStyles.Top,
            Margin = new Padding(5, 12, 0, 0)
        };

        _sliderSysVol.ValueChanged += (s, e) => _labelSysVolPct.Text = $"{_sliderSysVol.Value}%";

        layout.Controls.Add(labelSysVol, 0, 4);
        layout.Controls.Add(_sliderSysVol, 1, 4);
        layout.Controls.Add(_labelSysVolPct, 2, 4);

        // Row 5: Status/Time
        _labelStatus = new Label
        {
            Text = "Initializing...",
            AutoSize = true,
            ForeColor = Color.Gray,
            Margin = new Padding(0, 10, 0, 5)
        };

        _labelTime = new Label
        {
            Text = "Elapsed: 00:00:00",
            AutoSize = true,
            Font = new Font("Segoe UI", 12, FontStyle.Bold),
            Visible = false,
            Margin = new Padding(0, 10, 0, 5)
        };

        layout.Controls.Add(_labelStatus, 0, 5);
        layout.SetColumnSpan(_labelStatus, 3);
        layout.Controls.Add(_labelTime, 0, 5);
        layout.SetColumnSpan(_labelTime, 3);

        // Row 6: Buttons
        var buttonPanel = new TableLayoutPanel
        {
            ColumnCount = 5,
            RowCount = 1,
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            Dock = DockStyle.Bottom,
            Margin = new Padding(0)
        };

        buttonPanel.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        buttonPanel.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        buttonPanel.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        buttonPanel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        buttonPanel.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));

        _btnStart = new Button
        {
            Text = "Start",
            Size = new Size(80, 30),
            Margin = new Padding(0, 0, 3, 0),
            Enabled = false,
            FlatStyle = FlatStyle.Flat,
            BackColor = SuccessColor,
            ForeColor = Color.White,
            Cursor = Cursors.Hand,
            Font = new Font("Segoe UI", 9, FontStyle.Bold)
        };
        _btnStart.FlatAppearance.BorderSize = 0;
        _btnStart.Click += BtnStart_Click;

        _btnStop = new Button
        {
            Text = "Stop",
            Size = new Size(80, 30),
            Margin = new Padding(0, 0, 3, 0),
            Enabled = false,
            FlatStyle = FlatStyle.Flat,
            BackColor = DangerColor,
            ForeColor = Color.White,
            Cursor = Cursors.Hand,
            Font = new Font("Segoe UI", 9, FontStyle.Bold)
        };
        _btnStop.FlatAppearance.BorderSize = 0;
        _btnStop.Click += BtnStop_Click;

        var btnQuit = new Button
        {
            Text = "Quit",
            Size = new Size(80, 30),
            Margin = new Padding(0),
            FlatStyle = FlatStyle.Flat,
            BackColor = SurfaceColor,
            Cursor = Cursors.Hand,
            TabStop = false
        };
        btnQuit.FlatAppearance.BorderColor = BorderColor;
        btnQuit.Click += (s, e) => Close();

        buttonPanel.Controls.Add(_btnStart, 0, 0);
        buttonPanel.Controls.Add(_btnStop, 1, 0);
        buttonPanel.Controls.Add(btnQuit, 4, 0);

        layout.Controls.Add(buttonPanel, 0, 6);
        layout.SetColumnSpan(buttonPanel, 3);

        Controls.Add(layout);

        // Timer for elapsed time
        _timer = new System.Windows.Forms.Timer { Interval = 500 };
        _timer.Tick += (s, e) =>
        {
            if (_isRecording)
            {
                var elapsed = DateTime.Now - _startTime;
                _labelTime.Text = $"Elapsed: {elapsed:hh\\:mm\\:ss}";
            }
        };

        FormClosing += MainForm_FormClosing;
    }

    private void SetupIcon()
    {
        try
        {
            // Try to load embedded icon
            var assembly = System.Reflection.Assembly.GetExecutingAssembly();
            using var stream = assembly.GetManifestResourceStream("RosyRecorder.rose.ico");
            if (stream != null)
            {
                Icon = new Icon(stream);
                return;
            }
        }
        catch { }

        // Fallback to shell32 microphone icon
        try
        {
            var iconHandle = ExtractIcon(IntPtr.Zero, @"C:\Windows\System32\shell32.dll", 168);
            if (iconHandle != IntPtr.Zero)
                Icon = Icon.FromHandle(iconHandle);
        }
        catch { }
    }

    private void DeviceCheckList_DrawItem(object? sender, DrawItemEventArgs e)
    {
        if (e.Index < 0) return;

        var isSelected = (e.State & DrawItemState.Selected) == DrawItemState.Selected;

        // Draw background
        using var bgBrush = new SolidBrush(isSelected ? Color.LightSteelBlue : Color.White);
        e.Graphics.FillRectangle(bgBrush, e.Bounds);

        // Draw checkbox
        var checkSize = 13;
        var checkX = e.Bounds.X + 2;
        var checkY = e.Bounds.Y + (e.Bounds.Height - checkSize) / 2;
        var checkRect = new Rectangle(checkX, checkY, checkSize, checkSize);

        ControlPaint.DrawCheckBox(e.Graphics, checkRect,
            _deviceCheckList.GetItemChecked(e.Index) ? ButtonState.Checked : ButtonState.Normal);

        // Draw text
        var textX = checkX + checkSize + 4;
        var textBounds = new Rectangle(textX, e.Bounds.Y, e.Bounds.Width - textX, e.Bounds.Height);
        using var sf = new StringFormat { LineAlignment = StringAlignment.Center };
        e.Graphics.DrawString(_deviceCheckList.Items[e.Index]?.ToString() ?? "", e.Font!, Brushes.Black, textBounds, sf);
    }

    private void Initialize()
    {
        Log("Initialize starting");

        // Find ffmpeg
        _labelStatus.Text = "Searching for ffmpeg...";
        Refresh();

        _ffmpegPath = FindFfmpeg();
        Log($"FFmpeg path: {_ffmpegPath ?? "NOT FOUND"}");

        if (string.IsNullOrEmpty(_ffmpegPath))
        {
            var result = MessageBox.Show(this,
                "FFmpeg is required but was not found.\n\nWould you like to download and install it automatically?\n\n(~100MB download)\n\nSource: https://www.gyan.dev/ffmpeg/builds/",
                "Install FFmpeg?",
                MessageBoxButtons.YesNo,
                MessageBoxIcon.Question);

            if (result == DialogResult.Yes)
            {
                _labelStatus.Text = "Downloading FFmpeg...";
                Refresh();
                _ffmpegPath = InstallFfmpeg();
            }

            if (string.IsNullOrEmpty(_ffmpegPath))
            {
                _labelStatus.Text = "FFmpeg not found!";
                _labelStatus.ForeColor = Color.Red;
                return;
            }
        }

        // Discover devices
        _labelStatus.Text = "Discovering audio devices...";
        Refresh();

        Log("Getting audio devices...");
        var audioDevices = GetDShowAudioDevices();
        Log($"Found {audioDevices.Count} devices");

        // Check for Virtual Audio Capturer
        if (!IsVirtualAudioCapturerInstalled())
        {
            var result = MessageBox.Show(this,
                "Virtual Audio Capturer is not installed.\n\nThis is required to record system audio (what you hear).\n\nInstall now?\n\nSource: https://github.com/rdp/screen-capture-recorder-to-video-windows-free",
                "Install Virtual Audio Capturer?",
                MessageBoxButtons.YesNo,
                MessageBoxIcon.Question);

            if (result == DialogResult.Yes)
            {
                _labelStatus.Text = "Installing Virtual Audio Capturer...";
                Refresh();
                if (InstallVirtualAudioCapturer())
                {
                    _labelStatus.Text = "Refreshing audio devices...";
                    Refresh();
                    audioDevices = GetDShowAudioDevices();
                }
            }
        }

        if (audioDevices.Count == 0)
        {
            _labelStatus.Text = "No audio devices found!";
            _labelStatus.ForeColor = Color.Red;
            return;
        }

        // Populate device list
        _deviceList = audioDevices;
        var (micDevice, sysDevice) = GuessDefaultDevices(audioDevices);

        foreach (var device in audioDevices)
        {
            var prefix = GetDeviceTypePrefix(device);
            var index = _deviceCheckList.Items.Add($"{prefix} {device}");
            if (device == micDevice || device == sysDevice)
                _deviceCheckList.SetItemChecked(index, true);
        }

        // Ready
        _labelStatus.Visible = false;
        _labelTime.Visible = true;
        _btnStart.Enabled = true;
    }

    #region FFmpeg Management

    private string? FindFfmpeg()
    {
        // Check config cache
        var config = LoadConfig();
        if (!string.IsNullOrEmpty(config?.FfmpegPath) && File.Exists(config.FfmpegPath))
            return config.FfmpegPath;

        // Check PATH
        var pathEnv = Environment.GetEnvironmentVariable("PATH") ?? "";
        foreach (var dir in pathEnv.Split(';'))
        {
            var ffmpegPath = Path.Combine(dir, "ffmpeg.exe");
            if (File.Exists(ffmpegPath))
            {
                SaveConfig(ffmpegPath, _sliderMicVol?.Value ?? 100, _sliderSysVol?.Value ?? 100);
                return ffmpegPath;
            }
        }

        // Common locations
        var commonPaths = new[]
        {
            @"C:\ProgramData\chocolatey\bin\ffmpeg.exe",
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), @"scoop\shims\ffmpeg.exe"),
            @"C:\Program Files\ffmpeg\bin\ffmpeg.exe",
            @"C:\Program Files (x86)\ffmpeg\bin\ffmpeg.exe",
            @"C:\ffmpeg\bin\ffmpeg.exe",
            @"C:\ffmpeg\ffmpeg.exe"
        };

        foreach (var path in commonPaths)
        {
            if (File.Exists(path))
            {
                SaveConfig(path, _sliderMicVol?.Value ?? 100, _sliderSysVol?.Value ?? 100);
                return path;
            }
        }

        // Check our install location
        var ffmpegDir = Path.Combine(_cacheDir, "ffmpeg");
        if (Directory.Exists(ffmpegDir))
        {
            var found = Directory.GetFiles(ffmpegDir, "ffmpeg.exe", SearchOption.AllDirectories).FirstOrDefault();
            if (found != null)
            {
                SaveConfig(found, _sliderMicVol?.Value ?? 100, _sliderSysVol?.Value ?? 100);
                return found;
            }
        }

        return null;
    }

    private string? InstallFfmpeg()
    {
        var zipPath = Path.Combine(Path.GetTempPath(), "ffmpeg-essentials.zip");
        var extractPath = Path.Combine(_cacheDir, "ffmpeg");

        try
        {
            // Download with progress
            if (!ShowDownloadProgress("Downloading FFmpeg", FfmpegUrl, zipPath))
                return null;

            // Extract
            if (!Directory.Exists(extractPath))
                Directory.CreateDirectory(extractPath);

            ZipFile.ExtractToDirectory(zipPath, extractPath);

            // Find ffmpeg.exe
            var ffmpegExe = Directory.GetFiles(extractPath, "ffmpeg.exe", SearchOption.AllDirectories).FirstOrDefault();

            if (ffmpegExe != null)
            {
                SaveConfig(ffmpegExe, _sliderMicVol?.Value ?? 100, _sliderSysVol?.Value ?? 100);
                MessageBox.Show(this, "FFmpeg installed successfully!", "Done", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return ffmpegExe;
            }

            throw new Exception("ffmpeg.exe not found in extracted archive");
        }
        catch (Exception ex)
        {
            MessageBox.Show(this,
                $"FFmpeg installation failed: {ex.Message}\n\nDownload manually from:\nhttps://ffmpeg.org/download.html",
                "Error",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            return null;
        }
        finally
        {
            if (File.Exists(zipPath))
                File.Delete(zipPath);
        }
    }

    private bool InstallVirtualAudioCapturer()
    {
        var installerPath = Path.Combine(Path.GetTempPath(), "Setup.Screen.Capturer.Recorder.exe");

        try
        {
            // Download
            if (!ShowDownloadProgress("Downloading Virtual Audio Capturer", VacInstallerUrl, installerPath))
                return false;

            // Run installer silently
            var process = Process.Start(new ProcessStartInfo
            {
                FileName = installerPath,
                Arguments = "/S",
                UseShellExecute = true
            });

            process?.WaitForExit();

            // Check if installed
            if (IsVirtualAudioCapturerInstalled())
            {
                MessageBox.Show(this,
                    "Virtual Audio Capturer installed successfully!\n\nThe device list will now refresh.",
                    "Done",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Information);
                return true;
            }

            MessageBox.Show(this,
                "Installation may have failed.\n\nTry running the installer manually from:\nhttps://github.com/rdp/screen-capture-recorder-to-video-windows-free/releases",
                "Warning",
                MessageBoxButtons.OK,
                MessageBoxIcon.Warning);
            return false;
        }
        catch (Exception ex)
        {
            MessageBox.Show(this,
                $"Installation failed: {ex.Message}\n\nDownload manually from:\nhttps://github.com/rdp/screen-capture-recorder-to-video-windows-free/releases",
                "Error",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            return false;
        }
        finally
        {
            if (File.Exists(installerPath))
                File.Delete(installerPath);
        }
    }

    private bool IsVirtualAudioCapturerInstalled()
    {
        var paths = new[]
        {
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Screen Capturer Recorder"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Screen Capturer Recorder")
        };

        return paths.Any(Directory.Exists);
    }

    #endregion

    #region Device Management

    private List<string> GetDShowAudioDevices()
    {
        if (string.IsNullOrEmpty(_ffmpegPath))
        {
            Log("GetDShowAudioDevices: ffmpegPath is empty");
            return new List<string>();
        }

        Log($"Running: {_ffmpegPath} -f dshow -list_devices true -i dummy");

        var psi = new ProcessStartInfo
        {
            FileName = _ffmpegPath,
            Arguments = "-f dshow -list_devices true -i dummy",
            UseShellExecute = false,
            RedirectStandardError = true,
            RedirectStandardOutput = true,
            CreateNoWindow = true
        };

        var process = Process.Start(psi);
        if (process == null)
        {
            Log("GetDShowAudioDevices: Process.Start returned null");
            return new List<string>();
        }

        var stderr = process.StandardError.ReadToEnd();
        process.WaitForExit();

        Log($"FFmpeg stderr length: {stderr.Length}");
        Log($"FFmpeg stderr:\n{stderr}");

        var devices = new List<string>();
        // Match either "device" (audio) or (audio) "device"
        var regexBefore = new Regex(@"""(.+)""\s*\(audio\)");
        var regexAfter = new Regex(@"\(audio\).*""(.+)""");

        foreach (var line in stderr.Split('\n'))
        {
            if (line.Contains("(audio)") && !line.Contains("Alternative name"))
            {
                var match = regexBefore.Match(line);
                if (!match.Success)
                    match = regexAfter.Match(line);

                if (match.Success)
                {
                    Log($"Found device: {match.Groups[1].Value}");
                    devices.Add(match.Groups[1].Value);
                }
            }
        }

        return devices;
    }

    private static string GetDeviceTypePrefix(string deviceName)
    {
        var lower = deviceName.ToLowerInvariant();

        if (Regex.IsMatch(lower, @"stereo mix|virtual-audio-capturer|loopback|what u hear|wave out"))
            return "[System Audio]";

        if (Regex.IsMatch(lower, @"speakers|headphones|realtek.*output|output"))
            return "[System Audio]";

        if (Regex.IsMatch(lower, @"microphone|mic|input|webcam|usb audio"))
            return "[Microphone]";

        return "[Audio Device]";
    }

    private static (string? mic, string? sys) GuessDefaultDevices(List<string> devices)
    {
        string? mic = null;
        string? sys = null;

        foreach (var d in devices)
        {
            var lower = d.ToLowerInvariant();
            if (mic == null && Regex.IsMatch(lower, @"microphone|mic"))
                mic = d;
            if (sys == null && Regex.IsMatch(lower, @"stereo mix|virtual-audio-capturer|loopback|speakers|headphones"))
                sys = d;
        }

        if (mic == null && devices.Count > 0) mic = devices[0];
        if (sys == null && devices.Count > 1) sys = devices[1];
        else if (sys == null && devices.Count > 0) sys = devices[0];

        return (mic, sys);
    }

    #endregion

    #region Recording

    private string BuildFfmpegArgs(string outputPath, List<string> devices, List<double> volumes)
    {
        var args = new List<string> { "-y" };

        foreach (var device in devices)
        {
            args.AddRange(new[] { "-f", "dshow", "-i", $"audio=\"{device}\"" });
        }

        if (devices.Count > 1)
        {
            var filterParts = new List<string>();
            var mixInputs = new List<string>();

            for (int i = 0; i < devices.Count; i++)
            {
                filterParts.Add($"[{i}:a]volume={volumes[i]}[a{i}]");
                mixInputs.Add($"[a{i}]");
            }

            var filterComplex = string.Join(";", filterParts) + ";" +
                                string.Join("", mixInputs) +
                                $"amix=inputs={devices.Count}:duration=longest:dropout_transition=2";
            args.AddRange(new[] { "-filter_complex", $"\"{filterComplex}\"" });
        }
        else if (volumes[0] != 1.0)
        {
            args.AddRange(new[] { "-af", $"volume={volumes[0]}" });
        }

        args.AddRange(new[] { "-ac", "2", "-ar", "48000", "-c:a", "libmp3lame", "-b:a", "192k", $"\"{outputPath}\"" });

        return string.Join(" ", args);
    }

    private void StartRecording(List<string> devices, List<double> volumes)
    {
        if (_isRecording || string.IsNullOrEmpty(_ffmpegPath)) return;

        _isRecording = true;
        _startTime = DateTime.Now;

        var args = BuildFfmpegArgs(_outputPath, devices, volumes);

        var psi = new ProcessStartInfo
        {
            FileName = _ffmpegPath,
            Arguments = args,
            UseShellExecute = false,
            RedirectStandardInput = true,
            RedirectStandardError = false,
            RedirectStandardOutput = false,
            CreateNoWindow = true
        };

        _ffmpegProcess = Process.Start(psi);
    }

    private void StopRecording()
    {
        if (_ffmpegProcess != null && !_ffmpegProcess.HasExited)
        {
            try
            {
                _ffmpegProcess.StandardInput.WriteLine("q");
                _ffmpegProcess.StandardInput.Close();
                if (!_ffmpegProcess.WaitForExit(5000))
                    _ffmpegProcess.Kill();
            }
            catch
            {
                try { _ffmpegProcess.Kill(); } catch { }
            }
        }

        _isRecording = false;
    }

    #endregion

    #region Config

    private class Config
    {
        public string? FfmpegPath { get; set; }
        public int MicVolume { get; set; } = 100;
        public int SysVolume { get; set; } = 100;
    }

    private Config? LoadConfig()
    {
        try
        {
            if (File.Exists(_cacheFile))
            {
                var json = File.ReadAllText(_cacheFile);
                return JsonSerializer.Deserialize<Config>(json);
            }
        }
        catch { }

        return null;
    }

    private void SaveConfig(string? ffmpegPath, int micVolume, int sysVolume)
    {
        try
        {
            if (!Directory.Exists(_cacheDir))
                Directory.CreateDirectory(_cacheDir);

            var config = new Config
            {
                FfmpegPath = ffmpegPath,
                MicVolume = micVolume,
                SysVolume = sysVolume
            };

            var json = JsonSerializer.Serialize(config);
            File.WriteAllText(_cacheFile, json);
        }
        catch { }
    }

    #endregion

    #region Download Progress

    private bool ShowDownloadProgress(string title, string url, string destinationPath)
    {
        using var progressForm = new Form
        {
            Text = title,
            Size = new Size(400, 130),
            StartPosition = FormStartPosition.CenterParent,
            FormBorderStyle = FormBorderStyle.FixedDialog,
            MaximizeBox = false,
            MinimizeBox = false,
            TopMost = true,
            Font = new Font("Segoe UI", 9),
            BackColor = BackgroundColor,
            ForeColor = TextPrimaryColor
        };

        var progressLabel = new Label
        {
            Location = new Point(15, 15),
            Size = new Size(360, 20),
            Text = "Starting download..."
        };

        var progressBar = new ProgressBar
        {
            Location = new Point(15, 40),
            Size = new Size(355, 25),
            Style = ProgressBarStyle.Continuous
        };

        progressForm.Controls.Add(progressLabel);
        progressForm.Controls.Add(progressBar);

        var completed = false;
        Exception? error = null;

        using var webClient = new WebClient();
        webClient.DownloadProgressChanged += (s, e) =>
        {
            progressBar.Value = e.ProgressPercentage;
            var mb = Math.Round(e.BytesReceived / 1048576.0, 1);
            var totalMb = Math.Round(e.TotalBytesToReceive / 1048576.0, 1);
            progressLabel.Text = $"Downloading: {mb} MB / {totalMb} MB ({e.ProgressPercentage}%)";
        };

        webClient.DownloadFileCompleted += (s, e) =>
        {
            error = e.Error;
            completed = true;
        };

        progressForm.Shown += async (s, e) =>
        {
            try
            {
                webClient.DownloadFileAsync(new Uri(url), destinationPath);

                while (!completed)
                {
                    await System.Threading.Tasks.Task.Delay(50);
                    Application.DoEvents();
                }
            }
            catch (Exception ex)
            {
                error = ex;
            }
            finally
            {
                progressForm.Close();
            }
        };

        progressForm.ShowDialog(this);

        if (error != null)
            throw error;

        return completed && error == null;
    }

    #endregion

    #region Event Handlers

    private void BtnBrowse_Click(object? sender, EventArgs e)
    {
        using var saveDialog = new SaveFileDialog
        {
            Filter = "MP3 Audio|*.mp3|All Files|*.*",
            FileName = Path.GetFileName(_txtSavePath.Text),
            InitialDirectory = Path.GetDirectoryName(_txtSavePath.Text)
        };

        if (saveDialog.ShowDialog(this) == DialogResult.OK)
        {
            _txtSavePath.Text = saveDialog.FileName;
            _outputPath = saveDialog.FileName;
        }
    }

    private void BtnStart_Click(object? sender, EventArgs e)
    {
        if (_isRecording) return;

        var selectedIndices = _deviceCheckList.CheckedIndices;
        if (selectedIndices.Count == 0)
        {
            MessageBox.Show(this, "Please select at least one audio device.", "No Device", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        var selectedDevices = selectedIndices.Cast<int>().Select(i => _deviceList[i]).ToList();

        _outputPath = _txtSavePath.Text;
        if (string.IsNullOrWhiteSpace(_outputPath))
        {
            MessageBox.Show(this, "Please specify a save location.", "No Path", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        var recordDir = Path.GetDirectoryName(_outputPath);
        if (!string.IsNullOrEmpty(recordDir) && !Directory.Exists(recordDir))
            Directory.CreateDirectory(recordDir);

        // Calculate volumes
        var micVol = _sliderMicVol.Value / 100.0;
        var sysVol = _sliderSysVol.Value / 100.0;
        var volumes = selectedDevices.Select(d =>
            GetDeviceTypePrefix(d) == "[Microphone]" ? micVol : sysVol).ToList();

        StartRecording(selectedDevices, volumes);

        _btnStart.Enabled = false;
        _btnStop.Enabled = true;
        _btnBrowse.Enabled = false;
        _txtSavePath.Enabled = false;
        _deviceCheckList.Enabled = false;
        _sliderMicVol.Enabled = false;
        _sliderSysVol.Enabled = false;
        _timer.Start();
    }

    private void BtnStop_Click(object? sender, EventArgs e)
    {
        _timer.Stop();
        StopRecording();

        MessageBox.Show(this, $"Recording saved to:\n{_outputPath}", "Done", MessageBoxButtons.OK, MessageBoxIcon.Information);

        // Re-enable for next recording
        _btnStart.Enabled = true;
        _btnStop.Enabled = false;
        _btnBrowse.Enabled = true;
        _txtSavePath.Enabled = true;
        _deviceCheckList.Enabled = true;
        _sliderMicVol.Enabled = true;
        _sliderSysVol.Enabled = true;

        // New filename for next recording
        _outputPath = Path.Combine(_defaultSaveDir, string.Format(DefaultFileNamePattern, DateTime.Now));
        _txtSavePath.Text = _outputPath;
        _labelTime.Text = "Elapsed: 00:00:00";
    }

    private void MainForm_FormClosing(object? sender, FormClosingEventArgs e)
    {
        SaveConfig(_ffmpegPath, _sliderMicVol.Value, _sliderSysVol.Value);

        if (_ffmpegProcess != null && !_ffmpegProcess.HasExited)
        {
            try { _ffmpegProcess.Kill(); } catch { }
        }
    }

    #endregion
    }
}
