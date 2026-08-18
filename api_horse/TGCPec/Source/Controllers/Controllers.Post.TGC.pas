unit Controllers.Post.TGC;

interface

uses
  Horse,
  System.JSON,
  System.SysUtils,
  FireDAC.Comp.Client;

procedure RegistraRotas;

implementation

uses
  System.Classes,
  System.DateUtils,
  System.IniFiles,
  System.IOUtils,
  UdmTGC,
  Controllers.Mirror;

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
end;

function StrToFloatBR(const S: string): Double;
var
  L: string;
  FS: TFormatSettings;
  PosDot, PosComma: Integer;
begin
  L := Trim(S);
  if L = '' then
    Exit(0);
  FS := TFormatSettings.Create;
  FS.DecimalSeparator := '.';
  FS.ThousandSeparator := #0;

  PosDot := LastDelimiter('.', L);
  PosComma := LastDelimiter(',', L);

  if (PosDot > 0) and (PosComma > 0) then
  begin
    // ambos presentes: o ultimo separador e o decimal
    if PosComma > PosDot then
    begin
      // BR: 1.234,56 -> remove milhar (ponto), virgula vira ponto
      L := StringReplace(L, '.', '', [rfReplaceAll]);
      L := StringReplace(L, ',', '.', [rfReplaceAll]);
    end
    else
    begin
      // US: 1,234.56 -> remove milhar (virgula)
      L := StringReplace(L, ',', '', [rfReplaceAll]);
    end;
  end
  else if PosComma > 0 then
    // so virgula: decimal BR
    L := StringReplace(L, ',', '.', [rfReplaceAll]);
  // so ponto (ou sem separador): ja e decimal com ponto (ex.: "52.000" = 52,0)

  Result := StrToFloat(L, FS);
end;

function NormalizeDecimalStr(const S: string): string;
var
  FS: TFormatSettings;
begin
  FS := TFormatSettings.Create;
  FS.DecimalSeparator := '.';
  Result := FloatToStr(StrToFloatBR(S), FS);
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

procedure SetParamAsFloatBR(Q: TFDQuery; const ParamName, Value: string);
begin
  Q.ParamByName(ParamName).AsFloat := StrToFloatBR(Value);
end;

function ParseQtde(const S: string): Double;
var
  Txt: string;
  FS: TFormatSettings;
begin
  Txt := Trim(S);
  if Txt = '' then
    Exit(0);
  Txt := StringReplace(Txt, ',', '.', [rfReplaceAll]);
  FS := TFormatSettings.Create;
  FS.DecimalSeparator := '.';
  FS.ThousandSeparator := #0;
  Result := StrToFloat(Txt, FS);
end;

procedure SetParamAsIntRound(Q: TFDQuery; const ParamName, Value: string);
begin
  Q.ParamByName(ParamName).AsInteger := Round(ParseQtde(Value));
end;

function LookupNomeOperador(Conn: TFDConnection; const CodOperador: string): string;
var
  Q: TFDQuery;
begin
  Result := '';
  if Trim(CodOperador) = '' then
    Exit;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;
    Q.SQL.Text := 'SELECT CF_NOME FROM CAD_FUNCIONARIO WHERE CF_CODIGO = :COD';
    Q.ParamByName('COD').AsInteger := StrToIntDef(CodOperador, 0);
    Q.Open;
    if not Q.Eof then
      Result := Q.FieldByName('CF_NOME').AsString;
  finally
    Q.Free;
  end;
end;

function ResolveMotoristaNome(Conn: TFDConnection; const AItem: TJSONObject): string;
var
  IdMot, CfornMot: string;
begin
  Result := Trim(JSONStrFirst(AItem, ['nome_motorista', 'motorista_nome']));
  if Result <> '' then
    Exit;

  IdMot := Trim(JSONStrFirst(AItem,
    ['id_tratador', 'id_usuario_lancamento', 'id_motorista']));
  CfornMot := Trim(JSONStrFirst(AItem, ['CFORN_MOTORISTA']));

  if (CfornMot <> '') and (not SameText(CfornMot, IdMot)) then
  begin
    Result := CfornMot;
    Exit;
  end;

  if IdMot <> '' then
    Result := LookupNomeOperador(Conn, IdMot);
end;

function LookupCustoKgInsumo(Conn: TFDConnection; const CodRacao, CodAlimento: string): Double;
var
  Q: TFDQuery;
begin
  Result := 0;
  if (Trim(CodRacao) = '') or (Trim(CodAlimento) = '') then
    Exit;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;
    Q.SQL.Text :=
      'SELECT DETRAP_VALOR FROM DET_ALIM_RACAO_PROD ' +
      'WHERE DETRAP_CODRACAOPROD = :ID_RACAO AND DETRAP_CODALIMENTO = :ID_INSUMO';
    Q.ParamByName('ID_RACAO').AsInteger := StrToIntDef(CodRacao, 0);
    Q.ParamByName('ID_INSUMO').AsInteger := StrToIntDef(CodAlimento, 0);
    Q.Open;
    if not Q.Eof then
      Result := Q.FieldByName('DETRAP_VALOR').AsFloat;
  finally
    Q.Free;
  end;
end;

function LookupCustoKgRacao(Conn: TFDConnection; const CodRacaoProd: string): Double;
var
  Q: TFDQuery;
begin
  Result := 0;
  if Trim(CodRacaoProd) = '' then
    Exit;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;
    Q.SQL.Text :=
      'SELECT FIRST 1 CUR_CMR_MN FROM CAD_CUSTO_RACAO ' +
      'WHERE CUR_COD_RACAOPROD = :COD ORDER BY CUR_DATA DESC';
    Q.ParamByName('COD').AsInteger := StrToIntDef(CodRacaoProd, 0);
    Q.Open;
    if not Q.Eof then
      Result := Q.FieldByName('CUR_CMR_MN').AsFloat;
  finally
    Q.Free;
  end;
end;

procedure SetParamAsIntStr(Q: TFDQuery; const ParamName, Value: string;
  const DefaultIfEmpty: Integer = 0);
var
  Txt: string;
begin
  Txt := Trim(Value);
  if Txt = '' then
    Q.ParamByName(ParamName).AsInteger := DefaultIfEmpty
  else
    Q.ParamByName(ParamName).AsInteger := StrToIntDef(Txt, DefaultIfEmpty);
end;

procedure SetParamAsDateBR(Q: TFDQuery; const ParamName, Value: string);
begin
  if Trim(Value) = '' then
    Q.ParamByName(ParamName).Clear
  else
    Q.ParamByName(ParamName).AsDate := StrToDateBR(Value);
end;

procedure SetParamAsTimeStr(Q: TFDQuery; const ParamName, Value: string);
var
  T: TDateTime;
begin
  if Trim(Value) = '' then
  begin
    Q.ParamByName(ParamName).Clear;
    Exit;
  end;
  T := ParseHoraRef(Value);
  if T > 0 then
    Q.ParamByName(ParamName).AsTime := T
  else
    Q.ParamByName(ParamName).Clear;
end;

function TgcUsuarioId: string;
begin
  Result := '1';
end;

function ResolveTgcOperadorId(const Obj: TJSONObject;
  const ExtraKeys: array of string): string;
begin
  Result := JSONStrFirst(Obj, ExtraKeys);
  if Trim(Result) = '' then
    raise Exception.Create('id_operador ausente (selecione o operador na fabricacao).');
end;

function JSONArrayFirst(const Obj: TJSONObject; const Keys: array of string): TJSONArray;
var
  I: Integer;
  V: TJSONValue;
begin
  Result := nil;
  if Obj = nil then
    Exit;
  for I := 0 to High(Keys) do
  begin
    V := Obj.Values[Keys[I]];
    if Assigned(V) and (V is TJSONArray) then
      Exit(TJSONArray(V));
  end;
end;

function TgcApiConfigIniPath: string;
begin
  Result := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'ApiConfig.ini';
  if not FileExists(Result) then
    Result := IncludeTrailingPathDelimiter(GetCurrentDir) + 'ApiConfig.ini';
end;

function ReadTgcIniGenerator(const IniKey: string): string;
var
  LIni: TIniFile;
  LPath: string;
begin
  Result := '';
  LPath := TgcApiConfigIniPath;
  if not FileExists(LPath) then
    Exit;
  LIni := TIniFile.Create(LPath);
  try
    Result := UpperCase(Trim(LIni.ReadString('TGC', IniKey, '')));
  finally
    LIni.Free;
  end;
end;

function GeneratorExists(Conn: TFDConnection; const GenName: string): Boolean;
var
  Q: TFDQuery;
  N: string;
begin
  Result := False;
  N := UpperCase(Trim(GenName));
  if N = '' then
    Exit;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;
    Q.SQL.Text :=
      'SELECT COUNT(*) AS C FROM RDB$GENERATORS ' +
      'WHERE RDB$SYSTEM_FLAG = 0 AND RDB$GENERATOR_NAME = :N';
    Q.ParamByName('N').AsString := N;
    Q.Open;
    Result := Q.FieldByName('C').AsInteger > 0;
  finally
    Q.Free;
  end;
end;

function ResolveTgcGeneratorName(const IniKey: string): string;
begin
  Result := ReadTgcIniGenerator(IniKey);
end;

function FindExistingGenerator(
  Conn: TFDConnection;
  const CandidateNames: array of string): string;
var
  I: Integer;
  N: string;
begin
  Result := '';
  for I := 0 to High(CandidateNames) do
  begin
    N := UpperCase(Trim(CandidateNames[I]));
    if (N <> '') and GeneratorExists(Conn, N) then
      Exit(N);
  end;
end;

function TableMaxId(Conn: TFDConnection; const TableName, IdColumn: string): Int64;
var
  Q: TFDQuery;
begin
  Result := 0;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;
    Q.SQL.Text := Format(
      'SELECT COALESCE(MAX(%s), 0) AS MX FROM %s',
      [IdColumn, TableName]);
    Q.Open;
    Result := Q.FieldByName('MX').AsLargeInt;
  finally
    Q.Free;
  end;
end;

procedure SyncGeneratorToTableMax(
  Conn: TFDConnection;
  const GeneratorName, TableName, IdColumn: string);
var
  Q: TFDQuery;
  MaxId, CurGen: Int64;
  Gen: string;
begin
  Gen := UpperCase(Trim(GeneratorName));
  if (Gen = '') or not GeneratorExists(Conn, Gen) then
    Exit;

  MaxId := TableMaxId(Conn, TableName, IdColumn);
  if MaxId < 0 then
    MaxId := 0;

  // valor atual do generator (incremento 0 nao altera o valor)
  CurGen := 0;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;
    Q.SQL.Text := Format('SELECT GEN_ID(%s, 0) AS CUR FROM RDB$DATABASE', [Gen]);
    Q.Open;
    CurGen := Q.FieldByName('CUR').AsLargeInt;
  finally
    Q.Free;
  end;

  // so SOBE o generator; nunca abaixa (evita colisao com IDs ja alocados pelo ERP TGC)
  if CurGen >= MaxId then
    Exit;

  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;
    Q.SQL.Text := Format('SET GENERATOR %s TO %d', [Gen, MaxId]);
    Q.ExecSQL;
  finally
    Q.Free;
  end;
end;

procedure SyncTgcFabricacaoGenerators(Conn: TFDConnection);
const
  CadBatidaFallback: array[0..4] of string = (
    'AUT_CAD_BATIDA', 'GEN_CAD_BATIDA', 'GEN_CBT_CODIGO', 'CAD_BATIDA_GEN', 'GEN_CBT');
  DetBatidaFallback: array[0..4] of string = (
    'AUT_DET_BATIDA', 'GEN_DET_BATIDA', 'GEN_DBT_CODIGO', 'DET_BATIDA_GEN', 'GEN_DBT');
var
  GenCad, GenDet: string;
begin
  GenCad := ResolveTgcGeneratorName('GenCadBatida');
  if (GenCad = '') or not GeneratorExists(Conn, GenCad) then
    GenCad := FindExistingGenerator(Conn, CadBatidaFallback);

  GenDet := ResolveTgcGeneratorName('GenDetBatida');
  if (GenDet = '') or not GeneratorExists(Conn, GenDet) then
    GenDet := FindExistingGenerator(Conn, DetBatidaFallback);

  SyncGeneratorToTableMax(Conn, GenCad, 'CAD_BATIDA', 'CBT_CODIGO');
  SyncGeneratorToTableMax(Conn, GenDet, 'DET_BATIDA', 'DBT_CODIGO');
end;

function AllocateTgcTableId(
  Conn: TFDConnection;
  const TableName, IdColumn, IniGenKey: string;
  const FallbackGenNames: array of string): Integer;
var
  Q: TFDQuery;
  GenName: string;
  UsedMaxFallback: Boolean;
begin
  Result := 0;
  UsedMaxFallback := False;

  GenName := ResolveTgcGeneratorName(IniGenKey);
  if (GenName = '') or not GeneratorExists(Conn, GenName) then
    GenName := FindExistingGenerator(Conn, FallbackGenNames);

  SyncGeneratorToTableMax(Conn, GenName, TableName, IdColumn);

  if GenName <> '' then
  begin
    Q := TFDQuery.Create(nil);
    try
      Q.Connection := Conn;
      Q.SQL.Text := Format('SELECT GEN_ID(%s, 1) AS NX FROM RDB$DATABASE', [GenName]);
      Q.Open;
      Result := Q.FieldByName('NX').AsInteger;
      if Result > 0 then
        Exit;
    finally
      Q.Free;
    end;
  end;

  UsedMaxFallback := True;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;
    Q.SQL.Text := Format(
      'SELECT COALESCE(MAX(%s), 0) + 1 AS NX FROM %s',
      [IdColumn, TableName]);
    Q.Open;
    Result := Q.FieldByName('NX').AsInteger;
    if Result <= 0 then
      Result := 1;
  finally
    Q.Free;
  end;

  if UsedMaxFallback then
    SyncGeneratorToTableMax(Conn, GenName, TableName, IdColumn);
end;

function RetornaMaxIDFabricacaoTGC(Conn: TFDConnection): string;
begin
  Result := IntToStr(TableMaxId(Conn, 'CAD_BATIDA', 'CBT_CODIGO'));
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

function CompactLoteRef(const S: string): string;
begin
  Result := UpperCase(StringReplace(StringReplace(Trim(S), '-', '', [rfReplaceAll]),
    ' ', '', [rfReplaceAll]));
end;

function TruncateLoteTGC(const S: string; const MaxLen: Integer): string;
var
  L: string;
begin
  L := CompactLoteRef(S);
  if L = '' then
    Exit('');
  if Length(L) > MaxLen then
    SetLength(L, MaxLen);
  Result := L;
end;

function ResolveLoteFabricacaoTGC(const Obj: TJSONObject; const MaxLen: Integer): string;
begin
  // Nao usar 'id'/'id_fornecimento' como lote — cada trato tem CFORN_CODIGO
  // diferente e isso gerava lote errado no mesmo carregamento.
  Result := TruncateLoteTGC(
    JSONStrFirst(Obj,
      ['lote_fabricacao', 'CBT_LOTE_FABRICACAO', 'CFORN_LOTE_FABRICACAO',
       'handoff_id', 'handoff_id_fabricacao', 'id_local']),
    MaxLen);
end;

procedure PostGravaTag(Req: THorseRequest; Res: THorseResponse; Next: TProc); forward;
procedure PostFabricacao(Req: THorseRequest; Res: THorseResponse; Next: TProc); forward;
procedure PostFabricacaoInsumo(Req: THorseRequest; Res: THorseResponse; Next: TProc); forward;
procedure PostFornecimento(Req: THorseRequest; Res: THorseResponse; Next: TProc); forward;
procedure PostFornecimentoAudit(Req: THorseRequest; Res: THorseResponse; Next: TProc); forward;
procedure PostFabricacaoAudit(Req: THorseRequest; Res: THorseResponse; Next: TProc); forward;

function ExtractStrCI(const Obj: TJSONObject; const Keys: array of string): string;
var
  Pair: TJSONPair;
  k: string;
begin
  Result := '';
  if not Assigned(Obj) then
    Exit;
  for k in Keys do
    for Pair in Obj do
      if SameText(Pair.JsonString.Value, k) then
      begin
        Result := JSONValueToStr(Pair.JsonValue);
        Exit;
      end;
end;

procedure RegistraRotas;
begin
  THorse.Post('/Post/Fornecimento', PostFornecimento);
  THorse.Post('/Post/Fabricacao', PostFabricacao);
  THorse.Post('/Post/Fabricacao_Insumo', PostFabricacaoInsumo);
  THorse.Post('/Post/GravaTag', PostGravaTag);
  THorse.Post('/Post/FornecimentoAudit', PostFornecimentoAudit);
  THorse.Post('/Post/FabricacaoAudit', PostFabricacaoAudit);
end;

procedure InsertFabricacaoTGC(
  Conn: TFDConnection;
  const CodRacaoProd, QtdeBatida: string;
  const CustoTotal: Double;
  const DataFab, HoraIni, HoraFim, Usuario,
    QtdePrevista, LoteFab, NomeOperador, CodOperadorPA, NomeMotorista: string;
  out IdBatida: string);
var
  Q: TFDQuery;
  NextId: Integer;
  NomeOp, NomeMot: string;
begin
  NomeOp := Trim(NomeOperador);
  if NomeOp = '' then
    NomeOp := LookupNomeOperador(Conn, CodOperadorPA);

  NomeMot := Trim(NomeMotorista);

  NextId := AllocateTgcTableId(
    Conn,
    'CAD_BATIDA',
    'CBT_CODIGO',
    'GenCadBatida',
    ['AUT_CAD_BATIDA', 'GEN_CAD_BATIDA', 'GEN_CBT_CODIGO', 'CAD_BATIDA_GEN', 'GEN_CBT']);

  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;
    Q.SQL.Text :=
      'INSERT INTO CAD_BATIDA ( ' +
      '  CBT_CODIGO, CBT_CODRACAOPROD, CBT_QTDEBATIDA, CBT_CUSTO, CBT_DATA, ' +
      '  CBT_INICIO, CBT_FIM, CBT_USUARIO, CBT_QTDEPREVISTA, CBT_LOTE_FABRICACAO, ' +
      '  CBT_NOMEOPERADOR, CBT_COD_OPERADOR_PA, CBT_NOME_MOTORISTA ' +
      ') VALUES ( ' +
      '  :CBT_CODIGO, :CBT_CODRACAOPROD, :CBT_QTDEBATIDA, :CBT_CUSTO, :CBT_DATA, ' +
      '  :CBT_INICIO, :CBT_FIM, :CBT_USUARIO, :CBT_QTDEPREVISTA, :CBT_LOTE_FABRICACAO, ' +
      '  :CBT_NOMEOPERADOR, :CBT_COD_OPERADOR_PA, :CBT_NOME_MOTORISTA ' +
      ')';
    Q.ParamByName('CBT_CODIGO').AsInteger := NextId;
    Q.ParamByName('CBT_CODRACAOPROD').AsString := CodRacaoProd;
    SetParamAsIntRound(Q, 'CBT_QTDEBATIDA', QtdeBatida);
    Q.ParamByName('CBT_CUSTO').AsFloat := CustoTotal;
    SetParamAsDateBR(Q, 'CBT_DATA', DataFab);
    SetParamAsTimeStr(Q, 'CBT_INICIO', HoraIni);
    SetParamAsTimeStr(Q, 'CBT_FIM', HoraFim);
    SetParamAsIntStr(Q, 'CBT_USUARIO', Usuario);
    SetParamAsIntRound(Q, 'CBT_QTDEPREVISTA', QtdePrevista);
    Q.ParamByName('CBT_LOTE_FABRICACAO').AsString := LoteFab;
    Q.ParamByName('CBT_NOMEOPERADOR').AsString := NomeOp;
    SetParamAsIntStr(Q, 'CBT_COD_OPERADOR_PA', CodOperadorPA);
    Q.ParamByName('CBT_NOME_MOTORISTA').AsString := NomeMot;
    Q.ExecSQL;
    IdBatida := IntToStr(NextId);
  finally
    Q.Free;
  end;
end;

procedure InsertFabricacaoInsumoTGC(
  Conn: TFDConnection;
  const Item: TJSONObject;
  const DefaultCodBatida, DefaultDataFab, DefaultUsuario,
    DefaultOperador, DefaultCodRacao: string);
var
  Q: TFDQuery;
  NextId: Integer;
  CodBatida, DataFab, Hora, HoraIni, HoraFim, MsInsumo: string;
  CodAlimento, Usuario, Operador, CodRacao: string;
  ValorKgInsumo, CustoInsumo: Double;
begin
  if Item = nil then
    Exit;

  NextId := AllocateTgcTableId(
    Conn,
    'DET_BATIDA',
    'DBT_CODIGO',
    'GenDetBatida',
    ['AUT_DET_BATIDA', 'GEN_DET_BATIDA', 'GEN_DBT_CODIGO', 'DET_BATIDA_GEN', 'GEN_DBT']);

  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;

    CodBatida := DefaultCodBatida;
    if CodBatida = '' then
      CodBatida := JSONStrFirst(Item, ['DBT_CODBATIDA'], '');
    if CodBatida = '' then
      raise Exception.Create('DBT_CODBATIDA ausente no insumo da fabricacao.');

    DataFab := JSONStrFirst(Item, ['data', 'DBT_DATA', 'DATA_FAB'], DefaultDataFab);
    if Trim(DataFab) = '' then
      raise Exception.Create('Data da fabricacao ausente no insumo.');

    HoraIni := JSONStrFirst(Item, ['hora_ini', 'DBT_HORA_INI', 'hora_inicio', 'HORA_INI']);
    HoraFim := JSONStrFirst(Item, ['hora_fim', 'DBT_HORA_FIM', 'HORA_FIM']);
    Hora := JSONStrFirst(Item, ['hora', 'DBT_HORA', 'HORA'], HoraIni);
    MsInsumo := JSONStrFirst(Item, ['ms_insumo', 'DBT_MS', 'DBT_PREV_MS'], '0');

    CodAlimento := JSONStrFirst(Item,
      ['id_insumo', 'DBT_CODALIMENTO', 'ID_ALIMENTO', 'id_alimento']);
    if Trim(CodAlimento) = '' then
      raise Exception.Create('id_insumo/DBT_CODALIMENTO ausente no item da fabricacao.');

    CodRacao := JSONStrFirst(Item, ['id_dieta', 'id_racao', 'IDRACAO'], DefaultCodRacao);
    ValorKgInsumo := LookupCustoKgInsumo(Conn, CodRacao, CodAlimento);
    CustoInsumo := ValorKgInsumo;

    Usuario := TgcUsuarioId;
    Operador := JSONStrFirst(Item,
      ['id_operador', 'DBT_CODOPERADOR', 'cod_operador'], DefaultOperador);
    if Trim(Operador) = '' then
      raise Exception.Create('id_operador ausente (selecione o operador na fabricacao).');

    Q.Close;
    Q.SQL.Text :=
      'INSERT INTO DET_BATIDA ( ' +
      '  DBT_CODIGO, DBT_CODBATIDA, DBT_CODALIMENTO, DBT_QTDE, DBT_USUARIO, DBT_CUSTO, ' +
      '  DBT_DATA, DBT_HORA, DBT_QTDEPREVISTA, DBT_PREV_MS, DBT_PREV_KGMNP, DBT_PREV_KGMSP, ' +
      '  DBT_PREV_VALOR_KG, DBT_PREV_VALOR_TOTAL, DBT_REAL_KGMSP, DBT_HORA_INI, ' +
      '  DBT_HORA_FIM, DBT_REAL_KGMNP, DBT_CODOPERADOR, DBT_MS ' +
      ') VALUES ( ' +
      '  :DBT_CODIGO, :DBT_CODBATIDA, :DBT_CODALIMENTO, :DBT_QTDE, :DBT_USUARIO, :DBT_CUSTO, ' +
      '  :DBT_DATA, :DBT_HORA, :DBT_QTDEPREVISTA, :DBT_PREV_MS, :DBT_PREV_KGMNP, :DBT_PREV_KGMSP, ' +
      '  :DBT_PREV_VALOR_KG, :DBT_PREV_VALOR_TOTAL, :DBT_REAL_KGMSP, :DBT_HORA_INI, ' +
      '  :DBT_HORA_FIM, :DBT_REAL_KGMNP, :DBT_CODOPERADOR, :DBT_MS ' +
      ')';
    Q.ParamByName('DBT_CODIGO').AsInteger := NextId;
    SetParamAsIntStr(Q, 'DBT_CODBATIDA', CodBatida);
    SetParamAsIntStr(Q, 'DBT_CODALIMENTO', CodAlimento);
    SetParamAsIntRound(Q, 'DBT_QTDE',
      JSONStrFirst(Item, ['qtd_realizada', 'DBT_QTDE', 'qtde_realizada'], '0'));
    SetParamAsIntStr(Q, 'DBT_USUARIO', Usuario);
    Q.ParamByName('DBT_CUSTO').AsFloat := CustoInsumo;
    SetParamAsDateBR(Q, 'DBT_DATA', DataFab);
    SetParamAsTimeStr(Q, 'DBT_HORA', Hora);
    SetParamAsIntRound(Q, 'DBT_QTDEPREVISTA',
      JSONStrFirst(Item, ['qtde_prevista', 'DBT_QTDEPREVISTA'], '0'));
    SetParamAsFloatBR(Q, 'DBT_PREV_MS', MsInsumo);
    SetParamAsFloatBR(Q, 'DBT_PREV_KGMNP',
      JSONStrFirst(Item, ['DBT_PREV_KGMNP', 'prev_kgmnp'], '0'));
    SetParamAsFloatBR(Q, 'DBT_PREV_KGMSP',
      JSONStrFirst(Item, ['DBT_PREV_KGMSP', 'prev_kgmsp'], '0'));
    SetParamAsFloatBR(Q, 'DBT_PREV_VALOR_KG',
      JSONStrFirst(Item, ['DBT_PREV_VALOR_KG', 'prev_valor_kg'], '0'));
    SetParamAsFloatBR(Q, 'DBT_PREV_VALOR_TOTAL',
      JSONStrFirst(Item, ['DBT_PREV_VALOR_TOTAL', 'prev_valor_total'], '0'));
    SetParamAsFloatBR(Q, 'DBT_REAL_KGMSP',
      JSONStrFirst(Item, ['DBT_REAL_KGMSP', 'real_kgmsp'], '0'));
    SetParamAsTimeStr(Q, 'DBT_HORA_INI', HoraIni);
    SetParamAsTimeStr(Q, 'DBT_HORA_FIM', HoraFim);
    SetParamAsFloatBR(Q, 'DBT_REAL_KGMNP',
      JSONStrFirst(Item, ['DBT_REAL_KGMNP', 'real_kgmnp'], '0'));
    SetParamAsIntStr(Q, 'DBT_CODOPERADOR', Operador);
    SetParamAsFloatBR(Q, 'DBT_MS', MsInsumo);
    Q.ExecSQL;
  finally
    Q.Free;
  end;
end;

procedure PostFabricacao(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  dm: TdmTGC;
  Body, Resp: TJSONObject;
  Itens: TJSONArray;
  IdBatida, DataFab, HoraIni, HoraFim, LoteFab, CodRacao, QtdeRealizadaStr: string;
  CustoKg, QtdeRealizada, CustoFab: Double;
  I: Integer;
  Item: TJSONObject;
begin
  dm := nil;
  Body := nil;
  Resp := nil;
  try
    Body := TJSONObject.ParseJSONValue(Req.Body) as TJSONObject;
    if not Assigned(Body) then
      raise Exception.Create('JSON inválido.');

    dm := TdmTGC.Create(nil);
    dm.ConectaDBTGC;

    CodRacao := JSONStrFirst(Body, ['id_dieta', 'CBT_CODRACAOPROD', 'IDRACAO']);
    QtdeRealizadaStr := JSONStrFirst(Body, ['qtde_realizada', 'CBT_QTDEBATIDA', 'qtd_realizada'], '0');
    QtdeRealizada := ParseQtde(QtdeRealizadaStr);
    CustoKg := LookupCustoKgRacao(dm.FBCon, CodRacao);
    CustoFab := CustoKg * QtdeRealizada;

    if not dm.FBCon.InTransaction then
      dm.FBCon.StartTransaction;

    try
      DataFab := JSONStrFirst(Body, ['data', 'CBT_DATA', 'DATA_FAB']);
      HoraIni := JSONStrFirst(Body, ['hora_inicio', 'CBT_INICIO', 'HORA_INICIO']);
      HoraFim := JSONStrFirst(Body, ['hora_fim', 'CBT_FIM', 'HORA_FIM']);
      LoteFab := ResolveLoteFabricacaoTGC(Body, 100);

      InsertFabricacaoTGC(
        dm.FBCon,
        CodRacao,
        QtdeRealizadaStr,
        CustoFab,
        DataFab,
        HoraIni,
        HoraFim,
        TgcUsuarioId,
        JSONStrFirst(Body, ['qtde_prevista', 'CBT_QTDEPREVISTA'], '0'),
        LoteFab,
        JSONStrFirst(Body, ['CBT_NOMEOPERADOR', 'nome_operador']),
        ResolveTgcOperadorId(Body, ['id_operador', 'CBT_COD_OPERADOR_PA']),
        ResolveMotoristaNome(dm.FBCon, Body),
        IdBatida);

      Itens := JSONArrayFirst(Body, ['itens', 'FabricacaoAlimentosTGC', 'TGCFabricacao']);
      if Assigned(Itens) then
      begin
        for I := 0 to Itens.Count - 1 do
        begin
          if not (Itens.Items[I] is TJSONObject) then
            Continue;
          Item := TJSONObject(Itens.Items[I]);
          InsertFabricacaoInsumoTGC(dm.FBCon, Item, IdBatida, DataFab,
            TgcUsuarioId,
            ResolveTgcOperadorId(Body, ['id_operador', 'CBT_COD_OPERADOR_PA']),
            CodRacao);
        end;
      end;

      SyncTgcFabricacaoGenerators(dm.FBCon);
      dm.FBCon.Commit;

      Resp := TJSONObject.Create;
      Resp.AddPair('Ok', IdBatida);
      Resp.AddPair('id_servidor', IdBatida);
      if LoteFab <> '' then
        Resp.AddPair('lote_fabricacao', LoteFab);
      Resp.AddPair('success', TJSONTrue.Create(True));
      Resp.AddPair('_debug_cod_racao', CodRacao);
      Resp.AddPair('_debug_custo_kg', TJSONNumber.Create(CustoKg));
      Resp.AddPair('_debug_qtde_realizada', TJSONNumber.Create(QtdeRealizada));
      Resp.AddPair('_debug_custo_fab', TJSONNumber.Create(CustoFab));
      MirrorPostBody('/Post/Fabricacao', Body, Resp.ToJSON, 200);
      Res.Status(200).Send<TJSONObject>(Resp);
      Resp := nil;
    except
      on E: Exception do
      begin
        if Assigned(dm) and dm.FBCon.InTransaction then
          dm.FBCon.Rollback;
        Resp := TJSONObject.Create;
        Resp.AddPair('Erro', 'Erro Ao Sincronizar Operacao:' + E.Message);
        MirrorPostBody('/Post/Fabricacao', Body, Resp.ToJSON, 500);
        Res.Status(500).Send<TJSONObject>(Resp);
        Resp := nil;
      end;
    end;
  finally
    if Assigned(Resp) then
      Resp.Free;
    Body.Free;
    dm.Free;
  end;
end;

procedure PostFabricacaoInsumo(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  dm: TdmTGC;
  Body, Resp: TJSONObject;
  Itens: TJSONArray;
  I: Integer;
  Item: TJSONObject;
  IdBatida, DataFab, CodRacao: string;
begin
  dm := nil;
  Body := nil;
  Resp := nil;
  try
    Body := TJSONObject.ParseJSONValue(Req.Body) as TJSONObject;
    if not Assigned(Body) then
      raise Exception.Create('JSON inválido.');

    Itens := JSONArrayFirst(Body, ['itens', 'FabricacaoAlimentosTGC']);
    if not Assigned(Itens) then
      raise Exception.Create('Array itens/FabricacaoAlimentosTGC ausente.');

    dm := TdmTGC.Create(nil);
    dm.ConectaDBTGC;

    CodRacao := JSONStrFirst(Body, ['id_dieta', 'CBT_CODRACAOPROD', 'IDRACAO']);

    if not dm.FBCon.InTransaction then
      dm.FBCon.StartTransaction;

    try
      for I := 0 to Itens.Count - 1 do
      begin
        if not (Itens.Items[I] is TJSONObject) then
          Continue;
        Item := TJSONObject(Itens.Items[I]);
        IdBatida := JSONStrFirst(Item, ['DBT_CODBATIDA', 'id_fabricacao']);
        DataFab := JSONStrFirst(Item, ['data', 'DBT_DATA']);
        InsertFabricacaoInsumoTGC(dm.FBCon, Item, IdBatida, DataFab,
          TgcUsuarioId,
          ResolveTgcOperadorId(Body, ['id_operador', 'CBT_COD_OPERADOR_PA']),
          CodRacao);
      end;
      SyncTgcFabricacaoGenerators(dm.FBCon);
      dm.FBCon.Commit;
      Resp := TJSONObject.Create;
      Resp.AddPair('Ok', IdBatida);
      MirrorPostBody('/Post/Fabricacao_Insumo', Body, Resp.ToJSON, 200);
      Res.Status(200).Send<TJSONObject>(Resp);
      Resp := nil;
    except
      on E: Exception do
      begin
        if dm.FBCon.InTransaction then
          dm.FBCon.Rollback;
        Resp := TJSONObject.Create;
        Resp.AddPair('Erro', 'Erro Ao Sincronizar Insumos Racao:' + E.Message);
        MirrorPostBody('/Post/Fabricacao_Insumo', Body, Resp.ToJSON, 500);
        Res.Status(500).Send<TJSONObject>(Resp);
        Resp := nil;
      end;
    end;
  finally
    if Assigned(Resp) then
      Resp.Free;
    Body.Free;
    dm.Free;
  end;
end;

procedure PostFornecimento(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  dm: TdmTGC;
  Body, Resp: TJSONObject;
  Itens: TJSONArray;
  I: Integer;
  Item: TJSONObject;

  procedure ApplyFornecimentoItem(const AItem: TJSONObject);
  var
    Q: TFDQuery;
    LoteForn, CodRacao, RealizadoStr, CodForn: string;
    CustoKg: Double;

    procedure BindUpdateCommon;
    begin
      SetParamAsIntRound(Q, 'CFORN_REALIZADO', RealizadoStr);
      Q.ParamByName('CFORN_CUSTO').AsFloat := CustoKg;
      Q.ParamByName('CFORN_MOTORISTA').AsString :=
        ResolveMotoristaNome(dm.FBCon, AItem);
      SetParamAsTimeStr(Q, 'CFORN_HORA',
        JSONStrFirst(AItem, ['hora_forn', 'CFORN_HORA', 'hora_fim']));
      Q.ParamByName('CFORN_LOTE_FABRICACAO').AsString := LoteForn;
      SetParamAsTimeStr(Q, 'CFORN_HORA_INI',
        JSONStrFirst(AItem, ['hora_inicio', 'CFORN_HORA_INI']));
      SetParamAsTimeStr(Q, 'CFORN_HORA_FIM',
        JSONStrFirst(AItem, ['hora_fim', 'CFORN_HORA_FIM']));
      SetParamAsDateBR(Q, 'CFORN_DATAFORNECIDO',
        JSONStrFirst(AItem, ['data', 'CFORN_DATAFORNECIDO', 'DATA_FORN']));
      Q.ParamByName('CFORN_CODRACAOPROD_PREV').AsString :=
        JSONStrFirst(AItem, ['id_racao', 'CFORN_CODRACAOPROD_PREV', 'id_dieta']);
    end;

  begin
    LoteForn := ResolveLoteFabricacaoTGC(AItem, 20);
    CodRacao := JSONStrFirst(AItem, ['id_racao', 'CFORN_CODRACAOPROD_PREV', 'id_dieta']);
    RealizadoStr := JSONStrFirst(AItem, ['realizado', 'CFORN_REALIZADO'], '0');
    CodForn := JSONStrFirst(AItem,
      ['id_fornecimento', 'CFORN_CODIGO', 'idFornecimento']);
    // 'id' sozinho pode ser ambiguo; so usa se nao veio id_fornecimento.
    if CodForn = '' then
      CodForn := JSONStrFirst(AItem, ['id']);
    CustoKg := LookupCustoKgRacao(dm.FBCon, CodRacao);

    Q := TFDQuery.Create(nil);
    try
      Q.Connection := dm.FBCon;

      // 1) Preferencia: CFORN_CODIGO (cada trato do mesmo carregamento tem o seu).
      if Trim(CodForn) <> '' then
      begin
        Q.SQL.Text :=
          'UPDATE CAD_FORNECIMENTO SET ' +
          '  CFORN_FLAG = ''S'', ' +
          '  CFORN_REALIZADO = CFORN_REALIZADO + :CFORN_REALIZADO, ' +
          '  CFORN_CUSTO = :CFORN_CUSTO, ' +
          '  CFORN_MOTORISTA = :CFORN_MOTORISTA, ' +
          '  CFORN_HORA = :CFORN_HORA, ' +
          '  CFORN_LOTE_FABRICACAO = :CFORN_LOTE_FABRICACAO, ' +
          '  CFORN_HORA_INI = :CFORN_HORA_INI, ' +
          '  CFORN_HORA_FIM = :CFORN_HORA_FIM, ' +
          '  CFORN_DATAFORNECIDO = :CFORN_DATAFORNECIDO, ' +
          '  CFORN_CODRACAOPROD_PREV = :CFORN_CODRACAOPROD_PREV ' +
          'WHERE CFORN_CODIGO = :CFORN_CODIGO';
        BindUpdateCommon;
        SetParamAsIntStr(Q, 'CFORN_CODIGO', CodForn);
        Q.ExecSQL;
      end;

      // 2) Fallback: chave natural baia + trato + data (trato como inteiro).
      if Q.RowsAffected = 0 then
      begin
        Q.SQL.Text :=
          'UPDATE CAD_FORNECIMENTO SET ' +
          '  CFORN_FLAG = ''S'', ' +
          '  CFORN_REALIZADO = CFORN_REALIZADO + :CFORN_REALIZADO, ' +
          '  CFORN_CUSTO = :CFORN_CUSTO, ' +
          '  CFORN_MOTORISTA = :CFORN_MOTORISTA, ' +
          '  CFORN_HORA = :CFORN_HORA, ' +
          '  CFORN_LOTE_FABRICACAO = :CFORN_LOTE_FABRICACAO, ' +
          '  CFORN_HORA_INI = :CFORN_HORA_INI, ' +
          '  CFORN_HORA_FIM = :CFORN_HORA_FIM, ' +
          '  CFORN_DATAFORNECIDO = :CFORN_DATAFORNECIDO, ' +
          '  CFORN_CODRACAOPROD_PREV = :CFORN_CODRACAOPROD_PREV ' +
          'WHERE CFORN_CODBAIA = :CFORN_CODBAIA ' +
          '  AND CFORN_TRATO = :CFORN_TRATO ' +
          '  AND CFORN_DATAFORNECIDO = :CFORN_DATAFORNECIDO_W';
        BindUpdateCommon;
        Q.ParamByName('CFORN_CODBAIA').AsString :=
          JSONStrFirst(AItem, ['id_baia', 'CFORN_CODBAIA', 'IDCURRAL']);
        SetParamAsIntStr(Q, 'CFORN_TRATO',
          JSONStrFirst(AItem, ['trato', 'CFORN_TRATO', 'TRATO']));
        SetParamAsDateBR(Q, 'CFORN_DATAFORNECIDO_W',
          JSONStrFirst(AItem, ['data', 'CFORN_DATAFORNECIDO', 'DATA_FORN']));
        Q.ExecSQL;
      end;

      if Q.RowsAffected = 0 then
        raise Exception.CreateFmt(
          'Fornecimento nao encontrado (id=%s baia=%s trato=%s data=%s).',
          [
            CodForn,
            JSONStrFirst(AItem, ['id_baia', 'CFORN_CODBAIA', 'IDCURRAL']),
            JSONStrFirst(AItem, ['trato', 'CFORN_TRATO', 'TRATO']),
            JSONStrFirst(AItem, ['data', 'CFORN_DATAFORNECIDO', 'DATA_FORN'])
          ]);
    finally
      Q.Free;
    end;
  end;

begin
  dm := nil;
  Body := nil;
  Resp := nil;
  try
    Body := TJSONObject.ParseJSONValue(Req.Body) as TJSONObject;
    if not Assigned(Body) then
      raise Exception.Create('JSON inválido.');

    Itens := JSONArrayFirst(Body, ['TGCFornecimento']);
    if not Assigned(Itens) then
    begin
      Itens := TJSONArray.Create;
      try
        Itens.AddElement(TJSONObject.ParseJSONValue(Body.ToJSON) as TJSONObject);
        dm := TdmTGC.Create(nil);
        dm.ConectaDBTGC;
        if not dm.FBCon.InTransaction then
          dm.FBCon.StartTransaction;
        try
          for I := 0 to Itens.Count - 1 do
          begin
            Item := TJSONObject(Itens.Items[I]);
            ApplyFornecimentoItem(Item);
          end;
          dm.FBCon.Commit;
          Resp := TJSONObject.Create;
          Resp.AddPair('Ok', '');
          Resp.AddPair('ok', TJSONTrue.Create(True));
          MirrorPostBody('/Post/Fornecimento', Body, Resp.ToJSON, 200);
          Res.Status(200).Send<TJSONObject>(Resp);
          Resp := nil;
        except
          on E: Exception do
          begin
            if dm.FBCon.InTransaction then
              dm.FBCon.Rollback;
            raise;
          end;
        end;
      finally
        Itens.Free;
      end;
      Exit;
    end;

    dm := TdmTGC.Create(nil);
    dm.ConectaDBTGC;
    if not dm.FBCon.InTransaction then
      dm.FBCon.StartTransaction;
    try
      for I := 0 to Itens.Count - 1 do
      begin
        Item := TJSONObject(Itens.Items[I]);
        ApplyFornecimentoItem(Item);
      end;
      dm.FBCon.Commit;
      Resp := TJSONObject.Create;
      Resp.AddPair('Ok', '');
      MirrorPostBody('/Post/Fornecimento', Body, Resp.ToJSON, 200);
      Res.Status(200).Send<TJSONObject>(Resp);
      Resp := nil;
    except
      on E: Exception do
      begin
        if dm.FBCon.InTransaction then
          dm.FBCon.Rollback;
        Resp := TJSONObject.Create;
        Resp.AddPair('Erro', 'Erro Ao Sincronizar Operacao:' + E.Message);
        MirrorPostBody('/Post/Fornecimento', Body, Resp.ToJSON, 500);
        Res.Status(500).Send<TJSONObject>(Resp);
        Resp := nil;
      end;
    end;
  finally
    if Assigned(Resp) then
      Resp.Free;
    Body.Free;
    dm.Free;
  end;
end;

procedure PostGravaTag(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  dm: TdmTGC;
  Body, Resp: TJSONObject;
  vIdCurral, vTag: string;
  Q: TFDQuery;
  Rows: Integer;
begin
  dm := nil;
  Body := nil;
  Resp := nil;
  try
    Body := Req.Body<TJSONObject>;
    if not Assigned(Body) then
      raise Exception.Create('JSON inválido.');

    vIdCurral := JSONStrFirst(Body, ['ID_PASTO_CURRAL', 'id_baia', 'id']);
    vTag := JSONStrFirst(Body, ['TAG', 'rfid', 'epc', 'tag']);
    if vIdCurral = '' then
      raise Exception.Create('ID do curral ausente.');
    if vTag = '' then
      raise Exception.Create('TAG ausente.');
    vTag := NormalizeEPC(vTag);

    dm := TdmTGC.Create(nil);
    dm.ConectaDBTGC;
    Q := TFDQuery.Create(nil);
    try
      Q.Connection := dm.FBCon;
      Q.SQL.Text :=
        'UPDATE CAD_CURRAL SET CC_TAG_INICIAL = :TAG WHERE CC_CODIGO = :ID';
      Q.ParamByName('TAG').AsString := vTag;
      Q.ParamByName('ID').AsString := vIdCurral;
      Q.ExecSQL;
      Rows := Q.RowsAffected;

      if Rows = 0 then
        raise Exception.CreateFmt('Curral %s não encontrado para atualização.', [vIdCurral]);

      Resp := TJSONObject.Create;
      Resp.AddPair('success', TJSONTrue.Create(True));
      Resp.AddPair('id', vIdCurral);
      Resp.AddPair('tag', vTag);
      Resp.AddPair('updated', TJSONNumber.Create(Rows));
      MirrorPostBody('/Post/GravaTag', Body, Resp.ToJSON, 200);
      Res.Status(200).Send<TJSONObject>(Resp);
      Resp := nil;
    finally
      Q.Free;
    end;
  except
    on E: Exception do
    begin
      Resp := TJSONObject.Create;
      Resp.AddPair('success', TJSONFalse.Create(False));
      Resp.AddPair('erro', E.Message);
      Res.Status(500).Send<TJSONObject>(Resp);
      Resp := nil;
    end;
  end;
  if Assigned(Resp) then
    Resp.Free;
  dm.Free;
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

end.
