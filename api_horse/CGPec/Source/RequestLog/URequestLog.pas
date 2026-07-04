unit URequestLog;

interface

uses
  Horse;

procedure RequestLogMiddleware(Req: THorseRequest; Res: THorseResponse; Next: TProc);

function GetRequestLogJson(ALimit: Integer): string;
procedure ClearRequestLog;

implementation

uses
  System.Classes,
  System.DateUtils,
  System.IOUtils,
  System.JSON,
  System.SysUtils,
  System.SyncObjs;

const
  MAX_MEMORY_ENTRIES = 500;
  MAX_BODY_PREVIEW = 400;

type
  TRequestLogEntry = record
    Id: Integer;
    AtIso: string;
    Method: string;
    Route: string;
    StatusCode: Integer;
    DurationMs: Integer;
    ClientIp: string;
    UserAgent: string;
    RequestPreview: string;
    ErrorMsg: string;
  end;

var
  GLock: TCriticalSection;
  GEntries: TArray<TRequestLogEntry>;
  GNextId: Integer;
  GLogDir: string;

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

function LogDir: string;
begin
  if GLogDir <> '' then
    Exit(GLogDir);
  GLogDir := TPath.Combine(GetLogBaseDir, 'api-monitor');
  ForceDirectories(GLogDir);
  Result := GLogDir;
end;

function DailyLogPath: string;
begin
  Result := TPath.Combine(LogDir, 'requests-' + FormatDateTime('yyyymmdd', Now) + '.jsonl');
end;

function ClipText(const S: string; AMax: Integer): string;
begin
  if Length(S) <= AMax then
    Exit(S);
  Result := Copy(S, 1, AMax) + '...';
end;

function ShouldLogPath(const APath: string): Boolean;
var
  L: string;
begin
  L := LowerCase(Trim(APath));
  if L = '' then
    Exit(False);
  if L = '/api/request-logs' then
    Exit(False);
  if (Length(L) >= 6) and (Copy(L, 1, 6) = '/_next') then
    Exit(False);
  Result := True;
end;

function MethodToText(Req: THorseRequest): string;
var
  M: string;
begin
  M := UpperCase(Trim(Req.RawWebRequest.Method));
  if (M = 'GET') or (M = 'POST') or (M = 'PUT') or (M = 'DELETE') or (M = 'PATCH') or (M = 'HEAD') then
    Result := M
  else if M = '' then
    Result := 'GET'
  else
    Result := M;
end;

function HeaderValue(Req: THorseRequest; const AName: string): string;
begin
  Result := '';
  if not Req.Headers.TryGetValue(AName, Result) then
    Req.Headers.TryGetValue(LowerCase(AName), Result);
  Result := Trim(Result);
end;

function ClientIpOf(Req: THorseRequest): string;
begin
  Result := Trim(Req.RawWebRequest.RemoteAddr);
  if Result = '' then
    Result := HeaderValue(Req, 'X-Forwarded-For');
  if Result = '' then
    Result := 'unknown';
end;

procedure PersistEntry(const E: TRequestLogEntry);
var
  LLine: string;
  LObj: TJSONObject;
begin
  LObj := TJSONObject.Create;
  try
    LObj.AddPair('id', TJSONNumber.Create(E.Id));
    LObj.AddPair('at', E.AtIso);
    LObj.AddPair('method', E.Method);
    LObj.AddPair('route', E.Route);
    LObj.AddPair('statusCode', TJSONNumber.Create(E.StatusCode));
    LObj.AddPair('durationMs', TJSONNumber.Create(E.DurationMs));
    LObj.AddPair('ok', TJSONBool.Create((E.StatusCode >= 200) and (E.StatusCode < 300)));
    LObj.AddPair('clientIp', E.ClientIp);
    LObj.AddPair('userAgent', E.UserAgent);
    LObj.AddPair('source', 'horse');
    if E.RequestPreview <> '' then
      LObj.AddPair('requestPreview', E.RequestPreview);
    if E.ErrorMsg <> '' then
      LObj.AddPair('error', E.ErrorMsg);
    LLine := LObj.ToJSON;
  finally
    LObj.Free;
  end;

  try
    TFile.AppendAllText(DailyLogPath, LLine + sLineBreak, TEncoding.UTF8);
  except
    // não derruba a API
  end;
end;

procedure PushEntry(const E: TRequestLogEntry);
var
  LCopy: TArray<TRequestLogEntry>;
begin
  GLock.Enter;
  try
    SetLength(GEntries, Length(GEntries) + 1);
    GEntries[High(GEntries)] := E;
    if Length(GEntries) > MAX_MEMORY_ENTRIES then
    begin
      LCopy := Copy(GEntries, Length(GEntries) - MAX_MEMORY_ENTRIES + 1, MAX_MEMORY_ENTRIES);
      GEntries := LCopy;
    end;
  finally
    GLock.Leave;
  end;
  PersistEntry(E);
end;

procedure RequestLogAppend(Req: THorseRequest; Res: THorseResponse; ADurationMs: Integer);
var
  E: TRequestLogEntry;
  LPath, LBody, LQuery, LMethod: string;
begin
  LPath := Req.PathInfo;
  if not ShouldLogPath(LPath) then
    Exit;

  LMethod := UpperCase(Trim(Req.RawWebRequest.Method));
  LBody := '';
  if (LMethod = 'POST') or (LMethod = 'PUT') or (LMethod = 'PATCH') then
  begin
    try
      if (Pos('/post/', LowerCase(LPath)) > 0) then
        LBody := ClipText(Trim(Req.Body), 2000)
      else
        LBody := ClipText(Trim(Req.Body), MAX_BODY_PREVIEW);
    except
      LBody := '';
    end;
  end;

  LQuery := '';
  try
    LQuery := Trim(Req.RawWebRequest.Query);
  except
    LQuery := '';
  end;
  if (LQuery <> '') and (LBody = '') then
    LBody := ClipText('?' + LQuery, MAX_BODY_PREVIEW)
  else if (LQuery <> '') and (LBody <> '') then
    LBody := ClipText(LBody + ' | ?' + LQuery, MAX_BODY_PREVIEW);

  FillChar(E, SizeOf(E), 0);
  GLock.Enter;
  try
    Inc(GNextId);
    E.Id := GNextId;
  finally
    GLock.Leave;
  end;

  E.AtIso := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now);
  E.Method := MethodToText(Req);
  E.Route := LPath;
  E.StatusCode := Res.Status;
  E.DurationMs := ADurationMs;
  E.ClientIp := ClientIpOf(Req);
  E.UserAgent := ClipText(HeaderValue(Req, 'User-Agent'), 120);
  E.RequestPreview := LBody;
  if (E.StatusCode >= 400) and (E.StatusCode < 600) then
    E.ErrorMsg := 'HTTP ' + IntToStr(E.StatusCode);

  PushEntry(E);
end;

procedure RequestLogMiddleware(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LStart: TDateTime;
  LMs: Integer;
begin
  LStart := Now;
  try
    Next();
  finally
    LMs := MilliSecondsBetween(Now, LStart);
    RequestLogAppend(Req, Res, LMs);
  end;
end;

function GetRequestLogJson(ALimit: Integer): string;
var
  LArr: TJSONArray;
  LObj: TJSONObject;
  I, LStart, LCount: Integer;
  E: TRequestLogEntry;
begin
  if ALimit <= 0 then
    ALimit := 200;
  if ALimit > MAX_MEMORY_ENTRIES then
    ALimit := MAX_MEMORY_ENTRIES;

  LArr := TJSONArray.Create;
  try
    GLock.Enter;
    try
      LCount := Length(GEntries);
      LStart := LCount - ALimit;
      if LStart < 0 then
        LStart := 0;
      for I := LCount - 1 downto LStart do
      begin
        E := GEntries[I];
        LObj := TJSONObject.Create;
        LObj.AddPair('id', TJSONNumber.Create(E.Id));
        LObj.AddPair('at', E.AtIso);
        LObj.AddPair('method', E.Method);
        LObj.AddPair('route', E.Route);
        LObj.AddPair('statusCode', TJSONNumber.Create(E.StatusCode));
        LObj.AddPair('durationMs', TJSONNumber.Create(E.DurationMs));
        LObj.AddPair('ok', TJSONBool.Create((E.StatusCode >= 200) and (E.StatusCode < 300)));
        LObj.AddPair('clientIp', E.ClientIp);
        LObj.AddPair('userAgent', E.UserAgent);
        LObj.AddPair('source', 'horse');
        if E.RequestPreview <> '' then
          LObj.AddPair('requestPreview', E.RequestPreview);
        if E.ErrorMsg <> '' then
          LObj.AddPair('error', E.ErrorMsg);
        LArr.AddElement(LObj);
      end;
    finally
      GLock.Leave;
    end;
    Result := '{"items":' + LArr.ToJSON + ',"filePath":"' + DailyLogPath + '"}';
  finally
    LArr.Free;
  end;
end;

procedure ClearRequestLog;
begin
  GLock.Enter;
  try
    SetLength(GEntries, 0);
    GNextId := 0;
  finally
    GLock.Leave;
  end;
  try
    if TFile.Exists(DailyLogPath) then
      TFile.Delete(DailyLogPath);
  except
  end;
end;

initialization
  GLock := TCriticalSection.Create;
  GEntries := nil;
  GNextId := 0;
  GLogDir := '';

finalization
  FreeAndNil(GLock);

end.
