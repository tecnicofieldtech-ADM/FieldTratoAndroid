unit UPrincipal;

interface

uses
  System.SysUtils, System.Classes, Vcl.SvcMgr,  Horse,
  Horse.Jhonson,
  System.Threading, System.Diagnostics, Windows,
  LoggerPro.GlobalLogger,Horse.CORS,Horse.HandleException,Horse.BasicAuthentication,
  Horse.Provider.IOHandleSSL;

type
  TApiRFeed = class(TService)
  procedure ServiceStart(Sender: TService; var Started: Boolean);
    procedure ServiceStop(Sender: TService; var Stopped: Boolean);
  private
    FServerThread: ITask;
  public
    function GetServiceController: TServiceController; override;
    { Public declarations }
  end;

var
  ApiRFeed: TApiRFeed;

implementation

{$R *.dfm}

uses Udm, Controllers.Get, Controllers.Post, Controllers.Get.Field, Controllers.Post.Field,
  Controllers.Admin, UBiMirror, URequestLog, ULogger;

procedure ServiceController(CtrlCode: DWord); stdcall;
begin
  ApiRFeed.Controller(CtrlCode);
end;

function TApiRFeed.GetServiceController: TServiceController;
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


procedure TApiRFeed.ServiceStart(Sender: TService; var Started: Boolean);
begin
  try
    StartLogger;
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
    GlobalLogger.Info('Servi�o iniciado', '');
    // Inicia o servidor Horse em uma thread separada
    FServerThread := TTask.Run(
      procedure
      begin
        THorse.Use(Jhonson);
        THorse.Use(HandleException);
        THorse.Use(RequestLogMiddleware);
        THorse.Listen(3001);
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

procedure TApiRFeed.ServiceStop(Sender: TService; var Stopped: Boolean);
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
