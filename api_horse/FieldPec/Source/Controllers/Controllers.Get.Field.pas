unit Controllers.Get.Field;

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

uses DataSet.Serialize, UdmFieldPec, Controllers.Mirror;

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


procedure GetPrevisaoTrato(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  dmGlobal: TdmFieldPec;
  LArr: TJSONArray;
begin
  try
    dmGlobal := TdmFieldPec.Create(nil);
    try
      dmGlobal.ConectaDBField;
      dmGlobal.PREVISAO.Connection := dmGlobal.FBCon;
      dmGlobal.PREVISAO.Close;
      dmGlobal.PREVISAO.Open;
      dmGlobal.PREVISAO.RecordCount;

      LArr := dmGlobal.PREVISAO.ToJSONArray;
      Res.Send<TJSONArray>(LArr).Status(200);
      MirrorGetArray('/previsao_trato/get/[idfazenda]/[dataPrev]',
        MirrorReqPrevisao(Req), LArr, 200);
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
