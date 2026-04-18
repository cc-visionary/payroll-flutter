; Payroll Flutter — Windows installer (Inno Setup 6+)
; Builds an UNSIGNED .exe installer for V1. Code-signing hook is included but
; commented out — drop a .pfx cert in and uncomment `SignTool` lines later.
;
; Local build:
;   flutter build windows --release --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
;   iscc installer\windows\payroll_flutter.iss
;
; CI passes /DVersion=x.y.z so the installer filename stays in sync with
; pubspec.yaml. If omitted we default to 0.1.0 for local builds.

#ifndef Version
  #define Version "0.1.0"
#endif

#define AppName        "Payroll Flutter"
#define AppPublisher   "Luxium"
#define AppURL         "https://luxium.ph"
#define AppExeName     "payroll_flutter.exe"
#define BuildDir       "..\..\build\windows\x64\runner\Release"
#define OutputBaseName "PayrollFlutter-Setup-v" + Version

[Setup]
AppId={{B0A7E3C8-5D8A-4F19-9E1F-PAYROLLFLUTTER}}
AppName={#AppName}
AppVersion={#Version}
AppVerName={#AppName} {#Version}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}
DefaultDirName={localappdata}\PayrollFlutter
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
DisableDirPage=auto
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
Compression=lzma2/ultra64
SolidCompression=yes
LZMAUseSeparateProcess=yes
WizardStyle=modern
OutputDir=..\..\dist
OutputBaseFilename={#OutputBaseName}
UninstallDisplayIcon={app}\{#AppExeName}
UninstallDisplayName={#AppName}
SetupLogging=yes
; SignTool=signtool      ; enable once a cert is configured in CI (see README)

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "quicklaunchicon"; Description: "{cm:CreateQuickLaunchIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#BuildDir}\{#AppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildDir}\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildDir}\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon
Name: "{userappdata}\Microsoft\Internet Explorer\Quick Launch\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: quicklaunchicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
