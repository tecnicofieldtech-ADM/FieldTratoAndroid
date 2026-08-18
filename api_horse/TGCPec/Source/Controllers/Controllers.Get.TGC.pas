unit Controllers.Get.TGC;

interface

uses
  Horse,
  System.JSON,
  System.SysUtils,
  FireDAC.Comp.Client;

procedure RegistraRotas;

implementation

uses
  DataSet.Serialize,
  UdmTGC,
  Controllers.Mirror;

procedure GetTeste(Req: THorseRequest; Res: THorseResponse; Next: TProc); forward;
procedure GetUsuarios(Req: THorseRequest; Res: THorseResponse; Next: TProc); forward;
procedure GetBaias(Req: THorseRequest; Res: THorseResponse; Next: TProc); forward;
procedure GetDietas(Req: THorseRequest; Res: THorseResponse; Next: TProc); forward;
procedure GetDietasDetalhes(Req: THorseRequest; Res: THorseResponse; Next: TProc); forward;
procedure GetPrevisaoTrato(Req: THorseRequest; Res: THorseResponse; Next: TProc); forward;
procedure GetFazendas(Req: THorseRequest; Res: THorseResponse; Next: TProc); forward;
procedure GetVagao(Req: THorseRequest; Res: THorseResponse; Next: TProc); forward;

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

procedure RunGetQuery(
  Req: THorseRequest;
  Res: THorseResponse;
  const ASql: string;
  const AMirrorPath, AMirrorReq: string);
var
  dm: TdmTGC;
  Q: TFDQuery;
  LArr: TJSONArray;
begin
  dm := nil;
  Q := nil;
  try
    dm := TdmTGC.Create(nil);
    dm.ConectaDBTGC;
    Q := TFDQuery.Create(nil);
    Q.Connection := dm.FBCon;
    Q.SQL.Text := ASql;
    Q.Open;
    LArr := Q.ToJSONArray;
    Res.Send<TJSONArray>(LArr).Status(200);
    if AMirrorPath <> '' then
      MirrorGetArray(AMirrorPath, AMirrorReq, LArr, 200);
  except
    on E: Exception do
      Res.Send(TJSONObject.Create.AddPair('erro', E.Message)).Status(500);
  end;
  Q.Free;
  dm.Free;
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
end;

procedure GetTeste(Req: THorseRequest; Res: THorseResponse; Next: TProc);
begin
  try
    Res.Send(TJSONObject.Create.AddPair('OK', 'Servidor Online TGC')).Status(200);
  except
    on E: Exception do
      Res.Send(TJSONObject.Create.AddPair('Erro', E.Message)).Status(500);
  end;
end;

procedure GetUsuarios(Req: THorseRequest; Res: THorseResponse; Next: TProc);
const
  SQL_CAD_FUNCIONARIO =
    'SELECT ' +
    '  U.CF_CODIGO AS ID, ' +
    '  U.CF_NOME AS NOME, ' +
    '  U.CF_APELIDO AS LOGIN, ' +
    '  U.CF_APELIDO AS USUARIO, ' +
    '  U.CF_SENHA AS SENHA, ' +
    '  CASE ' +
    '    WHEN U.CF_CARGO = ''OPERADOR DE PA'' THEN ''1'' ' +
    '    WHEN U.CF_CARGO = ''OPERADOR'' THEN ''1'' ' +
    '    WHEN U.CF_CARGO = ''PASEIRO'' THEN ''1'' ' +
    '    WHEN U.CF_CARGO = ''OPERADOR PÁ'' THEN ''1'' ' +
    '    ELSE ''0'' ' +
    '  END AS CARGO, ' +
    '  CASE ' +
    '    WHEN U.CF_CARGO = ''OPERADOR DE PA'' THEN ''1'' ' +
    '    WHEN U.CF_CARGO = ''OPERADOR'' THEN ''1'' ' +
    '    WHEN U.CF_CARGO = ''PASEIRO'' THEN ''1'' ' +
    '    WHEN U.CF_CARGO = ''OPERADOR PÁ'' THEN ''1'' ' +
    '    ELSE ''0'' ' +
    '  END AS OPERADOR, ' +
    '  CURRENT_DATE AS DATAREG, ' +
    '  CASE ' +
    '    WHEN U.CF_STATUS = ''A'' THEN ''1'' ' +
    '    ELSE ''0'' ' +
    '  END AS STATUS, ' +
    '  ''1'' AS TIPO ' +
    'FROM CAD_FUNCIONARIO U ' +
    'WHERE U.CF_SENHA IS NOT NULL ' +
    '  AND U.CF_SENHA <> '''' ';
begin
  RunGetQuery(Req, Res, SQL_CAD_FUNCIONARIO, '/usuarios/get/[idfazenda]', MirrorReqIdFazenda(Req));
end;

procedure GetBaias(Req: THorseRequest; Res: THorseResponse; Next: TProc);
const
  SQL_CURRAIS =
    'SELECT ' +
    '  A.CC_CODIGO AS ID, ' +
    '  A.CC_CODIGO AS ID_BAIA, ' +
    '  A.CC_NOME AS NOME_LOCAL, ' +
    '  A.CC_NOME AS NOME, ' +
    '  A.CC_LINHA AS LINHA, ' +
    '  A.CC_NUMERO AS NUMERO, ' +
    '  A.CC_TAG_INICIAL AS TAG_INICIO, ' +
    '  A.CC_TAG_INICIAL AS RFID, ' +
    '  A.CC_TAG_FINAL AS TAG_FIM, ' +
    '  A.CC_ORDEM AS ORDEM_TRATO, ' +
    '  A.CC_ORDEM AS ORDEM, ' +
    '  CASE WHEN A.CC_STATUS = ''ATIVO'' THEN ''1'' ELSE ''-1'' END AS STATUS ' +
    'FROM CAD_CURRAL A ' +
    'WHERE A.CC_STATUS = ''ATIVO''';
begin
  RunGetQuery(Req, Res, SQL_CURRAIS, '/baias/get/[idfazenda]', MirrorReqIdFazenda(Req));
end;

procedure GetDietas(Req: THorseRequest; Res: THorseResponse; Next: TProc);
const
  SQL_RACAO =
    'SELECT ' +
    '  RD.CRP_CODIGO AS ID, ' +
    '  REPLACE(V.CR_NOME, ''%'', '''') AS NOME_DIETA, ' +
    '  REPLACE(V.CR_NOME, ''%'', '''') AS NOME, ' +
    '  V.CR_TIPO AS TIPO_DIETA, ' +
    '  V.CR_TIPO AS TIPO, ' +
    '  RD.CRP_TEMPO_MISTURA * 60 AS TempoMistura, ' +
    '  ''1'' AS STATUS, ' +
    '  RD.CRP_DATAREG AS Datareg ' +
    'FROM CAD_RACAO_PROD RD ' +
    'JOIN CAD_RACAO V ON V.CR_CODIGO = RD.CRP_CODRACAO ' +
    'WHERE RD.CRP_STATUS = ''A''';
begin
  RunGetQuery(Req, Res, SQL_RACAO, '/dietas/get/[idfazenda]', MirrorReqIdFazenda(Req));
end;

procedure GetDietasDetalhes(Req: THorseRequest; Res: THorseResponse; Next: TProc);
const
  SQL_INSUMOS =
    'SELECT ' +
    '  A.ID, ' +
    '  ca.AA_NOME AS NOME, ' +
    '  ca.AA_NOME AS INGREDIENTE, ' +
    '  A.CODIGORECEITA AS ID_DIETA, ' +
    '  A.CODIGORECEITA AS IDRACAO, ' +
    '  A.CODIGOINGREDIENTE AS ID_INSUMO, ' +
    '  A.CODIGOINGREDIENTE AS IDALIMENTO, ' +
    '  A.PERCENTUALMATERIANATURAL AS MN_PERC, ' +
    '  A.PERCENTUALMATERIANATURAL AS INCLUSAOMN, ' +
    '  A.ORDEMBATIDA AS ORDEM, ' +
    '  A.TOLERANCIA AS PERCENTTOLERANCIA, ' +
    '  DP.DETRAP_VALOR AS VALORKG, ' +
    '  DP.DETRAP_MSALIM AS MS_INSUMO, ' +
    '  DP.DETRAP_MSALIM AS MS ' +
    'FROM CR1_INGREDIENTES_RECEITA A ' +
    'JOIN DET_ALIM_RACAO_PROD DP ON DP.DETRAP_CODRACAOPROD = A.CODIGORECEITA ' +
    '  AND DP.DETRAP_CODALIMENTO = A.CODIGOINGREDIENTE ' +
    'JOIN CAD_ALIMENTO ca ON ca.AA_CODIGO = DP.DETRAP_CODALIMENTO ' +
    'JOIN CAD_RACAO_PROD CRP ON A.CODIGORECEITA = CRP.CRP_CODIGO ' +
    'WHERE CRP.CRP_STATUS = ''A'' ' +
    '  AND A.COD_MISTURADOR = 1';
  SQL_INSUMOS_SEM_DP =
    'SELECT ' +
    '  A.ID, ' +
    '  ca.AA_NOME AS NOME, ' +
    '  ca.AA_NOME AS INGREDIENTE, ' +
    '  A.CODIGORECEITA AS ID_DIETA, ' +
    '  A.CODIGORECEITA AS IDRACAO, ' +
    '  A.CODIGOINGREDIENTE AS ID_INSUMO, ' +
    '  A.CODIGOINGREDIENTE AS IDALIMENTO, ' +
    '  A.PERCENTUALMATERIANATURAL AS MN_PERC, ' +
    '  A.PERCENTUALMATERIANATURAL AS INCLUSAOMN, ' +
    '  A.ORDEMBATIDA AS ORDEM, ' +
    '  A.TOLERANCIA AS PERCENTTOLERANCIA, ' +
    '  0 AS VALORKG, ' +
    '  0 AS MS_INSUMO, ' +
    '  0 AS MS ' +
    'FROM CR1_INGREDIENTES_RECEITA A ' +
    'JOIN CAD_ALIMENTO ca ON ca.AA_CODIGO = A.CODIGOINGREDIENTE ' +
    'JOIN CAD_RACAO_PROD CRP ON A.CODIGORECEITA = CRP.CRP_CODIGO ' +
    'WHERE CRP.CRP_STATUS = ''A'' ' +
    '  AND A.COD_MISTURADOR = 1';

  function TryOpenDetalhes(Q: TFDQuery; const ASql: string; out AErr: string): Boolean;
  begin
    Result := False;
    AErr := '';
    try
      Q.Close;
      Q.SQL.Text := ASql;
      Q.Open;
      Result := True;
    except
      on E: Exception do
        AErr := E.Message;
    end;
  end;

var
  dm: TdmTGC;
  Q: TFDQuery;
  LArr: TJSONArray;
  LErr: string;
begin
  dm := nil;
  Q := nil;
  try
    dm := TdmTGC.Create(nil);
    dm.ConectaDBTGC;
    Q := TFDQuery.Create(nil);
    Q.Connection := dm.FBCon;

    if not TryOpenDetalhes(Q, SQL_INSUMOS, LErr) then
    begin
      if not TryOpenDetalhes(Q, SQL_INSUMOS_SEM_DP, LErr) then
        raise Exception.Create('Dietas detalhes TGC: ' + LErr);
    end;

    LArr := Q.ToJSONArray;
    Res.Send<TJSONArray>(LArr).Status(200);
    try
      MirrorGetArray('/dietas_detalhes/get/[idfazenda]', MirrorReqIdFazenda(Req), LArr, 200);
    except
    end;
  except
    on E: Exception do
      Res.Send(TJSONObject.Create.AddPair('erro', E.Message)).Status(500);
  end;
  Q.Free;
  dm.Free;
end;

procedure GetPrevisaoTrato(Req: THorseRequest; Res: THorseResponse; Next: TProc);
{ Ultimo trato (igual FieldPec):
  PREVISTO_CADASTRO     = CFORN_PREVISTO                        — previsto do trato, sem ajuste
  PREVISTO_ORIGINAL     = (SumPrev - SumReal) + RealizadoAtual  — meta, nao encolhe
  PREVISTO_RECALCULADO  = (SumPrev - SumReal)                   — saldo com ajuste
  PREVISTO / KGPREVISTO = PREVISTO_RECALCULADO
  Demais tratos: cadastro/original/recalculado = CFORN_PREVISTO. }
const
  SQL_PREVISAO =
    'SELECT ' +
    '  y.CFORN_CODIGO AS ID, ' +
    '  y.CFORN_CODIGO AS ID_FORNECIMENTO, ' +
    '  y.DATA, ' +
    '  y.IDCURRAL AS ID_BAIA, ' +
    '  y.IDCURRAL, ' +
    '  y.IDRACAO AS ID_RACAO, ' +
    '  y.IDRACAO, ' +
    '  y.STATUS, ' +
    '  y.TRATO, ' +
    '  y.TIPO, ' +
    '  y.PREVISTO_CADASTRO, ' +
    '  y.PREVISTO_ORIGINAL, ' +
    '  y.PREVISTO_RECALCULADO, ' +
    '  y.PREVISTO_RECALCULADO AS PREVISTO, ' +
    '  y.PREVISTO_RECALCULADO AS KGPREVISTO, ' +
    '  y.ULTIMO_TRATO, ' +
    '  COALESCE(y.KGREALIZADO, 0) AS REALIZADO, ' +
    '  COALESCE(y.KGREALIZADO, 0) AS KGREALIZADO ' +
    'FROM ( ' +
    '  SELECT ' +
    '    A.CFORN_CODIGO, ' +
    '    A.CFORN_DATAFORNECIDO AS DATA, ' +
    '    A.CFORN_CODBAIA AS IDCURRAL, ' +
    '    A.CFORN_CODRACAOPROD AS IDRACAO, ' +
    '    ''1'' AS STATUS, ' +
    '    A.CFORN_TRATO AS TRATO, ' +
    '    1 AS TIPO, ' +
    '    ROUND(A.CFORN_PREVISTO) AS PREVISTO_CADASTRO, ' +
    '    CASE ' +
    '      WHEN A.CFORN_TRATO = ( ' +
    '        SELECT MAX(F.CFORN_TRATO) FROM CAD_FORNECIMENTO F ' +
    '        WHERE F.CFORN_DATAFORNECIDO = A.CFORN_DATAFORNECIDO ' +
    '          AND F.CFORN_CODLOTE = A.CFORN_CODLOTE ' +
    '          AND F.CFORN_CODBAIA = A.CFORN_CODBAIA) THEN 1 ' +
    '      ELSE 0 ' +
    '    END AS ULTIMO_TRATO, ' +
    '    CASE ' +
    '      WHEN A.CFORN_TRATO = ( ' +
    '        SELECT MAX(F.CFORN_TRATO) FROM CAD_FORNECIMENTO F ' +
    '        WHERE F.CFORN_DATAFORNECIDO = A.CFORN_DATAFORNECIDO ' +
    '          AND F.CFORN_CODLOTE = A.CFORN_CODLOTE ' +
    '          AND F.CFORN_CODBAIA = A.CFORN_CODBAIA) THEN ' +
    '        ROUND((SELECT SUM(F.CFORN_PREVISTO) - SUM(F.CFORN_REALIZADO) ' +
    '               FROM CAD_FORNECIMENTO F ' +
    '               WHERE F.CFORN_DATAFORNECIDO = A.CFORN_DATAFORNECIDO ' +
    '                 AND F.CFORN_CODBAIA = A.CFORN_CODBAIA) ' +
    '              + COALESCE(A.CFORN_REALIZADO, 0)) ' +
    '      ELSE ROUND(A.CFORN_PREVISTO) ' +
    '    END AS PREVISTO_ORIGINAL, ' +
    '    CASE ' +
    '      WHEN A.CFORN_TRATO = ( ' +
    '        SELECT MAX(F.CFORN_TRATO) FROM CAD_FORNECIMENTO F ' +
    '        WHERE F.CFORN_DATAFORNECIDO = A.CFORN_DATAFORNECIDO ' +
    '          AND F.CFORN_CODLOTE = A.CFORN_CODLOTE ' +
    '          AND F.CFORN_CODBAIA = A.CFORN_CODBAIA) THEN ' +
    '        ROUND((SELECT SUM(F.CFORN_PREVISTO) - SUM(F.CFORN_REALIZADO) ' +
    '               FROM CAD_FORNECIMENTO F ' +
    '               WHERE F.CFORN_DATAFORNECIDO = A.CFORN_DATAFORNECIDO ' +
    '                 AND F.CFORN_CODBAIA = A.CFORN_CODBAIA)) ' +
    '      ELSE ROUND(A.CFORN_PREVISTO) ' +
    '    END AS PREVISTO_RECALCULADO, ' +
    '    ROUND(A.CFORN_REALIZADO) AS KGREALIZADO ' +
    '  FROM CAD_FORNECIMENTO A ' +
    '  WHERE A.CFORN_DATAFORNECIDO = (SELECT MAX(CFORN_DATAFORNECIDO) FROM CAD_FORNECIMENTO) ' +
    ') y';
begin
  RunGetQuery(Req, Res, SQL_PREVISAO,
    '/previsao_trato/get/[idfazenda]/[dataPrev]', MirrorReqPrevisao(Req));
end;

procedure GetFazendas(Req: THorseRequest; Res: THorseResponse; Next: TProc);
const
  SQL_FAZENDA =
    'SELECT ' +
    '  f.CF_CODIGO AS IDFAZENDA, ' +
    '  f.CF_NOME AS FAZENDA, ' +
    '  COALESCE(f.CF_FANTASIA, f.CF_NOME) AS CLIENTE ' +
    'FROM CAD_FAZENDA f';
begin
  RunGetQuery(Req, Res, SQL_FAZENDA, '/fazenda/get', '{}');
end;

procedure GetVagao(Req: THorseRequest; Res: THorseResponse; Next: TProc);
const
  SQL_VAGAO =
    'SELECT cv.CCA_NUMERO AS Vagao, ' +
    '       cv.CCA_NUMERO AS ID, ' +
    '       cv.CCA_NUMERO AS NOME ' +
    'FROM CAD_VAGAO cv';
begin
  RunGetQuery(Req, Res, SQL_VAGAO, '/vagao/get', '{}');
end;

end.
