Set WshShell = CreateObject("WScript.Shell")
Set FSO = CreateObject("Scripting.FileSystemObject")

' App directory in LocalAppData
AppDir = WshShell.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\RosyRecorder"
PS1File = AppDir & "\Rosy-Recorder.ps1"
ICOFile = AppDir & "\rose.ico"
LogFile = AppDir & "\launcher.log"

' URLs for downloading assets
PS1URL = "https://raw.githubusercontent.com/shitchell/rrecord/main/Rosy-Recorder.ps1"
ICOURL = "https://raw.githubusercontent.com/shitchell/rrecord/main/rose.ico"

' Create app directory if it doesn't exist
If Not FSO.FolderExists(AppDir) Then
    FSO.CreateFolder(AppDir)
End If

' Logging function
Sub Log(msg)
    Set logStream = FSO.OpenTextFile(LogFile, 8, True)
    logStream.WriteLine "[" & Now & "] " & msg
    logStream.Close
End Sub

Log "Rosy Recorder Launcher starting"

' Download PowerShell script if missing
If Not FSO.FileExists(PS1File) Then
    Log "PowerShell script not found, downloading..."
    WshShell.Run "powershell -Command ""(New-Object System.Net.WebClient).DownloadFile('" & PS1URL & "', '" & PS1File & "')""", 0, True
    If FSO.FileExists(PS1File) Then
        Log "Downloaded Rosy-Recorder.ps1"
    Else
        Log "ERROR: Failed to download PowerShell script"
        MsgBox "Failed to download Rosy Recorder." & vbCrLf & vbCrLf & "Please check your internet connection and try again." & vbCrLf & vbCrLf & "URL: " & PS1URL, vbCritical, "Rosy Recorder - Download Error"
        WScript.Quit 1
    End If
End If

' Download icon if missing
If Not FSO.FileExists(ICOFile) Then
    Log "Icon not found, downloading..."
    WshShell.Run "powershell -Command ""(New-Object System.Net.WebClient).DownloadFile('" & ICOURL & "', '" & ICOFile & "')""", 0, True
    If FSO.FileExists(ICOFile) Then
        Log "Downloaded rose.ico"
    Else
        Log "WARNING: Failed to download icon"
    End If
End If

Log "Launching Rosy Recorder"

' Launch the PowerShell script
WshShell.Run "powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & PS1File & """", 0, False

Log "Launcher finished"

Set FSO = Nothing
Set WshShell = Nothing
