program LMUTrackHarvester;

uses
  System.SysUtils,
  Vcl.Forms,
  Vcl.Themes,
  MainForm in 'MainForm.pas' {MainForm},
  AddLapForm in 'AddLapForm.pas' {AddLapForm},
  ImportTelemetryForm in 'ImportTelemetryForm.pas' {ImportTelemetryForm},
  DatabaseManager in 'DatabaseManager.pas',
  LapTimeModels in 'LapTimeModels.pas',
  AppSettings in 'AppSettings.pas',
  CSVExporter in 'CSVExporter.pas',
  GeminiAPI in 'GeminiAPI.pas',
  ResultsXMLImporter in 'ResultsXMLImporter.pas';

{$R *.res}

procedure TryApplyPreferredVclStyle;
const
  PreferredStyles: array[0..4] of string = ('Glow', 'Carbon', 'Auric', 'Obsidian', 'TabletDark');
var
  StyleName: string;
begin
  for StyleName in PreferredStyles do
    if TStyleManager.TrySetStyle(StyleName, False) then
      Exit;
end;

begin
  Application.Initialize;
  TryApplyPreferredVclStyle;
  Application.MainFormOnTaskbar := True;
  Application.Title := 'LMU Track Harvester';
  Application.CreateForm(TMainForm, FrmMain);
  Application.Run;
end.
