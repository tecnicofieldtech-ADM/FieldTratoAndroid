; FieldPec Online Conector - Inno Setup 6
; Compile com: Pack-ConnectorSetup.ps1  (ou ISCC.exe neste arquivo)

#define MyAppName "FieldPec Online Conector"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "R Sistemas"
#define MyAppURL "http://127.0.0.1:3080/"
#define MyAppExeName "Abrir-Painel.cmd"
#define MyServiceName "FieldPecOnlineConnector"

[Setup]
AppId={{8F3C2A91-6B4E-4D17-9C2A-1A2B3C4D5E6F}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
DefaultDirName=C:\FieldPecConnector
DefaultGroupName=FieldPec Online
DisableProgramGroupPage=yes
PrivilegesRequired=admin
OutputDir=..\..\dist
OutputBaseFilename=FieldPec-Conector-Setup-{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayName={#MyAppName}
SetupLogging=yes
CloseApplications=force

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Criar atalho na area de trabalho"; GroupDescription: "Atalhos:"; Flags: checkedonce

[Files]
; Conteudo preparado por Pack-ConnectorSetup.ps1 em staging\
Source: "staging\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Desinstalar {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
; Node + npm + servico NSSM
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\deploy\connector\PostInstall-Connector.ps1"" -InstallDir ""{app}"" -ServiceName ""{#MyServiceName}"" -Port 3080 -SkipBrowser"; \
  StatusMsg: "Instalando Node (se necessario), dependencias e registrando servico Windows..."; \
  Flags: runhidden waituntilterminated
; Abre o painel ao final
Filename: "{app}\{#MyAppExeName}"; \
  Description: "Abrir o painel do conector agora"; \
  Flags: nowait postinstall skipifsilent shellexec

[UninstallRun]
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\deploy\connector\Uninstall-Connector.ps1"" -InstallDir ""{app}"" -ServiceName ""{#MyServiceName}"""; \
  RunOnceId: "StopConnectorService"; \
  Flags: runhidden waituntilterminated

[Code]
function InitializeSetup(): Boolean;
begin
  Result := True;
end;

