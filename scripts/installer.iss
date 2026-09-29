; 学习桌 Todo App — Windows 安装包脚本（Inno Setup 6）
; AppId 固定不变：后续版本的安装/升级/卸载都靠它识别同一应用
; 安装模式：按当前用户安装（{autopf} → %LOCALAPPDATA%\Programs），无需管理员、无 UAC

#define MyAppName "学习桌"
#define MyAppNameEn "TodoApp"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "RJL816"
#define MyAppExeName "todo_app.exe"
#define MyAppURL "https://github.com/RJL816/TODOAPP"

[Setup]
AppId={{8F3A9C42-6B1D-4E8A-9C35-A7D2F0B4E1C6}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} v{#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}/issues
DefaultDirName={autopf}\{#MyAppNameEn}
DisableProgramGroupPage=yes
OutputDir=dist
OutputBaseFilename=todo_app_v{#MyAppVersion}-setup
SetupIconFile=app.ico
Compression=lzma2/max
SolidCompression=yes
LZMAUseSeparateProcess=yes
WizardStyle=modern
PrivilegesRequired=lowest
UninstallDisplayName={#MyAppName}
UninstallDisplayIcon={app}\{#MyAppExeName}
VersionInfoVersion={#MyAppVersion}
VersionInfoCompany={#MyAppPublisher}
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent
