unit Controllers.Get.Field;

interface
uses
  Horse,
  Horse.Jhonson,
  Horse.CORS,
  System.JSON,
  System.SysUtils,
  FireDAC.Comp.Client;

function RetornaDataFormadata(vData: string): string;
procedure RegistraRotas;
procedure GetUsuarios(Req: THorseRequest; Res: THorseResponse; Next: TProc);
procedure GetFazendas(Req: THorseRequest; Res: THorseResponse; Next: TProc);
procedure GetDietas(Req: THorseRequest; Res: THorseResponse; Next: TProc);
procedure GetDietasDetalhes(Req: THorseRequest; Res: THorseResponse; Next: TProc);
procedure GetPrevisaoTrato(Req: THorseRequest; Res: THorseResponse; Next: TProc);
procedure GetBaias(Req: THorseRequest; Res: THorseResponse; Next: TProc);
procedure GetTeste(Req: THorseRequest; Res: THorseResponse; Next: TProc);
procedure GetVagao(Req: THorseRequest; Res: THorseResponse; Next: TProc);
procedure GetDashboardFabricacaoResumo(Req: THorseRequest; Res: THorseResponse; Next: TProc);
procedure GetDashboardFabricacaoInsumos(Req: THorseRequest; Res: THorseResponse; Next: TProc);
procedure GetDashboardFabricacaoFornecimento(Req: THorseRequest; Res: THorseResponse; Next: TProc);
implementation

uses
  DataSet.Serialize,
  UdmFieldPec,
  Controllers.Mirror,
  System.Math,
  System.IOUtils;

function MirrorReqIdFazenda(Req: THorseRequest): string;
var
  idF: string;
begin
  idF := Trim(Req.Params.Items['idfazenda']);
  if idF = '' then
    Result := '{}'
  else
    Result := Format('{"idFazenda":"%s"}', [idF]);
end;

function MirrorReqPrevisao(Req: THorseRequest): string;
var
  idF, dataP: string;
begin
  idF := Trim(Req.Params.Items['idfazenda']);
  dataP := Trim(Req.Params.Items['dataPrev']);
  if dataP = '' then
    dataP := Trim(Req.Query.Items['dataPrev']);
  if (idF <> '') and (dataP <> '') then
    Result := Format('{"idFazenda":"%s","dataIso":"%s"}', [idF, dataP])
  else if dataP <> '' then
    Result := Format('{"dataIso":"%s"}', [dataP])
  else if idF <> '' then
    Result := Format('{"idFazenda":"%s"}', [idF])
  else
    Result := '{}';
end;

function RetornaDataFormadata(vData: string): string;
var
  VAno, vMes, vDia: string;
begin
  if vData.Length = 10 then
  begin
    VAno := Copy(vData, 1, 4);
    vMes := Copy(vData, 6, 2);
    vDia := Copy(vData, 9, 2);
    Result := vDia + '/' + vMes + '/' + VAno;
  end
  else
    Result := 'Sem Data';
end;

function QueryParam(const Req: THorseRequest; const AName, ADefault: string): string;
begin
  if not Req.Query.TryGetValue(AName, Result) then
    Result := ADefault;
  Result := Trim(Result);
  if Result = '' then
    Result := ADefault;
end;

function TryParseIsoDate(const AIso: string; out ADate: TDateTime): Boolean;
var
  Y, M, D: Integer;
begin
  Result := False;
  if Length(AIso) <> 10 then
    Exit;
  if not TryStrToInt(Copy(AIso, 1, 4), Y) then
    Exit;
  if not TryStrToInt(Copy(AIso, 6, 2), M) then
    Exit;
  if not TryStrToInt(Copy(AIso, 9, 2), D) then
    Exit;
  try
    ADate := EncodeDate(Word(Y), Word(M), Word(D));
    Result := True;
  except
    Result := False;
  end;
end;

procedure RequireDateRangeOr400(Req: THorseRequest; Res: THorseResponse;
  out AIni, AFim: TDateTime; out AOk: Boolean);
var
  SIni, SFim: string;
begin
  AOk := False;
  SIni := QueryParam(Req, 'data_ini', '');
  SFim := QueryParam(Req, 'data_fim', '');

  if (SIni = '') or (SFim = '') then
  begin
    Res.Send(TJSONObject.Create
      .AddPair('erro', 'Parâmetros obrigatórios: data_ini e data_fim (yyyy-mm-dd).')
    ).Status(400);
    Exit;
  end;

  if (not TryParseIsoDate(SIni, AIni)) or (not TryParseIsoDate(SFim, AFim)) then
  begin
    Res.Send(TJSONObject.Create
      .AddPair('erro', 'Data inválida. Use yyyy-mm-dd.')
    ).Status(400);
    Exit;
  end;

  AOk := True;
end;

procedure BindCommonFiltersField(Q: TFDQuery; Req: THorseRequest);
var
  S: string;
begin
  S := QueryParam(Req, 'id_dieta', '');
  Q.ParamByName('SKIP_DIETA').AsInteger := IfThen(S = '', 1, 0);
  Q.ParamByName('ID_RACAO').AsInteger := StrToIntDef(S, 0);

  S := QueryParam(Req, 'id_operador', '');
  Q.ParamByName('SKIP_OPERADOR').AsInteger := IfThen(S = '', 1, 0);
  Q.ParamByName('ID_OPERADOR').AsInteger := StrToIntDef(S, 0);
end;

procedure RegistraRotas;
begin
  THorse.Get('/GetTeste', GetTeste);
  THorse.Get('/usuarios/get', GetUsuarios);
  THorse.Get('/usuarios/get/:idfazenda', GetUsuarios);
  THorse.Get('/dietas/get', GetDietas);
  THorse.Get('/dietas/get/:idfazenda', GetDietas);
  THorse.Get('/dietas_detalhes/get', GetDietasDetalhes);
  THorse.Get('/dietas_detalhes/get/:idfazenda', GetDietasDetalhes);
  THorse.Get('/fazenda/get', GetFazendas);
  THorse.Get('/baias/get', GetBaias);
  THorse.Get('/baias/get/:idfazenda', GetBaias);
  THorse.Get('/previsao_trato/get', GetPrevisaoTrato);
  THorse.Get('/previsao_trato/get/:idfazenda/:dataPrev', GetPrevisaoTrato);
  THorse.Get('/vagao/get', GetVagao);
  THorse.Get('/vagao/get/', GetVagao);
  THorse.Get('/dashboard/fabricacao/resumo', GetDashboardFabricacaoResumo);
  THorse.Get('/dashboard/fabricacao/insumos', GetDashboardFabricacaoInsumos);
  THorse.Get('/dashboard/fabricacao/fornecimento', GetDashboardFabricacaoFornecimento);
end;

procedure GetDashboardFabricacaoResumo(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  dmGlobal: TdmFieldPec;
  Q: TFDQuery;
  DIni, DFim: TDateTime;
  OkRange: Boolean;
begin
  RequireDateRangeOr400(Req, Res, DIni, DFim, OkRange);
  if not OkRange then
    Exit;

  dmGlobal := TdmFieldPec.Create(nil);
  Q := TFDQuery.Create(nil);
  try
    dmGlobal.ConectaDBField;
    Q.Connection := dmGlobal.FBCon;
    Q.SQL.Text :=
      'SELECT ' +
      '  cop.NAME AS OPERADOR, ' +
      '  CAST(''VAGAO'' AS VARCHAR(20)) AS VAGAO, ' +
      '  cd.NOME AS NOME_DIETA, ' +
      '  CAST(f.KG_PREVISTO AS DOUBLE PRECISION) AS QTDE_PREVISTA, ' +
      '  CAST(f.KG_REALIZADO AS DOUBLE PRECISION) AS QTDE_REALIZADA, ' +
      '  CAST((f.KG_PREVISTO - f.KG_REALIZADO) AS DOUBLE PRECISION) AS DIFKG, ' +
      '  CAST(((f.KG_PREVISTO - f.KG_REALIZADO) * 100.0) / NULLIF(f.KG_PREVISTO, 0) AS DOUBLE PRECISION) AS DIFPERCENT, ' +
      '  f.ID, f.IDRACAO AS ID_DIETA, ' +
      '  COALESCE(NULLIF(f.ID_OPERADOR, 0), f.ID_USUARIO) AS ID_OPERADOR, ' +
      '  CAST(NULL AS INTEGER) AS ID_VAGAO, ' +
      '  CAST(f.DATAREG AS TIMESTAMP) AS DATA_REGISTO ' +
      'FROM FABRICACAO f ' +
      'JOIN RACAO cd ON cd.ID = f.IDRACAO ' +
      'LEFT JOIN USERS cop ON cop.ID = COALESCE(NULLIF(f.ID_OPERADOR, 0), f.ID_USUARIO) ' +
      'WHERE f.DATA_FAB BETWEEN :DATA_INI AND :DATA_FIM ' +
      '  AND f.STATUS = 1 ' +
      '  AND ((:SKIP_DIETA = 1) OR (f.IDRACAO = :ID_RACAO)) ' +
      '  AND ((:SKIP_OPERADOR = 1) OR (COALESCE(NULLIF(f.ID_OPERADOR, 0), f.ID_USUARIO) = :ID_OPERADOR)) ' +
      'ORDER BY f.DATAREG DESC, f.ID DESC';
    Q.ParamByName('DATA_INI').AsDate := DIni;
    Q.ParamByName('DATA_FIM').AsDate := DFim;
    BindCommonFiltersField(Q, Req);
    Q.Open;
    Res.Send<TJSONArray>(Q.ToJSONArray).Status(200);
  except
    on E: Exception do
      Res.Send(TJSONObject.Create.AddPair('erro', E.Message)).Status(500);
  end;
  Q.Free;
  dmGlobal.Free;
end;

procedure GetDashboardFabricacaoInsumos(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  dmGlobal: TdmFieldPec;
  Q: TFDQuery;
  DIni, DFim: TDateTime;
  OkRange: Boolean;
begin
  RequireDateRangeOr400(Req, Res, DIni, DFim, OkRange);
  if not OkRange then
    Exit;

  dmGlobal := TdmFieldPec.Create(nil);
  Q := TFDQuery.Create(nil);
  try
    dmGlobal.ConectaDBField;
    Q.Connection := dmGlobal.FBCon;
    Q.SQL.Text :=
      'SELECT ' +
      '  cop.NAME AS OPERADOR, ' +
      '  CAST(''VAGAO'' AS VARCHAR(20)) AS VAGAO, ' +
      '  cd.NOME AS NOME_DIETA, ' +
      '  CAST(f.KG_PREVISTO AS DOUBLE PRECISION) AS QTDE_PREVISTA, ' +
      '  CAST(f.KG_REALIZADO AS DOUBLE PRECISION) AS QTDE_REALIZADA, ' +
      '  CAST((f.KG_PREVISTO - f.KG_REALIZADO) AS DOUBLE PRECISION) AS DIFKG_TOTAL, ' +
      '  CAST(((f.KG_PREVISTO - f.KG_REALIZADO) * 100.0) / NULLIF(f.KG_PREVISTO, 0) AS DOUBLE PRECISION) AS DIFPERCENT_TOTAL, ' +
      '  ci2.NOME AS INSUMO, ' +
      '  CAST(fi.KG_PREVISTO AS DOUBLE PRECISION) AS PREVISTO_KG_INSUMO, ' +
      '  CAST(fi.KG_FABRICADO AS DOUBLE PRECISION) AS REALIZADO_KG_INSUMO, ' +
      '  CAST((fi.KG_PREVISTO - fi.KG_FABRICADO) AS DOUBLE PRECISION) AS DIF_KG_INSUMO, ' +
      '  CAST(((fi.KG_PREVISTO - fi.KG_FABRICADO) * 100.0) / NULLIF(fi.KG_PREVISTO, 0) AS DOUBLE PRECISION) AS DIFPERCENT_INSUMO, ' +
      '  f.ID, fi.ID AS ID_DETALHE, f.IDRACAO AS ID_DIETA, ' +
      '  COALESCE(NULLIF(f.ID_OPERADOR, 0), f.ID_USUARIO) AS ID_OPERADOR, ' +
      '  CAST(NULL AS INTEGER) AS ID_VAGAO ' +
      'FROM FABRICACAO f ' +
      'JOIN FABRICACAO_INSUMOS fi ON fi.ID_FABRICACAO = f.ID ' +
      'JOIN ALIMENTO ci2 ON ci2.ID = fi.ID_ALIMENTO ' +
      'JOIN RACAO cd ON cd.ID = f.IDRACAO ' +
      'LEFT JOIN USERS cop ON cop.ID = COALESCE(NULLIF(f.ID_OPERADOR, 0), f.ID_USUARIO) ' +
      'WHERE f.DATA_FAB BETWEEN :DATA_INI AND :DATA_FIM ' +
      '  AND f.STATUS = 1 ' +
      '  AND fi.STATUS = 1 ' +
      '  AND ((:SKIP_DIETA = 1) OR (f.IDRACAO = :ID_RACAO)) ' +
      '  AND ((:SKIP_OPERADOR = 1) OR (COALESCE(NULLIF(f.ID_OPERADOR, 0), f.ID_USUARIO) = :ID_OPERADOR)) ' +
      'ORDER BY f.DATAREG DESC, f.ID DESC, fi.ID';
    Q.ParamByName('DATA_INI').AsDate := DIni;
    Q.ParamByName('DATA_FIM').AsDate := DFim;
    BindCommonFiltersField(Q, Req);
    Q.Open;
    Res.Send<TJSONArray>(Q.ToJSONArray).Status(200);
  except
    on E: Exception do
      Res.Send(TJSONObject.Create.AddPair('erro', E.Message)).Status(500);
  end;
  Q.Free;
  dmGlobal.Free;
end;

procedure GetDashboardFabricacaoFornecimento(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  dmGlobal: TdmFieldPec;
  Q: TFDQuery;
  DIni, DFim: TDateTime;
  OkRange: Boolean;
begin
  RequireDateRangeOr400(Req, Res, DIni, DFim, OkRange);
  if not OkRange then
    Exit;

  dmGlobal := TdmFieldPec.Create(nil);
  Q := TFDQuery.Create(nil);
  try
    dmGlobal.ConectaDBField;
    Q.Connection := dmGlobal.FBCon;
    Q.SQL.Text :=
      'SELECT ' +
      '  cop.NAME AS OPERADOR, ' +
      '  CAST(''VAGAO'' AS VARCHAR(20)) AS VAGAO, ' +
      '  cd.NOME AS NOME_DIETA, ' +
      '  CAST(f.KG_PREVISTO AS DOUBLE PRECISION) AS QTDE_PREVISTA, ' +
      '  CAST(f.KG_REALIZADO AS DOUBLE PRECISION) AS QTDE_REALIZADA, ' +
      '  CAST((f.KG_PREVISTO - f.KG_REALIZADO) AS DOUBLE PRECISION) AS DIFKG, ' +
      '  CAST(((f.KG_PREVISTO - f.KG_REALIZADO) * 100.0) / NULLIF(f.KG_PREVISTO, 0) AS DOUBLE PRECISION) AS DIFPERCENT, ' +
      '  c.CODIGO AS CURRAL, ' +
      '  CAST(fc.PREVISTO_MN_KG AS DOUBLE PRECISION) AS PREVISTO_FORNECIMENTO, ' +
      '  CAST(fc.REALIZADO_MN_KG AS DOUBLE PRECISION) AS REALIZADO_FORNECIMENTO, ' +
      '  CAST((fc.PREVISTO_MN_KG - fc.REALIZADO_MN_KG) AS DOUBLE PRECISION) AS DIF_KG_FORNECIMENTO, ' +
      '  f.ID, f.IDRACAO AS ID_DIETA, ' +
      '  COALESCE(NULLIF(f.ID_OPERADOR, 0), f.ID_USUARIO) AS ID_OPERADOR, ' +
      '  CAST(NULL AS INTEGER) AS ID_VAGAO, ' +
      '  fc.ID AS ID_FORNECIMENTO, fc.ID_LOCAL AS ID_BAIA ' +
      'FROM FABRICACAO f ' +
      'JOIN RACAO cd ON cd.ID = f.IDRACAO ' +
      'LEFT JOIN USERS cop ON cop.ID = COALESCE(NULLIF(f.ID_OPERADOR, 0), f.ID_USUARIO) ' +
      'LEFT JOIN FORNECIMENTO_CONF fc ON fc.STATUS = 1 AND ( ' +
      '  (TRIM(COALESCE(fc.LOTE_FABRICACAO, '''')) <> '''' AND fc.LOTE_FABRICACAO = f.LOTE_FABRICACAO) ' +
      '  OR fc.LOTE_FABRICACAO = CAST(f.ID AS VARCHAR(20)) ' +
      ') ' +
      'LEFT JOIN CURRAIS c ON c.ID = fc.ID_LOCAL ' +
      'WHERE f.DATA_FAB BETWEEN :DATA_INI AND :DATA_FIM ' +
      '  AND f.STATUS = 1 ' +
      '  AND ((:SKIP_DIETA = 1) OR (f.IDRACAO = :ID_RACAO)) ' +
      '  AND ((:SKIP_OPERADOR = 1) OR (COALESCE(NULLIF(f.ID_OPERADOR, 0), f.ID_USUARIO) = :ID_OPERADOR)) ' +
      'ORDER BY f.DATAREG DESC, f.ID DESC, fc.ID';
    Q.ParamByName('DATA_INI').AsDate := DIni;
    Q.ParamByName('DATA_FIM').AsDate := DFim;
    BindCommonFiltersField(Q, Req);
    Q.Open;
    Res.Send<TJSONArray>(Q.ToJSONArray).Status(200);
  except
    on E: Exception do
      Res.Send(TJSONObject.Create.AddPair('erro', E.Message)).Status(500);
  end;
  Q.Free;
  dmGlobal.Free;
end;

procedure GetTeste(Req: THorseRequest; Res: THorseResponse; Next: TProc);
begin
  try
   Res.Send(tjsonobject.Create.AddPair('OK ','Sevidor Online')).Status(200);
   except on ex:exception do
    begin
     Res.Send(tjsonobject.Create.AddPair('Erro '+
     StringReplace(GetCurrentDir,'\\','\',[rfReplaceAll]),ex.Message)).Status(500);
    end;
   end;
end;




procedure GetBaias(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  dmGlobal: TdmFieldPec;
  LArr: TJSONArray;
begin
  try
    dmGlobal := TdmFieldPec.Create(nil);
    try
      dmGlobal.ConectaDBField;
      dmGlobal.BAIAS.Connection := dmGlobal.FBCon;
      dmGlobal.BAIAS.Close;
      dmGlobal.BAIAS.Open;

      LArr := dmGlobal.BAIAS.ToJSONArray;
      Res.Send<TJSONArray>(LArr).Status(200);
      MirrorGetArray('/baias/get/[idfazenda]', MirrorReqIdFazenda(Req), LArr, 200);
    except
      on ex: Exception do
        Res.Send(
          TJSONObject.Create.AddPair(
            'Erro ' + StringReplace(GetCurrentDir, '\\', '\', [rfReplaceAll]),
            ex.Message)
        ).Status(500);
    end;
  finally
    FreeAndNil(dmGlobal);
  end;
end;


procedure LogPrevisaoTratoSql(const AUrl, ADataRaw, ADb, ASql: string;
  ADini, ADfim: TDateTime; ACount: Integer);
var
  Dir, F, Line, SqlExec: string;
begin
  SqlExec := ASql;
  SqlExec := StringReplace(SqlExec, ':DINI',
    'TIMESTAMP ''' + FormatDateTime('yyyy-mm-dd hh:nn:ss', ADini) + '''',
    [rfReplaceAll, rfIgnoreCase]);
  SqlExec := StringReplace(SqlExec, ':DFIM',
    'TIMESTAMP ''' + FormatDateTime('yyyy-mm-dd hh:nn:ss', ADfim) + '''',
    [rfReplaceAll, rfIgnoreCase]);

  Line :=
    FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) + sLineBreak +
    'URL=' + AUrl + sLineBreak +
    'dataPrev_raw=' + ADataRaw + sLineBreak +
    'DINI=' + FormatDateTime('yyyy-mm-dd hh:nn:ss', ADini) + sLineBreak +
    'DFIM=' + FormatDateTime('yyyy-mm-dd hh:nn:ss', ADfim) + sLineBreak +
    'DB=' + ADb + sLineBreak +
    'RecordCount=' + IntToStr(ACount) + sLineBreak +
    'SQL_COM_DATAS=' + sLineBreak +
    SqlExec + sLineBreak +
    StringOfChar('-', 80) + sLineBreak;

  try
    Dir := TPath.Combine(ExtractFilePath(ParamStr(0)), 'logs');
    ForceDirectories(Dir);
    F := TPath.Combine(Dir, 'previsao_trato.log');
    TFile.AppendAllText(F, Line, TEncoding.UTF8);
  except
  end;
end;

procedure GetPrevisaoTrato(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  dmGlobal: TdmFieldPec;
  LArr: TJSONArray;
  dataP, LUrl, LDb: string;
  dataPrev, LDini, LDfim: TDateTime;
  LCount: Integer;
begin
  LUrl := '';
  LDb := '';
  dataP := '';
  LCount := -1;
  LDini := 0;
  LDfim := 0;
  try
    dmGlobal := TdmFieldPec.Create(nil);
    try
      dmGlobal.ConectaDBField;
      dmGlobal.PREVISAO.Connection := dmGlobal.FBCon;
      LDb := dmGlobal.FBCon.Params.Values['Database'];
      LUrl := Trim(Req.PathInfo);
      if Trim(Req.RawWebRequest.Query) <> '' then
        LUrl := LUrl + '?' + Trim(Req.RawWebRequest.Query);

      dataP := Trim(Req.Params.Items['dataPrev']);
      if dataP = '' then
        dataP := QueryParam(Req, 'dataPrev', '');
      if not TryParseIsoDate(dataP, dataPrev) then
        dataPrev := Date;

      LDini := Trunc(dataPrev);
      LDfim := Trunc(dataPrev) + 1;

      dmGlobal.PREVISAO.Close;
      dmGlobal.PREVISAO.SQL.Text :=
        'SELECT ' +
        ' forn.ID ID_FORNECIMENTO, ' +
        ' forn.DATA, ' +
        ' forn.IDCURRAL ID, ' +
        ' forn.TRATO, ' +
        ' forn.IDRACAO ID_DIETA, ' +
        ' forn.KGPREVISTO AS PREVISTO_CADASTRO, ' +
        ' CASE ' +
        '  WHEN forn.TRATO = forn.UltimoTrato THEN forn.TotalPrev - forn.TotalReal + forn.Realizado ' +
        '  ELSE forn.KGPREVISTO ' +
        ' END PREVISTO_ORIGINAL, ' +
        ' CASE ' +
        '  WHEN forn.TRATO = forn.UltimoTrato THEN forn.TotalPrev - forn.TotalReal ' +
        '  ELSE forn.KGPREVISTO ' +
        ' END PREVISTO_RECALCULADO, ' +
        ' CASE ' +
        '  WHEN forn.TRATO = forn.UltimoTrato THEN forn.TotalPrev - forn.TotalReal ' +
        '  ELSE forn.KGPREVISTO ' +
        ' END PREVISTO, ' +
        ' forn.Realizado REALIZADO, ' +
        ' IIF(forn.TRATO = forn.UltimoTrato, 1, 0) ULTIMO_TRATO ' +
        'FROM ( ' +
        ' SELECT ' +
        '  A.ID, ' +
        '  DATA_FORN DATA, ' +
        '  ID_LOCAL IDCURRAL, ' +
        '  ID_RACAO IDRACAO, ' +
        '  STATUS, ' +
        '  TRATO, ' +
        '  1 TIPO, ' +
        '  PREVISTO_MN_KG KGPREVISTO, ' +
        '  (SELECT COALESCE(SUM(REALIZADO_MN_KG), 0) FROM FORNECIMENTO_CONF ' +
        '    WHERE STATUS = 1 AND ID_LOCAL = A.ID_LOCAL AND ID_LOTE = A.ID_LOTE ' +
        '      AND DATA_FORN = A.DATA_FORN AND TRATO = A.TRATO) Realizado, ' +
        '  (SELECT COALESCE(SUM(REALIZADO_MN_KG), 0) FROM FORNECIMENTO_CONF ' +
        '    WHERE STATUS = 1 AND ID_LOCAL = A.ID_LOCAL AND ID_LOTE = A.ID_LOTE ' +
        '      AND DATA_FORN = A.DATA_FORN) TotalReal, ' +
        '  (SELECT SUM(PREVISTO_MN_KG) FROM FORNECIMENTO_CONF ' +
        '    WHERE STATUS = 1 AND ID_LOCAL = A.ID_LOCAL AND ID_LOTE = A.ID_LOTE ' +
        '      AND DATA_FORN = A.DATA_FORN) TotalPrev, ' +
        '  (SELECT MAX(TRATO) FROM FORNECIMENTO_CONF ' +
        '    WHERE STATUS = 1 AND ID_LOCAL = A.ID_LOCAL AND ID_LOTE = A.ID_LOTE ' +
        '      AND DATA_FORN = A.DATA_FORN) UltimoTrato ' +
        ' FROM FORNECIMENTO_CONF A ' +
        ' WHERE STATUS = 1 ' +
        '   AND A.DATA_FORN >= :DINI ' +
        '   AND A.DATA_FORN < :DFIM ' +
        ') Forn';
      dmGlobal.PREVISAO.ParamByName('DINI').AsDateTime := LDini;
      dmGlobal.PREVISAO.ParamByName('DFIM').AsDateTime := LDfim;
      dmGlobal.PREVISAO.Open;
      LCount := dmGlobal.PREVISAO.RecordCount;
      LogPrevisaoTratoSql(LUrl, dataP, LDb, dmGlobal.PREVISAO.SQL.Text,
        LDini, LDfim, LCount);

      LArr := dmGlobal.PREVISAO.ToJSONArray;
      Res.Send<TJSONArray>(LArr).Status(200);
      MirrorGetArray('/previsao_trato/get/[idfazenda]/[dataPrev]',
        MirrorReqPrevisao(Req), LArr, 200);
    except
      on ex: Exception do
      begin
        try
          if Assigned(dmGlobal) and Assigned(dmGlobal.PREVISAO) then
            LogPrevisaoTratoSql(LUrl, dataP, LDb, dmGlobal.PREVISAO.SQL.Text,
              LDini, LDfim, LCount);
        except
        end;
        Res.Send(
          TJSONObject.Create.AddPair(
            'Erro ' + StringReplace(GetCurrentDir, '\\', '\', [rfReplaceAll]),
            ex.Message)
        ).Status(500);
      end;
    end;
  finally
    FreeAndNil(dmGlobal);
  end;
end;


procedure GetDietasDetalhes(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  dmGlobal: TdmFieldPec;
  LArr: TJSONArray;
begin
  try
    dmGlobal := TdmFieldPec.Create(nil);
    try
      dmGlobal.ConectaDBField;
      dmGlobal.DETALHES_DIETAS.Connection := dmGlobal.FBCon;
      dmGlobal.DETALHES_DIETAS.Close;
      dmGlobal.DETALHES_DIETAS.Open;

      LArr := dmGlobal.DETALHES_DIETAS.ToJSONArray;
      Res.Send<TJSONArray>(LArr).Status(200);
      MirrorGetArray('/dietas_detalhes/get/[idfazenda]', MirrorReqIdFazenda(Req), LArr, 200);
    except
      on ex: Exception do
      begin
        Res.Send(
          TJSONObject.Create.AddPair(
            'Erro ' + StringReplace(GetCurrentDir, '\\', '\', [rfReplaceAll]),
            ex.Message)
        ).Status(500);
      end;
    end;
  finally
    FreeAndNil(dmGlobal);
  end;
end;

procedure GetDietas(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  dmGlobal: TdmFieldPec;
  LArr: TJSONArray;
begin
  try
    dmGlobal := TdmFieldPec.Create(nil);
    try
      dmGlobal.ConectaDBField;
      dmGlobal.CADASTRO_DIETAS.Connection := dmGlobal.FBCon;
      dmGlobal.CADASTRO_DIETAS.Close;
      dmGlobal.CADASTRO_DIETAS.Open;

      LArr := dmGlobal.CADASTRO_DIETAS.ToJSONArray;
      Res.Send<TJSONArray>(LArr).Status(200);
      MirrorGetArray('/dietas/get/[idfazenda]', MirrorReqIdFazenda(Req), LArr, 200);
    except
      on ex: Exception do
      begin
        Res.Send(
          TJSONObject.Create.AddPair(
            'Erro ' + StringReplace(GetCurrentDir, '\\', '\', [rfReplaceAll]),
            ex.Message)
        ).Status(500);
      end;
    end;
  finally
    FreeAndNil(dmGlobal);
  end;
end;


procedure GetUsuarios(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  dmGlobal: TdmFieldPec;
  LJson: TJSONArray;
begin
  dmGlobal := nil;
  LJson := nil;

  try
    dmGlobal := TdmFieldPec.Create(nil);
    try
      try
        if Assigned(dmGlobal.CADASTRO_USUARIO) and dmGlobal.CADASTRO_USUARIO.Active then
          dmGlobal.CADASTRO_USUARIO.Close;
      except
      end;

      try
        if Assigned(dmGlobal.FBCon) and dmGlobal.FBCon.Connected then
          dmGlobal.FBCon.Connected := False;
      except
      end;

      dmGlobal.ConectaDBField;

      dmGlobal.CADASTRO_USUARIO.Close;
      dmGlobal.CADASTRO_USUARIO.Connection := dmGlobal.FBCon;
      dmGlobal.CADASTRO_USUARIO.Open;

      LJson := dmGlobal.CADASTRO_USUARIO.ToJSONArray;
      Res.Status(200).Send<TJSONArray>(LJson);
      MirrorGetArray('/usuarios/get/[idfazenda]', MirrorReqIdFazenda(Req), LJson, 200);
      LJson := nil;
    finally
      try
        if Assigned(dmGlobal.CADASTRO_USUARIO) and dmGlobal.CADASTRO_USUARIO.Active then
          dmGlobal.CADASTRO_USUARIO.Close;
      except
      end;

      try
        if Assigned(dmGlobal.FBCon) and dmGlobal.FBCon.Connected then
          dmGlobal.FBCon.Connected := False;
      except
      end;

      FreeAndNil(dmGlobal);
    end;
  except
    on Ex: Exception do
    begin
      if Assigned(LJson) then
        LJson.Free;

      Res.Status(500).Send(
        TJSONObject.Create.AddPair('error', Ex.Message)
      );
    end;
  end;
end;

procedure GetVagao(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  dmGlobal: TdmFieldPec;
  LArr: TJSONArray;
begin
  try
    dmGlobal := TdmFieldPec.Create(nil);
    try
      dmGlobal.ConectaDBField;
      dmGlobal.Vagao.Connection := dmGlobal.FBCon;
      dmGlobal.Vagao.Close;
      dmGlobal.Vagao.Open;

      LArr := dmGlobal.Vagao.ToJSONArray;
      Res.Send<TJSONArray>(LArr).Status(200);
      MirrorGetArray('/vagao/get', '{}', LArr, 200);
    except
      on ex: Exception do
      begin
        Res.Send(
          TJSONObject.Create.AddPair(
            'Erro ' + StringReplace(GetCurrentDir, '\\', '\', [rfReplaceAll]),
            ex.Message)
        ).Status(500);
      end;
    end;
  finally
    FreeAndNil(dmGlobal);
  end;
end;

procedure GetFazendas(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  dmGlobal: TdmFieldPec;
  LArr: TJSONArray;
begin
  try
    dmGlobal := TdmFieldPec.Create(nil);
    try
      dmGlobal.ConectaDBField;
      dmGlobal.CADASTRO_FAZENDA.Connection := dmGlobal.FBCon;
      dmGlobal.CADASTRO_FAZENDA.Close;
      dmGlobal.CADASTRO_FAZENDA.Open;

      LArr := dmGlobal.CADASTRO_FAZENDA.ToJSONArray;
      Res.Send<TJSONArray>(LArr).Status(200);
      MirrorGetArray('/fazenda/get', '{}', LArr, 200);
    except
      on ex: Exception do
      begin
        Res.Send(
          TJSONObject.Create.AddPair(
            'Erro ' + StringReplace(GetCurrentDir, '\\', '\', [rfReplaceAll]),
            ex.Message)
        ).Status(500);
      end;
    end;
  finally
    FreeAndNil(dmGlobal);
  end;
end;


end.
