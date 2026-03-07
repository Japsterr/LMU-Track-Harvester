program LMUTrackHarvester;

uses
  System.SysUtils,
  System.IOUtils,
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
  DelphiVersions: array[0..3] of string = ('23.0', '22.0', '21.0', '20.0');
var
  StyleName: string;
  StylePath: string;
  ProgramFilesX86Path: string;
  Version: string;
  function TryLoadStyleFromFile(const AStylePath: string): Boolean;
  begin
    Result := False;
    if not TFile.Exists(AStylePath) then
      Exit;

    try
      TStyleManager.SetStyle(TStyleManager.LoadFromFile(AStylePath));
      Result := True;
    except
      on ECustomStyleException do
        Result := False;
      on Exception do
        Result := False;
    end;
  end;
begin
  ProgramFilesX86Path := Trim(GetEnvironmentVariable('ProgramFiles(x86)'));

  for StyleName in PreferredStyles do
  begin
    if TStyleManager.TrySetStyle(StyleName, False) then
      Exit;

    StylePath := TPath.Combine(ExtractFilePath(ParamStr(0)), 'styles\' + StyleName + '.vsf');
    if TryLoadStyleFromFile(StylePath) then
      Exit;

    if ProgramFilesX86Path = '' then
      Continue;

    for Version in DelphiVersions do
    begin
      StylePath := TPath.Combine(ProgramFilesX86Path,
        Format('Embarcadero\Studio\%s\Redist\styles\vcl\%s.vsf', [Version, StyleName]));
      if TryLoadStyleFromFile(StylePath) then
        Exit;
    end;
  end;
end;

begin
  Application.Initialize;
  TryApplyPreferredVclStyle;
  Application.MainFormOnTaskbar := True;
  Application.Title := 'LMU Track Harvester';
  Application.CreateForm(TMainForm, FrmMain);
  Application.Run;
end.
