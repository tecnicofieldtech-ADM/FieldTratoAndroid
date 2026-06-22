unit Controllers.Get;

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
  Udm,
  DataSet.Serialize,
  Horse.Commons,
  Controllers.Mirror,
  System.Math;

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
  D: string;
begin
  D := RetornaDataFormadata(AIso);
  Result := TryStrToDate(D, ADate);
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

procedure BindCommonFilters(Q: TFDQuery; Req: THorseRequest);
var
  S: string;
begin
  S := QueryParam(Req, 'id_dieta', '');
  Q.ParamByName('SKIP_DIETA').AsInteger := IfThen(S = '', 1, 0);
  Q.ParamByName('ID_DIETA').AsString := S;

  S := QueryParam(Req, 'id_operador', '');
  Q.ParamByName('SKIP_OPERADOR').AsInteger := IfThen(S = '', 1, 0);
  Q.ParamByName('ID_OPERADOR').AsString := S;

  S := QueryParam(Req, 'id_vagao', '');
  Q.ParamByName('SKIP_VAGAO').AsInteger := IfThen(S = '', 1, 0);
  Q.ParamByName('ID_VAGAO').AsString := S;
end;

procedure RegistraRotas;
begin
 THorse.Get('/GetTeste',GetTeste);
 THorse.Get('/usuarios/get/:idfazenda',GetUsuarios);
 THorse.Get('/dietas/get/:idfazenda',GetDietas);
 THorse.Get('/dietas_detalhes/get/:idfazenda',GetDietasDetalhes);
 THorse.Get('/fazenda/get',GetFazendas);
 THorse.Get('/baias/get/:idfazenda',GetBaias);
 THorse.Get('/previsao_trato/get/:idfazenda/:dataPrev',GetPrevisaoTrato);
 THorse.Get('/vagao/get',GetVagao);
 THorse.Get('/dashboard/fabricacao/resumo', GetDashboardFabricacaoResumo);
 THorse.Get('/dashboard/fabricacao/insumos', GetDashboardFabricacaoInsumos);
 THorse.Get('/dashboard/fabricacao/fornecimento', GetDashboardFabricacaoFornecimento);
end;

procedure GetDashboardFabricacaoResumo(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  dmGlobal: TdmDB;
  Q: TFDQuery;
  DIni, DFim: TDateTime;
  OkRange: Boolean;
begin
  RequireDateRangeOr400(Req, Res, DIni, DFim, OkRange);
  if not OkRange then
    Exit;

  dmGlobal := TdmDB.Create(nil);
  Q := TFDQuery.Create(nil);
  try
    dmGlobal.ConectaDBCGPec;
    Q.Connection := dmGlobal.FBCon;
    Q.SQL.Text :=
      'SELECT ' +
      '  cop.NOME AS OPERADOR, ' +
      '  vag.NOME AS VAGAO, ' +
      '  cd.NOME_DIETA, ' +
      '  CAST(cfr.QTDE_PREVISTA AS DOUBLE PRECISION) AS QTDE_PREVISTA, ' +
      '  CAST(cfr.QTDE_REALIZADA AS DOUBLE PRECISION) AS QTDE_REALIZADA, ' +
      '  CAST((cfr.QTDE_PREVISTA - cfr.QTDE_REALIZADA) AS DOUBLE PRECISION) AS DIFKG, ' +
      '  CAST(((cfr.QTDE_PREVISTA - cfr.QTDE_REALIZADA) * 100.0) / NULLIF(cfr.QTDE_PREVISTA, 0) AS DOUBLE PRECISION) AS DIFPERCENT, ' +
      '  cfr.ID, cfr.ID_DIETA, cfr.ID_OPERADOR, cfr.ID_VAGAO, ' +
      '  CAST(cfr.DATA_REGISTO AS TIMESTAMP) AS DATA_REGISTO ' +
      'FROM CADASTRO_FABRICA_RACAO cfr ' +
      'JOIN CADASTRO_DIETAS cd ON cfr.ID_DIETA = cd.ID ' +
      'JOIN CADASTRO_USUARIO cop ON cfr.ID_OPERADOR = cop.ID ' +
      'LEFT JOIN CADASTRO_INSUMOS vag ON vag.ID = cfr.ID_VAGAO ' +
      'WHERE cfr."DATA" BETWEEN :DATA_INI AND :DATA_FIM ' +
      '  AND ((:SKIP_DIETA = 1) OR (cfr.ID_DIETA = :ID_DIETA)) ' +
      '  AND ((:SKIP_OPERADOR = 1) OR (cfr.ID_OPERADOR = :ID_OPERADOR)) ' +
      '  AND ((:SKIP_VAGAO = 1) OR (cfr.ID_VAGAO = :ID_VAGAO)) ' +
      'ORDER BY cfr.DATA_REGISTO DESC';
    Q.ParamByName('DATA_INI').AsDate := DIni;
    Q.ParamByName('DATA_FIM').AsDate := DFim;
    BindCommonFilters(Q, Req);
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
  dmGlobal: TdmDB;
  Q: TFDQuery;
  DIni, DFim: TDateTime;
  OkRange: Boolean;
begin
  RequireDateRangeOr400(Req, Res, DIni, DFim, OkRange);
  if not OkRange then
    Exit;

  dmGlobal := TdmDB.Create(nil);
  Q := TFDQuery.Create(nil);
  try
    dmGlobal.ConectaDBCGPec;
    Q.Connection := dmGlobal.FBCon;
    Q.SQL.Text :=
      'SELECT ' +
      '  cop.NOME AS OPERADOR, ' +
      '  vag.NOME AS VAGAO, ' +
      '  cd.NOME_DIETA, ' +
      '  CAST(cfr.QTDE_PREVISTA AS DOUBLE PRECISION) AS QTDE_PREVISTA, ' +
      '  CAST(cfr.QTDE_REALIZADA AS DOUBLE PRECISION) AS QTDE_REALIZADA, ' +
      '  CAST((cfr.QTDE_PREVISTA - cfr.QTDE_REALIZADA) AS DOUBLE PRECISION) AS DIFKG_TOTAL, ' +
      '  CAST(((cfr.QTDE_PREVISTA - cfr.QTDE_REALIZADA) * 100.0) / NULLIF(cfr.QTDE_PREVISTA, 0) AS DOUBLE PRECISION) AS DIFPERCENT_TOTAL, ' +
      '  ci2.NOME AS INSUMO, ' +
      '  CAST(dfr.QTDE_PREVISTA AS DOUBLE PRECISION) AS PREVISTO_KG_INSUMO, ' +
      '  CAST(dfr.QTDE_REALIZADA AS DOUBLE PRECISION) AS REALIZADO_KG_INSUMO, ' +
      '  CAST((dfr.QTDE_PREVISTA - dfr.QTDE_REALIZADA) AS DOUBLE PRECISION) AS DIF_KG_INSUMO, ' +
      '  CAST(((dfr.QTDE_PREVISTA - dfr.QTDE_REALIZADA) * 100.0) / NULLIF(dfr.QTDE_PREVISTA, 0) AS DOUBLE PRECISION) AS DIFPERCENT_INSUMO, ' +
      '  cfr.ID, dfr.ID AS ID_DETALHE, cfr.ID_DIETA, cfr.ID_OPERADOR, cfr.ID_VAGAO ' +
      'FROM CADASTRO_FABRICA_RACAO cfr ' +
      'JOIN DETALHES_FABRICA_RACAO dfr ON dfr.ID_CADASTRO_FABRICA_RACAO = cfr.ID ' +
      'JOIN CADASTRO_INSUMOS ci2 ON ci2.ID = dfr.ID_INSUMO ' +
      'JOIN CADASTRO_DIETAS cd ON cfr.ID_DIETA = cd.ID ' +
      'JOIN CADASTRO_USUARIO cop ON cfr.ID_OPERADOR = cop.ID ' +
      'LEFT JOIN CADASTRO_INSUMOS vag ON vag.ID = cfr.ID_VAGAO ' +
      'WHERE cfr."DATA" BETWEEN :DATA_INI AND :DATA_FIM ' +
      '  AND ((:SKIP_DIETA = 1) OR (cfr.ID_DIETA = :ID_DIETA)) ' +
      '  AND ((:SKIP_OPERADOR = 1) OR (cfr.ID_OPERADOR = :ID_OPERADOR)) ' +
      '  AND ((:SKIP_VAGAO = 1) OR (cfr.ID_VAGAO = :ID_VAGAO)) ' +
      'ORDER BY cfr.DATA_REGISTO DESC';
    Q.ParamByName('DATA_INI').AsDate := DIni;
    Q.ParamByName('DATA_FIM').AsDate := DFim;
    BindCommonFilters(Q, Req);
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
  dmGlobal: TdmDB;
  Q: TFDQuery;
  DIni, DFim: TDateTime;
  OkRange: Boolean;
begin
  RequireDateRangeOr400(Req, Res, DIni, DFim, OkRange);
  if not OkRange then
    Exit;

  dmGlobal := TdmDB.Create(nil);
  Q := TFDQuery.Create(nil);
  try
    dmGlobal.ConectaDBCGPec;
    Q.Connection := dmGlobal.FBCon;
    Q.SQL.Text :=
      'SELECT ' +
      '  cop.NOME AS OPERADOR, ' +
      '  vag.NOME AS VAGAO, ' +
      '  cd.NOME_DIETA, ' +
      '  CAST(cfr.QTDE_PREVISTA AS DOUBLE PRECISION) AS QTDE_PREVISTA, ' +
      '  CAST(cfr.QTDE_REALIZADA AS DOUBLE PRECISION) AS QTDE_REALIZADA, ' +
      '  CAST((cfr.QTDE_PREVISTA - cfr.QTDE_REALIZADA) AS DOUBLE PRECISION) AS DIFKG, ' +
      '  CAST(((cfr.QTDE_PREVISTA - cfr.QTDE_REALIZADA) * 100.0) / NULLIF(cfr.QTDE_PREVISTA, 0) AS DOUBLE PRECISION) AS DIFPERCENT, ' +
      '  db.NOME_LOCAL AS CURRAL, ' +
      '  CAST(cf.PREVISTO AS DOUBLE PRECISION) AS PREVISTO_FORNECIMENTO, ' +
      '  CAST(cf.REALIZADO AS DOUBLE PRECISION) AS REALIZADO_FORNECIMENTO, ' +
      '  CAST((cf.PREVISTO - cf.REALIZADO) AS DOUBLE PRECISION) AS DIF_KG_FORNECIMENTO, ' +
      '  cfr.ID, cfr.ID_DIETA, cfr.ID_OPERADOR, cfr.ID_VAGAO, cf.ID AS ID_FORNECIMENTO, cf.ID_BAIA ' +
      'FROM CADASTRO_FABRICA_RACAO cfr ' +
      'JOIN CADASTRO_DIETAS cd ON cfr.ID_DIETA = cd.ID ' +
      'JOIN CADASTRO_USUARIO cop ON cfr.ID_OPERADOR = cop.ID ' +
      'LEFT JOIN CADASTRO_INSUMOS vag ON vag.ID = cfr.ID_VAGAO ' +
      'LEFT JOIN CADASTRO_FORNECIMENTO cf ON cf.ID_FABRICACAO = cfr.ID ' +
      'LEFT JOIN DETALHES_BAIAS db ON db.ID = cf.ID_BAIA ' +
      'WHERE cfr."DATA" BETWEEN :DATA_INI AND :DATA_FIM ' +
      '  AND ((:SKIP_DIETA = 1) OR (cfr.ID_DIETA = :ID_DIETA)) ' +
      '  AND ((:SKIP_OPERADOR = 1) OR (cfr.ID_OPERADOR = :ID_OPERADOR)) ' +
      '  AND ((:SKIP_VAGAO = 1) OR (cfr.ID_VAGAO = :ID_VAGAO)) ' +
      'ORDER BY cfr.DATA_REGISTO DESC';
    Q.ParamByName('DATA_INI').AsDate := DIni;
    Q.ParamByName('DATA_FIM').AsDate := DFim;
    BindCommonFilters(Q, Req);
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
var
  LJson: TJSONObject;
begin
  try
    LJson := TJSONObject.Create;
    LJson.AddPair('OK', 'Servidor Online');
    LJson.AddPair('ini', dmdb.ConfigIniFilePath);
    Res.Send(LJson).Status(THTTPStatus.OK);
  except
    on E: Exception do
      Res.Send(TJSONObject.Create.AddPair('erro', E.Message)).Status(THTTPStatus.InternalServerError);
  end;
end;




procedure GetBaias(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  dmGlobal: TdmDB;
  idFazenda: string;
  LArr: TJSONArray;
begin
  try
    dmGlobal := TdmDB.Create(nil);
    try
      // Conecta usando o ApiConfig.ini
      dmGlobal.ConectaDBCGPec;

      // Aponta a conex�o da query corretamente
      dmGlobal.BAIAS.Connection := dmGlobal.FBCon;

      // Par�metro
      idFazenda := Req.Params.Items['idfazenda'];

      // Executa a query
      dmGlobal.BAIAS.Close;
      dmGlobal.BAIAS.ParamByName('ID').AsString := idFazenda;
      dmGlobal.BAIAS.Open;

      LArr := dmGlobal.BAIAS.ToJSONArray;
      Res.Send<TJSONArray>(LArr).Status(200);
      MirrorGetArray('/baias/get/[idfazenda]',
        Format('{"idFazenda":"%s"}', [idFazenda]), LArr, 200);
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


//procedure GetPrevisaoTrato(Req: THorseRequest; Res: THorseResponse; Next: TProc);
//var
//  dmGlobal: TdmDB;
//  idFazenda, dataPrevStr: string;
//  dataPrev: TDateTime;
//begin
//  try
//    dmGlobal := TdmDB.Create(nil);
//    try
//      dmGlobal.ConectaDBCGPec;
//
//      dmGlobal.PREVISAO.Connection := dmGlobal.FBCon;
//
//      // Agora os par�metros v�m da URL segmentada
//      idFazenda   := Req.Params['idFazenda'];
//      dataPrevStr := RetornaDataFormadata(Req.Params['dataPrev']);
//
//      if not TryStrToDate(dataPrevStr, dataPrev) then
//      begin
//        Res.Send(TJSONObject.Create.AddPair('erro', 'Data inv�lida')).Status(400);
//        Exit;
//      end;
//
//      dmGlobal.PREVISAO.Close;
//
//      dmGlobal.PREVISAO.SQL.Text :=
//      'SELECT ' +
//      '  s.ID AS ID_FORNECIMENTO, ' +
//      '  s."DATA" AS data, ' +
//      '  db.ID AS id, ' +
//      '  s.TRATO AS trato, ' +
//      '  trunc(IIF( ' +
//      '    s.TRATO = ( ' +
//      '      SELECT MAX(ss.TRATO) ' +
//      '      FROM CADASTRO_FORNECIMENTO ss ' +
//      '      WHERE ss.ID_LOTE = s.ID_LOTE ' +
//      '        AND ss.DATA = s.DATA ' +
//      '    ), ' +
//      '    ( ' +
//      '      SELECT ( ' +
//      '        COALESCE(SUM(sss.PREV_MS_CONSUMIDA),0) - COALESCE(SUM(sss.REAL_MS_CONSUMIDA),0) ' +
//      '      ) ' +
//      '      FROM CADASTRO_FORNECIMENTO sss ' +
//      '      WHERE sss.DATA = s.DATA ' +
//      '        AND sss.ID_LOTE = s.ID_LOTE ' +
//      '    ) / (s.MS_DIETA_PREVISTA) * 100, ' +
//      '    s.PREVISTO ' +
//      '  ))  AS previsto, ' +
//      '  TRUNC(s.REALIZADO) AS realizado, ' +
//      '  s.ID_DIETA AS id_Dieta ' +
//      'FROM CADASTRO_FORNECIMENTO s ' +
//      'JOIN CADASTRO_LOTE_ENGORDA l ON l.ID = s.ID_LOTE ' +
//      'JOIN DETALHES_BAIAS db ON db.ID = s.ID_BAIA ' +
//      'JOIN CADASTRO_DIETAS d ON d.ID = s.ID_DIETA ' +
//      'JOIN CADASTRO_AREAS a ON a.ID = db.ID_BAIA ' +
//      'WHERE s."DATA" = :DATA ' +
//      '  AND L.ID_FAZENDA  = :ID ' +
//      'ORDER BY d.NOME_DIETA, db.ORDEM_TRATO';
//
//
//
//
//      dmGlobal.PREVISAO.ParamByName('DATA').AsDate := dataPrev;
//      dmGlobal.PREVISAO.ParamByName('ID').AsString := idFazenda;
//
//      dmGlobal.PREVISAO.Open;
//
//      Res.Send<TJSONArray>(dmGlobal.PREVISAO.ToJSONArray).Status(200);
//    except
//      on ex: Exception do
//      begin
//        Res.Send(
//          TJSONObject.Create.AddPair('erro', ex.Message)
//        ).Status(500);
//      end;
//    end;
//  finally
//    FreeAndNil(dmGlobal);
//  end;
//end;

procedure GetPrevisaoTrato(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  dmGlobal: TdmDB;
  idFazenda, dataPrevStr: string;
  dataPrev: TDateTime;
  LArr: TJSONArray;
begin
  try
    dmGlobal := TdmDB.Create(nil);
    try
      // Conex�o via .ini
      dmGlobal.ConectaDBCGPec;

      // Aponta conex�o da query corretamente
      dmGlobal.PREVISAO.Connection := dmGlobal.FBCon;

      // Par�metros
      idFazenda    := Req.Params.Items['idfazenda'];
      dataPrevStr  := RetornaDataFormadata(Req.Params.Items['dataPrev']);

      if not TryStrToDate(dataPrevStr, dataPrev) then
      begin
        Res.Send(TJSONObject.Create.AddPair('erro', 'Data inv�lida')).Status(400);
        Exit;
      end;

      dmGlobal.GeraTabelaTMP_Previsao(idFazenda, dataPrev);

      // Execu��o da query
      dmGlobal.PREVISAO.Close;
      dmGlobal.PREVISAO.Open;
      dmGlobal.PREVISAO.RecordCount;

      LArr := dmGlobal.PREVISAO.ToJSONArray;
      Res.Send<TJSONArray>(LArr).Status(200);
      MirrorGetArray('/previsao_trato/get/[idfazenda]/[dataPrev]',
        Format('{"idFazenda":"%s","dataIso":"%s"}',
          [idFazenda, FormatDateTime('yyyy-mm-dd', dataPrev)]), LArr, 200);
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


procedure GetDietasDetalhes(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  dmGlobal: TdmDB;
  idFazenda: string;
  LArr: TJSONArray;
begin
  try
    dmGlobal := TdmDB.Create(nil);
    try
      // Garante conex�o com dados do INI
      dmGlobal.ConectaDBCGPec;

      // Aponta a conex�o da query para a conex�o correta
      dmGlobal.DETALHES_DIETAS.Connection := dmGlobal.FBCon;

      idFazenda := Req.Params.Items['idfazenda'];

      dmGlobal.DETALHES_DIETAS.Close;
      dmGlobal.DETALHES_DIETAS.ParamByName('ID').AsString := idFazenda;
      dmGlobal.DETALHES_DIETAS.Open;

      LArr := dmGlobal.DETALHES_DIETAS.ToJSONArray;
      Res.Send<TJSONArray>(LArr).Status(200);
      MirrorGetArray('/dietas_detalhes/get/[idfazenda]',
        Format('{"idFazenda":"%s"}', [idFazenda]), LArr, 200);
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
  dmGlobal: TdmDB;
  idFazenda: string;
  LArr: TJSONArray;
begin
  try
    dmGlobal := TdmDB.Create(nil);
    try
      // Conecta corretamente ao banco com dados do INI
      dmGlobal.ConectaDBCGPec;

      // Aponta a conex�o da query para a conex�o rec�m-carregada
      dmGlobal.CADASTRO_DIETAS.Connection := dmGlobal.FBCon;

      idFazenda := Req.Params.Items['idfazenda'];

      dmGlobal.CADASTRO_DIETAS.Close;
      dmGlobal.CADASTRO_DIETAS.ParamByName('ID').AsString := idFazenda;
      dmGlobal.CADASTRO_DIETAS.Open;

      LArr := dmGlobal.CADASTRO_DIETAS.ToJSONArray;
      Res.Send<TJSONArray>(LArr).Status(200);
      MirrorGetArray('/dietas/get/[idfazenda]',
        Format('{"idFazenda":"%s"}', [idFazenda]), LArr, 200);
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
  dmGlobal: TdmDB;
  idFazenda: string;
  LArr: TJSONArray;
begin
  try
    dmGlobal := TdmDB.Create(nil);
    try
      // Aplica conex�o correta
      dmGlobal.ConectaDBCGPec;

      // Garante que a query esteja usando a conex�o atual
      dmGlobal.CADASTRO_USUARIO.Connection := dmGlobal.FBCon;

      idFazenda := Req.Params.Items['idfazenda'];

      dmGlobal.CADASTRO_USUARIO.Close;
      dmGlobal.CADASTRO_USUARIO.ParamByName('ID').AsString := idFazenda;
      dmGlobal.CADASTRO_USUARIO.Open;

      LArr := dmGlobal.CADASTRO_USUARIO.ToJSONArray;
      Res.Send<TJSONArray>(LArr).Status(200);
      MirrorGetArray('/usuarios/get/[idfazenda]',
        Format('{"idFazenda":"%s"}', [idFazenda]), LArr, 200);
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

procedure GetVagao(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  dmGlobal: TdmDB;
  LArr: TJSONArray;
begin
  try
    dmGlobal := TdmDB.Create(nil);
    try
      dmGlobal.ConectaDBCGPec; // <- CORRETO AGORA

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
  dmGlobal: TdmDB;
  LArr: TJSONArray;
begin
  try
    dmGlobal := TdmDB.Create(nil);
    try
      // Aplica conex�o da inst�ncia correta
      dmGlobal.ConectaDBCGPec;

      // Garante que a query esteja usando a conex�o correta
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
