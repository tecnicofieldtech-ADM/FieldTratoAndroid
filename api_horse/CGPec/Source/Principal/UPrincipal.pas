unit UPrincipal;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs,
  Horse,
  Horse.Jhonson,
  Horse.CORS,
  System.JSON,
  Horse.BasicAuthentication,
  Horse.HandleException;

type
  TfrmPrincipal = class(TForm)
    procedure FormShow(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  frmPrincipal: TfrmPrincipal;

implementation

{$R *.fmx}

uses
  Udm,
  Controllers.Get,
  Controllers.Post,
  Controllers.Get.Field,
  Controllers.Post.Field,
  Controllers.Admin,
  UBiMirror,
  URequestLog,
  Winapi.ShellAPI,
  Winapi.Windows;

procedure TfrmPrincipal.FormShow(Sender: TObject);
var
  LPort: Integer;
begin
  THorse.Use(Jhonson());
  THorse.Use(Cors);
  THorse.Use(HandleException);
  THorse.Use(RequestLogMiddleware);
  if SameText(dmdb.GetActiveClient, 'fieldpec') then
  begin
    Controllers.Get.Field.RegistraRotas;
    Controllers.Post.Field.RegistraRotas;
  end
  else
  begin
    Controllers.Get.RegistraRotas;
    Controllers.Post.RegistraRotas;
  end;
  Controllers.Admin.RegistraRotasAdmin;
  BiMirrorStart;
  LPort := dmdb.GetApiListenPort;
  THorse.Listen(LPort);
  ShellExecute(0, 'open', PChar('http://127.0.0.1:' + IntToStr(LPort) + '/config'), nil, nil, SW_SHOWNORMAL);
end;

end.
