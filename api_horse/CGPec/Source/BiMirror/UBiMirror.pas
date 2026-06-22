unit UBiMirror;

interface

procedure BiMirrorStart;
procedure BiMirrorStop;
procedure BiMirrorReloadConfig;
function NextApiBaseUrl: string;
procedure TrySyncConfigToNextApi(const AJsonBody: string; out AOk: Boolean; out AMessage: string);
procedure TryTestPostgresViaNextApi(const AJsonBody: string; out AOk: Boolean; out AMessage: string);
procedure BiMirrorQueueEvent(const AMethod, ARoute, ARequestJson, AResponseJson: string;
  AStatusCode, ADurationMs: Integer; const AErrorMsg: string = '');

implementation

uses
  System.Classes,
  System.SysUtils,
  System.JSON,
  System.SyncObjs,
  System.Generics.Collections,
  System.Net.HttpClient,
  System.Net.URLClient,
  IdHTTP,
  IdSSLOpenSSL,
  Udm;

type
  TMirrorJob = class
  public
    Method: string;
    Route: string;
    RequestJson: string;
    ResponseJson: string;
    StatusCode: Integer;
    DurationMs: Integer;
    ErrorMsg: string;
  end;

var
  GQueue: TThreadList<TMirrorJob>;
  GWorker: TThread;
  GStopEvent: TEvent;
  GEnabled: Boolean;
  GMirrorUrl: string;

function ReadMirrorIni(const AKey, ADefault: string): string;
begin
  Result := Trim(dmdb.ReadIniValue(dmdb.ConfigIniFilePath, 'MIRROR', AKey, ADefault));
end;

procedure BiMirrorReloadConfig;
var
  LVal: string;
begin
  LVal := LowerCase(ReadMirrorIni('Enabled', '0'));
  GEnabled := (LVal = '1') or (LVal = 'true') or (LVal = 's') or (LVal = 'sim');
  GMirrorUrl := ReadMirrorIni('Url', 'http://127.0.0.1:3000/api/mirror/event');
  if GMirrorUrl = '' then
    GEnabled := False;
end;

function NextApiBaseUrl: string;
const
  SUFFIX = '/api/mirror/event';
var
  LBase: string;
begin
  LBase := Trim(ReadMirrorIni('NextApiBase', ''));
  if LBase <> '' then
  begin
    Result := LBase;
    Exit;
  end;

  Result := Trim(GMirrorUrl);
  if Result = '' then
    Result := ReadMirrorIni('Url', 'http://127.0.0.1:3000/api/mirror/event');
  if (Length(Result) >= Length(SUFFIX)) and
     SameText(Copy(Result, Length(Result) - Length(SUFFIX) + 1, Length(SUFFIX)), SUFFIX) then
    SetLength(Result, Length(Result) - Length(SUFFIX));
  Result := Trim(Result);
  if Result = '' then
    Result := 'http://127.0.0.1:3000';
end;

function HttpPostJson(const AUrl, ABody: string; out AResponse: string): Boolean;
var
  LClient: THTTPClient;
  LContent: TStringStream;
  LResp: IHTTPResponse;
begin
  Result := False;
  AResponse := '';
  LClient := THTTPClient.Create;
  try
    LClient.ConnectionTimeout := 4000;
    LClient.ResponseTimeout := 30000;
    LContent := TStringStream.Create(ABody, TEncoding.UTF8);
    try
      LResp := LClient.Post(AUrl, LContent, nil,
        [TNetHeader.Create('Content-Type', 'application/json; charset=utf-8')]);
      AResponse := LResp.ContentAsString(TEncoding.UTF8);
      Result := True;
    finally
      LContent.Free;
    end;
  except
    on E: Exception do
      AResponse := E.Message;
  end;
end;

procedure TrySyncConfigToNextApi(const AJsonBody: string; out AOk: Boolean; out AMessage: string);
var
  LUrl, LResp: string;
  LJson: TJSONObject;
begin
  AOk := False;
  AMessage := '';
  LUrl := NextApiBaseUrl + '/api/config';
  try
    if not HttpPostJson(LUrl, AJsonBody, LResp) then
    begin
      AMessage := 'Não foi possível contactar a next-api em ' + LUrl;
      Exit;
    end;
    LJson := TJSONObject.ParseJSONValue(LResp) as TJSONObject;
    if LJson = nil then
    begin
      if (Length(LResp) > 0) and (LResp[1] = '<') then
        AMessage := 'Resposta HTML em ' + LUrl + '. A next-api deve rodar em outra porta que a API Horse (ex.: 3000).'
      else
        AMessage := 'Resposta inválida da next-api em ' + LUrl + '.';
      Exit;
    end;
    try
      if LJson.GetValue('erro') <> nil then
        AMessage := LJson.GetValue('erro').Value
      else
      begin
        AOk := True;
        AMessage := 'PostgreSQL sincronizado com a next-api (espelho BI).';
      end;
    finally
      LJson.Free;
    end;
  except
    on E: Exception do
      AMessage := E.Message;
  end;
end;

procedure TryTestPostgresViaNextApi(const AJsonBody: string; out AOk: Boolean; out AMessage: string);
var
  LUrl, LResp: string;
  LJson: TJSONObject;
  LOkVal: TJSONValue;
begin
  AOk := False;
  AMessage := '';
  LUrl := NextApiBaseUrl + '/api/config/test';
  try
    if not HttpPostJson(LUrl, AJsonBody, LResp) then
    begin
      AMessage := 'Não foi possível contactar a next-api em ' + LUrl + '. Inicie a next-api (porta 3000 ou NextApiBase no INI).';
      Exit;
    end;
    LJson := TJSONObject.ParseJSONValue(LResp) as TJSONObject;
    if LJson = nil then
    begin
      if (Length(LResp) > 0) and (LResp[1] = '<') then
        AMessage := 'Resposta HTML em ' + LUrl + '. A next-api deve rodar em outra porta que a API Horse (ex.: 3000).'
      else
        AMessage := 'Resposta inválida da next-api em ' + LUrl + '.';
      Exit;
    end;
    try
      LOkVal := LJson.GetValue('ok');
      AOk := (LOkVal <> nil) and (LOkVal is TJSONTrue);
      if not AOk then
      begin
        if LJson.GetValue('erro') <> nil then
          AMessage := LJson.GetValue('erro').Value
        else
          AMessage := 'Falha ao conectar no PostgreSQL.';
      end;
    finally
      LJson.Free;
    end;
  except
    on E: Exception do
      AMessage := E.Message;
  end;
end;

procedure PostMirrorJob(AJob: TMirrorJob);
var
  LList: TList<TMirrorJob>;
begin
  if not GEnabled or (AJob = nil) then
  begin
    AJob.Free;
    Exit;
  end;
  LList := GQueue.LockList;
  try
    LList.Add(AJob);
  finally
    GQueue.UnlockList;
  end;
end;

procedure SendJobToNextApi(AJob: TMirrorJob);
var
  LHttp: TIdHTTP;
  LSSL: TIdSSLIOHandlerSocketOpenSSL;
  LBody: TJSONObject;
  LStream: TStringStream;
  LResp: string;
begin
  if (AJob = nil) or (GMirrorUrl = '') then
    Exit;

  LBody := TJSONObject.Create;
  try
    LBody.AddPair('method', AJob.Method);
    LBody.AddPair('route', AJob.Route);
    LBody.AddPair('statusCode', TJSONNumber.Create(AJob.StatusCode));
    LBody.AddPair('durationMs', TJSONNumber.Create(AJob.DurationMs));

    if AJob.RequestJson <> '' then
    begin
      try
        LBody.AddPair('request', TJSONObject.ParseJSONValue(AJob.RequestJson));
      except
        LBody.AddPair('request', AJob.RequestJson);
      end;
    end
    else
      LBody.AddPair('request', TJSONObject.Create);

    if AJob.ErrorMsg <> '' then
      LBody.AddPair('error', AJob.ErrorMsg)
    else if AJob.ResponseJson <> '' then
    begin
      try
        LBody.AddPair('response', TJSONObject.ParseJSONValue(AJob.ResponseJson));
      except
        try
          LBody.AddPair('response', TJSONArray.ParseJSONValue(AJob.ResponseJson));
        except
          LBody.AddPair('response', AJob.ResponseJson);
        end;
      end;
    end;

    LHttp := TIdHTTP.Create(nil);
    LSSL := nil;
    try
      LHttp.ConnectTimeout := 3000;
      LHttp.ReadTimeout := 120000;
      LHttp.Request.ContentType := 'application/json';
      LHttp.Request.CharSet := 'utf-8';
      LHttp.HandleRedirects := True;
      if Pos('https://', LowerCase(GMirrorUrl)) = 1 then
      begin
        LSSL := TIdSSLIOHandlerSocketOpenSSL.Create(LHttp);
        LHttp.IOHandler := LSSL;
      end;
      LStream := TStringStream.Create(UTF8Encode(LBody.ToJSON));
      LStream.Position := 0;
      try
        LResp := LHttp.Post(GMirrorUrl, LStream);
      finally
        LStream.Free;
      end;
    finally
      LSSL.Free;
      LHttp.Free;
    end;
  finally
    LBody.Free;
  end;
end;

procedure WorkerExecute;
var
  LList: TList<TMirrorJob>;
  LJob: TMirrorJob;
  I: Integer;
begin
  while GStopEvent.WaitFor(200) <> wrSignaled do
  begin
    if not GEnabled then
      Continue;

    LList := GQueue.LockList;
    try
      for I := 0 to LList.Count - 1 do
      begin
        LJob := LList[I];
        try
          SendJobToNextApi(LJob);
        except
          // espelho não deve derrubar a API Horse
        end;
        LJob.Free;
      end;
      LList.Clear;
    finally
      GQueue.UnlockList;
    end;
  end;
end;

procedure BiMirrorStart;
begin
  if GWorker <> nil then
    Exit;
  GQueue := TThreadList<TMirrorJob>.Create;
  GStopEvent := TEvent.Create(nil, True, False, '');
  BiMirrorReloadConfig;
  GWorker := TThread.CreateAnonymousThread(WorkerExecute);
  GWorker.FreeOnTerminate := False;
  GWorker.Start;
end;

procedure BiMirrorStop;
begin
  if GWorker = nil then
    Exit;
  if GStopEvent <> nil then
    GStopEvent.SetEvent;
  GWorker.WaitFor;
  FreeAndNil(GWorker);
  if GQueue <> nil then
    FreeAndNil(GQueue);
  if GStopEvent <> nil then
    FreeAndNil(GStopEvent);
end;

procedure BiMirrorQueueEvent(const AMethod, ARoute, ARequestJson, AResponseJson: string;
  AStatusCode, ADurationMs: Integer; const AErrorMsg: string);
var
  LJob: TMirrorJob;
begin
  if not GEnabled then
    Exit;
  if AStatusCode >= 400 then
    Exit;

  LJob := TMirrorJob.Create;
  LJob.Method := AMethod;
  LJob.Route := ARoute;
  LJob.RequestJson := ARequestJson;
  LJob.ResponseJson := AResponseJson;
  LJob.StatusCode := AStatusCode;
  LJob.DurationMs := ADurationMs;
  LJob.ErrorMsg := AErrorMsg;
  PostMirrorJob(LJob);
end;

initialization

finalization
  BiMirrorStop;

end.
