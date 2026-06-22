unit Controllers.Post;

interface
uses
  Horse,
  Horse.Jhonson,
  Horse.CORS,
  System.JSON,
  System.SysUtils,
  System.Classes, System.IOUtils, System.DateUtils, System.Hash,
  System.AnsiStrings,FireDAC.Comp.Client;

  procedure LimpaJSONObject(JSON: TJSONObject);
  procedure RegistraRotas;
  procedure PostFornecimento(Req: THorseRequest; Res: THorseResponse; Next: TProc);
  procedure PostGravaTag(Req: THorseRequest; Res: THorseResponse; Next: TProc);
  procedure PostFabricacao(Req: THorseRequest; Res: THorseResponse; Next: TProc);
  procedure PostFabricacaoInsumos(Req: THorseRequest; Res: THorseResponse; Next: TProc);
  procedure PostGpsTrack(Req: THorseRequest; Res: THorseResponse; Next: TProc);
  procedure PostFornecimentoAudit(Req: THorseRequest; Res: THorseResponse; Next: TProc);
  procedure PostFabricacaoAudit(Req: THorseRequest; Res: THorseResponse; Next: TProc);
  function VerificaCampoObrigatorio(const JSON: TJSONObject; const NomeCampo: string; out Valor: string): Boolean;
  procedure UploadLog(Req: THorseRequest; Res: THorseResponse; Next: TProc);
implementation

uses
  Udm,
  Controllers.Mirror;

function ExtractStrCI(const Obj: TJSONObject; const Keys: array of string): string; forward;

function ParseFlexNumber(const S: string): Double;
var
  T: string;
  FS: TFormatSettings;
begin
  T := Trim(S);
  if T = '' then
    Exit(0);
  FS := TFormatSettings.Create;
  if Pos(',', T) > 0 then
    FS.DecimalSeparator := ','
  else
    FS.DecimalSeparator := '.';
  if not TryStrToFloat(T, Result, FS) then
  begin
    T := StringReplace(T, ',', '.', [rfReplaceAll]);
    FS.DecimalSeparator := '.';
    Result := StrToFloatDef(T, 0, FS);
  end;
end;

function JsonFlexNumber(const Obj: TJSONObject; const Keys: array of string): Double;
begin
  Result := ParseFlexNumber(ExtractStrCI(Obj, Keys));
end;

function ParseFlexDate(const S: string; out Dt: TDateTime): Boolean;
var
  T, D, M, Y: string;
  FS: TFormatSettings;
  Yi, Mi, Di: Integer;
begin
  Result := False;
  Dt := 0;
  T := Trim(S);
  if T = '' then
    Exit;

  // dd/mm/yyyy (enviado pelo app Flutter)
  if (Length(T) >= 10) and (T[3] = '/') and (T[6] = '/') then
  begin
    D := Copy(T, 1, 2);
    M := Copy(T, 4, 2);
    Y := Copy(T, 7, 4);
    Yi := StrToIntDef(Y, 0);
    Mi := StrToIntDef(M, 0);
    Di := StrToIntDef(D, 0);
    if (Yi > 0) and (Mi in [1..12]) and (Di in [1..31]) then
    begin
      try
        Dt := EncodeDate(Yi, Mi, Di);
        Exit(True);
      except
      end;
    end;
  end;

  // yyyy-mm-dd (ISO)
  if (Length(T) >= 10) and (T[5] = '-') and (T[8] = '-') then
  begin
    Y := Copy(T, 1, 4);
    M := Copy(T, 6, 2);
    D := Copy(T, 9, 2);
    Yi := StrToIntDef(Y, 0);
    Mi := StrToIntDef(M, 0);
    Di := StrToIntDef(D, 0);
    if (Yi > 0) and (Mi in [1..12]) and (Di in [1..31]) then
    begin
      try
        Dt := EncodeDate(Yi, Mi, Di);
        Exit(True);
      except
      end;
    end;
  end;

  FS := TFormatSettings.Create;
  Result := TryStrToDate(T, Dt, FS);
end;

function NormalizeMsPercent(const Value: Double): Double;
begin
  Result := 0;
  if Value <= 0 then
    Exit;
  if Value > 100 then
    Exit;
  Result := Value;
end;

function TryFetchDietaMsCgPec(dm: TdmDB; const IdDieta: string): Double;
var
  Q: TFDQuery;
  Id: string;
begin
  Result := 0;
  Id := Trim(IdDieta);
  if Id = '' then
    Exit;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := dm.FBCon;
    Q.SQL.Text :=
      'SELECT FIRST 1 COALESCE(d.MS_DIETA, 0) AS M FROM CADASTRO_DIETAS d ' +
      'WHERE TRIM(CAST(d.ID AS VARCHAR(64))) = TRIM(:ID)';
    Q.ParamByName('ID').AsString := Id;
    Q.Open;

    if not Q.IsEmpty then
      Result := NormalizeMsPercent(Q.FieldByName('M').AsFloat);
  except
    Result := 0;
  end;
  Q.Free;
end;

function TryFetchFabricacaoMsBatida(dm: TdmDB; const IdFabricacao: string): Double;
var
  Q: TFDQuery;
  Id: string;
begin
  Result := 0;
  Id := Trim(IdFabricacao);
  if (Id = '') or (Id = '0') then
    Exit;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := dm.FBCon;
    Q.SQL.Text :=
      'SELECT FIRST 1 COALESCE(cfr.MS_BATIDA, 0) AS M ' +
      'FROM CADASTRO_FABRICA_RACAO cfr ' +
      'WHERE UPPER(TRIM(CAST(cfr.ID AS VARCHAR(64)))) = UPPER(TRIM(:ID))';
    Q.ParamByName('ID').AsString := Id;
    Q.Open;
    if not Q.IsEmpty then
      Result := NormalizeMsPercent(Q.FieldByName('M').AsFloat);
  except
    Result := 0;
  end;
  Q.Free;
end;

/// MS do fornecimento: MS_BATIDA da fabricação → MS_DIETA do cadastro (0 < MS <= 100).
function ResolveMsFornecimento(dm: TdmDB; const IdFabricacao, IdDieta: string): Double;
var
  IdFab, IdD: string;
begin
  Result := 0;

  IdFab := Trim(IdFabricacao);
  if (IdFab <> '') and (IdFab <> '0') then
    Result := TryFetchFabricacaoMsBatida(dm, IdFab);
  if Result > 0 then
    Exit;

  IdD := Trim(IdDieta);
  if (IdD <> '') and (IdD <> '0') then
    Result := TryFetchDietaMsCgPec(dm, IdD);
end;

function ResolveMsInsumoCgPec(dm: TdmDB; const IdInsumo, IdDieta: string): Double;
var
  Q: TFDQuery;
begin
  Result := 0;
  if (Trim(IdInsumo) = '') or (Trim(IdDieta) = '') then
    Exit;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := dm.FBCon;
    Q.SQL.Text :=
      'SELECT FIRST 1 MS_INSUMO FROM DETALHES_DIETAS ' +
      'WHERE UPPER(TRIM(CAST(ID_INSUMO AS VARCHAR(64)))) = UPPER(TRIM(:ID_INSUMO)) ' +
      '  AND UPPER(TRIM(CAST(ID_DIETA AS VARCHAR(64)))) = UPPER(TRIM(:ID_DIETA)) ' +
      '  AND COALESCE(MS_INSUMO, 0) > 0';
    Q.ParamByName('ID_INSUMO').AsString := IdInsumo;
    Q.ParamByName('ID_DIETA').AsString := IdDieta;
    Q.Open;
    if not Q.IsEmpty then
      Result := Q.FieldByName('MS_INSUMO').AsFloat;
  except
    Result := 0;
  end;
  Q.Free;
end;

function ResolveMsPercentFabricacao(dm: TdmDB; const IdDieta: string;
  MsFromBody, MsAlternate: Double): Double;
begin
  Result := MsFromBody;
  if Result <= 0 then
    Result := MsAlternate;
  if Result <= 0 then
    Result := TryFetchDietaMsCgPec(dm, IdDieta);
  if Result <= 0 then
    Result := 1;
end;

function CalcMsPrevistaFromDetalhes(dm: TdmDB; const IdFabricacao: string): Double;
var
  Q: TFDQuery;
begin
  Result := 0;
  if Trim(IdFabricacao) = '' then
    Exit;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := dm.FBCon;
    Q.SQL.Text :=
      'SELECT CASE ' +
      '  WHEN COALESCE(SUM(CAST(QTDE_PREVISTA AS DOUBLE PRECISION) * ' +
      '                CAST(MS_INSUMO AS DOUBLE PRECISION)), 0) > 0 THEN ' +
      '    COALESCE(( ' +
      '      SUM(CAST(QTDE_PREVISTA AS DECIMAL(18, 2)) * ' +
      '          (CAST(MS_INSUMO AS DOUBLE PRECISION) / 100)) / ' +
      '      NULLIF(SUM(CAST(QTDE_PREVISTA AS DOUBLE PRECISION)), 0) * 100 ' +
      '    ), 0) ' +
      '  ELSE 0 ' +
      'END AS M ' +
      'FROM DETALHES_FABRICA_RACAO ' +
      'WHERE ID_INSUMO IS NOT NULL ' +
      '  AND UPPER(TRIM(CAST(ID_CADASTRO_FABRICA_RACAO AS VARCHAR(64)))) = ' +
      '      UPPER(TRIM(:ID))';
    Q.ParamByName('ID').AsString := IdFabricacao;
    Q.Open;
    if (not Q.IsEmpty) and (Q.FieldByName('M').AsFloat > 0) then
      Result := Q.FieldByName('M').AsFloat;
  except
    Result := 0;
  end;
  Q.Free;
end;

function ResolveIdDietaFabricacao(dm: TdmDB; const IdFabricacao: string): string;
var
  Q: TFDQuery;
begin
  Result := '';
  if Trim(IdFabricacao) = '' then
    Exit;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := dm.FBCon;
    Q.SQL.Text :=
      'SELECT FIRST 1 ID_DIETA FROM CADASTRO_FABRICA_RACAO ' +
      'WHERE UPPER(TRIM(CAST(ID AS VARCHAR(64)))) = UPPER(TRIM(:ID))';
    Q.ParamByName('ID').AsString := IdFabricacao;
    Q.Open;
    if not Q.IsEmpty then
      Result := Trim(Q.FieldByName('ID_DIETA').AsString);
  except
    Result := '';
  end;
  Q.Free;
end;

procedure EnsureCgPecFabricacaoMsValores(dm: TdmDB; const IdFabricacao: string);
var
  Q: TFDQuery;
  QKg, QMsBatida, QMsPrev, MsCalc, MsPrevOrig, MsBatOrig: Double;
  IdDieta: string;
  PrecisaUpdate: Boolean;
begin
  if Trim(IdFabricacao) = '' then
    Exit;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := dm.FBCon;
    Q.SQL.Text :=
      'SELECT COALESCE(QTDE_REALIZADA, 0) AS Q, COALESCE(MS_BATIDA, 0) AS B, ' +
      '       COALESCE(MS_PREVISTA, 0) AS P, TRIM(CAST(ID_DIETA AS VARCHAR(64))) AS D ' +
      '  FROM CADASTRO_FABRICA_RACAO ' +
      ' WHERE UPPER(TRIM(CAST(ID AS VARCHAR(64)))) = UPPER(TRIM(:ID))';
    Q.ParamByName('ID').AsString := IdFabricacao;
    Q.Open;
    if Q.IsEmpty then
      Exit;

    QKg := Q.FieldByName('Q').AsFloat;
    MsBatOrig := Q.FieldByName('B').AsFloat;
    MsPrevOrig := Q.FieldByName('P').AsFloat;
    QMsBatida := MsBatOrig;
    QMsPrev := MsPrevOrig;
    IdDieta := Trim(Q.FieldByName('D').AsString);

    if QMsPrev <= 0 then
    begin
      MsCalc := CalcMsPrevistaFromDetalhes(dm, IdFabricacao);
      if MsCalc > 0 then
        QMsPrev := MsCalc;
    end;
    if QMsPrev <= 0 then
      QMsPrev := ResolveMsPercentFabricacao(dm, IdDieta, 0, QMsBatida);

    if (QKg > 0) and (QMsBatida <= 0) then
      QMsBatida := ResolveMsPercentFabricacao(dm, IdDieta, 0, QMsPrev);

    PrecisaUpdate := (MsPrevOrig <= 0) or ((QKg > 0) and (MsBatOrig <= 0));
    if not PrecisaUpdate then
      Exit;

    Q.Close;
    Q.SQL.Text :=
      'UPDATE CADASTRO_FABRICA_RACAO SET ' +
      '  MS_PREVISTA = :MS_PREV, ' +
      '  MS_BATIDA = CASE WHEN COALESCE(QTDE_REALIZADA, 0) > 0 THEN :MS_BAT ELSE MS_BATIDA END ' +
      ' WHERE UPPER(TRIM(CAST(ID AS VARCHAR(64)))) = UPPER(TRIM(:ID))';
    Q.ParamByName('MS_PREV').AsFloat := QMsPrev;
    Q.ParamByName('MS_BAT').AsFloat := QMsBatida;
    Q.ParamByName('ID').AsString := IdFabricacao;
    Q.ExecSQL;
  except
    // não derruba o POST por falha no fallback de MS
  end;
  Q.Free;
end;

procedure LimpaJSONObject(JSON: TJSONObject);
begin
  while JSON.Count > 0 do
    JSON.RemovePair(JSON.Pairs[0].JsonString.Value);
end;

procedure UploadLog(Req: THorseRequest; Res: THorseResponse; Next: TProc);
const
  MAX_SIZE_BYTES = 50 * 1024 * 1024; // 50 MB
var
  DeviceId, DateYMD, CT: string;
  SaveBase, SaveDir, SaveName, SavePath: string;
  SizeHdr: Int64;
  InS: TStream;
  BodyStr: string;
  BytesUtf8, EOL: TBytes;
  AppendedBytes: Int64;
  J: TJSONObject;

  function GetLogBaseDir: string;
  var
    Env: string;
  begin
    // 1) Override por variável de ambiente (configure no serviço): RFEED_LOG_DIR
    Env := GetEnvironmentVariable('RFEED_LOG_DIR');
    if Env <> '' then
      Exit(IncludeTrailingPathDelimiter(Env));

    // 2) Padrão: %PROGRAMDATA%\RFeed\logs
    // Obs: PROGRAMDATA normalmente é C:\ProgramData (gravação permitida)
    Result := TPath.Combine(GetEnvironmentVariable('PROGRAMDATA'), 'RFeed');
    Result := TPath.Combine(Result, 'logs');
    Result := IncludeTrailingPathDelimiter(Result);
  end;

  procedure EnsureDir(const P: string);
  begin
    if not TDirectory.Exists(P) then
    begin
      try
        ForceDirectories(P);
      except
        on E: Exception do
        begin
          raise Exception.CreateFmt('Não foi possível criar a pasta "%s". Erro: %s', [P, E.Message]);
        end;
      end;
    end;
  end;

  procedure AppendBytesToFileUtf8(const FileName: string; const Data: TBytes);
  var
    FS: TFileStream;
    NeedEOL: Boolean;
  begin
    // Abre para append; permite leitura por outros processos
    if TFile.Exists(FileName) then
      FS := TFileStream.Create(FileName, fmOpenReadWrite or fmShareDenyNone)
    else
      FS := TFileStream.Create(FileName, fmCreate or fmShareDenyNone);
    try
      FS.Seek(0, soEnd);

      // Se já existe conteúdo e o novo bloco não começa com EOL, escreva EOL antes (em UTF-8)
      NeedEOL := (FS.Size > 0) and (Length(Data) > 0);
      if NeedEOL then
      begin
        // Escreve CRLF em UTF-8
        EOL := TEncoding.UTF8.GetBytes(sLineBreak);
        FS.WriteBuffer(EOL[0], Length(EOL));
      end;

      if Length(Data) > 0 then
        FS.WriteBuffer(Data[0], Length(Data));
    finally
      FS.Free;
    end;
  end;

begin
  try
    // Identificação
    DeviceId := Trim(Req.Params.Items['device']);
    if DeviceId = '' then
      DeviceId := 'unknown';

    DateYMD := Req.Query.Items['date'];
    if DateYMD = '' then
      DateYMD := FormatDateTime('yyyymmdd', Date);

    // Limite por Content-Length (se presente)
    SizeHdr := StrToInt64Def(Req.Headers['content-length'], -1);
    if (MAX_SIZE_BYTES > 0) and (SizeHdr > MAX_SIZE_BYTES) then
    begin
      Res.Status(413).Send<TJSONObject>(TJSONObject.Create.AddPair('erro', 'arquivo muito grande'));
      Exit;
    end;

    // Content-Type: recusa binário/zip; queremos texto simples
    CT := LowerCase(Req.ContentType);
    if (Pos('zip', CT) > 0) or (Pos('octet-stream', CT) > 0) then
    begin
      Res.Status(415).Send<TJSONObject>(TJSONObject.Create.AddPair('erro', 'content-type binário não suportado'));
      Exit;
    end;

    // Base segura para serviço
    SaveBase := GetLogBaseDir;                        // %PROGRAMDATA%\RFeed\logs\  (ou override)
    SaveDir  := TPath.Combine(SaveBase, DateYMD);
    SaveDir  := TPath.Combine(SaveDir, DeviceId);
    EnsureDir(SaveDir);

    SaveName := 'fornecimento_' + DateYMD + '.txt';
    SavePath := TPath.Combine(SaveDir, SaveName);

    AppendedBytes := 0;

    // 1) Tenta corpo como stream (quando disponível)
    InS := Req.Body<TStream>;
    if (InS <> nil) and (InS.Size > 0) then
    begin
      InS.Position := 0;
      SetLength(BytesUtf8, InS.Size);
      InS.ReadBuffer(BytesUtf8[0], InS.Size);
      AppendBytesToFileUtf8(SavePath, BytesUtf8);
      AppendedBytes := Length(BytesUtf8);
    end
    else
    begin
      // 2) Fallback: corpo como texto (jsonl/linhas)
      BodyStr := Req.Body;
      if BodyStr = '' then
      begin
        Res.Status(400).Send<TJSONObject>(TJSONObject.Create.AddPair('erro', 'corpo vazio'));
        Exit;
      end;

      // Normaliza quebras de linha e garante UTF-8
      BodyStr := StringReplace(BodyStr, #13#10, #10, [rfReplaceAll]);
      BodyStr := StringReplace(BodyStr, #13,    #10, [rfReplaceAll]);
      BodyStr := StringReplace(BodyStr, #10, sLineBreak, [rfReplaceAll]);

      BytesUtf8 := TEncoding.UTF8.GetBytes(BodyStr);
      if (MAX_SIZE_BYTES > 0) and (Length(BytesUtf8) > MAX_SIZE_BYTES) then
      begin
        Res.Status(413).Send<TJSONObject>(TJSONObject.Create.AddPair('erro', 'arquivo muito grande'));
        Exit;
      end;

      AppendBytesToFileUtf8(SavePath, BytesUtf8);
      AppendedBytes := Length(BytesUtf8);
    end;

    // Resposta OK
    J := TJSONObject.Create;
    J.AddPair('ok', TJSONBool.Create(True));
    J.AddPair('device_id', DeviceId);
    J.AddPair('date', DateYMD);
    J.AddPair('filename', SaveName);
    J.AddPair('saved_path', SavePath);
    J.AddPair('appended_bytes', TJSONNumber.Create(AppendedBytes));
    Res.Status(200).Send<TJSONObject>(J);

  except
    on E: Exception do
      Res.Status(500).Send<TJSONObject>(
        TJSONObject.Create.AddPair('erro',
          Format('%s: %s (base=%s)',
                 [E.ClassName, E.Message, GetLogBaseDir]))
      );
  end;
end;


function ExtractSessionIdFromGpsBody(const Body: TJSONObject): string;
var
  S: TJSONObject;
begin
  Result := ExtractStrCI(Body, ['id', 'ID']);
  if Result <> '' then
    Exit;
  if Body.TryGetValue<TJSONObject>('session', S) and Assigned(S) then
    Result := ExtractStrCI(S, ['id', 'ID']);
end;

function CountGpsPointsInBody(const Body: TJSONObject): Integer;
var
  Arr: TJSONArray;
begin
  Result := 0;
  if not Assigned(Body) then
    Exit;
  if Body.TryGetValue<TJSONArray>('points', Arr) and Assigned(Arr) then
    Result := Arr.Count
  else if Body.TryGetValue<TJSONArray>('POINTS', Arr) and Assigned(Arr) then
    Result := Arr.Count;
end;

procedure PostGpsTrack(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  Body: TJSONObject;
  JSONResult: TJSONObject;
  SessionId: string;
  PointsCount: Integer;
begin
  Body := nil;
  JSONResult := nil;
  try
    Body := Req.Body<TJSONObject>;
    if not Assigned(Body) then
      raise Exception.Create('JSON invalido');

    SessionId := ExtractSessionIdFromGpsBody(Body);
    if SessionId = '' then
      raise Exception.Create('session.id obrigatorio');

    PointsCount := CountGpsPointsInBody(Body);

    JSONResult := TJSONObject.Create;
    JSONResult.AddPair('ok', TJSONBool.Create(True));
    JSONResult.AddPair('session_id', SessionId);
    JSONResult.AddPair('points_received', TJSONNumber.Create(PointsCount));
  except
    on E: Exception do
    begin
      if not Assigned(JSONResult) then
        JSONResult := TJSONObject.Create;
      JSONResult.AddPair('erro', E.Message);
      Res.Send(JSONResult).Status(400);
      Exit;
    end;
  end;

  Res.Send(JSONResult).Status(200);
  MirrorPostBody('/Post/GpsTrack', Body, JSONResult.ToJSON, 200);
end;

procedure PostFornecimentoAudit(Req: THorseRequest; Res: THorseResponse; Next: TProc);
const
  MAX_SIZE_BYTES = 50 * 1024 * 1024;
var
  Body: TJSONObject;
  JSONResult: TJSONObject;
  Registros: TJSONArray;
  DeviceId, SaveBase, SaveDir, SaveName, SavePath, JsonText: string;
  BytesUtf8: TBytes;
  Qtd: Integer;

  function GetAuditBaseDir: string;
  var
    Env: string;
  begin
    Env := GetEnvironmentVariable('RFEED_AUDIT_DIR');
    if Env <> '' then
      Exit(IncludeTrailingPathDelimiter(Env));

    Result := TPath.Combine(GetEnvironmentVariable('PROGRAMDATA'), 'RFeed');
    Result := TPath.Combine(Result, 'audit');
    Result := TPath.Combine(Result, 'fornecimento');
    Result := IncludeTrailingPathDelimiter(Result);
  end;

  procedure EnsureDir(const P: string);
  begin
    if not TDirectory.Exists(P) then
      ForceDirectories(P);
  end;

begin
  Body := nil;
  JSONResult := nil;
  try
    Body := Req.Body<TJSONObject>;
    if not Assigned(Body) then
      raise Exception.Create('JSON invalido ou corpo vazio');

    DeviceId := ExtractStrCI(Body, ['device_id', 'deviceId', 'DEVICE_ID']);
    if DeviceId = '' then
      DeviceId := Trim(Req.Params.Items['device']);
    if DeviceId = '' then
      DeviceId := 'tablet';

    if not Body.TryGetValue<TJSONArray>('registros', Registros) then
      Body.TryGetValue<TJSONArray>('REGISTROS', Registros);
    if not Assigned(Registros) then
      raise Exception.Create('Campo "registros" (array) obrigatorio');

    Qtd := Registros.Count;
    JsonText := Body.ToJSON;
    BytesUtf8 := TEncoding.UTF8.GetBytes(JsonText);
    if (MAX_SIZE_BYTES > 0) and (Length(BytesUtf8) > MAX_SIZE_BYTES) then
      raise Exception.Create('Payload maior que o limite de auditoria (50 MB)');

    SaveBase := GetAuditBaseDir;
    SaveDir := TPath.Combine(SaveBase, DeviceId);
    EnsureDir(SaveDir);

    SaveName := 'fornecimento_full_' + FormatDateTime('yyyymmdd_hhnnss', Now) + '.json';
    SavePath := TPath.Combine(SaveDir, SaveName);

    TFile.WriteAllBytes(SavePath, BytesUtf8);

    JSONResult := TJSONObject.Create;
    JSONResult.AddPair('ok', TJSONBool.Create(True));
    JSONResult.AddPair('device_id', DeviceId);
    JSONResult.AddPair('filename', SaveName);
    JSONResult.AddPair('saved_path', SavePath);
    JSONResult.AddPair('registros', TJSONNumber.Create(Qtd));
    JSONResult.AddPair('bytes', TJSONNumber.Create(Length(BytesUtf8)));
    Res.Send(JSONResult).Status(200);
  except
    on E: Exception do
    begin
      if not Assigned(JSONResult) then
        JSONResult := TJSONObject.Create;
      JSONResult.AddPair('erro', E.Message);
      Res.Send(JSONResult).Status(500);
    end;
  end;
end;

procedure PostFabricacaoAudit(Req: THorseRequest; Res: THorseResponse; Next: TProc);
const
  MAX_SIZE_BYTES = 50 * 1024 * 1024;
var
  Body: TJSONObject;
  JSONResult: TJSONObject;
  Registros: TJSONArray;
  DeviceId, SaveBase, SaveDir, SaveName, SavePath, JsonText: string;
  BytesUtf8: TBytes;
  Qtd: Integer;

  function GetAuditBaseDir: string;
  var
    Env: string;
  begin
    Env := GetEnvironmentVariable('RFEED_AUDIT_DIR');
    if Env <> '' then
      Exit(IncludeTrailingPathDelimiter(Env));

    Result := TPath.Combine(GetEnvironmentVariable('PROGRAMDATA'), 'RFeed');
    Result := TPath.Combine(Result, 'audit');
    Result := TPath.Combine(Result, 'fabricacao');
    Result := IncludeTrailingPathDelimiter(Result);
  end;

  procedure EnsureDir(const P: string);
  begin
    if not TDirectory.Exists(P) then
      ForceDirectories(P);
  end;

begin
  Body := nil;
  JSONResult := nil;
  try
    Body := Req.Body<TJSONObject>;
    if not Assigned(Body) then
      raise Exception.Create('JSON invalido ou corpo vazio');

    DeviceId := ExtractStrCI(Body, ['device_id', 'deviceId', 'DEVICE_ID']);
    if DeviceId = '' then
      DeviceId := Trim(Req.Params.Items['device']);
    if DeviceId = '' then
      DeviceId := 'tablet';

    if not Body.TryGetValue<TJSONArray>('registros', Registros) then
      Body.TryGetValue<TJSONArray>('REGISTROS', Registros);
    if not Assigned(Registros) then
      raise Exception.Create('Campo "registros" (array) obrigatorio');

    Qtd := Registros.Count;
    JsonText := Body.ToJSON;
    BytesUtf8 := TEncoding.UTF8.GetBytes(JsonText);
    if (MAX_SIZE_BYTES > 0) and (Length(BytesUtf8) > MAX_SIZE_BYTES) then
      raise Exception.Create('Payload maior que o limite de auditoria (50 MB)');

    SaveBase := GetAuditBaseDir;
    SaveDir := TPath.Combine(SaveBase, DeviceId);
    EnsureDir(SaveDir);

    SaveName := 'fabricacao_full_' + FormatDateTime('yyyymmdd_hhnnss', Now) + '.json';
    SavePath := TPath.Combine(SaveDir, SaveName);

    TFile.WriteAllBytes(SavePath, BytesUtf8);

    JSONResult := TJSONObject.Create;
    JSONResult.AddPair('ok', TJSONBool.Create(True));
    JSONResult.AddPair('device_id', DeviceId);
    JSONResult.AddPair('filename', SaveName);
    JSONResult.AddPair('saved_path', SavePath);
    JSONResult.AddPair('registros', TJSONNumber.Create(Qtd));
    JSONResult.AddPair('bytes', TJSONNumber.Create(Length(BytesUtf8)));
    Res.Send(JSONResult).Status(200);
  except
    on E: Exception do
    begin
      if not Assigned(JSONResult) then
        JSONResult := TJSONObject.Create;
      JSONResult.AddPair('erro', E.Message);
      Res.Send(JSONResult).Status(500);
    end;
  end;
end;

procedure RegistraRotas;
begin
  THorse.Post('/Post/Fornecimento',PostFornecimento);
  THorse.Post('/Post/Fabricacao',PostFabricacao);
  THorse.Post('/Post/Fabricacao_Insumo',PostFabricacaoInsumos);
  THorse.Put('/logs/upload/:device', UploadLog);
  THorse.Post('/Post/GravaTag', PostGravaTag);
  THorse.Post('/Post/GpsTrack', PostGpsTrack);
  THorse.Post('/Post/FornecimentoAudit', PostFornecimentoAudit);
  THorse.Post('/Post/FabricacaoAudit', PostFabricacaoAudit);
end;

function NormalizeEPC(const S: string): string;
var
  R: string;
begin
  R := Trim(S);
  if (R <> '') and (R[1] = ';') then
    Delete(R, 1, 1);
  if SameText(Copy(R, 1, 4), 'EPC:') then
    Delete(R, 1, 4);
  R := StringReplace(R, ' ', '', [rfReplaceAll]);
  Result := UpperCase(R);
end;

function ExtractStr(const Obj: TJSONObject; const A: array of string): string;
var
  k: string;
begin
  Result := '';
  for k in A do
    if not Obj.TryGetValue<string>(k, Result) then
      Result := '';
    if Result <> '' then Exit;
end;

procedure UpdateRFID(dm: Tdmdb; const IdBaia, EPC: string; var Rows: Integer);
var
  Q: TFDQuery;
  vErro:string;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := dm.FBCon;
    Q.SQL.Text := 'UPDATE DETALHES_BAIAS SET RFID = '''' WHERE RFID = :RFID';
    Q.ParamByName('RFID').AsString := EPC;
    Q.ExecSQL;

    Q.Connection := dm.FBCon;
    Q.SQL.Text := 'UPDATE DETALHES_BAIAS SET RFID = :RFID WHERE ID = :ID';
    Q.ParamByName('RFID').AsString := EPC;
    Q.ParamByName('ID').AsString   := IdBaia;
    Q.ExecSQL;
    Rows := Q.RowsAffected;
    Q.Free;
  except
    on E: Exception do
     vErro := e.Message;
  end;
end;

function ExtractStrCI(const Obj: TJSONObject; const Keys: array of string): string;
var
  Pair: TJSONPair;
  k: string;
begin
  Result := '';
  for k in Keys do
    for Pair in Obj do
      if SameText(Pair.JsonString.Value, k) then
      begin
        // pega o valor como string (funciona para string/number/bool)
        Result := Pair.JsonValue.Value;
        Exit;
      end;
end;

procedure ProcessOne(dm: Tdmdb; const Obj: TJSONObject; ArrResult: TJSONArray);
var
  vId, vEpc, err: string;
  rows: Integer;
  o: TJSONObject;
begin
  // pega id (id_baia ou id)
  vId  := ExtractStrCI(Obj, ['ID_PASTO_CURRAL', 'id_baia', 'id']);
  // pega tag (rfid, tag, epc)
  vEpc := ExtractStrCI(Obj, ['TAG', 'rfid', 'epc', 'tag']);

  o := TJSONObject.Create;
  try
    if vId = '' then
      err := 'Campo id/id_baia ausente'
    else if vEpc = '' then
      err := 'Campo rfid/tag/epc ausente'
    else
      vEpc := NormalizeEPC(vEpc);

    if err = '' then
    begin
      rows := 0;
      UpdateRFID(dm, vId, vEpc, rows);
      o.AddPair('id', vId);
      o.AddPair('rfid', vEpc);
      o.AddPair('updated', TJSONNumber.Create(rows));
      if rows = 0 then
        o.AddPair('warn', 'ID não encontrado ou sem alteração');
    end
    else
    begin
      o.AddPair('error', err);
      if vId <> '' then o.AddPair('id', vId);
    end;

    ArrResult.AddElement(o); // transfere propriedade
  except
    o.Free;
    raise;
  end;
end;

procedure PostGravaTag(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  dmGlobal: Tdmdb;
  Body: TJSONObject;
  JSONResult: TJSONObject;
  Q: TFDQuery;
  vIdBaia, vTag: string;

  function NormalizeEPC(const S: string): string;
  var
    R: string;
  begin
    R := Trim(S);
    if (R <> '') and (R[1] = ';') then
      Delete(R, 1, 1);
    if SameText(Copy(R, 1, 4), 'EPC:') then
      Delete(R, 1, 4);
    R := StringReplace(R, ' ', '', [rfReplaceAll]);
    Result := UpperCase(R);
  end;

begin
  dmGlobal := nil;
  Body := nil;
  JSONResult := nil;
  Q := nil;

  try
    dmGlobal := Tdmdb.Create(nil);
    dmGlobal.ConectaDBCGPec;

    JSONResult := TJSONObject.Create;
    Body := Req.Body<TJSONObject>;
    if not Assigned(Body) then
      raise Exception.Create('JSON inválido ou corpo vazio');

    // lê campos do JSON no padrão solicitado
    Body.TryGetValue<string>('ID_PASTO_CURRAL', vIdBaia);
    Body.TryGetValue<string>('TAG', vTag);

    if (vIdBaia.Trim = '') then
      raise Exception.Create('ID_PASTO_CURRAL ausente');
    if (vTag.Trim = '') then
      raise Exception.Create('TAG ausente');

    vTag := NormalizeEPC(vTag);

    // UPDATE simples na tabela
    Q := TFDQuery.Create(nil);
    Q.Connection := dmGlobal.FBCon;

    Q.SQL.Text := 'UPDATE DETALHES_BAIAS SET RFID = NULL WHERE RFID = :RFID';
    Q.ParamByName('RFID').AsString := vTag;
    Q.ExecSQL;


    Q.SQL.Text := 'UPDATE DETALHES_BAIAS SET RFID = :RFID WHERE ID = :ID';
    Q.ParamByName('RFID').AsString := vTag;
    Q.ParamByName('ID').AsString   := vIdBaia;
    Q.ExecSQL;

    // resposta no mesmo padrão dos outros métodos
    JSONResult.AddPair('id', vIdBaia);
    JSONResult.AddPair('tag', vTag);
    JSONResult.AddPair('updated', TJSONNumber.Create(Q.RowsAffected));
    Res.Send(JSONResult).Status(200);
    MirrorPostBody('/Post/GravaTag', Body, JSONResult.ToJSON, 200);

  except
    on E: Exception do
    begin
      if not Assigned(JSONResult) then
        JSONResult := TJSONObject.Create;

      JSONResult.AddPair('erro', 'Erro: ' + E.ClassName + ' - ' + E.Message);
      Res.Send(JSONResult).Status(500);
    end;
  end;

  Q.Free;
  // Body é gerenciado pelo Horse
  dmGlobal.Free;
end;


function VerificaCampoObrigatorio(const JSON: TJSONObject; const NomeCampo: string; out Valor: string): Boolean;
begin
  Result := JSON.TryGetValue<string>(NomeCampo, Valor) and (Valor.Trim <> '');
end;

//procedure PostFornecimento(Req: THorseRequest; Res: THorseResponse; Next: TProc);
//var
//  dmGlobal: Tdmdb;
//  Body: TJSONObject;
//  JSONResult: TJSONObject;
//  vMaxId, vIdFabricacao, vIdUsuario, vIdTratador, vIdDieta, vRealizado, vMS: string;
//begin
//  dmGlobal := nil;
//  Body := nil;
//  JSONResult := nil;
//
//  try
//    dmGlobal := Tdmdb.Create(nil);
//    dmGlobal.ConectaDBCGPec;
//
//    JSONResult := TJSONObject.Create;
//    Body := Req.Body<TJSONObject>;
//    if not Assigned(Body) then
//      raise Exception.Create('JSON inválido ou corpo vazio');
//
//    if  Body.TryGetValue<string>('id', vMaxId) or (vMaxId.Trim = '') then
//    begin
//      Body.TryGetValue<string>('id_fabricacao', vIdFabricacao);
//      Body.TryGetValue<string>('id_usuario_lancamento', vIdUsuario);
//      Body.TryGetValue<string>('id_tratador', vIdTratador);
//      Body.TryGetValue<string>('id_dieta_realizada', vIdDieta);
//      Body.TryGetValue<string>('realizado', vRealizado);
//      Body.TryGetValue<string>('ms_dieta_realizada', vMS);
//
//      // Defaults
//      if vIdFabricacao = '' then vIdFabricacao := '0';
//      if vIdUsuario = '' then vIdUsuario := '0';
//      if vIdTratador = '' then vIdTratador := '0';
//      if vIdDieta = '' then vIdDieta := '0';
//      if vRealizado = '' then vRealizado := '0';
//      if vMS = '' then vMS := '0';
//
//      dmGlobal.ConectaDBCGPec;
//      dmGlobal.Fornecimento.Connection := dmGlobal.FBCon;
//
//      with dmGlobal.Fornecimento do
//      begin
//        Close;
//        SQL.Text := 'SELECT * FROM CADASTRO_FORNECIMENTO WHERE ID = :ID';
//        ParamByName('ID').AsString := vMaxId;
//        Open;
//
//        if NOT IsEmpty then
//        BEGIN
//          Edit;
//          FieldByName('ID_FABRICACAO').AsString         := vIdFabricacao;
//          FieldByName('ID_USUARIO_LANCAMENTO').AsString := vIdUsuario;
//          FieldByName('ID_TRATADOR').AsString           := vIdTratador;
//          FieldByName('ID_DIETA_REALIZADA').AsString    := vIdDieta;
//          FieldByName('REALIZADO').AsFloat              := StrToFloatDef(vRealizado, 0);
//          FieldByName('MS_DIETA_REALIZADA').AsFloat     := StrToFloatDef(vMS, 0);
//          FieldByName('STATUS').AsString                := 'R';
//          Post;
//          ApplyUpdates;
//        END;
//      end;
//    end;
//    JSONResult.AddPair('id', vMaxId);
//    Res.Send(JSONResult).Status(200);
//
//  except
//    on E: Exception do
//    begin
//      if not Assigned(JSONResult) then
//        JSONResult := TJSONObject.Create;
//
//      JSONResult.AddPair('erro', 'Erro: ' + E.ClassName + ' - ' + E.Message);
//      Res.Send(JSONResult).Status(500);
//    end;
//  end;
//end;

function GetSyncDedupBaseDir: string;
var
  Env: string;
begin
  Env := GetEnvironmentVariable('RFEED_LOG_DIR');
  if Env <> '' then
    Result := TPath.Combine(IncludeTrailingPathDelimiter(Env), 'sync-dedup')
  else
    Result := TPath.Combine(
      TPath.Combine(GetEnvironmentVariable('PROGRAMDATA'), 'RFeed'),
      'sync-dedup');
  Result := IncludeTrailingPathDelimiter(Result);
end;

function FornecimentoCadastroJaProcessado(const IdCadastro: string): Boolean;
var
  P: string;
begin
  Result := False;
  if Trim(IdCadastro) = '' then
    Exit;
  P := TPath.Combine(
    TPath.Combine(GetSyncDedupBaseDir, 'fornecimento'),
    THashSHA2.GetHashString(Trim(IdCadastro)) + '.ok');
  Result := TFile.Exists(P);
end;

procedure MarcarFornecimentoCadastroProcessado(const IdCadastro: string);
var
  Dir, P: string;
begin
  if Trim(IdCadastro) = '' then
    Exit;
  Dir := TPath.Combine(GetSyncDedupBaseDir, 'fornecimento');
  if not TDirectory.Exists(Dir) then
    ForceDirectories(Dir);
  P := TPath.Combine(Dir, THashSHA2.GetHashString(Trim(IdCadastro)) + '.ok');
  TFile.WriteAllText(P, FormatDateTime('yyyy-mm-dd hh:nn:ss', Now), TEncoding.UTF8);
end;

procedure PostFornecimento(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  dmGlobal: Tdmdb;
  Body: TJSONObject;
  JSONResult: TJSONObject;

  vId: string;
  vIdCadastro: string;
  vIdFabricacao, vIdUsuario, vIdTratador, vIdDietaRealizada, vRealizado, vMS: string;
  vMsFornec, vRealizadoNum, vRealizadoAtual, vRealizadoGravar: Double;
  vIdDietaMs: string;
  vFornecimentoAcumulativo: Boolean;
  vPontoCorteKg: Double;

  // chave natural
  vIdBaia, vIdRacaoPrev, vTratoStr, vDataISO: string;
  vTrato: Integer;
  vData: TDateTime;
  vEncontrou: Boolean;
  vIdFallback: string;

  function GetStr(const K: string; const Def: string = ''): string;
  begin
    if not Body.TryGetValue<string>(K, Result) then
      Result := Def;
    Result := Result.Trim;
    if Result = '' then Result := Def;
  end;

begin
  dmGlobal := nil;
  Body := nil;
  JSONResult := nil;

  try
    Body := Req.Body<TJSONObject>;
    if not Assigned(Body) then
      raise Exception.Create('JSON inválido ou corpo vazio');

    dmGlobal := Tdmdb.Create(nil);
    try
      dmGlobal.ConectaDBCGPec;

      JSONResult := TJSONObject.Create;

      vId := GetStr('id', '');
      if vId = '' then
        vId := GetStr('id_fornecimento', '');

      vIdFabricacao := GetStr('id_fabricacao', '0');
      vIdUsuario := GetStr('id_usuario_lancamento', '0');
      vIdTratador := GetStr('id_tratador', '0');
      vIdDietaRealizada := GetStr('id_dieta_realizada', '0');
      vRealizado := GetStr('realizado', '0');
      vMS := GetStr('ms_dieta_realizada', '0');

      vIdBaia := GetStr('id_baia', '');
      if vIdBaia = '' then
        vIdBaia := GetStr('IDCURRAL', '');
      vIdRacaoPrev := GetStr('id_racao', '');
      if vIdRacaoPrev = '' then
        vIdRacaoPrev := GetStr('id_dieta_prevista', '');
      vTratoStr := GetStr('trato', '');
      if vTratoStr = '' then
        vTratoStr := GetStr('TRATO', '0');
      vDataISO := GetStr('data', '');
      if vDataISO = '' then
        vDataISO := GetStr('DATA_FORN', '');

      vTrato := StrToIntDef(vTratoStr, 0);
      if not ParseFlexDate(vDataISO, vData) then
        vData := 0;

      if (Trim(vIdRacaoPrev) = '') or (Trim(vIdRacaoPrev) = '0') then
      begin
        if (Trim(vIdDietaRealizada) <> '') and (Trim(vIdDietaRealizada) <> '0') then
          vIdRacaoPrev := Trim(vIdDietaRealizada);
      end;

      vRealizadoNum := ParseFlexNumber(vRealizado);
      vFornecimentoAcumulativo := dmGlobal.GetFornecimentoAcumulativo;
      vPontoCorteKg := dmGlobal.GetPontoCorteFornecimentoKg;
      vIdCadastro := GetStr('id_cadastro', '');
      vIdDietaMs := vIdDietaRealizada;
      if (Trim(vIdDietaMs) = '') or (Trim(vIdDietaMs) = '0') then
        vIdDietaMs := vIdRacaoPrev;
      vMsFornec := 0;

      if vIdCadastro <> '' then
      begin
        if FornecimentoCadastroJaProcessado(vIdCadastro) then
        begin
          if vId <> '' then
            JSONResult.AddPair('id', vId);
          JSONResult.AddPair('ok', TJSONBool.Create(True));
          JSONResult.AddPair('modo', 'dedup_id_cadastro');
          JSONResult.AddPair('id_cadastro', vIdCadastro);
          JSONResult.AddPair('fornecimento_acumulativo', TJSONBool.Create(vFornecimentoAcumulativo));
          Res.Send(JSONResult).Status(200);
          MirrorPostBody('/Post/Fornecimento', Body, JSONResult.ToJSON, 200);
          Exit;
        end;
      end;

      // Abaixo do ponto de corte: nao grava no CG Pec, mas confirma sync (HTTP 200).
      if (vPontoCorteKg > 0) and (vRealizadoNum <= vPontoCorteKg) then
      begin
        if vId <> '' then
          JSONResult.AddPair('id', vId);
        JSONResult.AddPair('ok', TJSONBool.Create(True));
        JSONResult.AddPair('ignorado_ponto_corte', TJSONBool.Create(True));
        JSONResult.AddPair('ponto_corte_kg', TJSONNumber.Create(vPontoCorteKg));
        JSONResult.AddPair('realizado_recebido', TJSONNumber.Create(vRealizadoNum));
        JSONResult.AddPair('modo', 'ignorado_ponto_corte');
        Res.Send(JSONResult).Status(200);
        MirrorPostBody('/Post/Fornecimento', Body, JSONResult.ToJSON, 200);
        Exit;
      end;

      vMsFornec := ResolveMsFornecimento(dmGlobal, vIdFabricacao, vIdDietaMs);
      if vMsFornec <= 0 then
        raise Exception.Create(
          'MS dieta realizada invalida (deve ser > 0 e <= 100). ' +
          'Verifique MS_BATIDA da fabricacao ou MS_DIETA no cadastro.');

      dmGlobal.Fornecimento.Connection := dmGlobal.FBCon;
      vIdFallback := vId;
      vEncontrou := False;

      // 1) Prioridade: chave natural (baia + trato + data + id_dieta)
      if (vIdBaia <> '') and (vIdRacaoPrev <> '') and (vIdRacaoPrev <> '0')
         and (vTrato > 0) and (vData <> 0) then
      begin
        with dmGlobal.qryAux do
        begin
          Close;
          SQL.Clear;
          SQL.Add('UPDATE CADASTRO_FORNECIMENTO');
          SQL.Add('SET');
          SQL.Add('  ID_FABRICACAO = :ID_FAB,');
          SQL.Add('  ID_USUARIO_LANCAMENTO = :ID_USU,');
          SQL.Add('  ID_TRATADOR = :ID_TRAT,');
          SQL.Add('  ID_DIETA_REALIZADA = :ID_DIETA_R,');
          if vFornecimentoAcumulativo then
            SQL.Add('  REALIZADO = COALESCE(REALIZADO, 0) + :REAL,')
          else
            SQL.Add('  REALIZADO = :REAL,');
          SQL.Add('  MS_DIETA_REALIZADA = :MS,');
          SQL.Add('  STATUS = ''R''');
          SQL.Add('WHERE');
          SQL.Add('  ID_BAIA = :ID_BAIA');
          SQL.Add('  AND TRATO = :TRATO');
          SQL.Add('  AND DATA = :DATA');
          SQL.Add('  AND ID_DIETA = :ID_RACAO');
          SQL.Add('RETURNING ID');

          ParamByName('ID_FAB').AsString := vIdFabricacao;
          ParamByName('ID_USU').AsString := vIdUsuario;
          ParamByName('ID_TRAT').AsString := vIdTratador;
          ParamByName('ID_DIETA_R').AsString := vIdDietaRealizada;
          ParamByName('REAL').AsFloat := vRealizadoNum;
          ParamByName('MS').AsFloat := vMsFornec;
          ParamByName('ID_BAIA').AsString := vIdBaia;
          ParamByName('TRATO').AsInteger := vTrato;
          ParamByName('DATA').AsDate := vData;
          ParamByName('ID_RACAO').AsString := vIdRacaoPrev;

          Open;

          if not IsEmpty then
          begin
            vId := FieldByName('ID').AsString;
            vEncontrou := True;
          end;
          Close;
        end;

        if vEncontrou then
        begin
          if vIdCadastro <> '' then
            MarcarFornecimentoCadastroProcessado(vIdCadastro);
          JSONResult.AddPair('id', vId);
          JSONResult.AddPair('modo', 'update_por_chave_natural');
          JSONResult.AddPair('fornecimento_acumulativo', TJSONBool.Create(vFornecimentoAcumulativo));
          Res.Send(JSONResult).Status(200);
          MirrorPostBody('/Post/Fornecimento', Body, JSONResult.ToJSON, 200);
          Exit;
        end;
      end;

      // 2) Fallback: ID da previsao (ultimo caso)
      vId := vIdFallback;
      if vId <> '' then
      begin
        with dmGlobal.Fornecimento do
        begin
          Close;
          SQL.Text := 'SELECT * FROM CADASTRO_FORNECIMENTO WHERE ID = :ID';
          ParamByName('ID').AsString := vId;
          Open;

          if IsEmpty then
            raise Exception.Create(
              'Registro nao encontrado por chave natural nem pelo ID: ' + vId);

          vRealizadoAtual := ParseFlexNumber(FieldByName('REALIZADO').AsString);
          if vFornecimentoAcumulativo then
            vRealizadoGravar := vRealizadoAtual + vRealizadoNum
          else
            vRealizadoGravar := vRealizadoNum;

          Edit;
          FieldByName('ID_FABRICACAO').AsString := vIdFabricacao;
          FieldByName('ID_USUARIO_LANCAMENTO').AsString := vIdUsuario;
          FieldByName('ID_TRATADOR').AsString := vIdTratador;
          FieldByName('ID_DIETA_REALIZADA').AsString := vIdDietaRealizada;
          FieldByName('REALIZADO').AsFloat := vRealizadoGravar;
          FieldByName('MS_DIETA_REALIZADA').AsFloat := vMsFornec;
          FieldByName('STATUS').AsString := 'R';
          Post;
          ApplyUpdates;
        end;

        if vIdCadastro <> '' then
          MarcarFornecimentoCadastroProcessado(vIdCadastro);

        JSONResult.AddPair('id', vId);
        JSONResult.AddPair('modo', 'update_por_id');
        JSONResult.AddPair('fornecimento_acumulativo', TJSONBool.Create(vFornecimentoAcumulativo));
        JSONResult.AddPair('realizado_gravado', TJSONNumber.Create(vRealizadoGravar));
        Res.Send(JSONResult).Status(200);
        MirrorPostBody('/Post/Fornecimento', Body, JSONResult.ToJSON, 200);
        Exit;
      end;

      if (vIdBaia = '') or (vIdRacaoPrev = '') or (vTrato <= 0) or (vData = 0) then
        raise Exception.Create('Chave natural incompleta e ID ausente. Envie: id_baia, id_racao, trato, data (ou id).');

      raise Exception.Create('Nenhum registro encontrado para (baia+dieta+trato+data).');
    finally
      FreeAndNil(dmGlobal);
    end;

  except
    on E: Exception do
    begin
      if not Assigned(JSONResult) then
        JSONResult := TJSONObject.Create;

      JSONResult.AddPair('erro', 'Erro: ' + E.ClassName + ' - ' + E.Message);
      Res.Send(JSONResult).Status(500);
    end;
  end;
end;



procedure PostFabricacaoInsumos(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  dmGlobal: TdmDB;
  Body: TJSONObject;
  JSONRetorno: TJSONObject;
  ItensArray: TJSONArray;
  Item: TJSONObject;
  i: Integer;
  vValorkgFloat, vKGPrevista, vKGRealizado, vMsInsumo: Double;
  vMaxId, vTempStr, vIdInsumo, vIdFazenda, vIdFabricacao, vIdDieta, vIdOperador: string;
  vProcessados, vIgnorados, vMsFallback: Integer;
  vExiste: Boolean;
begin
  dmGlobal := TdmDB.Create(nil);
  Body := nil;
  JSONRetorno := nil;
  vIdFabricacao := '';
  vProcessados := 0;
  vIgnorados := 0;
  vMsFallback := 0;

  try
    dmGlobal.ConectaDBCGPec;
    Body := Req.Body<TJSONObject>;
    if not Assigned(Body) then
      raise Exception.Create('JSON inválido ou vazio');

    ItensArray := Body.GetValue('itens') as TJSONArray;
    if not Assigned(ItensArray) or (ItensArray.Count = 0) then
      raise Exception.Create('Campo "itens" inválido ou vazio');

    for i := 0 to ItensArray.Count - 1 do
    begin
      Item := ItensArray.Items[i] as TJSONObject;

      vMaxId := Trim(ExtractStrCI(Item, ['id']));
      vIdFabricacao := Trim(ExtractStrCI(Item, ['id_fabricacao']));
      vIdInsumo := Trim(ExtractStrCI(Item, ['id_insumo', 'id_alimento']));
      vIdFazenda := Trim(ExtractStrCI(Item, ['id_fazenda']));
      vIdOperador := Trim(ExtractStrCI(Item, ['id_operador']));

      if vMaxId = '' then
        raise Exception.Create('Campo obrigatório "id" não informado');
      if vIdFabricacao = '' then
        raise Exception.Create('Campo obrigatório "id_fabricacao" não informado');
      if vIdInsumo = '' then
        raise Exception.Create('Campo obrigatório "id_insumo" não informado');

      vKGPrevista := JsonFlexNumber(Item, ['qtde_prevista', 'kg_previsto', 'dbt_qtdeprevista']);
      if vKGPrevista <= 0 then
      begin
        Inc(vIgnorados);
        Continue;
      end;

      vKGRealizado := JsonFlexNumber(Item, ['qtd_realizada', 'qtde_realizada', 'kg_fabricado']);
      vMsInsumo := JsonFlexNumber(Item, ['ms_insumo']);

      vIdDieta := Trim(ExtractStrCI(Item, ['id_dieta']));
      if vIdDieta = '' then
        vIdDieta := ResolveIdDietaFabricacao(dmGlobal, vIdFabricacao);

      if (vMsInsumo <= 0) and (vIdDieta <> '') then
      begin
        vMsInsumo := ResolveMsInsumoCgPec(dmGlobal, vIdInsumo, vIdDieta);
        if vMsInsumo > 0 then
          Inc(vMsFallback);
      end;
      if vMsInsumo <= 0 then
        vMsInsumo := ResolveMsPercentFabricacao(dmGlobal, vIdDieta, 0, 0);

      vValorkgFloat := dmGlobal.GetCustoMedioKgInsumo(
        vIdInsumo,
        vIdFazenda,
        FormatDateTime('yyyy-mm-dd', Now)
      );

      with dmGlobal.qryAux do
      begin
        Close;
        SQL.Text :=
          'SELECT ID FROM DETALHES_FABRICA_RACAO ' +
          'WHERE UPPER(TRIM(CAST(ID AS VARCHAR(64)))) = UPPER(TRIM(:ID))';
        ParamByName('ID').AsString := vMaxId;
        Open;
        vExiste := not IsEmpty;
        Close;

        if vExiste then
        begin
          SQL.Text :=
            'UPDATE DETALHES_FABRICA_RACAO SET ' +
            '  ID_CADASTRO_FABRICA_RACAO = :ID_FAB, ' +
            '  ID_INSUMO = :ID_INSUMO, ' +
            '  QTDE_PREVISTA = :QTDE_PREVISTA, ' +
            '  QTDE_REALIZADA = :QTDE_REALIZADA, ' +
            '  ID_OPERADOR = :ID_OPERADOR, ' +
            '  MS_INSUMO = :MS_INSUMO, ' +
            '  CUSTO_KG = :CUSTO_KG ' +
            'WHERE UPPER(TRIM(CAST(ID AS VARCHAR(64)))) = UPPER(TRIM(:ID))';
        end
        else
        begin
          SQL.Text :=
            'INSERT INTO DETALHES_FABRICA_RACAO (' +
            '  ID, ID_CADASTRO_FABRICA_RACAO, ID_INSUMO, ' +
            '  QTDE_PREVISTA, QTDE_REALIZADA, ID_OPERADOR, MS_INSUMO, CUSTO_KG' +
            ') VALUES (' +
            '  :ID, :ID_FAB, :ID_INSUMO, ' +
            '  :QTDE_PREVISTA, :QTDE_REALIZADA, :ID_OPERADOR, :MS_INSUMO, :CUSTO_KG' +
            ')';
        end;

        ParamByName('ID').AsString := vMaxId;
        ParamByName('ID_FAB').AsString := vIdFabricacao;
        ParamByName('ID_INSUMO').AsString := vIdInsumo;
        ParamByName('QTDE_PREVISTA').AsFloat := vKGPrevista;
        ParamByName('QTDE_REALIZADA').AsFloat := vKGRealizado;
        ParamByName('ID_OPERADOR').AsString := vIdOperador;
        ParamByName('MS_INSUMO').AsFloat := vMsInsumo;
        ParamByName('CUSTO_KG').AsFloat := vValorkgFloat;
        ExecSQL;
      end;

      Inc(vProcessados);
    end;

    if vProcessados = 0 then
      raise Exception.Create(
        'Nenhum item válido para gravar (todos com qtde_prevista <= 0 ou inválidos).'
      );

    if vIdFabricacao <> '' then
    begin
      dmGlobal.AtualizaResumoFabricacao(vIdFabricacao);
      EnsureCgPecFabricacaoMsValores(dmGlobal, vIdFabricacao);
    end;

    JSONRetorno := TJSONObject.Create;
    JSONRetorno.AddPair('result', 'Itens processados com sucesso');
    JSONRetorno.AddPair('itens_processados', TJSONNumber.Create(vProcessados));
    JSONRetorno.AddPair('itens_ignorados', TJSONNumber.Create(vIgnorados));
    JSONRetorno.AddPair('ms_insumo_fallback_cgpec', TJSONNumber.Create(vMsFallback));
    if vIdFabricacao <> '' then
      JSONRetorno.AddPair('id_fabricacao', vIdFabricacao);
    Res.Send(JSONRetorno).Status(200);
    MirrorPostBody('/Post/Fabricacao_Insumo', Body, JSONRetorno.ToJSON, 200);
  except
    on E: Exception do
    begin
      if not Assigned(JSONRetorno) then
        JSONRetorno := TJSONObject.Create;
      JSONRetorno.AddPair('erro', E.Message);
      Res.Send(JSONRetorno).Status(500);
    end;
  end;

  dmGlobal.Free;
end;

procedure PostFabricacao(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  dmGlobal: TdmDB;
  Body: TJSONObject;
  JSONRetorno: TJSONObject;
  vMaxId, vIdFazenda, vIdDieta, vModo, vTempStr: string;
  msRealizada, KGRealizada, msPrevista, qtdePrevista, custo_kg_dieta: Double;
  vDataFab: TDateTime;
  vExiste, vTemData: Boolean;
begin
  dmGlobal := TdmDB.Create(nil);
  Body := nil;
  JSONRetorno := nil;

  try
    dmGlobal.ConectaDBCGPec;
    Body := Req.Body<TJSONObject>;
    if not Assigned(Body) then
      raise Exception.Create('JSON inválido ou corpo vazio');

    vMaxId := Trim(ExtractStrCI(Body, ['id']));
    vIdFazenda := Trim(ExtractStrCI(Body, ['id_fazenda']));
    vIdDieta := Trim(ExtractStrCI(Body, ['id_dieta']));

    if vMaxId = '' then
      raise Exception.Create('Campo obrigatório "id" não informado');
    if vIdFazenda = '' then
      raise Exception.Create('Campo obrigatório "id_fazenda" não informado');
    if vIdDieta = '' then
      raise Exception.Create('Campo obrigatório "id_dieta" não informado');

    KGRealizada := JsonFlexNumber(Body, ['qtde_realizada', 'qtd_realizada', 'kg_realizado']);
    if KGRealizada <= 0 then
      raise Exception.Create('qtde_realizada deve ser maior que zero');

    msRealizada := JsonFlexNumber(Body, ['ms_realizada', 'msRealizada', 'ms_batida']);
    msPrevista := JsonFlexNumber(Body, ['ms_prevista', 'msPrevista']);
    qtdePrevista := JsonFlexNumber(Body, ['qtde_prevista', 'qtd_prevista', 'kg_previsto']);
    custo_kg_dieta := JsonFlexNumber(Body, ['custo_kg_dieta']);

    // Nunca gravar MS prevista/realizada zerada: body → alternativa → dieta → 1
    msPrevista := ResolveMsPercentFabricacao(dmGlobal, vIdDieta, msPrevista, msRealizada);
    msRealizada := ResolveMsPercentFabricacao(dmGlobal, vIdDieta, msRealizada, msPrevista);

    with dmGlobal.qryAux do
    begin
      Close;
      SQL.Text :=
        'SELECT ID FROM CADASTRO_FABRICA_RACAO ' +
        'WHERE UPPER(TRIM(CAST(ID AS VARCHAR(64)))) = UPPER(TRIM(:ID))';
      ParamByName('ID').AsString := vMaxId;
      Open;
      vExiste := not IsEmpty;
      Close;

      if vExiste then
      begin
        vModo := 'update_por_id';
        SQL.Text :=
          'UPDATE CADASTRO_FABRICA_RACAO SET ' +
          '  ID_FAZENDA = :ID_FAZENDA, ' +
          '  ID_DIETA = :ID_DIETA, ' +
          '  DATA = :DATA, ' +
          '  ID_USUARIO = :ID_USUARIO, ' +
          '  ID_OPERADOR = :ID_OPERADOR, ' +
          '  ID_VAGAO = :ID_VAGAO, ' +
          '  QTDE_PREVISTA = :QTDE_PREVISTA, ' +
          '  MS_PREVISTA = :MS_PREVISTA, ' +
          '  QTDE_REALIZADA = :QTDE_REALIZADA, ' +
          '  MS_BATIDA = :MS_BATIDA, ' +
          '  STATUS_ATUAL = :STATUS_ATUAL';
        if custo_kg_dieta > 0 then
          SQL.Text := SQL.Text + ', CUSTO_KG_DIETA = :CUSTO_KG_DIETA';
        SQL.Text := SQL.Text +
          ' WHERE UPPER(TRIM(CAST(ID AS VARCHAR(64)))) = UPPER(TRIM(:ID))';
      end
      else
      begin
        vModo := 'insert';
        SQL.Text :=
          'INSERT INTO CADASTRO_FABRICA_RACAO (' +
          '  ID, ID_FAZENDA, ID_DIETA, DATA, ID_USUARIO, ID_OPERADOR, ID_VAGAO, ' +
          '  QTDE_PREVISTA, MS_PREVISTA, QTDE_REALIZADA, MS_BATIDA, STATUS_ATUAL';
        if custo_kg_dieta > 0 then
          SQL.Text := SQL.Text + ', CUSTO_KG_DIETA';
        SQL.Text := SQL.Text +
          ') VALUES (' +
          '  :ID, :ID_FAZENDA, :ID_DIETA, :DATA, :ID_USUARIO, :ID_OPERADOR, :ID_VAGAO, ' +
          '  :QTDE_PREVISTA, :MS_PREVISTA, :QTDE_REALIZADA, :MS_BATIDA, :STATUS_ATUAL';
        if custo_kg_dieta > 0 then
          SQL.Text := SQL.Text + ', :CUSTO_KG_DIETA';
        SQL.Text := SQL.Text + ')';
      end;

      ParamByName('ID').AsString := vMaxId;
      ParamByName('ID_FAZENDA').AsString := vIdFazenda;
      ParamByName('ID_DIETA').AsString := vIdDieta;
      vTempStr := Trim(ExtractStrCI(Body, ['data', 'data_fabricacao']));
      vTemData := ParseFlexDate(vTempStr, vDataFab);
      if vTemData then
        ParamByName('DATA').AsDate := vDataFab
      else
        ParamByName('DATA').Clear;
      ParamByName('ID_USUARIO').AsString := Trim(ExtractStrCI(Body, ['id_usuario']));
      ParamByName('ID_OPERADOR').AsString := Trim(ExtractStrCI(Body, ['id_operador']));
      ParamByName('ID_VAGAO').AsString := Trim(ExtractStrCI(Body, ['id_vagao']));
      ParamByName('QTDE_PREVISTA').AsFloat := qtdePrevista;
      ParamByName('MS_PREVISTA').AsFloat := msPrevista;
      ParamByName('QTDE_REALIZADA').AsFloat := KGRealizada;
      ParamByName('MS_BATIDA').AsFloat := msRealizada;
      ParamByName('STATUS_ATUAL').AsString := 'FINALIZADO';
      if custo_kg_dieta > 0 then
        ParamByName('CUSTO_KG_DIETA').AsFloat := custo_kg_dieta;
      ExecSQL;
    end;

    EnsureCgPecFabricacaoMsValores(dmGlobal, vMaxId);

    JSONRetorno := TJSONObject.Create;
    JSONRetorno.AddPair('id', vMaxId);
    JSONRetorno.AddPair('modo', vModo);
    Res.Send(JSONRetorno).Status(200);
    MirrorPostBody('/Post/Fabricacao', Body, JSONRetorno.ToJSON, 200);
  except
    on E: Exception do
    begin
      if not Assigned(JSONRetorno) then
        JSONRetorno := TJSONObject.Create;
      JSONRetorno.AddPair('erro', E.Message);
      Res.Send(JSONRetorno).Status(500);
    end;
  end;

  dmGlobal.Free;
end;


end.
