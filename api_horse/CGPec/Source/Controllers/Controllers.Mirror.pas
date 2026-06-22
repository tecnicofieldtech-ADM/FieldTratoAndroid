unit Controllers.Mirror;

interface

uses
  System.JSON,
  Horse;

procedure MirrorAfterSuccess(const AMethod, ARoute: string; const ARequestJson, AResponseJson: string;
  AStatusCode: Integer; ADurationMs: Integer = 0);

procedure MirrorPostBody(const ARoute: string; ABody: TJSONObject; const AResponseJson: string;
  AStatusCode: Integer; ADurationMs: Integer = 0);

procedure MirrorGetArray(const ARoute, ARequestJson: string; AData: TJSONArray;
  AStatusCode: Integer; ADurationMs: Integer = 0);

implementation

uses
  System.SysUtils,
  UBiMirror;

procedure MirrorAfterSuccess(const AMethod, ARoute: string; const ARequestJson, AResponseJson: string;
  AStatusCode: Integer; ADurationMs: Integer);
begin
  BiMirrorQueueEvent(AMethod, ARoute, ARequestJson, AResponseJson, AStatusCode, ADurationMs);
end;

procedure MirrorPostBody(const ARoute: string; ABody: TJSONObject; const AResponseJson: string;
  AStatusCode: Integer; ADurationMs: Integer);
var
  LReq: string;
begin
  if Assigned(ABody) then
    LReq := ABody.ToJSON
  else
    LReq := '{}';
  MirrorAfterSuccess('POST', ARoute, LReq, AResponseJson, AStatusCode, ADurationMs);
end;

procedure MirrorGetArray(const ARoute, ARequestJson: string; AData: TJSONArray;
  AStatusCode: Integer; ADurationMs: Integer);
var
  LResp: string;
begin
  if Assigned(AData) then
    LResp := AData.ToJSON
  else
    LResp := '[]';
  MirrorAfterSuccess('GET', ARoute, ARequestJson, LResp, AStatusCode, ADurationMs);
end;

end.
