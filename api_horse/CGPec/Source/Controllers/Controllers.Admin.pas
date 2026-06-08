unit Controllers.Admin;

interface

uses
  Horse,
  System.SysUtils;

procedure RegistraRotasAdmin;

implementation

uses
  System.Classes,
  System.JSON,
  System.IOUtils,
  System.StrUtils,
  Udm,
  UBiMirror,
  URequestLog,
  UApiVersion;

const
  MASK_PASSWORD = '********';

function WebAdminDir: string;
begin
  Result := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'web-admin';
end;

procedure SendHtml(const AFileName: string; Res: THorseResponse);
var
  LPath, LHtml: string;
begin
  LPath := TPath.Combine(WebAdminDir, AFileName);
  if not TFile.Exists(LPath) then
    raise Exception.CreateFmt('Painel web não encontrado: %s', [LPath]);
  LHtml := TFile.ReadAllText(LPath, TEncoding.UTF8);
  Res.Send(LHtml).ContentType('text/html; charset=utf-8').Status(200);
end;

procedure SendWebAdminAsset(const AFileName, AContentType: string; Res: THorseResponse);
var
  LPath, LContent: string;
begin
  LPath := TPath.Combine(WebAdminDir, AFileName);
  if not TFile.Exists(LPath) then
  begin
    Res.Status(404).Send('Not found');
    Exit;
  end;
  LContent := TFile.ReadAllText(LPath, TEncoding.UTF8);
  Res.Send(LContent).ContentType(AContentType).Status(200);
end;

procedure GetRequestMonitorJs(Req: THorseRequest; Res: THorseResponse; Next: TProc);
begin
  SendWebAdminAsset('request-monitor.js', 'application/javascript; charset=utf-8', Res);
end;

procedure GetRoot(Req: THorseRequest; Res: THorseResponse; Next: TProc);
begin
  Res.RedirectTo('/config');
end;

procedure GetConfigPage(Req: THorseRequest; Res: THorseResponse; Next: TProc);
begin
  SendHtml('config.html', Res);
end;

procedure GetHealthPage(Req: THorseRequest; Res: THorseResponse; Next: TProc);
begin
  SendHtml('health.html', Res);
end;

procedure GetRequestsPage(Req: THorseRequest; Res: THorseResponse; Next: TProc);
begin
  SendHtml('requests.html', Res);
end;

procedure GetMonitorPage(Req: THorseRequest; Res: THorseResponse; Next: TProc);
begin
  SendHtml('requests.html', Res);
end;

procedure GetDashboardFabricacaoPage(Req: THorseRequest; Res: THorseResponse; Next: TProc);
begin
  SendHtml('dashboard-fabricacao.html', Res);
end;

procedure GetRequestLogsApi(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LLimit: Integer;
  LLimitStr: string;
begin
  LLimit := 200;
  if Req.Query.TryGetValue('limit', LLimitStr) then
    LLimit := StrToIntDef(LLimitStr, 200);
  Res.Send(GetRequestLogJson(LLimit)).ContentType('application/json; charset=utf-8').Status(200);
end;

procedure DeleteRequestLogsApi(Req: THorseRequest; Res: THorseResponse; Next: TProc);
begin
  ClearRequestLog;
  Res.Send('{"ok":true}').ContentType('application/json; charset=utf-8').Status(200);
end;

function BackendToJson(const Host, Database, User, Password: string; Port: Integer;
  const Role: string; MaskPassword: Boolean; const Enabled: string = ''): TJSONObject;
var
  LPass: string;
begin
  if MaskPassword and (Password <> '') then
    LPass := MASK_PASSWORD
  else
    LPass := Password;

  Result := TJSONObject.Create;
  Result.AddPair('host', Host);
  Result.AddPair('port', TJSONNumber.Create(Port));
  Result.AddPair('database', Database);
  Result.AddPair('user', User);
  Result.AddPair('password', LPass);
  if Role <> '' then
    Result.AddPair('role', Role);
  if Enabled <> '' then
    Result.AddPair('enabled', Enabled);
end;

function BuildPublicConfigJson: TJSONObject;
var
  LCgHost, LCgUser, LCgPass, LCgPortStr, LCgDb, LCgRole: string;
  LFpHost, LFpUser, LFpPass, LFpPortStr, LFpDb, LFpRole: string;
  LPgHost, LPgUser, LPgPass, LPgPortStr, LPgDb, LPgEnabled: string;
  LMirrorEnabled, LMirrorUrl, LMirrorNextApiBase: string;
  LCgPort, LFpPort, LPgPort: Integer;
  LBackends, LMirror: TJSONObject;
begin
  dmdb.ReadCgpecIni(LCgHost, LCgUser, LCgPass, LCgPortStr, LCgDb, LCgRole);
  LCgPort := StrToIntDef(LCgPortStr, 3050);

  dmdb.ReadFieldPecIni(LFpHost, LFpUser, LFpPass, LFpPortStr, LFpDb, LFpRole);
  LFpPort := StrToIntDef(LFpPortStr, 3050);

  dmdb.ReadPostgresIni(LPgHost, LPgUser, LPgPass, LPgPortStr, LPgDb, LPgEnabled);
  LPgPort := StrToIntDef(LPgPortStr, 5432);

  dmdb.ReadMirrorIni(LMirrorEnabled, LMirrorUrl, LMirrorNextApiBase);

  LBackends := TJSONObject.Create;
  LBackends.AddPair('cgpec', BackendToJson(LCgHost, LCgDb, LCgUser, LCgPass, LCgPort, LCgRole, True));
  LBackends.AddPair('fieldpec', BackendToJson(LFpHost, LFpDb, LFpUser, LFpPass, LFpPort, LFpRole, True));
  LBackends.AddPair('spreadsheet_import',
    BackendToJson(LPgHost, LPgDb, LPgUser, LPgPass, LPgPort, '', True, LPgEnabled));

  LMirror := TJSONObject.Create;
  LMirror.AddPair('enabled', LMirrorEnabled);
  LMirror.AddPair('nextApiBase', LMirrorNextApiBase);
  LMirror.AddPair('url', LMirrorUrl);

  Result := TJSONObject.Create;
  Result.AddPair('activeClient', dmdb.GetActiveClient);
  Result.AddPair('fornecimentoAcumulativo', TJSONBool.Create(dmdb.GetFornecimentoAcumulativo));
  ApiVersionAddPairs(Result);
  Result.AddPair('pontoCorteFornecimentoKg', TJSONNumber.Create(dmdb.GetPontoCorteFornecimentoKg));
  Result.AddPair('backends', LBackends);
  Result.AddPair('mirror', LMirror);
  Result.AddPair('nextApiBaseUrl', NextApiBaseUrl);
  Result.AddPair('iniPath', dmdb.ConfigIniFilePath);
  Result.AddPair('exePath', ParamStr(0));
end;

function BuildSyncJsonForNextApi(
  const ActiveClient: string;
  const FornecimentoAcumulativo: Boolean;
  const CgHost, CgDb, CgUser, CgPass: string; CgPort: Integer; const CgRole: string;
  const FpHost, FpDb, FpUser, FpPass: string; FpPort: Integer; const FpRole: string;
  const PgHost, PgDb, PgUser, PgPass: string; PgPort: Integer): string;
var
  LRoot, LBackends, LCg, LPg, LField: TJSONObject;
  LClient: string;
begin
  LCg := BackendToJson(CgHost, CgDb, CgUser, CgPass, CgPort, CgRole, False);
  LField := BackendToJson(FpHost, FpDb, FpUser, FpPass, FpPort, FpRole, False);
  LPg := BackendToJson(PgHost, PgDb, PgUser, PgPass, PgPort, '', False);
  LClient := LowerCase(Trim(ActiveClient));
  if (LClient <> 'fieldpec') and (LClient <> 'spreadsheet_import') then
    LClient := 'cgpec';
  LBackends := TJSONObject.Create;
  try
    LBackends.AddPair('cgpec', LCg);
    LBackends.AddPair('fieldpec', LField);
    LBackends.AddPair('spreadsheet_import', LPg);
    LRoot := TJSONObject.Create;
    try
      LRoot.AddPair('activeClient', LClient);
      LRoot.AddPair('fornecimentoAcumulativo', TJSONBool.Create(FornecimentoAcumulativo));
      LRoot.AddPair('backends', LBackends);
      Result := LRoot.ToJSON;
    finally
      LRoot.Free;
    end;
  finally
    LBackends.Free;
  end;
end;

procedure GetApiVersion(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LJson: TJSONObject;
begin
  try
    LJson := BuildApiVersionJson;
    try
      Res.Send(LJson.ToJSON).ContentType('application/json; charset=utf-8').Status(200);
    finally
      LJson.Free;
    end;
  except
    on E: Exception do
      Res.Send(TJSONObject.Create.AddPair('erro', E.Message)).Status(500);
  end;
end;

procedure GetApiVersionJs(Req: THorseRequest; Res: THorseResponse; Next: TProc);
begin
  SendWebAdminAsset('api-version.js', 'application/javascript; charset=utf-8', Res);
end;

procedure GetApiConfig(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LJson: TJSONObject;
begin
  try
    LJson := BuildPublicConfigJson;
    try
      Res.Send(LJson.ToJSON).ContentType('application/json').Status(200);
    finally
      LJson.Free;
    end;
  except
    on E: Exception do
      Res.Send(TJSONObject.Create.AddPair('erro', E.Message)).Status(500);
  end;
end;

function ExtractBackend(const Root: TJSONObject; const Key: string): TJSONObject;
begin
  Result := nil;
  if (Root = nil) or not (Root.GetValue('backends') is TJSONObject) then
    Exit;
  if (Root.GetValue('backends') as TJSONObject).GetValue(Key) is TJSONObject then
    Result := (Root.GetValue('backends') as TJSONObject).GetValue(Key) as TJSONObject;
end;

function ExtractMirror(const Root: TJSONObject): TJSONObject;
begin
  Result := nil;
  if (Root <> nil) and (Root.GetValue('mirror') is TJSONObject) then
    Result := Root.GetValue('mirror') as TJSONObject;
end;

function JsonStr(const Obj: TJSONObject; const Name, Default: string): string;
var
  LVal: TJSONValue;
begin
  Result := Default;
  if Obj = nil then
    Exit;
  LVal := Obj.GetValue(Name);
  if LVal = nil then
    Exit;
  Result := Trim(LVal.Value);
end;

function JsonInt(const Obj: TJSONObject; const Name: string; Default: Integer): Integer;
var
  LVal: TJSONValue;
begin
  Result := Default;
  if Obj = nil then
    Exit;
  LVal := Obj.GetValue(Name);
  if LVal = nil then
    Exit;
  Result := StrToIntDef(LVal.Value, Default);
end;

function JsonDouble(const Obj: TJSONObject; const Name: string; Default: Double): Double;
var
  LVal: TJSONValue;
  LS: string;
begin
  Result := Default;
  if Obj = nil then
    Exit;
  LVal := Obj.GetValue(Name);
  if LVal = nil then
    Exit;
  LS := StringReplace(Trim(LVal.Value), ',', '.', [rfReplaceAll]);
  Result := StrToFloatDef(LS, Default);
end;

function JsonBool(const Obj: TJSONObject; const Name: string; Default: Boolean): Boolean;
var
  LVal: TJSONValue;
  LS: string;
begin
  Result := Default;
  if Obj = nil then
    Exit;
  LVal := Obj.GetValue(Name);
  if LVal = nil then
    Exit;
  if LVal is TJSONTrue then
    Exit(True);
  if LVal is TJSONFalse then
    Exit(False);
  LS := LowerCase(Trim(LVal.Value));
  if (LS = '0') or (LS = 'false') or (LS = 'no') or (LS = 'nao') or (LS = 'não') then
    Result := False
  else if (LS = '1') or (LS = 'true') or (LS = 'yes') or (LS = 'sim') then
    Result := True;
end;

procedure PostApiConfig(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LBody: TJSONObject;
  LCgpec, LFieldpec, LSpreadsheet, LMirror, LResponse: TJSONObject;
  LCgHost, LCgUser, LCgPass, LCgDb, LCgRole: string;
  LCgPort: Integer;
  LFpHost, LFpUser, LFpPass, LFpDb, LFpRole: string;
  LFpPort: Integer;
  LPgHost, LPgUser, LPgPass, LPgDb, LPgEnabled: string;
  LPgPort: Integer;
  LActiveClient: string;
  LMirrorEnabled, LMirrorUrl, LMirrorNextApiBase: string;
  LCurCgHost, LCurCgUser, LCurCgPass, LCurCgPort, LCurCgDb, LCurCgRole: string;
  LCurFpHost, LCurFpUser, LCurFpPass, LCurFpPort, LCurFpDb, LCurFpRole: string;
  LCurPgHost, LCurPgUser, LCurPgPass, LCurPgPort, LCurPgDb, LCurPgEnabled: string;
  LSyncOk: Boolean;
  LSyncMsg: string;
  LSyncNote: string;
  LFornAcumulativo: Boolean;
  LFornAcumStr: string;
  LPontoCorteKg: Double;
  LPontoCorteStr: string;
begin
  try
    LBody := TJSONObject.ParseJSONValue(Req.Body) as TJSONObject;
    if LBody = nil then
      raise Exception.Create('JSON inválido.');

    try
      LActiveClient := LowerCase(JsonStr(LBody, 'activeClient', 'cgpec'));
      if (LActiveClient <> 'fieldpec') and (LActiveClient <> 'spreadsheet_import') then
        LActiveClient := 'cgpec';

      LCgpec := ExtractBackend(LBody, 'cgpec');
      if LCgpec = nil then
        raise Exception.Create('Backend cgpec é obrigatório.');

      LCgHost := JsonStr(LCgpec, 'host', '');
      LCgPort := JsonInt(LCgpec, 'port', 3050);
      LCgDb := JsonStr(LCgpec, 'database', '');
      LCgUser := JsonStr(LCgpec, 'user', '');
      LCgPass := JsonStr(LCgpec, 'password', '');
      LCgRole := JsonStr(LCgpec, 'role', '');

      if LCgHost = '' then
        raise Exception.Create('Host CGPec obrigatório.');
      if (LCgPort < 1) or (LCgPort > 65535) then
        raise Exception.Create('Porta Firebird CGPec inválida (1–65535).');
      if (LActiveClient <> 'fieldpec') and (LCgDb = '') then
        raise Exception.Create('Database CGPec obrigatório.');
      if (LActiveClient <> 'fieldpec') and (LCgUser = '') then
        raise Exception.Create('Usuário CGPec obrigatório.');

      dmdb.ReadCgpecIni(LCurCgHost, LCurCgUser, LCurCgPass, LCurCgPort, LCurCgDb, LCurCgRole);
      if LCgPass = MASK_PASSWORD then
        LCgPass := LCurCgPass;

      LFieldpec := ExtractBackend(LBody, 'fieldpec');
      if LFieldpec = nil then
        raise Exception.Create('Backend fieldpec é obrigatório.');

      LFpHost := JsonStr(LFieldpec, 'host', '127.0.0.1');
      LFpPort := JsonInt(LFieldpec, 'port', 3050);
      LFpDb := JsonStr(LFieldpec, 'database', '');
      LFpUser := JsonStr(LFieldpec, 'user', 'SYSDBA');
      LFpPass := JsonStr(LFieldpec, 'password', '');
      LFpRole := JsonStr(LFieldpec, 'role', '');

      if LFpDb = '' then
      begin
        if LActiveClient = 'fieldpec' then
          raise Exception.Create('Database FieldPec obrigatório.');
      end;
      if LFpUser = '' then
      begin
        if LActiveClient = 'fieldpec' then
          raise Exception.Create('Usuário FieldPec obrigatório.');
      end;
      if (LActiveClient = 'fieldpec') and (LFpHost = '') then
        raise Exception.Create('Host FieldPec obrigatório.');

      dmdb.ReadFieldPecIni(LCurFpHost, LCurFpUser, LCurFpPass, LCurFpPort, LCurFpDb, LCurFpRole);
      if LFpPass = MASK_PASSWORD then
        LFpPass := LCurFpPass;

      LSpreadsheet := ExtractBackend(LBody, 'spreadsheet_import');
      if LSpreadsheet = nil then
        raise Exception.Create('Backend spreadsheet_import é obrigatório.');

      LPgHost := JsonStr(LSpreadsheet, 'host', '127.0.0.1');
      LPgPort := JsonInt(LSpreadsheet, 'port', 5432);
      LPgDb := JsonStr(LSpreadsheet, 'database', '');
      LPgUser := JsonStr(LSpreadsheet, 'user', 'postgres');
      LPgPass := JsonStr(LSpreadsheet, 'password', '');
      LPgEnabled := JsonStr(LSpreadsheet, 'enabled', '1');
      if (LPgEnabled <> '0') and (LPgEnabled <> '1') then
        LPgEnabled := '1';

      dmdb.ReadPostgresIni(LCurPgHost, LCurPgUser, LCurPgPass, LCurPgPort, LCurPgDb, LCurPgEnabled);
      if LPgPass = MASK_PASSWORD then
        LPgPass := LCurPgPass;

      LMirror := ExtractMirror(LBody);
      if LMirror <> nil then
      begin
        LMirrorEnabled := JsonStr(LMirror, 'enabled', '0');
        LMirrorNextApiBase := JsonStr(LMirror, 'nextApiBase', 'http://127.0.0.1:3000');
        LMirrorUrl := JsonStr(LMirror, 'url', LMirrorNextApiBase + '/api/mirror/event');
      end
      else
        dmdb.ReadMirrorIni(LMirrorEnabled, LMirrorUrl, LMirrorNextApiBase);

      if LMirrorEnabled = '' then
        LMirrorEnabled := '0';
      if LMirrorNextApiBase = '' then
        LMirrorNextApiBase := 'http://127.0.0.1:3000';
      if LMirrorUrl = '' then
        LMirrorUrl := LMirrorNextApiBase + '/api/mirror/event';

      LFornAcumulativo := JsonBool(LBody, 'fornecimentoAcumulativo', dmdb.GetFornecimentoAcumulativo);
      if LFornAcumulativo then
        LFornAcumStr := '1'
      else
        LFornAcumStr := '0';

      LPontoCorteKg := JsonDouble(LBody, 'pontoCorteFornecimentoKg', dmdb.GetPontoCorteFornecimentoKg);
      if LPontoCorteKg < 0 then
        raise Exception.Create('Ponto de corte fornecimento (kg) deve ser 0 ou maior.');
      LPontoCorteStr := StringReplace(FormatFloat('0.###', LPontoCorteKg), ',', '.', [rfReplaceAll]);

      dmdb.WriteApiConfigIni(LActiveClient,
        LCgHost, LCgUser, LCgPass, IntToStr(LCgPort), LCgDb, LCgRole,
        LFpHost, LFpUser, LFpPass, IntToStr(LFpPort), LFpDb, LFpRole,
        LPgHost, LPgUser, LPgPass, IntToStr(LPgPort), LPgDb, LPgEnabled,
        LMirrorEnabled, LMirrorUrl, LMirrorNextApiBase,
        LFornAcumStr, LPontoCorteStr);
      dmdb.DisconnectCgpec;
      BiMirrorReloadConfig;

      TrySyncConfigToNextApi(BuildSyncJsonForNextApi(LActiveClient, LFornAcumulativo,
        LCgHost, LCgDb, LCgUser, LCgPass, LCgPort, LCgRole,
        LFpHost, LFpDb, LFpUser, LFpPass, LFpPort, LFpRole,
        LPgHost, LPgDb, LPgUser, LPgPass, LPgPort), LSyncOk, LSyncMsg);
      if LSyncOk then
        LSyncNote := LSyncMsg + ' Reinicie a API Horse para aplicar o cliente ativo.'
      else
        LSyncNote := 'Aviso: ' + LSyncMsg + ' Reinicie a API Horse para aplicar o cliente ativo.';

      LResponse := BuildPublicConfigJson;
      try
        LResponse.AddPair('syncNote', LSyncNote);
        Res.Send(LResponse.ToJSON).ContentType('application/json').Status(200);
      finally
        LResponse.Free;
      end;
    finally
      LBody.Free;
    end;
  except
    on E: Exception do
      Res.Send(TJSONObject.Create.AddPair('erro', E.Message)).Status(400);
  end;
end;

procedure PostApiConfigTest(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LBody: TJSONObject;
  LKind, LClient, LHost, LUser, LPass, LDb, LRole: string;
  LPort: Integer;
  LOk: Boolean;
  LErr: string;
  LResp: TJSONObject;
  LCurHost, LCurUser, LCurPass, LCurPort, LCurDb, LCurRole: string;
  LCurFpHost, LCurFpUser, LCurFpPass, LCurFpPort, LCurFpDb, LCurFpRole: string;
  LCurPgHost, LCurPgUser, LCurPgPass, LCurPgPort, LCurPgDb, LCurPgEnabled: string;
begin
  try
    LBody := TJSONObject.ParseJSONValue(Req.Body) as TJSONObject;
    if LBody = nil then
      raise Exception.Create('JSON inválido.');

    try
      LKind := JsonStr(LBody, 'kind', 'firebird');
      LClient := LowerCase(JsonStr(LBody, 'client', 'cgpec'));
      LHost := JsonStr(LBody, 'host', '');
      LPort := JsonInt(LBody, 'port', 3050);
      LDb := JsonStr(LBody, 'database', '');
      LUser := JsonStr(LBody, 'user', '');
      LPass := JsonStr(LBody, 'password', '');
      LRole := JsonStr(LBody, 'role', '');

      if SameText(LKind, 'postgres') then
      begin
        LPort := JsonInt(LBody, 'port', 5432);
        if LPass = MASK_PASSWORD then
        begin
          dmdb.ReadPostgresIni(LCurPgHost, LCurPgUser, LCurPgPass, LCurPgPort, LCurPgDb, LCurPgEnabled);
          LPass := LCurPgPass;
        end;
        if LHost = '' then
          raise Exception.Create('Host PostgreSQL obrigatório.');
        if LDb = '' then
          raise Exception.Create('Database PostgreSQL obrigatório.');
        if LUser = '' then
          raise Exception.Create('Usuário PostgreSQL obrigatório.');

        dmdb.TestPostgresConnection(LHost, LUser, LPass, IntToStr(LPort), LDb, LOk, LErr);
        if not LOk then
        begin
          LResp := TJSONObject.Create;
          LResp.AddPair('ok', TJSONFalse.Create);
          LResp.AddPair('erro', LErr);
          Res.Send(LResp.ToJSON).ContentType('application/json').Status(400);
          Exit;
        end;
        Res.Send('{"ok":true}').ContentType('application/json').Status(200);
        Exit;
      end;

      if LPass = MASK_PASSWORD then
      begin
        if LClient = 'fieldpec' then
          dmdb.ReadFieldPecIni(LCurFpHost, LCurFpUser, LCurFpPass, LCurFpPort, LCurFpDb, LCurFpRole)
        else
          dmdb.ReadCgpecIni(LCurHost, LCurUser, LCurPass, LCurPort, LCurDb, LCurRole);
        if LClient = 'fieldpec' then
          LPass := LCurFpPass
        else
          LPass := LCurPass;
      end;

      if LHost = '' then
        raise Exception.Create('Host obrigatório.');
      if LDb = '' then
        raise Exception.Create('Database obrigatório.');
      if LUser = '' then
        raise Exception.Create('Usuário obrigatório.');

      if LClient = 'fieldpec' then
        dmdb.TestFieldPecConnection(LHost, LUser, LPass, IntToStr(LPort), LDb, LOk, LErr)
      else
        dmdb.TestCgpecConnection(LHost, LUser, LPass, IntToStr(LPort), LDb, LOk, LErr);
      if not LOk then
      begin
        LResp := TJSONObject.Create;
        LResp.AddPair('ok', TJSONFalse.Create);
        LResp.AddPair('erro', LErr);
        Res.Send(LResp.ToJSON).ContentType('application/json').Status(400);
        Exit;
      end;

      Res.Send('{"ok":true}').ContentType('application/json').Status(200);
    finally
      LBody.Free;
    end;
  except
    on E: Exception do
    begin
      LResp := TJSONObject.Create;
      LResp.AddPair('ok', TJSONFalse.Create);
      LResp.AddPair('erro', E.Message);
      Res.Send(LResp.ToJSON).ContentType('application/json').Status(400);
    end;
  end;
end;

procedure PostApiConfigPostgres(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LBody, LSpreadsheet, LResponse: TJSONObject;
  LPgHost, LPgUser, LPgPass, LPgDb, LPgEnabled: string;
  LPgPort: Integer;
  LCurPgHost, LCurPgUser, LCurPgPass, LCurPgPort, LCurPgDb, LCurPgEnabled: string;
  LSyncOk: Boolean;
  LSyncMsg, LSyncNote: string;
  LCgHost, LCgUser, LCgPass, LCgPortStr, LCgDb, LCgRole: string;
  LFpHost, LFpUser, LFpPass, LFpPortStr, LFpDb, LFpRole: string;
  LCgPort, LFpPort: Integer;
begin
  try
    LBody := TJSONObject.ParseJSONValue(Req.Body) as TJSONObject;
    if LBody = nil then
      raise Exception.Create('JSON inválido.');

    try
      LSpreadsheet := ExtractBackend(LBody, 'spreadsheet_import');
      if LSpreadsheet = nil then
        LSpreadsheet := LBody;

      LPgHost := JsonStr(LSpreadsheet, 'host', '127.0.0.1');
      LPgPort := JsonInt(LSpreadsheet, 'port', 5432);
      LPgDb := JsonStr(LSpreadsheet, 'database', '');
      LPgUser := JsonStr(LSpreadsheet, 'user', 'postgres');
      LPgPass := JsonStr(LSpreadsheet, 'password', '');
      LPgEnabled := JsonStr(LSpreadsheet, 'enabled', '1');
      if (LPgEnabled <> '0') and (LPgEnabled <> '1') then
        LPgEnabled := '1';

      if LPgHost = '' then
        raise Exception.Create('Host PostgreSQL obrigatório.');
      if LPgDb = '' then
        raise Exception.Create('Database PostgreSQL obrigatório.');
      if LPgUser = '' then
        raise Exception.Create('Usuário PostgreSQL obrigatório.');

      dmdb.ReadPostgresIni(LCurPgHost, LCurPgUser, LCurPgPass, LCurPgPort, LCurPgDb, LCurPgEnabled);
      if LPgPass = MASK_PASSWORD then
        LPgPass := LCurPgPass;
      if LPgPass = '' then
        raise Exception.Create('Senha PostgreSQL obrigatória na primeira gravação.');

      dmdb.WritePostgresIni(LPgHost, LPgUser, LPgPass, IntToStr(LPgPort), LPgDb, LPgEnabled);

      dmdb.ReadCgpecIni(LCgHost, LCgUser, LCgPass, LCgPortStr, LCgDb, LCgRole);
      LCgPort := StrToIntDef(LCgPortStr, 3050);
      dmdb.ReadFieldPecIni(LFpHost, LFpUser, LFpPass, LFpPortStr, LFpDb, LFpRole);
      LFpPort := StrToIntDef(LFpPortStr, 3050);
      TrySyncConfigToNextApi(BuildSyncJsonForNextApi(dmdb.GetActiveClient,
        dmdb.GetFornecimentoAcumulativo,
        LCgHost, LCgDb, LCgUser, LCgPass, LCgPort, LCgRole,
        LFpHost, LFpDb, LFpUser, LFpPass, LFpPort, LFpRole,
        LPgHost, LPgDb, LPgUser, LPgPass, LPgPort), LSyncOk, LSyncMsg);
      if LSyncOk then
        LSyncNote := LSyncMsg
      else
        LSyncNote := 'Aviso: ' + LSyncMsg;

      LResponse := BuildPublicConfigJson;
      try
        LResponse.AddPair('syncNote', LSyncNote);
        Res.Send(LResponse.ToJSON).ContentType('application/json').Status(200);
      finally
        LResponse.Free;
      end;
    finally
      LBody.Free;
    end;
  except
    on E: Exception do
      Res.Send(TJSONObject.Create.AddPair('erro', E.Message)).Status(400);
  end;
end;

function GetAuditFornecimentoBaseDir: string;
var
  Env: string;
begin
  Env := Trim(GetEnvironmentVariable('RFEED_AUDIT_DIR'));
  if Env <> '' then
    Exit(IncludeTrailingPathDelimiter(Env));

  Result := TPath.Combine(GetEnvironmentVariable('PROGRAMDATA'), 'RFeed');
  Result := TPath.Combine(Result, 'audit');
  Result := TPath.Combine(Result, 'fornecimento');
  Result := IncludeTrailingPathDelimiter(Result);
end;

function IsSafeAuditDeviceId(const S: string): Boolean;
var
  I: Integer;
  C: Char;
begin
  Result := (Trim(S) <> '') and (Length(S) <= 128);
  if not Result then
    Exit;
  for I := 1 to Length(S) do
  begin
    C := S[I];
    if (C = '\') or (C = '/') or (C = ':') or (C = '*') or (C = '?') or (C = '"') or
       (C = '<') or (C = '>') or (C = '|') then
      Exit(False);
  end;
  Result := Pos('..', S) = 0;
end;

function IsSafeAuditFileName(const S: string): Boolean;
begin
  Result := (Trim(S) <> '') and (Length(S) <= 255);
  if not Result then
    Exit;
  if (Pos('\', S) > 0) or (Pos('/', S) > 0) or (Pos('..', S) > 0) then
    Exit(False);
  Result := StartsText('fornecimento_full_', S) and EndsText('.json', LowerCase(S));
end;

function ResolveAuditFornecimentoFile(const DeviceId, FileName: string): string;
var
  LBase, LDir, LPath: string;
begin
  if not IsSafeAuditDeviceId(DeviceId) then
    raise Exception.Create('device_id invalido');
  if not IsSafeAuditFileName(FileName) then
    raise Exception.Create('nome de arquivo invalido');

  LBase := TPath.GetFullPath(ExcludeTrailingPathDelimiter(GetAuditFornecimentoBaseDir));
  LDir := TPath.GetFullPath(TPath.Combine(LBase, DeviceId));
  if not SameText(TPath.GetDirectoryName(LDir), LBase) then
    raise Exception.Create('caminho fora da pasta de auditoria');

  LPath := TPath.GetFullPath(TPath.Combine(LDir, FileName));
  if not SameText(TPath.GetDirectoryName(LPath), LDir) then
    raise Exception.Create('arquivo fora da pasta do device');
  if not TFile.Exists(LPath) then
    raise Exception.Create('arquivo nao encontrado');
  Result := LPath;
end;

procedure GetAuditFornecimentoPage(Req: THorseRequest; Res: THorseResponse; Next: TProc);
begin
  SendHtml('audit-fornecimento.html', Res);
end;

procedure GetAuditFornecimentoListApi(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LBase, LFilterDevice, LDeviceName, LFilePath: string;
  LRoot, LItem: TJSONObject;
  LAllFiles: TJSONArray;
  LFileObj: TJSONObject;
  LDeviceDirs, LFileNames: TArray<string>;
  I, J: Integer;
  LModified: TDateTime;
begin
  LRoot := TJSONObject.Create;
  try
    try
      LBase := GetAuditFornecimentoBaseDir;
      LRoot.AddPair('baseDir', LBase);
      LRoot.AddPair('envOverride', TJSONBool.Create(Trim(GetEnvironmentVariable('RFEED_AUDIT_DIR')) <> ''));
      LAllFiles := TJSONArray.Create;
      LRoot.AddPair('files', LAllFiles);

      LFilterDevice := Trim(Req.Query.Items['device']);
      if (LFilterDevice <> '') and (not IsSafeAuditDeviceId(LFilterDevice)) then
        raise Exception.Create('Filtro device invalido');

      if TDirectory.Exists(LBase) then
      begin
        if LFilterDevice <> '' then
          LDeviceDirs := [TPath.Combine(LBase, LFilterDevice)]
        else
          LDeviceDirs := TDirectory.GetDirectories(LBase);

        for I := 0 to Length(LDeviceDirs) - 1 do
        begin
          if not TDirectory.Exists(LDeviceDirs[I]) then
            Continue;

          LDeviceName := ExtractFileName(ExcludeTrailingPathDelimiter(LDeviceDirs[I]));
          if not IsSafeAuditDeviceId(LDeviceName) then
            Continue;

          LFileNames := TDirectory.GetFiles(LDeviceDirs[I], 'fornecimento_full_*.json');
          for J := 0 to Length(LFileNames) - 1 do
          begin
            LFilePath := LFileNames[J];
            LFileObj := TJSONObject.Create;
            LFileObj.AddPair('device_id', LDeviceName);
            LFileObj.AddPair('filename', ExtractFileName(LFilePath));
            LFileObj.AddPair('bytes', TJSONNumber.Create(TFile.GetSize(LFilePath)));
            LModified := TFile.GetLastWriteTime(LFilePath);
            LFileObj.AddPair('modified', FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', LModified));
            LFileObj.AddPair('saved_path', LFilePath);
            LAllFiles.AddElement(LFileObj);
          end;
        end;
      end;

      LRoot.AddPair('totalFiles', TJSONNumber.Create(LAllFiles.Count));
      Res.Send(LRoot.ToJSON).ContentType('application/json; charset=utf-8').Status(200);
    except
      on E: Exception do
      begin
        LItem := TJSONObject.Create;
        try
          LItem.AddPair('erro', E.Message);
          Res.Send(LItem.ToJSON).ContentType('application/json; charset=utf-8').Status(400);
        finally
          LItem.Free;
        end;
      end;
    end;
  finally
    LRoot.Free;
  end;
end;

procedure GetAuditFornecimentoFileApi(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LDevice, LName, LInline, LPath, LContent: string;
  LErr: TJSONObject;
begin
  try
    LDevice := Trim(Req.Query.Items['device']);
    LName := Trim(Req.Query.Items['name']);
    if LDevice = '' then
      LDevice := Trim(Req.Query.Items['device_id']);
    if LName = '' then
      LName := Trim(Req.Query.Items['filename']);

    LPath := ResolveAuditFornecimentoFile(LDevice, LName);
    LInline := LowerCase(Trim(Req.Query.Items['inline']));

    if (LInline = '1') or (LInline = 'true') or (LInline = 'yes') then
    begin
      LContent := TFile.ReadAllText(LPath, TEncoding.UTF8);
      Res.Send(LContent).ContentType('application/json; charset=utf-8').Status(200);
    end
    else
      Res.Download(LPath, 'application/json; charset=utf-8');
  except
    on E: Exception do
    begin
      LErr := TJSONObject.Create;
      LErr.AddPair('erro', E.Message);
      Res.Send(LErr.ToJSON).ContentType('application/json; charset=utf-8').Status(404);
    end;
  end;
end;

procedure RegistraRotasAdmin;
begin
  THorse.Get('/', GetRoot);
  THorse.Get('/config', GetConfigPage);
  THorse.Get('/health', GetHealthPage);
  THorse.Get('/requests', GetRequestsPage);
  THorse.Get('/monitor', GetMonitorPage);
  THorse.Get('/dashboard/fabricacao', GetDashboardFabricacaoPage);
  THorse.Get('/audit/fornecimento', GetAuditFornecimentoPage);
  THorse.Get('/audit', GetAuditFornecimentoPage);
  THorse.Get('/web-admin/request-monitor.js', GetRequestMonitorJs);
  THorse.Get('/web-admin/api-version.js', GetApiVersionJs);
  THorse.Get('/api/request-logs', GetRequestLogsApi);
  THorse.Delete('/api/request-logs', DeleteRequestLogsApi);
  THorse.Get('/api/audit/fornecimento', GetAuditFornecimentoListApi);
  THorse.Get('/api/audit/fornecimento/file', GetAuditFornecimentoFileApi);
  THorse.Get('/api/version', GetApiVersion);
  THorse.Get('/api/config', GetApiConfig);
  THorse.Post('/api/config', PostApiConfig);
  THorse.Post('/api/config/postgres', PostApiConfigPostgres);
  THorse.Post('/api/config/test', PostApiConfigTest);
end;

end.
