; Inno Setup script for 6browser (Windows).
; Built by scripts/build_windows.ps1, which passes SourceDir and OutputDir.

#ifndef SourceDir
  #define SourceDir "..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\dist"
#endif

[Setup]
AppId={{2307D92A-03A6-40C5-8829-ED01F57293D5}
AppName=6browser
AppVersion=1.0.0
AppPublisher=6arshid
AppPublisherURL=https://www.6arshid.com
DefaultDirName={autopf}\6browser
DefaultGroupName=6browser
UninstallDisplayIcon={app}\6browser.exe
SetupIconFile=..\windows\runner\resources\app_icon.ico
OutputDir={#OutputDir}
OutputBaseFilename=6browser-setup
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
WizardStyle=modern

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\6browser"; Filename: "{app}\6browser.exe"
Name: "{autodesktop}\6browser"; Filename: "{app}\6browser.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop icon"; Flags: unchecked

[Run]
Filename: "{app}\6browser.exe"; Description: "Launch 6browser"; Flags: nowait postinstall skipifsilent
