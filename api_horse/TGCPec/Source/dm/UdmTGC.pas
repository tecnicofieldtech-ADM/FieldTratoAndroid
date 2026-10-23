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

uses
  System.SyncObjs,
  Udm;

{$R *.dfm}

var
  GFabSyncLock: TObject;
  GFabSyncReady: Boolean;
  GFabSyncKey: string;

function TgcMetaExists(Conn: TFDConnection; const SQL: string): Boolean;
var
  Q: TFDQuery;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;
    Q.SQL.Text := SQL;
    Q.Open;
    Result := not Q.Eof;
  finally
    Q.Free;
  end;
end;

procedure TgcExecDDL(Conn: TFDConnection; const SQL: string);
begin
  try
    if Conn.InTransaction then
      Conn.Commit;
  except
  end;
  try
    Conn.ExecSQL(SQL);
  except
    on E: Exception do
      if Pos('already exists', LowerCase(E.Message)) = 0 then
        raise;
  end;
end;

{ Cria RFEED_FABRICACAO_SYNC se ainda nao existir. Nao altera CAD_BATIDA
  nem o generator. Pode rodar mais de uma vez. }
procedure EnsureRfeedFabricacaoSync(Conn: TFDConnection);
const
  CCreateTable =
    'CREATE TABLE RFEED_FABRICACAO_SYNC (' +
    '  ORIGEM_SISTEMA     VARCHAR(30) NOT NULL,' +
    '  ID_EVENTO_SYNC     VARCHAR(64) NOT NULL,' +
    '  HANDOFF_ID         VARCHAR(64),' +
    '  ID_FABRICACAO_TGC  INTEGER,' +
    '  DATA_SINCRONIZACAO TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,' +
    '  HASH_PAYLOAD       VARCHAR(128) NOT NULL,' +
    '  HANDOFF_CHAVE      VARCHAR(80) NOT NULL,' +
    '  CONSTRAINT PK_RFEED_FAB_SYNC PRIMARY KEY (ORIGEM_SISTEMA, ID_EVENTO_SYNC),' +
    '  CONSTRAINT UX_RFEED_FAB_SYNC_HANDOFF UNIQUE (ORIGEM_SISTEMA, HANDOFF_CHAVE)' +
    ')';
  CCreateTrigger =
    'CREATE TRIGGER BI_RFEED_FAB_SYNC FOR RFEED_FABRICACAO_SYNC ' +
    'ACTIVE BEFORE INSERT OR UPDATE POSITION 0 ' +
    'AS ' +
    'BEGIN ' +
    '  IF (NEW.HANDOFF_ID IS NULL OR NEW.HANDOFF_ID = '''') THEN ' +
    '    NEW.HANDOFF_CHAVE = ''L:'' || NEW.ID_EVENTO_SYNC; ' +
    '  ELSE ' +
    '    NEW.HANDOFF_CHAVE = ''H:'' || NEW.HANDOFF_ID; ' +
    'END';
  CComment =
    'COMMENT ON TABLE RFEED_FABRICACAO_SYNC IS ' +
    '''Idempotencia FieldTrato. ID_FABRICACAO_TGC = CAD_BATIDA.CBT_CODIGO.''';
var
  HasTable, HasColumn, HasTrigger: Boolean;
begin
  HasTable := TgcMetaExists(Conn,
    'SELECT 1 FROM RDB$RELATIONS WHERE RDB$RELATION_NAME = ''RFEED_FABRICACAO_SYNC''');
  if HasTable then
  begin
    HasColumn := TgcMetaExists(Conn,
      'SELECT 1 FROM RDB$RELATION_FIELDS ' +
      'WHERE RDB$RELATION_NAME = ''RFEED_FABRICACAO_SYNC'' ' +
      '  AND RDB$FIELD_NAME = ''HANDOFF_CHAVE''');
    if not HasColumn then
      raise Exception.Create(
        'RFEED_FABRICACAO_SYNC existe sem HANDOFF_CHAVE. ' +
        'Nao foi alterada automaticamente.');
  end
  else
    TgcExecDDL(Conn, CCreateTable);

  HasTrigger := TgcMetaExists(Conn,
    'SELECT 1 FROM RDB$TRIGGERS WHERE RDB$TRIGGER_NAME = ''BI_RFEED_FAB_SYNC''');
  if not HasTrigger then
    TgcExecDDL(Conn, CCreateTrigger);

  try
    TgcExecDDL(Conn, CComment);
  except
    { Comentario nao participa da idempotencia. }
  end;

  if not TgcMetaExists(Conn,
       'SELECT 1 FROM RDB$RELATIONS WHERE RDB$RELATION_NAME = ''RFEED_FABRICACAO_SYNC''') or
     not TgcMetaExists(Conn,
       'SELECT 1 FROM RDB$RELATION_FIELDS ' +
       'WHERE RDB$RELATION_NAME = ''RFEED_FABRICACAO_SYNC'' ' +
       '  AND RDB$FIELD_NAME = ''HANDOFF_CHAVE''') or
     not TgcMetaExists(Conn,
       'SELECT 1 FROM RDB$TRIGGERS WHERE RDB$TRIGGER_NAME = ''BI_RFEED_FAB_SYNC''') then
    raise Exception.Create(
      'Nao foi possivel preparar RFEED_FABRICACAO_SYNC no Firebird TGC.');
end;

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

  if GFabSyncReady and SameText(GFabSyncKey, vServer + '|' + vDB) then
    Exit;

  TMonitor.Enter(GFabSyncLock);
  try
    if GFabSyncReady and SameText(GFabSyncKey, vServer + '|' + vDB) then
      Exit;
    EnsureRfeedFabricacaoSync(FBCon);
    GFabSyncKey := vServer + '|' + vDB;
    GFabSyncReady := True;
  finally
    TMonitor.Exit(GFabSyncLock);
  end;
end;

initialization
  GFabSyncLock := TObject.Create;
  GFabSyncReady := False;

finalization
  GFabSyncLock.Free;

end.
