unit UApiVersion;

interface

uses
  System.JSON;

const
  API_VERSION_NAME = '1.0.14';
  API_VERSION_BUILD = 2021;
  API_VERSION_LABEL = '1.0.14+2021';

function ApiVersionLabel: string;
function ApiExeModifiedIso: string;
procedure ApiVersionAddPairs(AJson: TJSONObject);
function BuildApiVersionJson: TJSONObject;

implementation

uses
  System.SysUtils,
  System.IOUtils;

function ApiVersionLabel: string;
begin
  Result := API_VERSION_LABEL;
end;

function ApiExeModifiedIso: string;
var
  LPath: string;
begin
  Result := '';
  LPath := ParamStr(0);
  if LPath = '' then
    Exit;
  if not TFile.Exists(LPath) then
    Exit;
  Result := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', TFile.GetLastWriteTime(LPath));
end;

procedure ApiVersionAddPairs(AJson: TJSONObject);
begin
  if AJson = nil then
    Exit;
  AJson.AddPair('version', API_VERSION_NAME);
  AJson.AddPair('build', TJSONNumber.Create(API_VERSION_BUILD));
  AJson.AddPair('label', API_VERSION_LABEL);
  AJson.AddPair('exeModified', ApiExeModifiedIso);
  AJson.AddPair('product', 'ApiRFeedHorse');
end;

function BuildApiVersionJson: TJSONObject;
begin
  Result := TJSONObject.Create;
  ApiVersionAddPairs(Result);
end;

end.
