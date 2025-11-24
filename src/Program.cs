using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace RosyRecorder
{
    static class Program
    {
        [DllImport("user32.dll")]
        private static extern bool SetProcessDPIAware();

        [DllImport("kernel32.dll")]
        private static extern IntPtr GetConsoleWindow();

        [DllImport("user32.dll")]
        private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

        private const int SW_HIDE = 0;

        [STAThread]
        static void Main()
        {
            // Hide console window if it appears (workaround for cross-compiled builds)
            var consoleWindow = GetConsoleWindow();
            if (consoleWindow != IntPtr.Zero)
                ShowWindow(consoleWindow, SW_HIDE);

            SetProcessDPIAware();
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new MainForm());
        }
    }
}
