unit Udm;

interface

uses
  System.SysUtils, System.Classes, FireDAC.Stan.Intf, FireDAC.Stan.Option,
  FireDAC.Stan.Error, FireDAC.UI.Intf, FireDAC.Phys.Intf, FireDAC.Stan.Def,
  FireDAC.Stan.Pool, FireDAC.Stan.Async, FireDAC.Phys, FireDAC.Phys.FB,
  FireDAC.Phys.FBDef, FireDAC.FMXUI.Wait, FireDAC.Phys.IBBase, Data.DB,
  FireDAC.Comp.Client,System.IniFiles,FMX.Dialogs, FireDAC.Stan.Param,
  FireDAC.DatS, FireDAC.DApt.Intf, FireDAC.DApt, FireDAC.Comp.DataSet;

type
  Tdmdb = class(TDataModule)
    FBCon: TFDConnection;
    FBDriver: TFDPhysFBDriverLink;
    CADASTRO_USUARIO: TFDQuery;
    CADASTRO_FAZENDA: TFDQuery;
    CADASTRO_FAZENDAIDFAZENDA: TStringField;
    CADASTRO_FAZENDACLIENTE: TStringField;
    CADASTRO_FAZENDAFAZENDA: TStringField;
    CADASTRO_FAZENDAIDCIDADE: TIntegerField;
    CADASTRO_FAZENDALOGOMARCA: TBlobField;
    CADASTRO_FAZENDAROTEIRO: TStringField;
    CADASTRO_FAZENDALATITUDE: TStringField;
    CADASTRO_FAZENDALONGITUDE: TStringField;
    CADASTRO_FAZENDARASTREADA: TStringField;
    CADASTRO_FAZENDATIPOPESSOA: TStringField;
    CADASTRO_FAZENDACNPJ: TStringField;
    CADASTRO_FAZENDACPF: TStringField;
    CADASTRO_FAZENDAIE: TStringField;
    CADASTRO_FAZENDAIM: TStringField;
    CADASTRO_FAZENDARAZAO_SOCIAL: TStringField;
    CADASTRO_FAZENDACEP: TStringField;
    CADASTRO_FAZENDABAIRRO: TStringField;
    CADASTRO_FAZENDALOGRADOURO: TStringField;
    CADASTRO_FAZENDANUMERO: TStringField;
    CADASTRO_FAZENDASALA: TStringField;
    CADASTRO_FAZENDABLOCO: TStringField;
    CADASTRO_FAZENDACOMPLEMENTO: TStringField;
    CADASTRO_FAZENDATELEFONE_1: TStringField;
    CADASTRO_FAZENDADESCR1: TStringField;
    CADASTRO_FAZENDAEMAIL1: TStringField;
    CADASTRO_FAZENDATELEFONE_2: TStringField;
    CADASTRO_FAZENDADESCR2: TStringField;
    CADASTRO_FAZENDAEMAIL2: TStringField;
    CADASTRO_FAZENDATELEFONE_3: TStringField;
    CADASTRO_FAZENDADESCR3: TStringField;
    CADASTRO_FAZENDAEMAIL3: TStringField;
    CADASTRO_FAZENDATIPO_CUSTO_COMPRA: TStringField;
    CADASTRO_FAZENDASALDO_FINANCEIRO_INICIAL: TFMTBCDField;
    CADASTRO_FAZENDAPROP_LOGOMARCA_PARCEIRO: TBlobField;
    CADASTRO_FAZENDACUSTO_CAPITAL: TFloatField;
    CADASTRO_FAZENDAINCRA: TStringField;
    CADASTRO_FAZENDACOD_ERAS: TStringField;
    CADASTRO_FAZENDADATA_INICIO_CUSTO: TDateField;
    CADASTRO_FAZENDAIDUNICO: TStringField;
    CADASTRO_FAZENDAMS_FORNECIMENTO_DIETA: TStringField;
    CADASTRO_FAZENDACONSULTOR_POS_VENDA: TStringField;
    CADASTRO_FAZENDAID_CLIENTE_SERVIDOR: TStringField;
    CADASTRO_FAZENDARATEIO_CONSUMO: TStringField;
    CADASTRO_DIETAS: TFDQuery;
    CADASTRO_DIETASID: TStringField;
    CADASTRO_DIETASID_FAZENDA: TStringField;
    CADASTRO_DIETASNOME_DIETA: TStringField;
    CADASTRO_DIETASTIPO_DIETA: TStringField;
    CADASTRO_DIETASSTATUS: TStringField;
    CADASTRO_DIETASLIBERADO: TStringField;
    CADASTRO_DIETASID_USUARIO: TStringField;
    CADASTRO_DIETASMN_TOTAL: TFloatField;
    CADASTRO_DIETASDATA_REGISTRO: TDateField;
    CADASTRO_DIETASMS_DIETA: TFMTBCDField;
    DETALHES_DIETAS: TFDQuery;
    DETALHES_DIETASID_DIETA: TStringField;
    DETALHES_DIETASNOME_DIETA: TStringField;
    DETALHES_DIETASTIPO_DIETA: TStringField;
    DETALHES_DIETASINGREDIENTE: TStringField;
    DETALHES_DIETASMS_INSUMO: TFloatField;
    DETALHES_DIETASMS_INCLUSAO: TFloatField;
    DETALHES_DIETASMN_PERC: TFloatField;
    DETALHES_DIETASORDEM: TIntegerField;
    BAIAS: TFDQuery;
    BAIASID_BAIA: TStringField;
    BAIASID_LOTE: TStringField;
    BAIASNOME_LOCAL: TStringField;
    BAIASLINHA: TStringField;
    BAIASORDEM_TRATO: TIntegerField;
    BAIASID_FAZENDA: TStringField;
    BAIASRFID: TStringField;
    DETALHES_DIETASID: TStringField;
    DETALHES_DIETASID_INSUMO: TStringField;
    Fabricacao: TFDQuery;
    Fabricacao_Insumos: TFDQuery;
    Fornecimento: TFDQuery;
    FornecimentoID: TStringField;
    FornecimentoDATA: TDateField;
    FornecimentoDATA_REGISTRO: TSQLTimeStampField;
    FornecimentoID_USUARIO: TStringField;
    FornecimentoID_LOTE: TStringField;
    FornecimentoTRATO: TIntegerField;
    FornecimentoID_DIETA: TStringField;
    FornecimentoQTDE_CAB: TIntegerField;
    FornecimentoPESO_MEDIO: TFMTBCDField;
    FornecimentoMS_DIETA_PREVISTA: TFMTBCDField;
    FornecimentoMS_DIETA_REALIZADA: TFMTBCDField;
    FornecimentoPREVISTO_LEITURA: TFMTBCDField;
    FornecimentoPREVISTO: TFMTBCDField;
    FornecimentoREALIZADO: TFMTBCDField;
    FornecimentoSTATUS: TStringField;
    FornecimentoMOTORISTA: TStringField;
    FornecimentoID_FABRICACAO: TStringField;
    FornecimentoID_BAIA: TStringField;
    FornecimentoDIF_KG: TFMTBCDField;
    FornecimentoDIF_PERC: TFMTBCDField;
    FornecimentoPREV_MS_CONSUMIDA: TFMTBCDField;
    FornecimentoREAL_MS_CONSUMIDA: TFMTBCDField;
    FornecimentoDIF_MS_CONSUMIDA: TFMTBCDField;
    FornecimentoDIF_PERC_MS: TFMTBCDField;
    FornecimentoDATA_LANCAMENTO: TSQLTimeStampField;
    FornecimentoID_USUARIO_LANCAMENTO: TStringField;
    FornecimentoID_LEITURA: TStringField;
    FornecimentoFLAG_GRAVADO: TStringField;
    FornecimentoID_TRATADOR: TStringField;
    FornecimentoID_DIETA_REALIZADA: TStringField;
    FornecimentoFORN_RATEIO: TFMTBCDField;
    FornecimentoFORN_TOTAL: TBCDField;
    FornecimentoTOTAL_MS_CONSUMIDA: TBCDField;
    FornecimentoPREVISTO_CAB: TBCDField;
    FornecimentoREALIZADO_CAB: TBCDField;
    FornecimentoMS_PREVISTA: TFloatField;
    FornecimentoFLAG_SYNC_SERVER: TStringField;
    Vagao: TFDQuery;
    VagaoNOME: TStringField;
    VagaoID: TStringField;
    FabricacaoID: TStringField;
    FabricacaoID_FAZENDA: TStringField;
    FabricacaoID_DIETA: TStringField;
    FabricacaoDATA: TDateField;
    FabricacaoDATA_REGISTO: TSQLTimeStampField;
    FabricacaoID_USUARIO: TStringField;
    FabricacaoID_OPERADOR: TStringField;
    FabricacaoID_VAGAO: TStringField;
    FabricacaoQTDE_PREVISTA: TFMTBCDField;
    FabricacaoGRAVADO: TStringField;
    FabricacaoMS_PREVISTA: TFMTBCDField;
    FabricacaoSTATUS_ATUAL: TStringField;
    FabricacaoFLAG_SYNC_SERVER: TStringField;
    FabricacaoCUSTO_KG_DIETA: TFloatField;
    FabricacaoMS_BATIDA: TFloatField;
    FabricacaoQTDE_REALIZADA: TFloatField;
    Fabricacao_InsumosID: TStringField;
    Fabricacao_InsumosID_CADASTRO_FABRICA_RACAO: TStringField;
    Fabricacao_InsumosID_INSUMO: TStringField;
    Fabricacao_InsumosQTDE_PREVISTA: TFMTBCDField;
    Fabricacao_InsumosQTDE_REALIZADA: TFMTBCDField;
    Fabricacao_InsumosDATA_REGISTRO: TSQLTimeStampField;
    Fabricacao_InsumosID_OPERADOR: TStringField;
    Fabricacao_InsumosGRAVADO: TStringField;
    Fabricacao_InsumosMS_INSUMO: TFMTBCDField;
    Fabricacao_InsumosDIF_KG: TFMTBCDField;
    Fabricacao_InsumosDIF_PER: TFloatField;
    Fabricacao_InsumosCUSTO_KG: TFloatField;
    qryAux: TFDQuery;
    PREVISAO: TFDQuery;
    DETALHES_DIETASPRE_PESAGEM: TStringField;
    procedure FBConAfterConnect(Sender: TObject);
    procedure FabricacaoReconcileError(DataSet: TFDDataSet; E: EFDException;
      UpdateKind: TFDDatSRowState; var Action: TFDDAptReconcileAction);
  private
    { Private declarations }
  public
    function  ConfigIniFilePath: string;
    function  ReadIniValue(const APath, ASection, AKey, ADefault: string): string;
    function  LerIni(Diretorio,Chave1, Chave2, ValorPadrao: String): String;
    procedure RepairIniEncodingIfNeeded(const APath: string);
    function  GetActiveClient: string;
    function  GetFornecimentoAcumulativo: Boolean;
    function  GetPontoCorteFornecimentoKg: Double;
    function  GetApiListenPort: Integer;
    procedure ReadCgpecIni(out AServer, AUser, APassword, APort, ADatabase, ARole: string);
    procedure ReadFieldPecIni(out AServer, AUser, APassword, APort, ADatabase, ARole: string);
    procedure ReadPostgresIni(out AHost, AUser, APassword, APort, ADatabase, AEnabled: string);
    procedure ReadMirrorIni(out AEnabled, AUrl, ANextApiBase: string);
    procedure WriteCgpecIni(const AServer, AUser, APassword, APort, ADatabase, ARole: string);
    procedure WriteFieldPecIni(const AServer, AUser, APassword, APort, ADatabase, ARole: string);
    procedure WritePostgresIni(const AHost, AUser, APassword, APort, ADatabase, AEnabled: string);
    procedure WriteApiConfigIni(
      const ActiveClient: string;
      const CgServer, CgUser, CgPassword, CgPort, CgDatabase, CgRole: string;
      const FpServer, FpUser, FpPassword, FpPort, FpDatabase, FpRole: string;
      const PgHost, PgUser, PgPassword, PgPort, PgDatabase, PgEnabled: string;
      const MirrorEnabled, MirrorUrl, MirrorNextApiBase: string;
      const FornecimentoAcumulativo: string = '1';
      const PontoCorteFornecimentoKg: string = '');
    procedure TestCgpecConnection(const AServer, AUser, APassword, APort, ADatabase: string;
      out AOk: Boolean; out AError: string);
    procedure TestFieldPecConnection(const AServer, AUser, APassword, APort, ADatabase: string;
      out AOk: Boolean; out AError: string);
    procedure TestPostgresConnection(const AHost, AUser, APassword, APort, ADatabase: string;
      out AOk: Boolean; out AError: string);
    procedure DisconnectCgpec;
    procedure ConectaDBCGPec;
    procedure AtualizaResumoFabricacao(const IDFabricacao: string);
    function  GetCustoMedioKgInsumo(const IdProduto, IdFazenda, DataBase: string): Double;
    function  VerificaTabelaExiste(vTable: string): Integer;
    procedure AtualizaDB;
    procedure GeraTabelaTMP_Previsao(idFazenda:String; DataPrev:TDate);
  end;

var
  dmdb: Tdmdb;

implementation

uses
  Winapi.Windows;

{%CLASSGROUP 'FMX.Controls.TControl'}

{$R *.dfm}

procedure LoadIniTextFile(const APath: string; ALines: TStringList);
var
  FS: TFileStream;
  LBom: array[0..2] of Byte;
  LHasBom: Boolean;
begin
  FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyWrite);
  try
    LHasBom := False;
    if FS.Size >= 3 then
    begin
      FS.ReadBuffer(LBom, SizeOf(LBom));
      LHasBom := (LBom[0] = $EF) and (LBom[1] = $BB) and (LBom[2] = $BF);
    end;
    if not LHasBom then
      FS.Position := 0;
    ALines.LoadFromStream(FS);
  finally
    FS.Free;
  end;
end;

{ TDataModule1 }

function Tdmdb.VerificaTabelaExiste(vTable: string): Integer;
begin
 with qryAux,qryAux.SQL do
 begin
   Clear;
   Add('SELECT COUNT(*) QTDE');
   Add('FROM RDB$RELATIONS');
   Add('WHERE RDB$FLAGS=1 and RDB$RELATION_NAME=:NomeTabela');
   ParamByName('NomeTabela').AsString := vTable;
   Open;
   Result := FieldByName('QTDE').AsInteger;
 end;
end;



procedure Tdmdb.AtualizaDB;
begin
 if VerificaTabelaExiste('TMP_PREV_ATUTOMACAO')=0 then
  begin
   with qryAux,qryAux.sql do
   begin
    Clear;
    Add('CREATE TABLE TMP_PREV_ATUTOMACAO(');
    Add('      ID_FORNECIMENTO CHAR(40),');
    Add('      DATA DATE,');
    Add('      ID_BAIA CHAR(40),');
    Add('      TRATO INTEGER,');
    Add('      PREVISAO_KG DECIMAL(15,3),');
    Add('      REALIZADO_KG DECIMAL(15,3),');
    Add('      ID_RACAO  CHAR(40)');
    Add('   )');
    ExecSQL;
   end;
  end;
end;

procedure Tdmdb.AtualizaResumoFabricacao(const IDFabricacao: string);
begin
  qryAux.Close;
  qryAux.SQL.Clear;
  qryAux.SQL.Add('UPDATE CADASTRO_FABRICA_RACAO SET');
  qryAux.SQL.Add('  GRAVADO = ''S'',');
  qryAux.SQL.Add('  CUSTO_KG_DIETA = (');
  qryAux.SQL.Add('    SELECT COALESCE(SUM(QTDE_REALIZADA * CUSTO_KG) / NULLIF(SUM(QTDE_REALIZADA), 0), 0)');
  qryAux.SQL.Add('    FROM DETALHES_FABRICA_RACAO');
  qryAux.SQL.Add('    WHERE ID_INSUMO IS NOT NULL AND ID_CADASTRO_FABRICA_RACAO = :ID');
  qryAux.SQL.Add('  ),');
  qryAux.SQL.Add('  MS_BATIDA = COALESCE((');
  qryAux.SQL.Add('    SELECT CASE');
  qryAux.SQL.Add('      WHEN COALESCE(SUM(CAST(QTDE_REALIZADA AS DOUBLE PRECISION) *');
  qryAux.SQL.Add('                    CAST(MS_INSUMO AS DOUBLE PRECISION)), 0) > 0 THEN');
  qryAux.SQL.Add('        COALESCE((');
  qryAux.SQL.Add('          SUM(CAST(QTDE_REALIZADA AS DECIMAL(18,2)) * (CAST(MS_INSUMO AS DOUBLE PRECISION) / 100)) /');
  qryAux.SQL.Add('          NULLIF(SUM(CAST(QTDE_REALIZADA AS DOUBLE PRECISION)), 0) * 100');
  qryAux.SQL.Add('        ), 0)');
  qryAux.SQL.Add('      ELSE (SELECT COALESCE(MS_BATIDA, 0) FROM CADASTRO_FABRICA_RACAO WHERE ID = :ID)');
  qryAux.SQL.Add('    END');
  qryAux.SQL.Add('    FROM DETALHES_FABRICA_RACAO');
  qryAux.SQL.Add('    WHERE ID_INSUMO IS NOT NULL AND ID_CADASTRO_FABRICA_RACAO = :ID');
  qryAux.SQL.Add('  ), MS_BATIDA),');
  qryAux.SQL.Add('  MS_PREVISTA = COALESCE((');
  qryAux.SQL.Add('    SELECT CASE');
  qryAux.SQL.Add('      WHEN COALESCE(SUM(CAST(QTDE_PREVISTA AS DOUBLE PRECISION) *');
  qryAux.SQL.Add('                    CAST(MS_INSUMO AS DOUBLE PRECISION)), 0) > 0 THEN');
  qryAux.SQL.Add('        COALESCE((');
  qryAux.SQL.Add('          SUM(CAST(QTDE_PREVISTA AS DECIMAL(18,2)) * (CAST(MS_INSUMO AS DOUBLE PRECISION) / 100)) /');
  qryAux.SQL.Add('          NULLIF(SUM(CAST(QTDE_PREVISTA AS DOUBLE PRECISION)), 0) * 100');
  qryAux.SQL.Add('        ), 0)');
  qryAux.SQL.Add('      ELSE (SELECT COALESCE(MS_PREVISTA, 0) FROM CADASTRO_FABRICA_RACAO WHERE ID = :ID)');
  qryAux.SQL.Add('    END');
  qryAux.SQL.Add('    FROM DETALHES_FABRICA_RACAO');
  qryAux.SQL.Add('    WHERE ID_INSUMO IS NOT NULL AND ID_CADASTRO_FABRICA_RACAO = :ID');
  qryAux.SQL.Add('  ), MS_PREVISTA),');
  qryAux.SQL.Add('  QTDE_REALIZADA = (');
  qryAux.SQL.Add('    SELECT COALESCE(SUM(QTDE_REALIZADA), 0)');
  qryAux.SQL.Add('    FROM DETALHES_FABRICA_RACAO');
  qryAux.SQL.Add('    WHERE ID_INSUMO IS NOT NULL AND ID_CADASTRO_FABRICA_RACAO = :ID');
  qryAux.SQL.Add('  )');
  qryAux.SQL.Add('WHERE ID = :ID');
  qryAux.ParamByName('ID').AsString := IDFabricacao;
  qryAux.ExecSQL;
end;

function Tdmdb.ConfigIniFilePath: string;
var
  LExeIni, LCurIni: string;
begin
  LExeIni := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'ApiConfig.ini';
  if FileExists(LExeIni) then
    Exit(LExeIni);

  LCurIni := IncludeTrailingPathDelimiter(GetCurrentDir) + 'ApiConfig.ini';
  if FileExists(LCurIni) then
    Exit(LCurIni);

  Result := LExeIni;
end;

function Tdmdb.ReadIniValue(const APath, ASection, AKey, ADefault: string): string;
var
  LLines: TStringList;
  I, P: Integer;
  LLine, LSect: string;
  LInSection: Boolean;
begin
  Result := ADefault;
  if not FileExists(APath) then
    Exit;

  LLines := TStringList.Create;
  try
    LoadIniTextFile(APath, LLines);
    LInSection := False;
    for I := 0 to LLines.Count - 1 do
    begin
      LLine := Trim(LLines[I]);
      if LLine = '' then
        Continue;
      if (LLine[1] = '[') and (LLine[Length(LLine)] = ']') then
      begin
        LSect := Trim(Copy(LLine, 2, Length(LLine) - 2));
        LInSection := SameText(LSect, ASection);
        Continue;
      end;
      if not LInSection then
        Continue;
      P := Pos('=', LLine);
      if P < 2 then
        Continue;
      if SameText(Trim(Copy(LLine, 1, P - 1)), AKey) then
        Exit(Trim(Copy(LLine, P + 1, MaxInt)));
    end;
  finally
    LLines.Free;
  end;
end;

procedure Tdmdb.RepairIniEncodingIfNeeded(const APath: string);
var
  FS: TFileStream;
  LBom: array[0..2] of Byte;
  LLines: TStringList;
begin
  if not FileExists(APath) then
    Exit;
  FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyWrite);
  try
    if FS.Size < 3 then
      Exit;
    FS.ReadBuffer(LBom, SizeOf(LBom));
    if (LBom[0] <> $EF) or (LBom[1] <> $BB) or (LBom[2] <> $BF) then
      Exit;
  finally
    FS.Free;
  end;

  LLines := TStringList.Create;
  try
    LoadIniTextFile(APath, LLines);
    LLines.SaveToFile(APath);
  finally
    LLines.Free;
  end;
end;

function IsLocalFirebirdHost(const AServer: string): Boolean;
var
  S: string;
  LBuf: array[0..MAX_COMPUTERNAME_LENGTH] of Char;
  LSize: DWORD;
begin
  S := LowerCase(Trim(AServer));
  if (S = '') or (S = 'localhost') or (S = '127.0.0.1') or (S = '.') or (S = 'local') then
    Exit(True);

  LSize := MAX_COMPUTERNAME_LENGTH + 1;
  if GetComputerName(LBuf, LSize) then
    Result := SameText(S, string(LBuf))
  else
    Result := False;
end;

procedure Tdmdb.ConectaDBCGPec;
var
  Arquivo: string;
  vVendorLib: string;
  vUser, vPass, vPort, vServer, vDB, vRole: string;
begin
  FBCon.Close;

  Arquivo := ConfigIniFilePath;
  if not FileExists(Arquivo) then
    raise Exception.Create('Arquivo ApiConfig.ini não localizado em: ' + Arquivo + sLineBreak +
      'Use http://127.0.0.1:' + IntToStr(GetApiListenPort) + '/config para criar a configuração.');

  RepairIniEncodingIfNeeded(Arquivo);

  vVendorLib := ExtractFilePath(ParamStr(0)) + 'fbclient.dll';
  if not FileExists(vVendorLib) then
    raise Exception.Create('fbclient.dll não localizada em: ' + vVendorLib);

  ReadCgpecIni(vServer, vUser, vPass, vPort, vDB, vRole);

  if vServer = '' then
    raise Exception.Create(
      'Server não lido do ApiConfig.ini.' + sLineBreak +
      'Arquivo: ' + Arquivo + sLineBreak +
      'Confira se [CGPEC] e Server= estão na pasta do executável: ' + ExtractFilePath(ParamStr(0)));
  if vPort = '' then
    raise Exception.Create('Port não lida do ApiConfig.ini (' + Arquivo + ')');
  if vDB = '' then
    raise Exception.Create('DB não lido do ApiConfig.ini (' + Arquivo + ')');
  // Só valida arquivo local quando o Firebird está nesta máquina.
  // Servidor remoto (ex.: 192.168.10.250) usa caminho do .FDB no host remoto.
  if IsLocalFirebirdHost(vServer) and not FileExists(vDB) then
    raise Exception.Create('Arquivo FDB não encontrado: ' + vDB);

  FBDriver.VendorLib := vVendorLib;

  try
    FBCon.Close;
    FBCon.Params.Clear;
    FBCon.DriverName := 'FB';
    FBCon.LoginPrompt := False;

    FBCon.Params.Values['Server']    := vServer;
    FBCon.Params.Values['Port']      := vPort;
    FBCon.Params.Values['Database']  := vDB;
    FBCon.Params.Values['User_Name'] := vUser;
    FBCon.Params.Values['Password']  := vPass;
    FBCon.Params.Values['Protocol']  := 'TCPIP';

    FBCon.Connected := True;
  except
    on E: Exception do
      raise Exception.Create(
        'Erro ao conectar no banco CGPec: ' + E.Message + sLineBreak +
        'INI=' + Arquivo + sLineBreak +
        'Server=' + vServer + sLineBreak +
        'Port=' + vPort + sLineBreak +
        'DB=' + vDB + sLineBreak +
        'DLL=' + vVendorLib
      );
  end;
end;

procedure Tdmdb.FabricacaoReconcileError(DataSet: TFDDataSet; E: EFDException;
  UpdateKind: TFDDatSRowState; var Action: TFDDAptReconcileAction);
begin
 TThread.Queue(nil,
  procedure
  begin
    ShowMessage('Erro: ' + e.Message);
  end
 );

end;

procedure Tdmdb.FBConAfterConnect(Sender: TObject);
begin
 AtualizaDB;
end;

procedure Tdmdb.GeraTabelaTMP_Previsao(idFazenda:String; DataPrev:TDate);
begin
  with qryAux,qryAux.SQL do
  begin
    Clear;
    Add(' DELETE FROM TMP_PREV_ATUTOMACAO ');
    ExecSQL;

    Clear;
    Add('INSERT INTO TMP_PREV_ATUTOMACAO');
    Add('SELECT');
    Add('  s.ID AS id_fornecimento,');
    Add('  s."DATA",');
    Add('  db.ID,');
    Add('  s.TRATO,');
    Add('  ROUND(IIF(');
    Add('    s.TRATO = (');
    Add('      SELECT MAX(ss.TRATO)');
    Add('      FROM CADASTRO_FORNECIMENTO ss');
    Add('      WHERE ss.ID_LOTE = s.ID_LOTE');
    Add('        AND ss.DATA = s.DATA');
    Add('    ),');
    Add('    (');
    Add('      SELECT (');
    Add('        COALESCE(SUM(sss.PREV_MS_CONSUMIDA),0) - COALESCE(SUM(sss.REAL_MS_CONSUMIDA),0)');
    Add('      )');
    Add('      FROM CADASTRO_FORNECIMENTO sss');
    Add('      WHERE sss.DATA = s.DATA');
    Add('        AND sss.ID_LOTE = s.ID_LOTE');
    Add('    ) / s.MS_DIETA_PREVISTA * 100,');
    Add('    s.PREVISTO');
    Add('  )) AS PREVISTO,');
    Add('  TRUNC(s.REALIZADO) AS REALIZADO,');
    Add('  s.ID_DIETA');
    Add('FROM CADASTRO_FORNECIMENTO s');
    Add('JOIN CADASTRO_LOTE_ENGORDA l ON l.ID = s.ID_LOTE');
    Add('JOIN DETALHES_BAIAS db ON db.ID = s.ID_BAIA');
    Add('JOIN CADASTRO_DIETAS d ON d.ID = s.ID_DIETA');
    Add('JOIN CADASTRO_AREAS a ON a.ID = db.ID_BAIA');
    Add('WHERE l.STATUS = ''A''');
    Add('  AND s.DATA = :DATA');
    Add('  AND l.ID_FAZENDA = :ID_FAZENDA');
    Add('ORDER BY d.NOME_DIETA, db.ORDEM_TRATO');
    ParamByName('DATA').AsDate := DataPrev;
    ParamByName('ID_FAZENDA').AsString := idFazenda;
    ExecSQL;
  end;
end;

function Tdmdb.GetCustoMedioKgInsumo(const IdProduto, IdFazenda,
  DataBase: string): Double;
begin
  Result := 0;
  ConectaDBCGPec;
  qryAux.Connection := FBCon;
  with qryAux do
  begin
    Close;
    SQL.Clear;
    SQL.Add('SELECT');
    SQL.Add('  IIF(SUM(IIF(TIPO_MOV = ''ENTRADA'', QTDE, QTDE * -1)) <= 0.1, 0,');
    SQL.Add('    COALESCE(SUM(IIF(TIPO_MOV = ''ENTRADA'', QTDE * VALOR_UNIT, QTDE * -1 * VALOR_UNIT)) /');
    SQL.Add('    NULLIF(SUM(IIF(TIPO_MOV = ''ENTRADA'', QTDE, QTDE * -1)), 0), 0)) AS CUSTO_MEDIO');
    SQL.Add('FROM ESTOQUE_MOVIMENTACAO S');
    SQL.Add('JOIN CADASTRO_INSCRICAO_ESTADUAL IE ON IE.IDINSCRICAO = S.ID_PROPRIETARIO');
    SQL.Add('JOIN CADASTRO_INSUMOS I ON I.ID = S.ID_PRODUTO');
    SQL.Add('JOIN CADASTRO_LOCAL_ARMAZEM L ON L.IDLOCALIDADE = S.ID_LOCALESTOQUE');
    SQL.Add('WHERE S.FLAG_STATUS = ''A''');
    SQL.Add('  AND L.LOCAL_FISICO = ''P''');
    SQL.Add('  AND S.ID_PRODUTO = :ID_PRODUTO');
    SQL.Add('  AND IE.IDFAZENDA = :IDFAZENDA');
    SQL.Add('  AND S.DATA <= :DATA_BASE');

    ParamByName('ID_PRODUTO').AsString := IdProduto;
    ParamByName('IDFAZENDA').AsString := IdFazenda;
    ParamByName('DATA_BASE').AsDate := StrToDateDef(DataBase, Date);

    Open;
    if not FieldByName('CUSTO_MEDIO').IsNull then
      Result := FieldByName('CUSTO_MEDIO').AsFloat;
  end;
end;

procedure Tdmdb.ReadCgpecIni(out AServer, AUser, APassword, APort, ADatabase, ARole: string);
var
  LIni: string;
begin
  LIni := ConfigIniFilePath;
  AServer := Trim(ReadIniValue(LIni, 'CGPEC', 'Server', ''));
  AUser := Trim(ReadIniValue(LIni, 'CGPEC', 'User', ''));
  APassword := ReadIniValue(LIni, 'CGPEC', 'Password', '');
  APort := Trim(ReadIniValue(LIni, 'CGPEC', 'Port', ''));
  ADatabase := Trim(ReadIniValue(LIni, 'CGPEC', 'DB', ''));
  ARole := Trim(ReadIniValue(LIni, 'CGPEC', 'Role', ''));
end;

procedure Tdmdb.ReadPostgresIni(out AHost, AUser, APassword, APort, ADatabase, AEnabled: string);
var
  LIni: string;
begin
  LIni := ConfigIniFilePath;
  AHost := Trim(ReadIniValue(LIni, 'POSTGRES', 'Host', '127.0.0.1'));
  AUser := Trim(ReadIniValue(LIni, 'POSTGRES', 'User', 'postgres'));
  APassword := ReadIniValue(LIni, 'POSTGRES', 'Password', '');
  APort := Trim(ReadIniValue(LIni, 'POSTGRES', 'Port', '5432'));
  ADatabase := Trim(ReadIniValue(LIni, 'POSTGRES', 'Database', ''));
  AEnabled := Trim(ReadIniValue(LIni, 'POSTGRES', 'Enabled', '1'));
end;

procedure Tdmdb.ReadMirrorIni(out AEnabled, AUrl, ANextApiBase: string);
var
  LIni: string;
begin
  LIni := ConfigIniFilePath;
  AEnabled := Trim(ReadIniValue(LIni, 'MIRROR', 'Enabled', '0'));
  ANextApiBase := Trim(ReadIniValue(LIni, 'MIRROR', 'NextApiBase', 'http://127.0.0.1:3000'));
  AUrl := Trim(ReadIniValue(LIni, 'MIRROR', 'Url', ANextApiBase + '/api/mirror/event'));
end;

procedure Tdmdb.ReadFieldPecIni(out AServer, AUser, APassword, APort, ADatabase, ARole: string);
var
  LIni: string;
begin
  LIni := ConfigIniFilePath;
  AServer := Trim(ReadIniValue(LIni, 'FIELDPEC', 'Server', ''));
  AUser := Trim(ReadIniValue(LIni, 'FIELDPEC', 'User', ''));
  APassword := ReadIniValue(LIni, 'FIELDPEC', 'Password', '');
  APort := Trim(ReadIniValue(LIni, 'FIELDPEC', 'Port', ''));
  ADatabase := Trim(ReadIniValue(LIni, 'FIELDPEC', 'DB', ''));
  ARole := Trim(ReadIniValue(LIni, 'FIELDPEC', 'Role', ''));
  if (AServer = '') and (ADatabase = '') then
  begin
    AServer := Trim(ReadIniValue(LIni, 'Field', 'Server', AServer));
    AUser := Trim(ReadIniValue(LIni, 'Field', 'User', AUser));
    if APassword = '' then
      APassword := ReadIniValue(LIni, 'Field', 'Password', '');
    if APort = '' then
      APort := Trim(ReadIniValue(LIni, 'Field', 'Port', '3050'));
    if ADatabase = '' then
      ADatabase := Trim(ReadIniValue(LIni, 'Field', 'DB', ''));
  end;
end;

function Tdmdb.GetActiveClient: string;
var
  LVal: string;
begin
  LVal := LowerCase(Trim(ReadIniValue(ConfigIniFilePath, 'API', 'ActiveClient', 'cgpec')));
  if (LVal = 'fieldpec') or (LVal = 'field') then
    Result := 'fieldpec'
  else
    Result := 'cgpec';
end;

function Tdmdb.GetFornecimentoAcumulativo: Boolean;
var
  LVal: string;
begin
  LVal := LowerCase(Trim(ReadIniValue(ConfigIniFilePath, 'API', 'FornecimentoAcumulativo', '1')));
  Result := not ((LVal = '0') or (LVal = 'false') or (LVal = 'no') or (LVal = 'nao') or (LVal = 'não'));
end;

function Tdmdb.GetPontoCorteFornecimentoKg: Double;
var
  LVal: string;
begin
  LVal := Trim(ReadIniValue(ConfigIniFilePath, 'API', 'PontoCorteFornecimentoKg', '50'));
  LVal := StringReplace(LVal, ',', '.', [rfReplaceAll]);
  Result := StrToFloatDef(LVal, 50);
  if Result < 0 then
    Result := 0;
end;

function Tdmdb.GetApiListenPort: Integer;
var
  LVal: string;
  LPort: Integer;
const
  DEFAULT_API_PORT = 3001;
begin
  LVal := Trim(ReadIniValue(ConfigIniFilePath, 'API', 'Port', IntToStr(DEFAULT_API_PORT)));
  LPort := StrToIntDef(LVal, DEFAULT_API_PORT);
  if (LPort < 1) or (LPort > 65535) then
    Result := DEFAULT_API_PORT
  else
    Result := LPort;
end;

function AcumIniStr(Acum: Boolean): string;
begin
  if Acum then
    Result := '1'
  else
    Result := '0';
end;

procedure Tdmdb.WriteApiConfigIni(
  const ActiveClient: string;
  const CgServer, CgUser, CgPassword, CgPort, CgDatabase, CgRole: string;
  const FpServer, FpUser, FpPassword, FpPort, FpDatabase, FpRole: string;
  const PgHost, PgUser, PgPassword, PgPort, PgDatabase, PgEnabled: string;
  const MirrorEnabled, MirrorUrl, MirrorNextApiBase: string;
  const FornecimentoAcumulativo: string = '1';
  const PontoCorteFornecimentoKg: string = '');
var
  LPath: string;
  LLines: TStringList;
  LNextBase, LMirrorUrl, LClient, LFornAcum, LPontoCorte: string;
begin
  LPath := ConfigIniFilePath;
  LClient := LowerCase(Trim(ActiveClient));
  if (LClient <> 'fieldpec') and (LClient <> 'spreadsheet_import') then
    LClient := 'cgpec';
  LFornAcum := Trim(FornecimentoAcumulativo);
  if (LFornAcum <> '0') and (LFornAcum <> '1') then
    LFornAcum := '1';
  LPontoCorte := Trim(PontoCorteFornecimentoKg);
  if LPontoCorte = '' then
    LPontoCorte := StringReplace(FormatFloat('0.###', GetPontoCorteFornecimentoKg), ',', '.', [rfReplaceAll]);
  LNextBase := Trim(MirrorNextApiBase);
  if LNextBase = '' then
    LNextBase := 'http://127.0.0.1:3000';
  LMirrorUrl := Trim(MirrorUrl);
  if LMirrorUrl = '' then
    LMirrorUrl := LNextBase + '/api/mirror/event';
  LLines := TStringList.Create;
  try
    LLines.Add('[API]');
    LLines.Add('ActiveClient=' + LClient);
    LLines.Add('FornecimentoAcumulativo=' + LFornAcum);
    LLines.Add('PontoCorteFornecimentoKg=' + LPontoCorte);
    LLines.Add('Port=' + IntToStr(GetApiListenPort));
    LLines.Add('');
    LLines.Add('[CGPEC]');
    LLines.Add('Server=' + Trim(CgServer));
    LLines.Add('User=' + Trim(CgUser));
    LLines.Add('Password=' + CgPassword);
    LLines.Add('Port=' + Trim(CgPort));
    LLines.Add('DB=' + Trim(CgDatabase));
    if Trim(CgRole) <> '' then
      LLines.Add('Role=' + Trim(CgRole));
    LLines.Add('');
    LLines.Add('[FIELDPEC]');
    LLines.Add('Server=' + Trim(FpServer));
    LLines.Add('User=' + Trim(FpUser));
    LLines.Add('Password=' + FpPassword);
    LLines.Add('Port=' + Trim(FpPort));
    LLines.Add('DB=' + Trim(FpDatabase));
    if Trim(FpRole) <> '' then
      LLines.Add('Role=' + Trim(FpRole));
    LLines.Add('');
    LLines.Add('[POSTGRES]');
    LLines.Add('Host=' + Trim(PgHost));
    LLines.Add('Port=' + Trim(PgPort));
    LLines.Add('Database=' + Trim(PgDatabase));
    LLines.Add('User=' + Trim(PgUser));
    LLines.Add('Password=' + PgPassword);
    LLines.Add('Enabled=' + Trim(PgEnabled));
    LLines.Add('');
    LLines.Add('[MIRROR]');
    LLines.Add('Enabled=' + Trim(MirrorEnabled));
    LLines.Add('NextApiBase=' + LNextBase);
    LLines.Add('Url=' + LMirrorUrl);
    LLines.SaveToFile(LPath);
  finally
    LLines.Free;
  end;
end;

procedure Tdmdb.WriteFieldPecIni(const AServer, AUser, APassword, APort, ADatabase, ARole: string);
var
  LCgServer, LCgUser, LCgPass, LCgPort, LCgDb, LCgRole: string;
  LPgHost, LPgUser, LPgPass, LPgPort, LPgDb, LPgEnabled: string;
  LMirrorEnabled, LMirrorUrl, LMirrorNextApiBase: string;
begin
  ReadCgpecIni(LCgServer, LCgUser, LCgPass, LCgPort, LCgDb, LCgRole);
  ReadPostgresIni(LPgHost, LPgUser, LPgPass, LPgPort, LPgDb, LPgEnabled);
  ReadMirrorIni(LMirrorEnabled, LMirrorUrl, LMirrorNextApiBase);
  WriteApiConfigIni('fieldpec', LCgServer, LCgUser, LCgPass, LCgPort, LCgDb, LCgRole,
    AServer, AUser, APassword, APort, ADatabase, ARole,
    LPgHost, LPgUser, LPgPass, LPgPort, LPgDb, LPgEnabled,
    LMirrorEnabled, LMirrorUrl, LMirrorNextApiBase,
    AcumIniStr(GetFornecimentoAcumulativo));
end;

procedure Tdmdb.WritePostgresIni(const AHost, AUser, APassword, APort, ADatabase, AEnabled: string);
var
  LCgServer, LCgUser, LCgPass, LCgPort, LCgDb, LCgRole: string;
  LFpServer, LFUser, LFPass, LFPort, LFDb, LFRole: string;
  LMirrorEnabled, LMirrorUrl, LMirrorNextApiBase: string;
  LPgPass, LPgEnabled: string;
begin
  ReadCgpecIni(LCgServer, LCgUser, LCgPass, LCgPort, LCgDb, LCgRole);
  ReadFieldPecIni(LFpServer, LFUser, LFPass, LFPort, LFDb, LFRole);
  ReadMirrorIni(LMirrorEnabled, LMirrorUrl, LMirrorNextApiBase);
  LPgPass := APassword;
  LPgEnabled := AEnabled;
  if LPgEnabled = '' then
    LPgEnabled := '1';
  WriteApiConfigIni(GetActiveClient, LCgServer, LCgUser, LCgPass, LCgPort, LCgDb, LCgRole,
    LFpServer, LFUser, LFPass, LFPort, LFDb, LFRole,
    AHost, AUser, LPgPass, APort, ADatabase, LPgEnabled,
    LMirrorEnabled, LMirrorUrl, LMirrorNextApiBase,
    AcumIniStr(GetFornecimentoAcumulativo));
end;

procedure Tdmdb.WriteCgpecIni(const AServer, AUser, APassword, APort, ADatabase, ARole: string);
var
  LPgHost, LPgUser, LPgPass, LPgPort, LPgDb, LPgEnabled: string;
  LFpServer, LFUser, LFPass, LFPort, LFDb, LFRole: string;
  LMirrorEnabled, LMirrorUrl, LMirrorNextApiBase: string;
begin
  ReadPostgresIni(LPgHost, LPgUser, LPgPass, LPgPort, LPgDb, LPgEnabled);
  ReadFieldPecIni(LFpServer, LFUser, LFPass, LFPort, LFDb, LFRole);
  ReadMirrorIni(LMirrorEnabled, LMirrorUrl, LMirrorNextApiBase);
  WriteApiConfigIni(GetActiveClient, AServer, AUser, APassword, APort, ADatabase, ARole,
    LFpServer, LFUser, LFPass, LFPort, LFDb, LFRole,
    LPgHost, LPgUser, LPgPass, LPgPort, LPgDb, LPgEnabled,
    LMirrorEnabled, LMirrorUrl, LMirrorNextApiBase,
    AcumIniStr(GetFornecimentoAcumulativo));
end;

procedure Tdmdb.TestFieldPecConnection(const AServer, AUser, APassword, APort, ADatabase: string;
  out AOk: Boolean; out AError: string);
begin
  TestCgpecConnection(AServer, AUser, APassword, APort, ADatabase, AOk, AError);
end;

function RunHiddenCommand(const AExe, AParams, AWorkDir: string; out AOutput: string): DWORD;
var
  SecAttr: TSecurityAttributes;
  hRead, hWrite: THandle;
  SI: TStartupInfo;
  PI: TProcessInformation;
  CmdLine: string;
  Buffer: array[0..4095] of AnsiChar;
  BytesRead: DWORD;
  LAvail: DWORD;
  LChunk: AnsiString;
begin
  AOutput := '';
  Result := DWORD(-1);
  SecAttr.nLength := SizeOf(SecAttr);
  SecAttr.bInheritHandle := True;
  SecAttr.lpSecurityDescriptor := nil;

  if not CreatePipe(hRead, hWrite, @SecAttr, 0) then
    Exit;
  try
    if not SetHandleInformation(hRead, HANDLE_FLAG_INHERIT, 0) then
      Exit;

    FillChar(SI, SizeOf(SI), 0);
    SI.cb := SizeOf(SI);
    SI.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
    SI.wShowWindow := SW_HIDE;
    SI.hStdOutput := hWrite;
    SI.hStdError := hWrite;
    SI.hStdInput := GetStdHandle(STD_INPUT_HANDLE);

    CmdLine := '"' + AExe + '" ' + AParams;
    if not CreateProcess(nil, PChar(CmdLine), nil, nil, True, CREATE_NO_WINDOW, nil,
      PChar(AWorkDir), SI, PI) then
      Exit;

    CloseHandle(hWrite);
    hWrite := 0;

    repeat
      if not PeekNamedPipe(hRead, nil, 0, nil, @LAvail, nil) then
        Break;
      if LAvail = 0 then
      begin
        if WaitForSingleObject(PI.hProcess, 50) = WAIT_OBJECT_0 then
        begin
          if not PeekNamedPipe(hRead, nil, 0, nil, @LAvail, nil) then
            Break;
          if LAvail = 0 then
            Break;
        end;
        Continue;
      end;
      if LAvail > SizeOf(Buffer) then
        LAvail := SizeOf(Buffer);
      if ReadFile(hRead, Buffer, LAvail, BytesRead, nil) and (BytesRead > 0) then
      begin
        SetString(LChunk, PAnsiChar(@Buffer[0]), BytesRead);
        AOutput := AOutput + string(LChunk);
      end;
    until False;

    WaitForSingleObject(PI.hProcess, INFINITE);
    GetExitCodeProcess(PI.hProcess, Result);
    CloseHandle(PI.hThread);
    CloseHandle(PI.hProcess);
  finally
    if hWrite <> 0 then
      CloseHandle(hWrite);
    CloseHandle(hRead);
  end;
end;

function FindPsqlExecutable: string;
var
  LVerDirs: array[0..6] of string;
  I: Integer;
begin
  Result := '';
  LVerDirs[0] := '18';
  LVerDirs[1] := '17';
  LVerDirs[2] := '16';
  LVerDirs[3] := '15';
  LVerDirs[4] := '14';
  LVerDirs[5] := '13';
  LVerDirs[6] := '12';
  for I := Low(LVerDirs) to High(LVerDirs) do
  begin
    Result := 'C:\Program Files\PostgreSQL\' + LVerDirs[I] + '\bin\psql.exe';
    if FileExists(Result) then
      Exit;
    Result := 'C:\Program Files (x86)\PostgreSQL\' + LVerDirs[I] + '\bin\psql.exe';
    if FileExists(Result) then
      Exit;
  end;
  Result := '';
end;

procedure Tdmdb.TestPostgresConnection(const AHost, AUser, APassword, APort, ADatabase: string;
  out AOk: Boolean; out AError: string);
var
  LPsql, LParams, LOut: string;
  LExit: DWORD;
  LOldPass: string;
begin
  AOk := False;
  AError := '';
  LPsql := FindPsqlExecutable;
  if LPsql = '' then
  begin
    AError := 'psql.exe não encontrado. Instale o cliente PostgreSQL (pasta bin).';
    Exit;
  end;

  LParams :=
    '-h ' + Trim(AHost) +
    ' -p ' + Trim(APort) +
    ' -U ' + Trim(AUser) +
    ' -d ' + Trim(ADatabase) +
    ' -v ON_ERROR_STOP=1 -tAc "SELECT 1"';

  LOldPass := GetEnvironmentVariable('PGPASSWORD');
  SetEnvironmentVariable('PGPASSWORD', PChar(APassword));
  try
    LExit := RunHiddenCommand(LPsql, LParams, ExtractFilePath(LPsql), LOut);
  finally
    if LOldPass <> '' then
      SetEnvironmentVariable('PGPASSWORD', PChar(LOldPass))
    else
      SetEnvironmentVariable('PGPASSWORD', nil);
  end;

  AOk := (LExit = 0) and (Trim(LOut) = '1');
  if not AOk then
  begin
    if LOut <> '' then
      AError := LOut
    else
      AError := 'Falha ao conectar no PostgreSQL.';
  end;
end;

procedure Tdmdb.TestCgpecConnection(const AServer, AUser, APassword, APort, ADatabase: string;
  out AOk: Boolean; out AError: string);
var
  LVendor: string;
  LWasConnected: Boolean;
  LOldParams: TStrings;
begin
  AOk := False;
  AError := '';
  LVendor := ExtractFilePath(ParamStr(0)) + 'fbclient.dll';
  if not FileExists(LVendor) then
  begin
    AError := 'fbclient.dll não localizada em: ' + LVendor;
    Exit;
  end;

  LOldParams := TStringList.Create;
  try
    LWasConnected := FBCon.Connected;
    if LWasConnected then
      FBCon.Close;
    LOldParams.Assign(FBCon.Params);

    try
      FBDriver.VendorLib := LVendor;
      FBCon.Params.Clear;
      FBCon.DriverName := 'FB';
      FBCon.LoginPrompt := False;
      FBCon.Params.Values['Server'] := Trim(AServer);
      FBCon.Params.Values['Port'] := Trim(APort);
      FBCon.Params.Values['Database'] := Trim(ADatabase);
      FBCon.Params.Values['User_Name'] := Trim(AUser);
      FBCon.Params.Values['Password'] := APassword;
      FBCon.Params.Values['Protocol'] := 'TCPIP';
      FBCon.Connected := True;
      FBCon.Close;
      AOk := True;
    except
      on E: Exception do
        AError := E.Message;
    end;

    FBCon.Close;
    FBCon.Params.Assign(LOldParams);
    if LWasConnected and (AOk or (LOldParams.Count > 0)) then
    begin
      try
        FBCon.Connected := True;
      except
        // conexão de produção será restabelecida no próximo ConectaDBCGPec
      end;
    end;
  finally
    LOldParams.Free;
  end;
end;

procedure Tdmdb.DisconnectCgpec;
begin
  if FBCon.Connected then
    FBCon.Close;
end;

function Tdmdb.LerIni(Diretorio, Chave1, Chave2,
  ValorPadrao: String): String;
var
 FileIni: TIniFile;
begin
  result := ValorPadrao;
  try
    FileIni := TIniFile.Create(Diretorio);
    if FileExists(Diretorio) then
      result := FileIni.ReadString(Chave1, Chave2, ValorPadrao);
  finally
    FreeAndNil(FileIni)
  end;
end;

end.
