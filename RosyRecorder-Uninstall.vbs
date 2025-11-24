Set WshShell = CreateObject("WScript.Shell")
Set FSO = CreateObject("Scripting.FileSystemObject")

' App directory in LocalAppData
AppDir = WshShell.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\RosyRecorder"

' Screen Capturer Recorder uninstaller paths
Uninstaller = "C:\Program Files (x86)\Screen Capturer Recorder\unins000.exe"
Uninstaller64 = "C:\Program Files\Screen Capturer Recorder\unins000.exe"

' Confirm uninstall
result = MsgBox("This will uninstall Rosy Recorder and its dependencies:" & vbCrLf & vbCrLf & _
    "- FFmpeg" & vbCrLf & _
    "- Screen Capturer Recorder (Virtual Audio)" & vbCrLf & _
    "- App data and settings" & vbCrLf & vbCrLf & _
    "Continue?", vbYesNo + vbQuestion, "Uninstall Rosy Recorder")

If result = vbNo Then
    WScript.Quit 0
End If

removed = ""

' Remove RosyRecorder app directory
If FSO.FolderExists(AppDir) Then
    FSO.DeleteFolder AppDir, True
    removed = removed & "- Removed app data directory" & vbCrLf
End If

' Uninstall Screen Capturer Recorder
If FSO.FileExists(Uninstaller) Then
    WshShell.Run """" & Uninstaller & """ /SILENT", 0, True
    removed = removed & "- Uninstalled Screen Capturer Recorder" & vbCrLf
ElseIf FSO.FileExists(Uninstaller64) Then
    WshShell.Run """" & Uninstaller64 & """ /SILENT", 0, True
    removed = removed & "- Uninstalled Screen Capturer Recorder" & vbCrLf
End If

' Show results
If removed = "" Then
    MsgBox "Nothing to uninstall - Rosy Recorder was not installed.", vbInformation, "Uninstall Complete"
Else
    MsgBox "Uninstall complete:" & vbCrLf & vbCrLf & removed, vbInformation, "Uninstall Complete"
End If

Set FSO = Nothing
Set WshShell = Nothing
