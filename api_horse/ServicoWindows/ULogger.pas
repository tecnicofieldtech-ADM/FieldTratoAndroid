unit ULogger;

interface

uses
  LoggerPro,System.SysUtils;

procedure StartLogger;

var
  GlobalLogger: ILogWriter;

implementation

uses
  LoggerPro.FileAppender;

procedure StartLogger;
var
  LogPath: string;
begin
  LogPath := ExtractFilePath(ParamStr(0)) + 'logs'; // mesmo local do .exe
  GlobalLogger := BuildLogWriter([
    TLoggerProFileAppender.Create(10, 2000, LogPath)
  ]);
end;

end.

