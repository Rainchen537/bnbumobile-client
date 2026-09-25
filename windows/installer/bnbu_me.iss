#ifndef MyAppVersion
  #define MyAppVersion "1.2.0"
#endif

[Setup]
AppId={{A4F4E626-599B-4F32-9E1F-8133B601E348}
AppName=BNBU.ME
AppVersion={#MyAppVersion}
AppPublisher=BNBU.ME
DefaultDirName={autopf}\BNBU.ME
DefaultGroupName=BNBU.ME
DisableProgramGroupPage=yes
OutputDir=..\..\build\windows\installer
OutputBaseFilename=bnbu-me-windows-x64-setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\bnbu_me.exe
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
WizardStyle=modern
Compression=lzma2
SolidCompression=yes
CloseApplications=yes
RestartApplications=no
MinVersion=10.0.17763

[Languages]
Name: "chinesesimp"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加选项："; Flags: unchecked

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\BNBU.ME"; Filename: "{app}\bnbu_me.exe"
Name: "{autodesktop}\BNBU.ME"; Filename: "{app}\bnbu_me.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\bnbu_me.exe"; Description: "启动 BNBU.ME"; Flags: nowait postinstall skipifsilent
