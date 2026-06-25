unit Controllers.Post.Field;

interface

uses
  Horse,
  Horse.Jhonson,
  Horse.CORS,
  System.JSON,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.DateUtils,
  System.Hash,
  System.AnsiStrings,
  FireDAC.Comp.Client;

procedure LimpaJSONObject(JSON: TJSONObject);
procedure RegistraRotas;
procedure PostFornecimento(Req: THorseRequest; Res: THorseResponse; Next: TProc);
procedure PostGravaTag(Req: THorseRequest; Res: THorseResponse; Next: TProc);
procedure PostFabricacao(Req: THorseRequest; Res: THorseResponse; Next: TProc);
procedure PostGpsTrack(Req: THorseRequest; Res: THorseResponse; Next: TProc);
function VerificaCampoObrigatorio(const JSON: TJSONObject; const NomeCampo: string; out Valor: string): Boolean;
procedure UploadLog(Req: THorseRequest; Res: THorseResponse; Next: TProc);

implementation

uses
  System.IniFiles,
  UdmFieldPec,
  Controllers.Mirror;

function ParseHoraRef(const S: string): TDateTime; forward;
procedure SetParamHoraOpcional(Q: TFDQuery; const Nome: string; H: TDateTime); forward;

function ExtractStrCI(const Obj: TJSONObject; const Keys: array of string): string; forward;

procedure LimpaJSONObject(JSON: TJSONObject);
begin
  while JSON.Count > 0 do
    JSON.RemovePair(JSON.Pairs[0].JsonString.Value);
end;

function JSONValueToStr(const V: TJSONValue): string;
var
  N: TJSONNumber;
begin
  Result := '';
  if not Assigned(V) or (V is TJSONNull) then
    Exit;

  if V is TJSONNumber then
  begin
    N := TJSONNumber(V);
    if Frac(N.AsDouble) = 0 then
      Result := IntToStr(Round(N.AsDouble))
    else
      Result := FloatToStr(N.AsDouble);
    Exit;
  end;

  Result := V.Value;
end;

function JSONStr(const Obj: TJSONObject; const Nome: string; const Padrao: string = ''): string;
var
  V: TJSONValue;
begin
  Result := Padrao;
  if Obj = nil then
    Exit;

  V := Obj.Values[Nome];
  if Assigned(V) then
    Result := JSONValueToStr(V);
end;

function JSONArray(const Obj: TJSONObject; const Nome: string): TJSONArray;
var
  V: TJSONValue;
begin
  Result := nil;
  if Obj = nil then
    Exit;

  V := Obj.Values[Nome];
  if Assigned(V) and (V is TJSONArray) then
    Result := TJSONArray(V);
end;

function StrToIntSafe(const S: string; const Default: Integer = 0): Integer;
begin
  if not TryStrToInt(Trim(S), Result) then
    Result := Default;
end;

function JSONStrFirst(const Obj: TJSONObject; const Keys: array of string;
  const Padrao: string = ''): string;
var
  I: Integer;
  V: string;
begin
  Result := Padrao;
  if Obj = nil then
    Exit;

  for I := 0 to High(Keys) do
  begin
    V := Trim(JSONStr(Obj, Keys[I]));
    if V <> '' then
      Exit(V);
  end;

  V := Trim(ExtractStrCI(Obj, Keys));
  if V <> '' then
    Result := V;
end;

function JSONIntFirst(const Obj: TJSONObject; const Keys: array of string;
  const Default: Integer = 0): Integer;
var
  I: Integer;
  V: TJSONValue;
  N: Integer;
  Pair: TJSONPair;
  k: string;
begin
  Result := Default;
  if Obj = nil then
    Exit;

  for I := 0 to High(Keys) do
  begin
    V := Obj.Values[Keys[I]];
    if not Assigned(V) or (V is TJSONNull) then
      Continue;

    if V is TJSONNumber then
      N := Round(TJSONNumber(V).AsDouble)
    else
      N := StrToIntSafe(Trim(JSONValueToStr(V)), 0);

    if N > 0 then
      Exit(N);
  end;

  for k in Keys do
    for Pair in Obj do
      if SameText(Pair.JsonString.Value, k) and Assigned(Pair.JsonValue) and
        not (Pair.JsonValue is TJSONNull) then
      begin
        if Pair.JsonValue is TJSONNumber then
          N := Round(TJSONNumber(Pair.JsonValue).AsDouble)
        else
          N := StrToIntSafe(Trim(JSONValueToStr(Pair.JsonValue)), 0);

        if N > 0 then
          Exit(N);
      end;
end;

function JSONArrayFirst(const Obj: TJSONObject; const Keys: array of string): TJSONArray;
var
  I: Integer;
  Pair: TJSONPair;
  k: string;
begin
  Result := nil;
  if Obj = nil then
    Exit;

  for I := 0 to High(Keys) do
  begin
    Result := JSONArray(Obj, Keys[I]);
    if Assigned(Result) then
      Exit;
  end;

  for k in Keys do
    for Pair in Obj do
      if SameText(Pair.JsonString.Value, k) and (Pair.JsonValue is TJSONArray) then
        Exit(TJSONArray(Pair.JsonValue));
end;

function StrToFloatBR(const S: string): Double;
var
  L: string;
  FS: TFormatSettings;
begin
  L := Trim(S);
  if L = '' then
    Exit(0);

  FS := TFormatSettings.Create;
  FS.DecimalSeparator := '.';
  FS.ThousandSeparator := #0;

  L := StringReplace(L, '.', '', [rfReplaceAll]);
  L := StringReplace(L, ',', '.', [rfReplaceAll]);

  Result := StrToFloat(L, FS);
end;

function StrToDateBR(const S: string): TDate;
var
  P: TArray<string>;
  D, M, Y: Word;
begin
  if Trim(S) = '' then
    raise Exception.Create('Campo data vazio.');

  P := S.Split(['/']);
  if Length(P) <> 3 then
    raise Exception.CreateFmt('Data inválida: %s. Use dd/MM/yyyy.', [S]);

  D := StrToInt(P[0]);
  M := StrToInt(P[1]);
  Y := StrToInt(P[2]);

  Result := EncodeDate(Y, M, D);
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
    Env := GetEnvironmentVariable('RFEED_LOG_DIR');
    if Env <> '' then
      Exit(IncludeTrailingPathDelimiter(Env));

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
          raise Exception.CreateFmt('Não foi possível criar a pasta "%s". Erro: %s', [P, E.Message]);
      end;
    end;
  end;

  procedure AppendBytesToFileUtf8(const FileName: string; const Data: TBytes);
  var
    FS: TFileStream;
    NeedEOL: Boolean;
  begin
    if TFile.Exists(FileName) then
      FS := TFileStream.Create(FileName, fmOpenReadWrite or fmShareDenyNone)
    else
      FS := TFileStream.Create(FileName, fmCreate or fmShareDenyNone);
    try
      FS.Seek(0, soEnd);

      NeedEOL := (FS.Size > 0) and (Length(Data) > 0);
      if NeedEOL then
      begin
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
    DeviceId := Trim(Req.Params.Items['device']);
    if DeviceId = '' then
      DeviceId := 'unknown';

    DateYMD := Req.Query.Items['date'];
    if DateYMD = '' then
      DateYMD := FormatDateTime('yyyymmdd', Date);

    SizeHdr := StrToInt64Def(Req.Headers['content-length'], -1);
    if (MAX_SIZE_BYTES > 0) and (SizeHdr > MAX_SIZE_BYTES) then
    begin
      Res.Status(413).Send<TJSONObject>(TJSONObject.Create.AddPair('erro', 'arquivo muito grande'));
      Exit;
    end;

    CT := LowerCase(Req.ContentType);
    if (Pos('zip', CT) > 0) or (Pos('octet-stream', CT) > 0) then
    begin
      Res.Status(415).Send<TJSONObject>(TJSONObject.Create.AddPair('erro', 'content-type binário não suportado'));
      Exit;
    end;

    SaveBase := GetLogBaseDir;
    SaveDir  := TPath.Combine(SaveBase, DateYMD);
    SaveDir  := TPath.Combine(SaveDir, DeviceId);
    EnsureDir(SaveDir);

    SaveName := 'fornecimento_' + DateYMD + '.txt';
    SavePath := TPath.Combine(SaveDir, SaveName);

    AppendedBytes := 0;

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
      BodyStr := Req.Body;
      if BodyStr = '' then
      begin
        Res.Status(400).Send<TJSONObject>(TJSONObject.Create.AddPair('erro', 'corpo vazio'));
        Exit;
      end;

      BodyStr := StringReplace(BodyStr, #13#10, #10, [rfReplaceAll]);
      BodyStr := StringReplace(BodyStr, #13, #10, [rfReplaceAll]);
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
        TJSONObject.Create.AddPair(
          'erro',
          Format('%s: %s (base=%s)', [E.ClassName, E.Message, GetLogBaseDir])
        )
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

procedure RegistraRotas;
begin
  THorse.Post('/Post/Fornecimento', PostFornecimento);
  THorse.Post('/Post/Fabricacao', PostFabricacao);
  THorse.Put('/logs/upload/:device', UploadLog);
  THorse.Post('/Post/GravaTag', PostGravaTag);
  THorse.Post('/Post/GpsTrack', PostGpsTrack);
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
  begin
    if Obj.TryGetValue<string>(k, Result) then
      if Result <> '' then
        Exit;
    Result := '';
  end;
end;

procedure UpdateRFID(dm: TdmFieldPec; const IdBaia, EPC: string; var Rows: Integer);
begin
  Rows := 0;
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
        Result := JSONValueToStr(Pair.JsonValue);
        Exit;
      end;
end;

procedure ProcessOne(dm: TdmFieldPec; const Obj: TJSONObject; ArrResult: TJSONArray);
var
  vId, vEpc, err: string;
  rows: Integer;
  o: TJSONObject;
begin
  vId := ExtractStrCI(Obj, ['ID_PASTO_CURRAL', 'id_baia', 'id']);
  vEpc := ExtractStrCI(Obj, ['TAG', 'rfid', 'epc', 'tag']);

  err := '';
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
      if vId <> '' then
        o.AddPair('id', vId);
    end;

    ArrResult.AddElement(o);
  except
    o.Free;
    raise;
  end;
end;

procedure PostGravaTag(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  dmGlobal: TdmFieldPec;
  Body: TJSONObject;
  JSONResult: TJSONObject;
  Q: TFDQuery;
  Conn: TFDConnection;
  vIdCurral, vTag: string;
  vRows: Integer;
  vResponseText: string;

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
  Conn := nil;
  vRows := 0;
  vResponseText := '';

  try
    Body := Req.Body<TJSONObject>;
    if not Assigned(Body) then
      raise Exception.Create('JSON inválido ou corpo vazio.');

    JSONResult := TJSONObject.Create;

    Body.TryGetValue<string>('ID_PASTO_CURRAL', vIdCurral);
    Body.TryGetValue<string>('TAG', vTag);

    if Trim(vIdCurral) = '' then
      raise Exception.Create('ID_PASTO_CURRAL ausente.');
    if Trim(vTag) = '' then
      raise Exception.Create('TAG ausente.');

    vTag := NormalizeEPC(vTag);

    dmGlobal := TdmFieldPec.Create(nil);
    dmGlobal.ConectaDBField;
    Conn := dmGlobal.FBCon;

    if not Conn.Connected then
      Conn.Connected := True;

    if not Conn.InTransaction then
      Conn.StartTransaction;

    try
      Q := TFDQuery.Create(nil);
      try
        Q.Connection := Conn;
        Q.SQL.Text :=
          'UPDATE CURRAIS ' +
          'SET TAG_INICIO = NULL ' +
          'WHERE TAG_INICIO = :TAG ' +
          '  AND ID <> :ID';
        Q.ParamByName('TAG').AsString := vTag;
        Q.ParamByName('ID').AsInteger := StrToInt(vIdCurral);
        Q.ExecSQL;
      finally
        FreeAndNil(Q);
      end;

      Q := TFDQuery.Create(nil);
      try
        Q.Connection := Conn;
        Q.SQL.Text :=
          'UPDATE CURRAIS ' +
          'SET TAG_INICIO = :TAG ' +
          'WHERE ID = :ID';
        Q.ParamByName('TAG').AsString := vTag;
        Q.ParamByName('ID').AsInteger := StrToInt(vIdCurral);
        Q.ExecSQL;

        vRows := Q.RowsAffected;
      finally
        FreeAndNil(Q);
      end;

      if vRows = 0 then
        raise Exception.CreateFmt('Curral %s não encontrado para atualização.', [vIdCurral]);

      Conn.Commit;

      JSONResult.AddPair('success', TJSONBool.Create(True));
      JSONResult.AddPair('id', vIdCurral);
      JSONResult.AddPair('tag', vTag);
      JSONResult.AddPair('updated', TJSONNumber.Create(vRows));

      vResponseText := JSONResult.ToJSON;
      Res.ContentType('application/json').Status(200).Send(vResponseText);
      MirrorPostBody('/Post/GravaTag', Body, vResponseText, 200);
      Exit;
    except
      on E: Exception do
      begin
        if Assigned(Conn) and Conn.InTransaction then
          Conn.Rollback;

        FreeAndNil(JSONResult);
        JSONResult := TJSONObject.Create;
        JSONResult.AddPair('success', TJSONBool.Create(False));
        JSONResult.AddPair('erro', 'Erro: ' + E.ClassName + ' - ' + E.Message);

        vResponseText := JSONResult.ToJSON;
        Res.ContentType('application/json').Status(500).Send(vResponseText);
        Exit;
      end;
    end;

  finally
    Q.Free;
    JSONResult.Free;
    dmGlobal.Free;
    // NAO liberar Body aqui
  end;
end;

function VerificaCampoObrigatorio(const JSON: TJSONObject; const NomeCampo: string; out Valor: string): Boolean;
begin
  Result := JSON.TryGetValue<string>(NomeCampo, Valor) and (Valor.Trim <> '');
end;

procedure PostFornecimento(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  dmGlobal: TdmFieldPec;
  Body: TJSONObject;
  JSONResult: TJSONObject;

  vId: string;
  vIdFabricacao, vIdUsuario, vIdTratador, vIdDietaRealizada, vRealizado, vMS: string;
  vIdBaia, vIdRacaoPrev, vTratoStr, vDataISO, vHoraForn: string;
  vTrato: Integer;
  vData: TDateTime;
  vHoraFornDt: TDateTime;
  vMsFornec, vRealizadoNum, vRealizadoAtual, vRealizadoGravar: Double;
  vFornecimentoAcumulativo: Boolean;
  vPontoCorteKg: Double;
  vEncontrou: Boolean;
  vIdFallback: string;
  IdFornecConf, IdLocal, IdRacao, IdMotorista: Integer;

  function GetStr(const K: string; const Def: string = ''): string;
  begin
    if not Body.TryGetValue<string>(K, Result) then
      Result := Def;
    Result := Result.Trim;
    if Result = '' then
      Result := Def;
  end;

  function ParseDataRef(const S: string): TDateTime;
  begin
    Result := 0;
    if Trim(S) = '' then
      Exit;
    try
      Result := ISO8601ToDate(S, True);
      Exit;
    except
    end;
    try
      Result := StrToDateBR(S);
    except
      Result := 0;
    end;
  end;

  function ReadFornecimentoAcumulativoIni: Boolean;
  var
    LIniPath, LVal: string;
    LIni: TIniFile;
  begin
    Result := True;
    LIniPath := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'ApiConfig.ini';
    if not FileExists(LIniPath) then
      LIniPath := IncludeTrailingPathDelimiter(GetCurrentDir) + 'ApiConfig.ini';
    if not FileExists(LIniPath) then
      Exit(True);

    LIni := TIniFile.Create(LIniPath);
    try
      LVal := LowerCase(Trim(LIni.ReadString('API', 'FornecimentoAcumulativo', '1')));
      Result := not ((LVal = '0') or (LVal = 'false') or (LVal = 'no') or (LVal = 'nao') or (LVal = 'não'));
    finally
      LIni.Free;
    end;
  end;

  function ReadPontoCorteFornecimentoKgIni: Double;
  var
    LIniPath, LVal: string;
    LIni: TIniFile;
  begin
    Result := 50;
    LIniPath := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'ApiConfig.ini';
    if not FileExists(LIniPath) then
      LIniPath := IncludeTrailingPathDelimiter(GetCurrentDir) + 'ApiConfig.ini';
    if not FileExists(LIniPath) then
      Exit(50);

    LIni := TIniFile.Create(LIniPath);
    try
      LVal := Trim(LIni.ReadString('API', 'PontoCorteFornecimentoKg', '50'));
      LVal := StringReplace(LVal, ',', '.', [rfReplaceAll]);
      Result := StrToFloatDef(LVal, 50);
      if Result < 0 then
        Result := 0;
    finally
      LIni.Free;
    end;
  end;

begin
  dmGlobal := nil;
  Body := nil;
  JSONResult := nil;

  try
    Body := Req.Body<TJSONObject>;
    if not Assigned(Body) then
      raise Exception.Create('JSON inválido ou corpo vazio');

    dmGlobal := TdmFieldPec.Create(nil);
    try
      dmGlobal.ConectaDBField;

      JSONResult := TJSONObject.Create;

      vId := GetStr('id', '');
      if vId = '' then
        vId := GetStr('id_fornecimento', '');
      vIdFabricacao := GetStr('id_fabricacao', '0');
      vIdUsuario := JSONStrFirst(Body, ['id_usuario_lancamento', 'ID_USUARIO', 'id_usuario'], '0');
      vIdTratador := JSONStrFirst(Body, ['id_tratador', 'ID_MOTORISTA', 'id_motorista'], '0');
      vIdDietaRealizada := JSONStrFirst(Body, ['id_dieta_realizada', 'ID_RACAO', 'IDRACAO', 'ID_DIETA'], '0');
      vRealizado := JSONStrFirst(Body, ['realizado', 'REALIZADO_MN_KG', 'REALIZADO'], '0');
      vMS := JSONStrFirst(Body, ['ms_dieta_realizada', 'MS_RACAO', 'MS_DIETA'], '0');

      vIdBaia := JSONStrFirst(Body, ['id_baia', 'IDCURRAL', 'id_curral', 'ID_LOCAL']);
      vIdRacaoPrev := JSONStrFirst(Body, ['id_racao', 'ID_RACAO', 'IDRACAO', 'id_dieta', 'id_dieta_prevista']);
      vTratoStr := JSONStrFirst(Body, ['trato', 'TRATO'], '0');
      vDataISO := JSONStrFirst(Body, ['data', 'DATA_FORN', 'data_forn', 'DATA_FAB']);
      vHoraForn := JSONStrFirst(Body, ['hora_forn', 'HORA_FORN', 'hora_fim', 'HORA_FIM']);

      vTrato := StrToIntDef(vTratoStr, 0);
      vData := ParseDataRef(vDataISO);
      if (Trim(vIdRacaoPrev) = '') or (Trim(vIdRacaoPrev) = '0') then
      begin
        if (Trim(vIdDietaRealizada) <> '') and (Trim(vIdDietaRealizada) <> '0') then
          vIdRacaoPrev := Trim(vIdDietaRealizada);
      end;

      vRealizadoNum := StrToFloatBR(vRealizado);
      vMsFornec := StrToFloatBR(vMS);
      vFornecimentoAcumulativo := ReadFornecimentoAcumulativoIni;
      vPontoCorteKg := ReadPontoCorteFornecimentoKgIni;

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

      dmGlobal.qryAux.Connection := dmGlobal.FBCon;
      vIdFallback := vId;
      vEncontrou := False;
      IdFornecConf := 0;
      IdLocal := StrToIntDef(Trim(vIdBaia), 0);
      IdRacao := StrToIntDef(Trim(vIdRacaoPrev), 0);
      if IdRacao <= 0 then
        IdRacao := StrToIntDef(Trim(vIdDietaRealizada), 0);
      IdMotorista := StrToIntDef(Trim(vIdTratador), 0);
      if IdMotorista <= 0 then
        IdMotorista := StrToIntDef(Trim(vIdUsuario), 0);

      if Trim(vIdFallback) <> '' then
      begin
        IdFornecConf := StrToIntDef(Trim(vIdFallback), 0);
        if IdFornecConf > 0 then
        begin
          with dmGlobal.qryAux do
          begin
            Close;
            SQL.Text :=
              'SELECT ID, REALIZADO_MN_KG FROM FORNECIMENTO_CONF ' +
              'WHERE ID = :ID AND STATUS = 1';
            ParamByName('ID').AsInteger := IdFornecConf;
            Open;
            if not IsEmpty then
            begin
              vEncontrou := True;
              vRealizadoAtual := FieldByName('REALIZADO_MN_KG').AsFloat;
              vId := FieldByName('ID').AsString;
            end;
            Close;
          end;
        end;
      end;

      if (not vEncontrou) and (IdLocal > 0) and (IdRacao > 0)
         and (vTrato > 0) and (vData <> 0) then
      begin
        with dmGlobal.qryAux do
        begin
          Close;
          SQL.Text :=
            'SELECT ID, REALIZADO_MN_KG FROM FORNECIMENTO_CONF ' +
            'WHERE STATUS = 1 AND ID_LOCAL = :ID_LOCAL AND TRATO = :TRATO ' +
            '  AND DATA_FORN = :DATA_FORN AND ID_RACAO = :ID_RACAO';
          ParamByName('ID_LOCAL').AsInteger := IdLocal;
          ParamByName('TRATO').AsInteger := vTrato;
          ParamByName('DATA_FORN').AsDate := vData;
          ParamByName('ID_RACAO').AsInteger := IdRacao;
          Open;
          if not IsEmpty then
          begin
            vEncontrou := True;
            IdFornecConf := FieldByName('ID').AsInteger;
            vRealizadoAtual := FieldByName('REALIZADO_MN_KG').AsFloat;
            vId := IntToStr(IdFornecConf);
          end;
          Close;
        end;
      end;

      if not vEncontrou then
      begin
        if (vIdBaia = '') or (vIdRacaoPrev = '') or (vTrato <= 0) or (vData = 0) then
          raise Exception.Create(
            'Chave natural incompleta e ID ausente. Envie: id_baia, id_racao, trato, data (ou id).');
        raise Exception.Create(
          'Nenhum FORNECIMENTO_CONF encontrado para (curral+dieta+trato+data).');
      end;

      if vFornecimentoAcumulativo then
        vRealizadoGravar := vRealizadoAtual + vRealizadoNum
      else
        vRealizadoGravar := vRealizadoNum;

      vHoraFornDt := ParseHoraRef(vHoraForn);

      with dmGlobal.qryAux do
      begin
        Close;
        if Frac(vHoraFornDt) > 0 then
          SQL.Text :=
            'UPDATE FORNECIMENTO_CONF SET ' +
            '  REALIZADO_MN_KG = :REALIZADO, ' +
            '  MS_RACAO = :MS, ' +
            '  ID_MOTORISTA = :ID_MOTORISTA, ' +
            '  HORA_FORN = :HORA_FORN, ' +
            '  DATA_ALTERACAO = CURRENT_TIMESTAMP, ' +
            '  ID_USUARIO_ALTERACAO = :ID_USUARIO ' +
            'WHERE ID = :ID'
        else
          SQL.Text :=
            'UPDATE FORNECIMENTO_CONF SET ' +
            '  REALIZADO_MN_KG = :REALIZADO, ' +
            '  MS_RACAO = :MS, ' +
            '  ID_MOTORISTA = :ID_MOTORISTA, ' +
            '  DATA_ALTERACAO = CURRENT_TIMESTAMP, ' +
            '  ID_USUARIO_ALTERACAO = :ID_USUARIO ' +
            'WHERE ID = :ID';
        ParamByName('REALIZADO').AsFloat := vRealizadoGravar;
        ParamByName('MS').AsFloat := vMsFornec;
        ParamByName('ID_MOTORISTA').AsInteger := IdMotorista;
        ParamByName('ID_USUARIO').AsInteger := IdMotorista;
        ParamByName('ID').AsInteger := IdFornecConf;
        if Frac(vHoraFornDt) > 0 then
          ParamByName('HORA_FORN').AsDateTime := Frac(vHoraFornDt);
        ExecSQL;
      end;

      JSONResult.AddPair('id', vId);
      JSONResult.AddPair('ok', TJSONBool.Create(True));
      JSONResult.AddPair('modo', 'update_fornecimento_conf');
      JSONResult.AddPair('fornecimento_acumulativo', TJSONBool.Create(vFornecimentoAcumulativo));
      JSONResult.AddPair('realizado_gravado', TJSONNumber.Create(vRealizadoGravar));
      Res.Send(JSONResult).Status(200);
      MirrorPostBody('/Post/Fornecimento', Body, JSONResult.ToJSON, 200);
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

function ParseHoraRef(const S: string): TDateTime;
var
  Txt: string;
  P: Integer;
begin
  Result := 0;
  Txt := Trim(S);
  if Txt = '' then
    Exit;

  if Pos('T', Txt) > 0 then
  begin
    P := Pos('T', Txt);
    Txt := Copy(Txt, P + 1, MaxInt);
  end
  else if Pos(' ', Txt) > 0 then
  begin
    P := LastDelimiter(' ', Txt);
    Txt := Copy(Txt, P + 1, MaxInt);
  end;

  Txt := Trim(StringReplace(Txt, '.', ':', [rfReplaceAll]));
  if Pos(':', Txt) = 0 then
    Exit;

  try
    if Length(Txt) = 5 then
      Result := StrToTime(Txt + ':00')
    else
      Result := StrToTime(Copy(Txt, 1, 8));
  except
    Result := 0;
  end;
end;

procedure SetParamHoraOpcional(Q: TFDQuery; const Nome: string; H: TDateTime);
begin
  if Frac(H) > 0 then
    Q.ParamByName(Nome).AsDateTime := Frac(H)
  else
    Q.ParamByName(Nome).Clear;
end;

function ProximoIdTabela(Conn: TFDConnection; const TableName: string): Integer;
var
  Q: TFDQuery;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;
    Q.SQL.Text := Format(
      'SELECT COALESCE(MAX(ID), 0) + 1 AS NX FROM %s',
      [TableName]);
    Q.Open;
    Result := Q.FieldByName('NX').AsInteger;
    if Result <= 0 then
      Result := 1;
  finally
    Q.Free;
  end;
end;

function ProximoIdFabricacao(Conn: TFDConnection): Integer;
begin
  Result := ProximoIdTabela(Conn, 'FABRICACAO');
end;

procedure AplicarParamsInsertFabricacao(
  Q: TFDQuery;
  IdDieta, IdFazenda, IdUsuario, IdOperador: Integer;
  DataFab: TDate;
  QtdePrevista, QtdeRealizada, CustoTotal: Double);
begin
  Q.ParamByName('IDRACAO').AsInteger := IdDieta;
  Q.ParamByName('DATA_FAB').AsDate := DataFab;
  Q.ParamByName('KG_PREVISTO').AsFloat := QtdePrevista;
  Q.ParamByName('KG_REALIZADO').AsFloat := QtdeRealizada;
  Q.ParamByName('CUSTO_TOTAL').AsFloat := CustoTotal;
  Q.ParamByName('ID_USUARIO').AsInteger := IdUsuario;
  Q.ParamByName('ID_OPERADOR').AsInteger := IdOperador;
  Q.ParamByName('ID_PROPRIEDADE').AsInteger := IdFazenda;
end;

function InserirFabricacaoComIdSeguro(
  Conn: TFDConnection;
  IdDieta, IdFazenda, IdUsuario, IdOperador: Integer;
  DataFab: TDate;
  QtdePrevista, QtdeRealizada, CustoTotal: Double): Integer;
var
  Q: TFDQuery;
  Attempt: Integer;
  ErrMsg: string;
  NextId: Integer;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;

    for Attempt := 1 to 4 do
    begin
      NextId := ProximoIdFabricacao(Conn);
      Q.Close;
      Q.SQL.Text :=
        'INSERT INTO FABRICACAO ( ' +
        '  ID, IDRACAO, DATA_FAB, KG_PREVISTO, KG_REALIZADO, CUSTO_TOTAL, ' +
        '  ID_USUARIO, ID_OPERADOR, ID_PROPRIEDADE, ORIGEM_DADOS, STATUS, DATAREG ' +
        ') VALUES ( ' +
        '  :ID, :IDRACAO, :DATA_FAB, :KG_PREVISTO, :KG_REALIZADO, :CUSTO_TOTAL, ' +
        '  :ID_USUARIO, :ID_OPERADOR, :ID_PROPRIEDADE, 1, 1, CURRENT_DATE ' +
        ')';

      Q.ParamByName('ID').AsInteger := NextId;
      AplicarParamsInsertFabricacao(
        Q, IdDieta, IdFazenda, IdUsuario, IdOperador, DataFab,
        QtdePrevista, QtdeRealizada, CustoTotal);

      try
        Q.ExecSQL;
        Result := NextId;
        Exit;
      except
        on E: Exception do
        begin
          ErrMsg := UpperCase(E.Message);
          if (Pos('PRIMARY', ErrMsg) = 0) and
             (Pos('UNIQUE', ErrMsg) = 0) and
             (Pos('PK_FABRICACAO', ErrMsg) = 0) then
            raise;
        end;
      end;
    end;

    raise Exception.Create('Falha ao inserir FABRICACAO (PK) apos 4 tentativas.');
  finally
    Q.Free;
  end;
end;

procedure InserirFabricacaoInsumoSeguro(
  Conn: TFDConnection;
  IdServidorFab, IdInsumo, IdUsuarioItem: Integer;
  DataFab: TDate;
  QtdePrevistaItem, QtdeRealizadaItem, MsInsumo, ValorKgInsumo: Double;
  HoraIni, HoraFim: TDateTime);
var
  Q: TFDQuery;
  Attempt: Integer;
  ErrMsg: string;
  NextId: Integer;

  procedure AplicarParams;
  begin
    Q.ParamByName('ID_FABRICACAO').AsInteger := IdServidorFab;
    Q.ParamByName('ID_ALIMENTO').AsInteger := IdInsumo;
    Q.ParamByName('DATA_FAB').AsDate := DataFab;
    Q.ParamByName('MS_INSUMO').AsFloat := MsInsumo;
    Q.ParamByName('KG_PREVISTO').AsFloat := QtdePrevistaItem;
    Q.ParamByName('KG_FABRICADO').AsFloat := QtdeRealizadaItem;
    Q.ParamByName('ID_USUARIO').AsInteger := IdUsuarioItem;
    Q.ParamByName('VALOR_KG').AsFloat := ValorKgInsumo;
  end;

begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;

    for Attempt := 1 to 4 do
    begin
      NextId := ProximoIdTabela(Conn, 'FABRICACAO_INSUMOS');
      Q.Close;
      Q.SQL.Text :=
        'INSERT INTO FABRICACAO_INSUMOS ( ' +
        '  ID, ID_FABRICACAO, ID_ALIMENTO, DATA_FAB, MS_INSUMO, ' +
        '  KG_PREVISTO, KG_FABRICADO, ID_USUARIO, STATUS, DATAREG, VALOR_KG, ' +
        '  HORA_INI, HORA_FIM ' +
        ') VALUES ( ' +
        '  :ID, :ID_FABRICACAO, :ID_ALIMENTO, :DATA_FAB, :MS_INSUMO, ' +
        '  :KG_PREVISTO, :KG_FABRICADO, :ID_USUARIO, 1, CURRENT_DATE, :VALOR_KG, ' +
        '  :HORA_INI, :HORA_FIM ' +
        ')';
      Q.ParamByName('ID').AsInteger := NextId;
      AplicarParams;
      SetParamHoraOpcional(Q, 'HORA_INI', HoraIni);
      SetParamHoraOpcional(Q, 'HORA_FIM', HoraFim);

      try
        Q.ExecSQL;
        Exit;
      except
        on E: Exception do
        begin
          ErrMsg := UpperCase(E.Message);
          if (Pos('PRIMARY', ErrMsg) = 0) and
             (Pos('UNIQUE', ErrMsg) = 0) and
             (Pos('PK_', ErrMsg) = 0) then
            raise Exception.CreateFmt(
              'FABRICACAO_INSUMOS insumo=%d fab=%d: %s',
              [IdInsumo, IdServidorFab, E.Message]);
        end;
      end;
    end;

    raise Exception.Create('Falha ao inserir FABRICACAO_INSUMOS (PK) apos 4 tentativas.');
  finally
    Q.Free;
  end;
end;

function BuscarValorKgInsumoConn(
  Conn: TFDConnection; const AIdRacao, AIdInsumo: Integer): Double;
var
  Qry: TFDQuery;
begin
  Result := -1;

  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := Conn;
    Qry.SQL.Text :=
      'SELECT FIRST 1 VALOR_MEDIO ' +
      'FROM HIST_VALOR_INSUMOS hvi ' +
      'WHERE hvi.ID_ALIMENTO = :ID_ALIMENTO ' +
      'ORDER BY hvi.ID DESC';
    Qry.ParamByName('ID_ALIMENTO').AsInteger := AIdInsumo;
    Qry.Open;

    if (not Qry.IsEmpty) and (not Qry.FieldByName('VALOR_MEDIO').IsNull) then
      Result := Qry.FieldByName('VALOR_MEDIO').AsFloat;
  finally
    Qry.Free;
  end;

  if Result < 0 then
  begin
    Qry := TFDQuery.Create(nil);
    try
      Qry.Connection := Conn;
      Qry.SQL.Text :=
        'SELECT VALORKG ' +
        'FROM RACAOINSUMOS r ' +
        'WHERE r.IDRACAO = :IDRACAO ' +
        '  AND r.IDINSUMOALIMENTO = :IDINSUMOALIMENTO';
      Qry.ParamByName('IDRACAO').AsInteger := AIdRacao;
      Qry.ParamByName('IDINSUMOALIMENTO').AsInteger := AIdInsumo;
      Qry.Open;

      if (not Qry.IsEmpty) and (not Qry.FieldByName('VALORKG').IsNull) then
        Result := Qry.FieldByName('VALORKG').AsFloat
      else
        Result := 0;
    finally
      Qry.Free;
    end;
  end;
end;

function ProcessarItensFabricacao(
  Conn: TFDConnection;
  IdServidorFab, IdDieta, IdUsuario: Integer;
  DataFab: TDate;
  Itens: TJSONArray): Integer;
var
  IdxItem: Integer;
  Item: TJSONObject;
  IdInsumo, IdUsuarioItem: Integer;
  QtdePrevistaItem, QtdeRealizadaItem, MsInsumo, ValorKgInsumo: Double;
  HoraIniItem, HoraFimItem: TDateTime;
begin
  Result := 0;
  if not Assigned(Itens) or (Itens.Count = 0) then
    Exit;

  for IdxItem := 0 to Itens.Count - 1 do
  begin
    if not (Itens.Items[IdxItem] is TJSONObject) then
      Continue;

    Item := TJSONObject(Itens.Items[IdxItem]);

    IdInsumo := JSONIntFirst(Item, ['id_insumo', 'ID_ALIMENTO', 'id_alimento']);
    QtdePrevistaItem := StrToFloatBR(JSONStrFirst(Item, ['qtde_prevista', 'KG_PREVISTO']));
    QtdeRealizadaItem := StrToFloatBR(JSONStrFirst(Item, ['qtd_realizada', 'KG_FABRICADO', 'qtd_realizado']));
    MsInsumo := StrToFloatBR(JSONStrFirst(Item, ['ms_insumo', 'MS_INSUMO']));
    IdUsuarioItem := JSONIntFirst(Item, ['id_usuario', 'ID_USUARIO'], IdUsuario);
    HoraIniItem := ParseHoraRef(JSONStrFirst(Item, ['hora_ini', 'HORA_INI', 'hora_inicio', 'HORA_INICIO']));
    HoraFimItem := ParseHoraRef(JSONStrFirst(Item, ['hora_fim', 'HORA_FIM']));

    if IdInsumo <= 0 then
      raise Exception.CreateFmt(
        'Item %d com id_insumo/ID_ALIMENTO invalido (valor recebido: %s).',
        [IdxItem + 1, JSONStrFirst(Item, ['id_insumo', 'ID_ALIMENTO', 'id_alimento'])]);

    ValorKgInsumo := BuscarValorKgInsumoConn(Conn, IdDieta, IdInsumo);
    if ValorKgInsumo < 0 then
      ValorKgInsumo := 0;

    try
      InserirFabricacaoInsumoSeguro(
        Conn,
        IdServidorFab,
        IdInsumo,
        IdUsuarioItem,
        DataFab,
        QtdePrevistaItem,
        QtdeRealizadaItem,
        MsInsumo,
        ValorKgInsumo,
        HoraIniItem,
        HoraFimItem);
    except
      on E: Exception do
        raise Exception.CreateFmt(
          'Erro ao inserir insumo %d (ID_ALIMENTO=%d, fab=%d, prev=%.3f, real=%.3f): %s',
          [IdxItem + 1, IdInsumo, IdServidorFab, QtdePrevistaItem, QtdeRealizadaItem, E.Message]);
    end;

    Inc(Result);
  end;
end;

procedure PostFabricacao(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  dmGlobal: TdmFieldPec;
  Body: TJSONObject;
  Itens: TJSONArray;
  Fornecimentos: TJSONArray;
  Item: TJSONObject;
  Forn: TJSONObject;
  Conn: TFDConnection;
  Q: TFDQuery;

  IdxItem: Integer;
  IdxForn: Integer;

  IdLocalFab: string;
  HandoffId: string;
  LoteFabricacao: string;
  IdServidorFab: Integer;

  IdFazenda: Integer;
  IdDieta: Integer;
  IdUsuario: Integer;
  IdOperador: Integer;

  DataFab: TDate;
  QtdePrevista: Double;
  QtdeRealizada: Double;
  ValorKgRacao: Double;
  CustoTotal: Double;

  IdInsumo: Integer;
  QtdePrevistaItem: Double;
  QtdeRealizadaItem: Double;
  MsInsumo: Double;
  IdUsuarioItem: Integer;
  ValorKgInsumo: Double;

  IdCurral: Integer;
  Trato: Integer;
  HoraForn: string;
  DataForn: TDate;
  IdMotorista: Integer;
  IdRacaoRealizada: Integer;
  Realizado: Double;
  QtdCab: Double;
  MediaPeso: Double;
  ValorFabricadoD: Double;
  CustoTotalTrato: Double;

  IdFornecimento: Integer;
  IdLote: Integer;
  RealizadoAtual: Double;
  MsRacaoAtual: Double;

  ItensProcessados: Integer;
  FornecimentosProcessados: Integer;

  HoraInicioFab: TDateTime;
  HoraFimFab: TDateTime;

  RespJson: TJSONObject;

  function BuscarValorKgRacao(const AIdRacao: Integer): Double;
  var
    Qry: TFDQuery;
  begin
    Result := 0;
    Qry := TFDQuery.Create(nil);
    try
      Qry.Connection := Conn;
      Qry.SQL.Text := 'SELECT VALORKG FROM RACAO WHERE ID = :ID';
      Qry.ParamByName('ID').AsInteger := AIdRacao;
      Qry.Open;

      if Qry.IsEmpty then
        raise Exception.CreateFmt('Ração %d não encontrada.', [AIdRacao]);

      if not Qry.FieldByName('VALORKG').IsNull then
        Result := Qry.FieldByName('VALORKG').AsFloat;
    finally
      Qry.Free;
    end;
  end;

  function BuscarValorKgInsumo(const AIdRacao, AIdInsumo: Integer): Double;
  var
    Qry: TFDQuery;
  begin
    Result := -1;

    Qry := TFDQuery.Create(nil);
    try
      Qry.Connection := Conn;
      Qry.SQL.Text :=
        'SELECT FIRST 1 VALOR_MEDIO ' +
        'FROM HIST_VALOR_INSUMOS hvi ' +
        'WHERE hvi.ID_ALIMENTO = :ID_ALIMENTO ' +
        'ORDER BY hvi.ID DESC';
      Qry.ParamByName('ID_ALIMENTO').AsInteger := AIdInsumo;
      Qry.Open;

      if (not Qry.IsEmpty) and (not Qry.FieldByName('VALOR_MEDIO').IsNull) then
        Result := Qry.FieldByName('VALOR_MEDIO').AsFloat;
    finally
      Qry.Free;
    end;

    if Result < 0 then
    begin
      Qry := TFDQuery.Create(nil);
      try
        Qry.Connection := Conn;
        Qry.SQL.Text :=
          'SELECT VALORKG ' +
          'FROM RACAOINSUMOS r ' +
          'WHERE r.IDRACAO = :IDRACAO ' +
          '  AND r.IDINSUMOALIMENTO = :IDINSUMOALIMENTO';
        Qry.ParamByName('IDRACAO').AsInteger := AIdRacao;
        Qry.ParamByName('IDINSUMOALIMENTO').AsInteger := AIdInsumo;
        Qry.Open;

        if (not Qry.IsEmpty) and (not Qry.FieldByName('VALORKG').IsNull) then
          Result := Qry.FieldByName('VALORKG').AsFloat
        else
          Result := 0;
      finally
        Qry.Free;
      end;
    end;
  end;

begin
  dmGlobal := nil;
  Body := nil;
  Conn := nil;
  Q := nil;
  RespJson := nil;

  try
    Body := TJSONObject.ParseJSONValue(Req.Body) as TJSONObject;
    if not Assigned(Body) then
      raise Exception.Create('JSON inválido.');

    IdLocalFab    := JSONStrFirst(Body, ['id', 'id_local', 'ID_LOCAL']);
    HandoffId     := JSONStrFirst(Body, ['handoff_id', 'HANDOFF_ID'], IdLocalFab);
    IdFazenda     := JSONIntFirst(Body, ['id_fazenda', 'ID_PROPRIEDADE', 'id_propriedade']);
    IdDieta       := JSONIntFirst(Body, ['id_dieta', 'IDRACAO', 'ID_RACAO', 'id_racao', 'ID_DIETA', 'ID']);
    IdUsuario     := JSONIntFirst(Body, ['id_usuario', 'ID_USUARIO']);
    IdOperador    := JSONIntFirst(Body, ['id_operador', 'ID_OPERADOR'], IdUsuario);
    DataFab       := StrToDateBR(JSONStrFirst(Body, ['data', 'DATA_FAB', 'data_fabricacao']));
    QtdePrevista  := StrToFloatBR(JSONStrFirst(Body, ['qtde_prevista', 'KG_PREVISTO', 'qtd_prevista']));
    QtdeRealizada := StrToFloatBR(JSONStrFirst(Body, ['qtde_realizada', 'KG_REALIZADO', 'qtd_realizada', 'kg_realizado']));
    Itens         := JSONArrayFirst(Body, ['itens', 'FABRICACAO_INSUMOS', 'insumos']);
    Fornecimentos := JSONArrayFirst(Body, ['fornecimentos', 'FORNECIMENTO_CONF']);
    HoraInicioFab := ParseHoraRef(JSONStrFirst(Body, ['hora_inicio', 'HORA_INICIO']));
    HoraFimFab := ParseHoraRef(JSONStrFirst(Body, ['hora_fim', 'HORA_FIM']));

    if IdFazenda <= 0 then
      raise Exception.Create('Campo id_fazenda/ID_PROPRIEDADE inválido.');
    if IdDieta <= 0 then
      raise Exception.Create(
        'Campo id_dieta/IDRACAO/ID inválido. Informe IDRACAO (ou id_dieta) com ID numérico da ração.'
      );
    if IdUsuario <= 0 then
      raise Exception.Create('Campo id_usuario/ID_USUARIO inválido.');

    dmGlobal := TdmFieldPec.Create(nil);
    dmGlobal.ConectaDBField;
    Conn := dmGlobal.FBCon;

    if not Conn.Connected then
      Conn.Connected := True;

    if not Conn.InTransaction then
      Conn.StartTransaction;

    try
      ItensProcessados := 0;
      FornecimentosProcessados := 0;
      IdServidorFab := 0;
      LoteFabricacao := '';

      ValorKgRacao := BuscarValorKgRacao(IdDieta);
      CustoTotal := QtdeRealizada * ValorKgRacao;

      IdServidorFab := InserirFabricacaoComIdSeguro(
        Conn, IdDieta, IdFazenda, IdUsuario, IdOperador, DataFab,
        QtdePrevista, QtdeRealizada, CustoTotal);

      LoteFabricacao := IntToStr(IdServidorFab);

      Q := TFDQuery.Create(nil);
      try
        Q.Connection := Conn;
        Q.SQL.Text :=
          'UPDATE FABRICACAO ' +
          'SET LOTE_FABRICACAO = :LOTE_FABRICACAO, ' +
          '    HORA_INICIO = :HORA_INICIO, ' +
          '    HORA_FIM = :HORA_FIM ' +
          'WHERE ID = :ID';
        Q.ParamByName('LOTE_FABRICACAO').AsString := LoteFabricacao;
        Q.ParamByName('ID').AsInteger := IdServidorFab;
        SetParamHoraOpcional(Q, 'HORA_INICIO', HoraInicioFab);
        SetParamHoraOpcional(Q, 'HORA_FIM', HoraFimFab);
        Q.ExecSQL;
      finally
        FreeAndNil(Q);
      end;

      Q := TFDQuery.Create(nil);
      try
        Q.Connection := Conn;
        Q.SQL.Text := 'DELETE FROM FABRICACAO_INSUMOS WHERE ID_FABRICACAO = :ID_FABRICACAO';
        Q.ParamByName('ID_FABRICACAO').AsInteger := IdServidorFab;
        Q.ExecSQL;
      finally
        FreeAndNil(Q);
      end;

      if Assigned(Itens) and (Itens.Count > 0) then
        ItensProcessados := ProcessarItensFabricacao(
          Conn, IdServidorFab, IdDieta, IdUsuario, DataFab, Itens);

      if Assigned(Fornecimentos) and (Fornecimentos.Count > 0) then
      begin
        for IdxForn := 0 to Fornecimentos.Count - 1 do
        begin
          if not (Fornecimentos.Items[IdxForn] is TJSONObject) then
            Continue;

          Forn := TJSONObject(Fornecimentos.Items[IdxForn]);

          IdCurral := StrToIntSafe(JSONStr(Forn, 'IDCURRAL'));
          if IdCurral <= 0 then
            IdCurral := StrToIntSafe(JSONStr(Forn, 'idcurral'));
          if IdCurral <= 0 then
            IdCurral := StrToIntSafe(JSONStr(Forn, 'id_curral'));

          HoraForn := JSONStr(Forn, 'HORA_FORN');
          if HoraForn = '' then
            HoraForn := JSONStr(Forn, 'hora_forn');
          if HoraForn = '' then
            HoraForn := JSONStrFirst(Forn, ['hora_fim', 'HORA_FIM']);
          if HoraForn = '' then
            HoraForn := JSONStrFirst(Forn, ['hora_inicio', 'HORA_INICIO']);
          if HoraForn = '' then
            HoraForn := '00:00:00';

          if JSONStr(Forn, 'DATA_FORN') <> '' then
            DataForn := StrToDateBR(JSONStr(Forn, 'DATA_FORN'))
          else if JSONStr(Forn, 'data_forn') <> '' then
            DataForn := StrToDateBR(JSONStr(Forn, 'data_forn'))
          else
            DataForn := DataFab;

          Trato := StrToIntSafe(JSONStr(Forn, 'TRATO'));
          if Trato <= 0 then
            Trato := StrToIntSafe(JSONStr(Forn, 'trato'));

          IdMotorista := JSONIntFirst(Forn, ['id_tratador', 'ID_MOTORISTA', 'id_usuario_lancamento', 'ID_USUARIO']);

          IdRacaoRealizada := JSONIntFirst(Forn, ['id_dieta_realizada', 'ID_RACAO', 'id_racao', 'IDRACAO', 'ID_DIETA']);
          if IdRacaoRealizada <= 0 then
            IdRacaoRealizada := IdDieta;

          Realizado := StrToFloatBR(JSONStrFirst(Forn, ['realizado', 'REALIZADO_MN_KG', 'REALIZADO']));

          if IdCurral <= 0 then
            raise Exception.CreateFmt('Fornecimento %d sem IDCURRAL.', [IdxForn + 1]);
          if Trato <= 0 then
            raise Exception.CreateFmt('Fornecimento %d sem TRATO.', [IdxForn + 1]);
          if IdMotorista <= 0 then
            raise Exception.CreateFmt('Fornecimento %d sem id_tratador/ID_MOTORISTA.', [IdxForn + 1]);
          if IdRacaoRealizada <= 0 then
            raise Exception.CreateFmt('Fornecimento %d sem id_dieta_realizada/ID_RACAO.', [IdxForn + 1]);

          CustoTotalTrato := Realizado * BuscarValorKgRacao(IdRacaoRealizada);

          QtdCab := 0;
          Q := TFDQuery.Create(nil);
          try
            Q.Connection := Conn;
            Q.SQL.Text :=
              'SELECT QTDE_CAB ' +
              'FROM LOTE_NUTRICIONAL ' +
              'WHERE STATUS = 1 AND ID_LOCAL = :ID_LOCAL';
            Q.ParamByName('ID_LOCAL').AsInteger := IdCurral;
            Q.Open;

            if (not Q.IsEmpty) and (not Q.FieldByName('QTDE_CAB').IsNull) then
              QtdCab := Q.FieldByName('QTDE_CAB').AsFloat;
          finally
            FreeAndNil(Q);
          end;

          ValorFabricadoD := 0;
          Q := TFDQuery.Create(nil);
          try
            Q.Connection := Conn;
            Q.SQL.Text :=
              'SELECT SUM(fi.CUSTO) / NULLIF(SUM(fi.KG_FABRICADO), 0) AS valorfab ' +
              'FROM FABRICACAO_INSUMOS fi ' +
              'JOIN FABRICACAO f ON f.ID = fi.ID_FABRICACAO ' +
              'WHERE f.LOTE_FABRICACAO = :LOTE_FAB';
            Q.ParamByName('LOTE_FAB').AsString := LoteFabricacao;
            Q.Open;

            if (not Q.IsEmpty) and (not Q.FieldByName('valorfab').IsNull) then
              ValorFabricadoD := Q.FieldByName('valorfab').AsFloat;
          finally
            FreeAndNil(Q);
          end;

          IdFornecimento := 0;
          IdLote := 0;
          RealizadoAtual := 0;
          MsRacaoAtual := 0;
          MediaPeso := 0;

          Q := TFDQuery.Create(nil);
          try
            Q.Connection := Conn;
            Q.SQL.Text :=
              'SELECT ID, ID_LOTE, REALIZADO_MN_KG, MEDIA_PESO, MS_RACAO ' +
              'FROM FORNECIMENTO_CONF fc ' +
              'WHERE fc.DATA_FORN = :DATA_FORN ' +
              '  AND fc.STATUS = 1 ' +
              '  AND fc.ID_LOCAL = :ID_LOCAL ' +
              '  AND fc.TRATO = :TRATO ' +
              '  AND fc.ID_RACAO = :ID_RACAO';
            Q.ParamByName('DATA_FORN').AsDate := DataForn;
            Q.ParamByName('ID_LOCAL').AsInteger := IdCurral;
            Q.ParamByName('TRATO').AsInteger := Trato;
            Q.ParamByName('ID_RACAO').AsInteger := IdRacaoRealizada;
            Q.Open;

            if Q.IsEmpty then
              raise Exception.CreateFmt(
                'Nenhum FORNECIMENTO_CONF encontrado para fornecimento %d (data=%s, curral=%d, trato=%d, racao=%d).',
                [IdxForn + 1, DateToStr(DataForn), IdCurral, Trato, IdRacaoRealizada]
              );

            IdFornecimento := Q.FieldByName('ID').AsInteger;
            IdLote := Q.FieldByName('ID_LOTE').AsInteger;

            if not Q.FieldByName('REALIZADO_MN_KG').IsNull then
              RealizadoAtual := Q.FieldByName('REALIZADO_MN_KG').AsFloat;

            if not Q.FieldByName('MS_RACAO').IsNull then
              MsRacaoAtual := Q.FieldByName('MS_RACAO').AsFloat;

            if not Q.FieldByName('MEDIA_PESO').IsNull then
              MediaPeso := Q.FieldByName('MEDIA_PESO').AsFloat;
          finally
            FreeAndNil(Q);
          end;

          if MediaPeso <= 0 then
          begin
            Q := TFDQuery.Create(nil);
            try
              Q.Connection := Conn;
              Q.SQL.Text :=
                'SELECT AVG((SELECT PESOPROJ FROM RETORNA_GMD_ACUMULADO(A.ID, :VDATA))) AS MEDIA_PESO ' +
                'FROM ANIMAL A ' +
                'WHERE STATUS = 1 AND ID_LOCAL = :ID_LOCAL';
              Q.ParamByName('VDATA').AsDate := DataForn;
              Q.ParamByName('ID_LOCAL').AsInteger := IdCurral;
              Q.Open;

              if (not Q.IsEmpty) and (not Q.FieldByName('MEDIA_PESO').IsNull) then
                MediaPeso := Q.FieldByName('MEDIA_PESO').AsFloat;
            finally
              FreeAndNil(Q);
            end;
          end;

          Q := TFDQuery.Create(nil);
          try
            Q.Connection := Conn;
            Q.SQL.Text :=
              'UPDATE FORNECIMENTO_CONF SET ' +
              '  LOTE_FABRICACAO = :LOTE_FABRICACAO, ' +
              '  ID_MOTORISTA = :ID_MOTORISTA, ' +
              '  HORA_FORN = :HORA_FORN, ' +
              '  QTD_CAB = :QTD_CAB, ' +
              '  REALIZADO_MN_KG = :REALIZADO_MN_KG, ' +
              '  DATA_ALTERACAO = CURRENT_TIMESTAMP, ' +
              '  ID_USUARIO_ALTERACAO = :ID_USUARIO_ALTERACAO, ' +
              '  MEDIA_PESO = :MEDIA_PESO, ' +
              '  VALOR_KG_RACAO = :VALOR_KG_RACAO, ' +
              '  CUSTO_TOTAL_TRATO = :CUSTO_TOTAL_TRATO ' +
              'WHERE ID = :ID';

            Q.ParamByName('LOTE_FABRICACAO').AsString := LoteFabricacao;
            Q.ParamByName('ID_MOTORISTA').AsInteger := IdMotorista;
            Q.ParamByName('HORA_FORN').AsDateTime := Frac(ParseHoraRef(HoraForn));
            Q.ParamByName('QTD_CAB').AsFloat := QtdCab;
            Q.ParamByName('REALIZADO_MN_KG').AsFloat := RealizadoAtual + Realizado;
            Q.ParamByName('ID_USUARIO_ALTERACAO').AsInteger := IdMotorista;
            Q.ParamByName('MEDIA_PESO').AsFloat := MediaPeso;

            if ValorFabricadoD > 0 then
            begin
              Q.ParamByName('VALOR_KG_RACAO').AsFloat := ValorFabricadoD;
              Q.ParamByName('CUSTO_TOTAL_TRATO').AsFloat := Realizado * ValorFabricadoD;
            end
            else
            begin
              Q.ParamByName('VALOR_KG_RACAO').AsFloat := 0;
              Q.ParamByName('CUSTO_TOTAL_TRATO').AsFloat := CustoTotalTrato;
            end;

            Q.ParamByName('ID').AsInteger := IdFornecimento;
            Q.ExecSQL;
          finally
            FreeAndNil(Q);
          end;

          Q := TFDQuery.Create(nil);
          try
            Q.Connection := Conn;
            Q.SQL.Text :=
              'UPDATE DET_LOTE_PLANEJAMENTO SET UTILIZADO = 1 ' +
              'WHERE DATA = :DATA ' +
              '  AND TRATO = :TRATO ' +
              '  AND ID_LOTE = :ID_LOTE';
            Q.ParamByName('DATA').AsDate := DataForn;
            Q.ParamByName('TRATO').AsInteger := Trato;
            Q.ParamByName('ID_LOTE').AsInteger := IdLote;
            Q.ExecSQL;
          finally
            FreeAndNil(Q);
          end;

          if Realizado > 0 then
          begin
            Q := TFDQuery.Create(nil);
            try
              Q.Connection := Conn;
              Q.SQL.Text := 'DELETE FROM ANIMAL_FORNECIMENTO_CONF WHERE ID_FORNECIMENTO = :ID_FORNECIMENTO';
              Q.ParamByName('ID_FORNECIMENTO').AsInteger := IdFornecimento;
              Q.ExecSQL;
            finally
              FreeAndNil(Q);
            end;

            Q := TFDQuery.Create(nil);
            try
              Q.Connection := Conn;
              Q.SQL.Text :=
                'INSERT INTO ANIMAL_FORNECIMENTO_CONF ( ' +
                '  ID_ANIMAL, ID_FORNECIMENTO, DATA_FORNECIMENTO, TRATO, ID_LOTE, ID_CURRAL, ' +
                '  CONSUMO_MN, CONSUMO_MS, IMS_PV, CUSTO, PESO_MEDIO, ID_RACAO ' +
                ') ' +
                'SELECT ' +
                '  B.ID, ' +
                '  A.ID, ' +
                '  A.DATA_FORN, ' +
                '  A.TRATO, ' +
                '  A.ID_LOTE, ' +
                '  A.ID_LOCAL, ' +
                '  CAST(A.REALIZADO_MN_KG AS DOUBLE PRECISION) / NULLIF(CAST(A.QTD_CAB AS DOUBLE PRECISION), 0), ' +
                '  CAST(A.REALIZADO_MN_KG AS DOUBLE PRECISION) / NULLIF(CAST(A.QTD_CAB AS DOUBLE PRECISION), 0) * (CAST(A.MS_RACAO AS DOUBLE PRECISION) / 100), ' +
                '  (((CAST(A.REALIZADO_MN_KG AS DOUBLE PRECISION) / NULLIF(A.QTD_CAB, 0)) * (CAST(A.MS_RACAO AS DOUBLE PRECISION) / 100) * 100) / NULLIF(CAST(A.MEDIA_PESO AS DOUBLE PRECISION), 0)), ' +
                '  A.CUSTO_TOTAL_TRATO / NULLIF(A.QTD_CAB, 0), ' +
                '  A.MEDIA_PESO, ' +
                '  A.ID_RACAO ' +
                'FROM FORNECIMENTO_CONF A ' +
                'JOIN ANIMAL B ON A.ID_LOCAL = B.ID_LOCAL ' +
                'WHERE B.STATUS = 1 ' +
                '  AND A.ID = :ID_FORNECIMENTO';
              Q.ParamByName('ID_FORNECIMENTO').AsInteger := IdFornecimento;
              Q.ExecSQL;
            finally
              FreeAndNil(Q);
            end;
          end;

          Inc(FornecimentosProcessados);
        end;
      end;

      Conn.Commit;

      RespJson := TJSONObject.Create;
      RespJson.AddPair('success', TJSONBool.Create(True));
      RespJson.AddPair('id_local', IdLocalFab);
      RespJson.AddPair('handoff_id', HandoffId);
      RespJson.AddPair('id_servidor', TJSONNumber.Create(IdServidorFab));
      RespJson.AddPair('lote_fabricacao', LoteFabricacao);
      RespJson.AddPair('itens_processados', TJSONNumber.Create(ItensProcessados));
      RespJson.AddPair('fornecimentos_processados', TJSONNumber.Create(FornecimentosProcessados));

      Res.Status(201).Send<TJSONObject>(RespJson);
      MirrorPostBody('/Post/Fabricacao', Body, RespJson.ToJSON, 201);
      RespJson := nil;
    except
      on E: Exception do
      begin
        if Assigned(Conn) and Conn.InTransaction then
          Conn.Rollback;

        RespJson := TJSONObject.Create;
        RespJson.AddPair('success', TJSONBool.Create(False));
        RespJson.AddPair('message', 'Erro ao salvar fabricação.');
        RespJson.AddPair('error', E.Message);
        RespJson.AddPair('id_local', IdLocalFab);
        RespJson.AddPair('handoff_id', HandoffId);

        Res.Status(500).Send<TJSONObject>(RespJson);
        RespJson := nil;
      end;
    end;

  finally
    Body.Free;
    Q.Free;
    RespJson.Free;
    dmGlobal.Free;
  end;
end;

end.
