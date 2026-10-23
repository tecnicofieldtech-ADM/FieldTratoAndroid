unit UPrincipal;

interface

uses
  System.SysUtils, System.Classes, Vcl.SvcMgr,  Horse,
  Horse.Jhonson,
  System.Threading, System.Diagnostics, Windows,
  LoggerPro.GlobalLogger,Horse.CORS,Horse.HandleException,Horse.BasicAuthentication,
  Horse.Provider.IOHandleSSL;

type
  TApiFiedlTrato = class(TService)
  procedure ServiceStart(Sender: TService; var Started: Boolean);
    procedure ServiceStop(Sender: TService; var Stopped: Boolean);
  private
    FServerThread: ITask;
  public
    function GetServiceController: TServiceController; override;
    { Public declarations }
  end;

var
  ApiFiedlTrato: TApiFiedlTrato;

implementation

{$R *.dfm}

uses Udm, Controllers.Get, Controllers.Post, Controllers.Get.Field, Controllers.Post.Field,
  Controllers.Get.TGC, Controllers.Post.TGC,
  Controllers.Admin, UBiMirror, URequestLog, ULogger;

procedure ServiceController(CtrlCode: DWord); stdcall;
begin
  ApiFiedlTrato.Controller(CtrlCode);
end;

function TApiFiedlTrato.GetServiceController: TServiceController;
begin
  Result := ServiceController;
end;

procedure LogEvent(const Msg: string);
var
  hEventLog: THandle;
begin
  hEventLog := RegisterEventSource(nil, 'ApiRFeed');
  if hEventLog <> 0 then
  begin
    ReportEvent(hEventLog, EVENTLOG_ERROR_TYPE, 0, 0, nil, 1, 0, @PChar(Msg)^, nil);
    DeregisterEventSource(hEventLog);
  end;
end;


procedure TApiFiedlTrato.ServiceStart(Sender: TService; var Started: Boolean);
begin
  try
    StartLogger;
    if SameText(dmdb.GetActiveClient, 'fieldpec') then
    begin
      Controllers.Get.Field.RegistraRotas;
      Controllers.Post.Field.RegistraRotas;
    end
    else if SameText(dmdb.GetActiveClient, 'tgc') then
    begin
      Controllers.Get.TGC.RegistraRotas;
      Controllers.Post.TGC.RegistraRotas;
    end
    else
    begin
      Controllers.Get.RegistraRotas;
      Controllers.Post.RegistraRotas;
    end;
    Controllers.Admin.RegistraRotasAdmin;
    BiMirrorStart;
    GlobalLogger.Info('Servi�o iniciado', '');
    // Inicia o servidor Horse em uma thread separada
    FServerThread := TTask.Run(
      procedure
      var
        LPort: Integer;
      begin
        THorse.Use(Jhonson);
        THorse.Use(HandleException);
        THorse.Use(RequestLogMiddleware);
        LPort := dmdb.GetApiListenPort;
        THorse.Listen(LPort);
      end
    );

    Started := True;
  except
    on E: Exception do
    begin
      LogEvent('Erro ao iniciar servi�o: ' + E.Message);
      Started := False;
    end;
  end;
end;

procedure TApiFiedlTrato.ServiceStop(Sender: TService; var Stopped: Boolean);
begin
 try
    GlobalLogger.Info('Servi�o finalizado', '');
    Stopped := True;
  except
    on E: Exception do
    begin
      LogEvent('Erro ao parar servi�o: ' + E.Message);
      Stopped := False;
    end;
  end;
end;

end.
