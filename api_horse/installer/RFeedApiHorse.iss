; Inno Setup — RFeed API Horse (serviço Windows)
; Compile com: ISCC.exe RFeedApiHorse.iss
; Ou: ..\scripts\Build-Installer.ps1

#define MyAppName "RFeed API Horse"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "RSistemas"
#define MyAppExeName "ApiRFeedWindows.exe"

[Setup]
AppId={{A7F3C2E1-9B4D-4F2A-8E1C-000000000001}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\RSistemas\RFeed\ApiHorse
DefaultGroupName=RFeed
DisableProgramGroupPage=yes
OutputDir=output
OutputBaseFilename=RFeedApiHorse-Setup-{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#MyAppExeName}
LicenseFile=
InfoAfterFile=LEIA-ME.txt

[Tasks]
Name: "firewall"; Description: "Liberar porta TCP 3001 no firewall do Windows"; GroupDescription: "Rede:"; Flags: checkedonce
Name: "desktopicon"; Description: "Atalho na área de trabalho (abre /config)"; GroupDescription: "Atalhos:"; Flags: unchecked

[Files]
; Preenchido por scripts\Stage-InstallerPayload.ps1 em installer\payload\
Source: "payload\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "install-service.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "uninstall-service.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "LEIA-ME.txt"; DestDir: "{app}"; Flags: ignoreversion
; Não sobrescrever configuração do cliente em upgrade
Source: "payload\ApiConfig.ini.example"; DestDir: "{app}"; DestName: "ApiConfig.ini"; Flags: onlyifdoesntexist ignoreversion

[Icons]
Name: "{group}\Painel API (config)"; Filename: "http://127.0.0.1:3001/config"; IconFilename: "{sys}\url.dll"
Name: "{group}\Monitor ao vivo"; Filename: "http://127.0.0.1:3001/monitor"; IconFilename: "{sys}\url.dll"
Name: "{group}\Pasta de instalação"; Filename: "{app}"
Name: "{autodesktop}\RFeed API — Configuração"; Filename: "http://127.0.0.1:3001/config"; Tasks: desktopicon; IconFilename: "{sys}\url.dll"

[Run]
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\install-service.ps1"" -InstallDir ""{app}"" {code:FirewallArg}"; \
  StatusMsg: "Instalando serviço Windows..."; \
  Flags: waituntilterminated; \
  Description: "Registrar e iniciar serviço ApiRFeed"

[UninstallRun]
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\uninstall-service.ps1"" -InstallDir ""{app}"""; \
  Flags: waituntilterminated

[Code]
function FirewallArg(Param: string): string;
begin
  if IsTaskSelected('firewall') then
    Result := ''
  else
    Result := '-SkipFirewall';
end;
