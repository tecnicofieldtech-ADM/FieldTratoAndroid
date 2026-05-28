unit Controllers.Get;

interface
uses
  Horse,
  Horse.Jhonson,
  Horse.CORS,
  System.JSON,
  System.SysUtils;

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
implementation

uses
  Udm,
  DataSet.Serialize,
  Horse.Commons,
  Controllers.Mirror;

function RetornaDataFormadata(vData: string): string;
var
  VAno, vMes, vDia: string;
begin
  if vData.Length = 10 then
  begin
    VAno := Copy(vData, 0, 4);
    vMes := Copy(vData, 6, 2);
    vDia := Copy(vData, 9, 2);
    Result := vDia + '/' + vMes + '/' + VAno;
  end
  else
    Result := 'Sem Data';
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
