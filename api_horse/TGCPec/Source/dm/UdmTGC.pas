unit UdmTGC;

interface

uses
  System.SysUtils, System.Classes, FireDAC.Stan.Intf, FireDAC.Stan.Option,
  FireDAC.Stan.Error, FireDAC.UI.Intf, FireDAC.Phys.Intf, FireDAC.Stan.Def,
  FireDAC.Stan.Pool, FireDAC.Stan.Async, FireDAC.Phys, FireDAC.Phys.FB,
  FireDAC.Phys.FBDef, FireDAC.FMXUI.Wait, FireDAC.Stan.Param, FireDAC.DatS,
  FireDAC.DApt.Intf, FireDAC.DApt, Data.DB, FireDAC.Comp.DataSet,
  FireDAC.Comp.Client, FireDAC.Phys.IBBase, FireDAC.VCLUI.Wait;

type
  TdmTGC = class(TDataModule)
    FBCon: TFDConnection;
    FBDriver: TFDPhysFBDriverLink;
    qryAux: TFDQuery;
  public
    procedure ConectaDBTGC;
  end;

implementation

uses Udm;

{$R *.dfm}

procedure TdmTGC.ConectaDBTGC;
var
  VendorDll, vServer, vUser, vPass, vPort, vDB, vRole: string;
begin
  VendorDll := ExtractFilePath(ParamStr(0)) + 'fbclient.dll';

  if not FileExists(dmdb.ConfigIniFilePath) then
    raise Exception.Create('Arquivo ApiConfig.ini não localizado em: ' + dmdb.ConfigIniFilePath);

  if not FileExists(VendorDll) then
    raise Exception.Create('fbclient.dll não localizada em: ' + VendorDll);

  try
    if FBCon.Connected then
      FBCon.Close;
  except
  end;

  dmdb.ReadTGCIni(vServer, vUser, vPass, vPort, vDB, vRole);

  if vServer = '' then
    raise Exception.Create('Server TGC não configurado em [TGC] do ApiConfig.ini.');
  if vDB = '' then
    raise Exception.Create('DB TGC não configurado em [TGC] do ApiConfig.ini.');
  if vUser = '' then
    raise Exception.Create('User TGC não configurado em [TGC] do ApiConfig.ini.');
  if vPort = '' then
    vPort := '3050';

  FBDriver.VendorLib := VendorDll;

  FBCon.LoginPrompt := False;
  FBCon.ResourceOptions.SilentMode := True;
  FBCon.DriverName := 'FB';
  FBCon.Params.Clear;

  FBCon.Params.Values['DriverID']     := 'FB';
  FBCon.Params.Values['Protocol']     := 'TCPIP';
  FBCon.Params.Values['Server']       := vServer;
  FBCon.Params.Values['Port']         := vPort;
  FBCon.Params.Values['Database']     := vDB;
  FBCon.Params.Values['User_Name']    := vUser;
  FBCon.Params.Values['Password']     := vPass;
  FBCon.Params.Values['CharacterSet'] := 'WIN1252';
  FBCon.Params.Values['LoginTimeout'] := '5';
  if vRole <> '' then
    FBCon.Params.Values['Role'] := vRole;

  FBCon.Connected := True;
end;

end.
