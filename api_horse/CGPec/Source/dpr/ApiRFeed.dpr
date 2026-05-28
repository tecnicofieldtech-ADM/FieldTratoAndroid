program ApiRFeed;

uses
  System.StartUpCopy,
  FMX.Forms,
  UPrincipal in '..\Principal\UPrincipal.pas' {frmPrincipal},
  DataSet.Serialize.Config in '..\DatasetSerialize\DataSet.Serialize.Config.pas',
  DataSet.Serialize.Consts in '..\DatasetSerialize\DataSet.Serialize.Consts.pas',
  DataSet.Serialize.Export in '..\DatasetSerialize\DataSet.Serialize.Export.pas',
  DataSet.Serialize.Import in '..\DatasetSerialize\DataSet.Serialize.Import.pas',
  DataSet.Serialize.Language in '..\DatasetSerialize\DataSet.Serialize.Language.pas',
  DataSet.Serialize in '..\DatasetSerialize\DataSet.Serialize.pas',
  DataSet.Serialize.UpdatedStatus in '..\DatasetSerialize\DataSet.Serialize.UpdatedStatus.pas',
  DataSet.Serialize.Utils in '..\DatasetSerialize\DataSet.Serialize.Utils.pas',
  Udm in '..\dm\Udm.pas' {dmdb: TDataModule},
  Controllers.Get in '..\Controllers\Controllers.Get.pas',
  Controllers.Post in '..\Controllers\Controllers.Post.pas',
  Controllers.Admin in '..\Controllers\Controllers.Admin.pas',
  Controllers.Mirror in '..\Controllers\Controllers.Mirror.pas',
  UBiMirror in '..\BiMirror\UBiMirror.pas',
  URequestLog in '..\RequestLog\URequestLog.pas',
  Controllers.Get.Field in '..\..\..\FieldPec\Source\Controllers\Controllers.Get.Field.pas',
  Controllers.Post.Field in '..\..\..\FieldPec\Source\Controllers\Controllers.Post.Field.pas',
  UdmFieldPec in '..\..\..\FieldPec\Source\dm\UdmFieldPec.pas' {dmFieldPec: TDataModule};

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TfrmPrincipal, frmPrincipal);
  Application.CreateForm(Tdmdb, dmdb);
  Application.Run;
end.
