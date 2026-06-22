unit UdmFieldPec;

interface

uses
  System.SysUtils, System.Classes, FireDAC.Stan.Intf, FireDAC.Stan.Option,
  FireDAC.Stan.Error, FireDAC.UI.Intf, FireDAC.Phys.Intf, FireDAC.Stan.Def,
  FireDAC.Stan.Pool, FireDAC.Stan.Async, FireDAC.Phys, FireDAC.Phys.FB,
  FireDAC.Phys.FBDef, FireDAC.FMXUI.Wait, FireDAC.Stan.Param, FireDAC.DatS,
  FireDAC.DApt.Intf, FireDAC.DApt, Data.DB, FireDAC.Comp.DataSet,
  FireDAC.Comp.Client, FireDAC.Phys.IBBase,System.TypInfo,System.IniFiles,
  FireDAC.VCLUI.Wait;

type
  TdmFieldPec = class(TDataModule)
    FBCon: TFDConnection;
    FBDriver: TFDPhysFBDriverLink;
    CADASTRO_USUARIO: TFDQuery;
    CADASTRO_FAZENDA: TFDQuery;
    CADASTRO_DIETAS: TFDQuery;
    DETALHES_DIETAS: TFDQuery;
    BAIAS: TFDQuery;
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
    qryAux: TFDQuery;
    PREVISAO: TFDQuery;
    CADASTRO_FAZENDAIDFAZENDA: TIntegerField;
    CADASTRO_FAZENDACLIENTE: TStringField;
    CADASTRO_FAZENDAFAZENDA: TStringField;
    DETALHES_DIETASID: TIntegerField;
    DETALHES_DIETASID_DIETA: TIntegerField;
    DETALHES_DIETASNOME_DIETA: TStringField;
    DETALHES_DIETASTIPO_DIETA: TStringField;
    DETALHES_DIETASID_INSUMO: TIntegerField;
    DETALHES_DIETASINGREDIENTE: TStringField;
    DETALHES_DIETASMS_INSUMO: TFMTBCDField;
    DETALHES_DIETASMS_INCLUSAO: TFMTBCDField;
    DETALHES_DIETASMN_PERC: TFMTBCDField;
    DETALHES_DIETASORDEM: TIntegerField;
    DETALHES_DIETASID_PREMISTURA: TIntegerField;
    CADASTRO_DIETASID: TIntegerField;
    CADASTRO_DIETASID_FAZENDA: TIntegerField;
    CADASTRO_DIETASNOME_DIETA: TStringField;
    CADASTRO_DIETASTIPO_DIETA: TStringField;
    CADASTRO_DIETASSTATUS: TStringField;
    CADASTRO_DIETASLIBERADO: TIntegerField;
    CADASTRO_DIETASID_USUARIO: TIntegerField;
    CADASTRO_DIETASMN_TOTAL: TIntegerField;
    CADASTRO_DIETASDATA_REGISTRO: TSQLTimeStampField;
    CADASTRO_DIETASMS_DIETA: TFMTBCDField;
    BAIASID_BAIA: TIntegerField;
    BAIASID_LOTE: TIntegerField;
    BAIASNOME_LOCAL: TStringField;
    BAIASLINHA: TStringField;
    BAIASNUMERO: TStringField;
    BAIASORDEM_TRATO: TIntegerField;
    BAIASRFID: TStringField;
    BAIASID_FAZENDA: TStringField;
    VagaoNOME: TStringField;
    VagaoID: TIntegerField;
    FabricacaoID: TIntegerField;
    FabricacaoIDRACAO: TIntegerField;
    FabricacaoDATA_FAB: TDateField;
    FabricacaoKG_PREVISTO: TBCDField;
    FabricacaoKG_REALIZADO: TBCDField;
    FabricacaoCUSTO_TOTAL: TBCDField;
    FabricacaoHORA_INICIO: TTimeField;
    FabricacaoHORA_FIM: TTimeField;
    FabricacaoDATAREG: TDateField;
    FabricacaoID_USUARIO: TIntegerField;
    FabricacaoTIPO_BAIXA: TIntegerField;
    FabricacaoID_CENTROCUSTO: TIntegerField;
    FabricacaoLOTE_FABRICACAO: TStringField;
    FabricacaoID_OPERADOR: TIntegerField;
    FabricacaoORIGEM_DADOS: TIntegerField;
    FabricacaoDATA_ALTERACAO: TSQLTimeStampField;
    FabricacaoID_USUARIO_ALTERACAO: TIntegerField;
    FabricacaoSTATUS: TIntegerField;
    FabricacaoID_PROPRIEDADE: TIntegerField;
    FabricacaoID_PREMISTURA: TIntegerField;
    Fabricacao_InsumosID: TIntegerField;
    Fabricacao_InsumosID_FABRICACAO: TIntegerField;
    Fabricacao_InsumosID_ALIMENTO: TIntegerField;
    Fabricacao_InsumosID_CONCENTRADO: TIntegerField;
    Fabricacao_InsumosDATA_FAB: TDateField;
    Fabricacao_InsumosHORA_INI: TTimeField;
    Fabricacao_InsumosHORA_FIM: TTimeField;
    Fabricacao_InsumosMS_INSUMO: TFMTBCDField;
    Fabricacao_InsumosKG_PREVISTO: TBCDField;
    Fabricacao_InsumosKG_FABRICADO: TBCDField;
    Fabricacao_InsumosDATAREG: TDateField;
    Fabricacao_InsumosID_USUARIO: TIntegerField;
    Fabricacao_InsumosID_USUARIO_ALTERACAO: TIntegerField;
    Fabricacao_InsumosDATA_ALTERACAO: TSQLTimeStampField;
    Fabricacao_InsumosSTATUS: TIntegerField;
    Fabricacao_InsumosVALOR_KG: TFMTBCDField;
    Fabricacao_InsumosCUSTO: TFMTBCDField;
  private
    { Private declarations }
  public
    function  LerIni(Diretorio,Chave1, Chave2, ValorPadrao: String): String;
    procedure ConectaDBField;
    procedure AtualizaResumoFabricacao(const IDFabricacao: string);
    function  GetCustoMedioKgInsumo(const IdProduto, IdFazenda, DataBase: string): Double;
    function  VerificaTabelaExiste(vTable: string): Integer;
    procedure AtualizaDB;
    procedure GeraTabelaTMP_Previsao(idFazenda:String; DataPrev:TDate);
  end;

var
  dmFieldPec: TdmFieldPec;

implementation

uses Udm;

{%CLASSGROUP 'FMX.Controls.TControl'}

{$R *.dfm}

{ TdmFieldPec }

procedure TdmFieldPec.AtualizaDB;
begin

end;

procedure TdmFieldPec.AtualizaResumoFabricacao(const IDFabricacao: string);
begin

end;


procedure TdmFieldPec.ConectaDBField;
var
  VendorDll, vServer, vUser, vPass, vPort, vDB, vRole: string;
  I: Integer;
  Msg: string;
begin
  VendorDll := ExtractFilePath(ParamStr(0)) + 'fbclient.dll';

  if not FileExists(dmdb.ConfigIniFilePath) then
    raise Exception.Create('Arquivo ApiConfig.ini n�o localizado em: ' + dmdb.ConfigIniFilePath);

  if not FileExists(VendorDll) then
    raise Exception.Create('fbclient.dll n�o localizada em: ' + VendorDll);

  try if CADASTRO_USUARIO.Active then CADASTRO_USUARIO.Close; except end;
  try if FBCon.Connected then FBCon.Close; except end;

  dmdb.ReadFieldPecIni(vServer, vUser, vPass, vPort, vDB, vRole);

  if vServer = '' then
    raise Exception.Create('Server FieldPec n�o configurado em [FIELDPEC] do ApiConfig.ini.');
  if vDB = '' then
    raise Exception.Create('DB FieldPec n�o configurado em [FIELDPEC] do ApiConfig.ini.');
  if vUser = '' then
    raise Exception.Create('User FieldPec n�o configurado em [FIELDPEC] do ApiConfig.ini.');
  if vPort = '' then
    vPort := '3050';

  FBDriver.VendorLib := VendorDll;

  FBCon.LoginPrompt := False;
  FBCon.ResourceOptions.SilentMode := True;
  FBCon.DriverName := 'FB';
  FBCon.Params.Clear;

  FBCon.Params.Values['DriverID']    := 'FB';
  FBCon.Params.Values['Protocol']    := 'TCPIP';
  FBCon.Params.Values['Server']      := vServer;
  FBCon.Params.Values['Port']        := vPort;
  FBCon.Params.Values['Database']    := vDB;
  FBCon.Params.Values['User_Name']   := vUser;
  FBCon.Params.Values['Password']    := vPass;
  FBCon.Params.Values['CharacterSet']:= 'WIN1252';
  FBCon.Params.Values['LoginTimeout']:= '5';

  try
    FBCon.Connected := True;
  except
    on E: EFDDBEngineException do
    begin
      Msg := E.Message;

      for I := 0 to E.ErrorCount - 1 do
        Msg := Msg + sLineBreak +
          Format('FD[%d] Code=%d Kind=%s Msg=%s',
            [I,
             E.Errors[I].ErrorCode,
             GetEnumName(TypeInfo(TFDCommandExceptionKind), Ord(E.Errors[I].Kind)),
             E.Errors[I].Message]);

      raise Exception.Create('Falha ao conectar Field:' + sLineBreak + Msg);
    end;

    on E: Exception do
      raise Exception.Create('Falha ao conectar Field: ' + E.ClassName + ' - ' + E.Message);
  end;
end;

procedure TdmFieldPec.GeraTabelaTMP_Previsao(idFazenda: String;
  DataPrev: TDate);
begin

end;

function TdmFieldPec.GetCustoMedioKgInsumo(const IdProduto, IdFazenda,
  DataBase: string): Double;
begin

end;

function TdmFieldPec.LerIni(Diretorio, Chave1, Chave2,
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

function TdmFieldPec.VerificaTabelaExiste(vTable: string): Integer;
begin

end;

end.
