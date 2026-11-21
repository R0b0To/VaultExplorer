; Inno Setup 6 script for the VaultExplorer Windows installer.
;
; Built by CI (see .github/workflows/build-desktop.yml); to build it by hand:
;   ISCC.exe /DAppVersion=1.66.0 /DBuildDir=<abs path to build\windows\x64\runner\Release> ^
;            /DOutputDir=<folder> /DOutputName=VaultExplorer-v1.66.0-windows-x64-setup packaging\windows\installer.iss
;
; BuildDir must already hold the finished app folder: vaultexplorer.exe, flutter_windows.dll,
; vaultexplorer_engine.dll, the plugin DLLs, data\ ... (the same folder the portable zip is made from).

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef BuildDir
  #error Pass /DBuildDir=<path to the Flutter Release folder>
#endif
#ifndef OutputDir
  #define OutputDir "."
#endif
#ifndef OutputName
  #define OutputName "VaultExplorer-setup"
#endif

#define AppName "VaultExplorer"
#define AppExeName "vaultexplorer.exe"
#define AppUrl "https://github.com/R0b0To/VaultExplorer"

[Setup]
; Never change AppId: it is how Windows (and this installer) recognises an existing install to upgrade.
AppId={{258BC7EB-32CD-4C88-9DE1-0C9E3B1F624C}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=R0b0To
AppPublisherURL={#AppUrl}
AppSupportURL={#AppUrl}/issues
AppUpdatesURL={#AppUrl}/releases
VersionInfoVersion={#AppVersion}.0
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExeName}
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
OutputDir={#OutputDir}
OutputBaseFilename={#OutputName}
; 64-bit only: the engine DLL and Flutter's Windows embedder are x64 builds.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Installs for the current user without admin rights by default; the wizard offers "all users" as an option.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; Close a running VaultExplorer during an upgrade instead of failing on locked files.
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

; Uninstalling removes only the program files. Settings and saved credentials live in the user's profile and
; Windows Credential Manager and are deliberately left alone.
