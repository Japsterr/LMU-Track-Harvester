program LMUTrackHarvester;

uses
  Vcl.Forms,
  MainForm in 'MainForm.pas' {MainForm},
  AddLapForm in 'AddLapForm.pas' {AddLapForm},
  ImportTelemetryForm in 'ImportTelemetryForm.pas' {ImportTelemetryForm},
  DatabaseManager in 'DatabaseManager.pas',
  LapTimeModels in 'LapTimeModels.pas',
  AppSettings in 'AppSettings.pas',
  CSVExporter in 'CSVExporter.pas',
  GeminiAPI in 'GeminiAPI.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.Title := 'LMU Track Harvester';
  Application.CreateForm(TMainForm, FrmMain);
  Application.Run;
end.
