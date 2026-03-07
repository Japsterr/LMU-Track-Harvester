unit MainForm;

{ Main application window for LMU Track Harvester.
  Tabs:
    1. Lap Times  – Select track + car class to view top-10 personal bests and
                    fastest lap per car.  Add / delete laps manually.
    2. Telemetry  – Manage saved telemetry sessions.  Export to CSV.
                    Analyze with Google Gemini AI directly in-app.
    3. Settings   – Store Gemini API key and choose the AI model. }

interface

uses
  Winapi.Windows, Winapi.Messages, Winapi.ShellAPI,
  System.SysUtils, System.Classes, System.IOUtils,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls,
  Vcl.FileCtrl,
  Vcl.Graphics,
  Vcl.Themes,
  FireDAC.Comp.Client,
  DatabaseManager, LapTimeModels, AppSettings,
  CSVExporter, GeminiAPI,
  AddLapForm, ImportTelemetryForm, ResultsXMLImporter;

type
  TMainForm = class(TForm)
    PageControl: TPageControl;
    TabLapTimes: TTabSheet;
    TabTelemetry: TTabSheet;
    TabSettings: TTabSheet;
    StatusBar: TStatusBar;

    // ---- Lap Times tab ----
    PnlLTTop: TPanel;
    LblTrack: TLabel;
    LblClass: TLabel;
    CboTrack: TComboBox;
    CboClass: TComboBox;
    BtnAddLap: TButton;
    BtnDeleteLap: TButton;
    BtnExportLaps: TButton;
    PnlLTContent: TPanel;
    SplitterLT: TSplitter;
    GrpTop10: TGroupBox;
    LvwTop10: TListView;
    GrpFastest: TGroupBox;
    LvwFastest: TListView;

    // ---- Telemetry tab ----
    SplitterTel: TSplitter;
    PnlTelLeft: TPanel;
    LblSessions: TLabel;
    LvwSessions: TListView;
    PnlTelLeftButtons: TPanel;
    BtnImportTel: TButton;
    BtnDeleteSession: TButton;
    PnlTelRight: TPanel;
    GrpSessionInfo: TGroupBox;
    MemoSessionInfo: TMemo;
    PnlTelActions: TPanel;
    BtnExportCSV: TButton;
    BtnAnalyzeAI: TButton;
    BtnClearAI: TButton;
    GrpAIResponse: TGroupBox;
    MemoAIResponse: TMemo;

    // ---- Settings tab ----
    PnlSettings: TPanel;
    LblSettingsTitle: TLabel;
    LblSep1: TLabel;
    LblAPIKey: TLabel;
    LblAPIKeyInfo: TLabel;
    LblModel: TLabel;
    LblGetKey: TLabel;
    LblTestResult: TLabel;
    LblTelemetrySource: TLabel;
    LblTelemetrySourceInfo: TLabel;
    LblResultsSource: TLabel;
    LblResultsSourceInfo: TLabel;
    LblPreferredDriver: TLabel;
    LblPreferredDriverInfo: TLabel;
    EdtAPIKey: TEdit;
    EdtTelemetryFolder: TEdit;
    EdtResultsFolder: TEdit;
    EdtPreferredDriver: TEdit;
    BtnShowKey: TButton;
    CboAIModel: TComboBox;
    BtnSaveSettings: TButton;
    BtnTestAPI: TButton;
    BtnBrowseTelemetryFolder: TButton;
    BtnRescanTelemetry: TButton;
    BtnBrowseResultsFolder: TButton;
    BtnRescanResults: TButton;

    // ---- Events ----
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);

    // Lap Times
    procedure CboTrackChange(Sender: TObject);
    procedure CboClassChange(Sender: TObject);
    procedure BtnAddLapClick(Sender: TObject);
    procedure BtnDeleteLapClick(Sender: TObject);
    procedure BtnExportLapsClick(Sender: TObject);
    procedure LvwTop10SelectItem(Sender: TObject; Item: TListItem;
                                  Selected: Boolean);

    // Telemetry
    procedure LvwSessionsSelectItem(Sender: TObject; Item: TListItem;
                                     Selected: Boolean);
    procedure BtnImportTelClick(Sender: TObject);
    procedure BtnDeleteSessionClick(Sender: TObject);
    procedure BtnExportCSVClick(Sender: TObject);
    procedure BtnAnalyzeAIClick(Sender: TObject);
    procedure BtnClearAIClick(Sender: TObject);

    // Settings
    procedure BtnShowKeyClick(Sender: TObject);
    procedure BtnSaveSettingsClick(Sender: TObject);
    procedure BtnTestAPIClick(Sender: TObject);
    procedure LblGetKeyClick(Sender: TObject);
    procedure BtnBrowseTelemetryFolderClick(Sender: TObject);
    procedure BtnRescanTelemetryClick(Sender: TObject);
    procedure BtnBrowseResultsFolderClick(Sender: TObject);
    procedure BtnRescanResultsClick(Sender: TObject);

  private
    FDB: TDatabaseManager;
    FSettings: TAppSettings;
    FTracks: TTrackArray;
    FClasses: TCarClassArray;
    FSessions: TTelemetrySessionArray;
    FSourceTelemetryFiles: TArray<string>;

    procedure LoadTrackCombo;
    procedure LoadClassCombo;
    procedure RefreshLapTimes;
    procedure PopulateLapListView(ALV: TListView; const ALaps: TLapTimeArray);
    procedure RefreshSessions;

    function SelectedTrackID: Integer;
    function SelectedClassID: Integer;
    function SelectedSessionID: Integer;
    function SelectedSourceTelemetryFile: string;
    function SelectedSessionInfo(out ATrackName, ACarName, AClassName: string): Boolean;

    procedure SetStatus(const AMsg: string);
    procedure RefreshTelemetrySourceInfo;
    procedure RefreshResultsSourceInfo;
    procedure ApplyRacingTheme;
    procedure ImportResultsFromConfiguredFolder(AShowStatus: Boolean);
    procedure DescribeTelemetrySourceFile(const AFilePath: string; ALines: TStrings);

    function DetectPreferredDriverName: string;
  end;

var
  FrmMain: TMainForm;

implementation

{$R *.dfm}

// ---------------------------------------------------------------------------
// Form lifecycle
// ---------------------------------------------------------------------------

procedure TMainForm.FormCreate(Sender: TObject);
begin
  FSettings := TAppSettings.Create;
  FDB       := TDatabaseManager.Create;

  ApplyRacingTheme;

  LoadTrackCombo;
  LoadClassCombo;
  RefreshLapTimes;
  RefreshSessions;

  // Restore settings
  EdtAPIKey.Text := FSettings.GeminiAPIKey;
  var ModelIdx := CboAIModel.Items.IndexOf(FSettings.AIModel);
  if ModelIdx >= 0 then
    CboAIModel.ItemIndex := ModelIdx
  else
    CboAIModel.ItemIndex := 0;

  SetStatus('Database loaded from: ' + FDB.DatabasePath);

  if FSettings.WindowMaximized then
    WindowState := wsMaximized;

  EdtTelemetryFolder.Text := FSettings.TelemetrySourceFolder;
  EdtResultsFolder.Text := FSettings.ResultsSourceFolder;
  EdtPreferredDriver.Text := FSettings.PreferredDriverName;
  if Trim(EdtPreferredDriver.Text) = '' then
    EdtPreferredDriver.Text := DetectPreferredDriverName;
  RefreshTelemetrySourceInfo;
  RefreshResultsSourceInfo;
  ImportResultsFromConfiguredFolder(False);
  RefreshLapTimes;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  FSettings.GeminiAPIKey := Trim(EdtAPIKey.Text);
  FSettings.TelemetrySourceFolder := Trim(EdtTelemetryFolder.Text);
  FSettings.ResultsSourceFolder := Trim(EdtResultsFolder.Text);
  FSettings.PreferredDriverName := Trim(EdtPreferredDriver.Text);
  if CboAIModel.ItemIndex >= 0 then
    FSettings.AIModel := CboAIModel.Items[CboAIModel.ItemIndex];
  FSettings.WindowMaximized := (WindowState = wsMaximized);
  FSettings.Save;
  FSettings.Free;
  FDB.Free;
end;

// ---------------------------------------------------------------------------
// Helper methods
// ---------------------------------------------------------------------------

procedure TMainForm.SetStatus(const AMsg: string);
begin
  StatusBar.Panels[0].Text := AMsg;
end;

procedure TMainForm.ApplyRacingTheme;
const
  COLOR_FRAME = $00140F0B;
  COLOR_PANEL = $00211A16;
  COLOR_SURFACE = $00F2F5F7;
  COLOR_SURFACE_ALT = $00E5ECF1;
  COLOR_ACCENT = $000066CC;
  COLOR_HEADER = $001F4A9D;
begin
  Caption := 'LMU Track Harvester - Driver Performance Hub';
  Color := COLOR_FRAME;

  PageControl.ParentBackground := False;
  PageControl.Color := COLOR_FRAME;

  PnlLTTop.ParentBackground := False;
  PnlLTTop.Color := COLOR_PANEL;
  PnlLTContent.ParentBackground := False;
  PnlLTContent.Color := COLOR_FRAME;
  LblTrack.Font.Color := clWhite;
  LblClass.Font.Color := clWhite;

  GrpTop10.Caption := ' Driver Top 10 Pace ';
  GrpFastest.Caption := ' Best Personal Lap Per Car ';
  GrpTop10.ParentBackground := False;
  GrpFastest.ParentBackground := False;
  GrpTop10.Color := COLOR_SURFACE_ALT;
  GrpFastest.Color := COLOR_SURFACE_ALT;
  GrpTop10.Font.Style := [fsBold];
  GrpFastest.Font.Style := [fsBold];
  LvwTop10.GridLines := False;
  LvwFastest.GridLines := False;
  LvwTop10.Color := COLOR_SURFACE;
  LvwFastest.Color := COLOR_SURFACE;

  LblSessions.Caption := 'Telemetry Garage';
  LblSessions.Color := COLOR_HEADER;
  LblSessions.Font.Color := clWhite;
  PnlTelLeft.ParentBackground := False;
  PnlTelLeft.Color := COLOR_FRAME;
  PnlTelRight.ParentBackground := False;
  PnlTelRight.Color := COLOR_FRAME;
  GrpSessionInfo.ParentBackground := False;
  GrpAIResponse.ParentBackground := False;
  GrpSessionInfo.Color := COLOR_SURFACE_ALT;
  GrpAIResponse.Color := COLOR_SURFACE_ALT;
  GrpSessionInfo.Font.Style := [fsBold];
  GrpAIResponse.Font.Style := [fsBold];
  PnlTelActions.ParentBackground := False;
  PnlTelActions.Color := COLOR_FRAME;
  MemoSessionInfo.Color := COLOR_SURFACE;
  MemoAIResponse.Color := COLOR_SURFACE;
  MemoSessionInfo.Font.Name := 'Bahnschrift';
  MemoAIResponse.Font.Name := 'Bahnschrift';

  PnlSettings.ParentBackground := False;
  PnlSettings.Color := COLOR_SURFACE;

  BtnAddLap.Font.Style := [fsBold];
  BtnDeleteLap.Font.Style := [fsBold];
  BtnExportLaps.Font.Style := [fsBold];
  BtnExportCSV.Font.Style := [fsBold];
  BtnAnalyzeAI.Font.Style := [fsBold];
  BtnImportTel.Font.Style := [fsBold];
  BtnSaveSettings.Font.Style := [fsBold];

  BtnAddLap.Caption := '+ Log Lap';
  BtnDeleteLap.Caption := 'Delete Lap';
  BtnExportLaps.Caption := 'Export Pace';
  BtnExportCSV.Caption := 'Export Telemetry CSV';
  BtnAnalyzeAI.Caption := 'Ask Gemini for Coaching';
  BtnImportTel.Caption := 'Import Telemetry CSV';
  BtnDeleteSession.Caption := 'Delete Saved Session';

  LblSettingsTitle.Caption := 'Driver and AI Control Centre';
  LblSep1.Color := COLOR_ACCENT;
end;

function TMainForm.DetectPreferredDriverName: string;
var
  Folder: string;
  Files: TArray<string>;
  LatestFile: string;
  LatestTime: TDateTime;
  FileTime: TDateTime;
  F: string;
  ErrorText: string;
begin
  Result := Trim(EdtPreferredDriver.Text);
  if Result <> '' then
    Exit;

  Result := '';

  Folder := Trim(EdtTelemetryFolder.Text);
  if Folder = '' then
    Folder := Trim(FSettings.TelemetrySourceFolder);
  if (Folder = '') or (not TDirectory.Exists(Folder)) then
    Exit;

  Files := TDirectory.GetFiles(Folder, '*.duckdb', TSearchOption.soTopDirectoryOnly);
  if Length(Files) = 0 then
    Exit;

  LatestFile := Files[0];
  LatestTime := TFile.GetLastWriteTime(LatestFile);
  for F in Files do
  begin
    FileTime := TFile.GetLastWriteTime(F);
    if FileTime > LatestTime then
    begin
      LatestTime := FileTime;
      LatestFile := F;
    end;
  end;

  TCSVExporter.ReadDuckDBMetadataValue(LatestFile, 'DriverName', Result, ErrorText);
  Result := Trim(Result);
  if Result <> '' then
    EdtPreferredDriver.Text := Result;
end;

procedure TMainForm.RefreshTelemetrySourceInfo;
var
  Folder: string;
  Files: TArray<string>;
  LatestFile: string;
  LatestTime: TDateTime;
  FileTime: TDateTime;
  F: string;
begin
  Folder := Trim(EdtTelemetryFolder.Text);
  if Folder = '' then
  begin
    LblTelemetrySourceInfo.Caption := 'No LMU telemetry folder configured.';
    Exit;
  end;

  if not TDirectory.Exists(Folder) then
  begin
    LblTelemetrySourceInfo.Caption := 'Folder not found: ' + Folder;
    Exit;
  end;

  Files := TDirectory.GetFiles(Folder, '*.duckdb', TSearchOption.soTopDirectoryOnly);
  if Length(Files) = 0 then
    LblTelemetrySourceInfo.Caption := 'No .duckdb files found in telemetry folder.'
  else
  begin
    LatestFile := '';
    LatestTime := 0;
    for F in Files do
    begin
      FileTime := TFile.GetLastWriteTime(F);
      if (LatestFile = '') or (FileTime > LatestTime) then
      begin
        LatestTime := FileTime;
        LatestFile := F;
      end;
    end;

    LblTelemetrySourceInfo.Caption := Format('%d .duckdb telemetry file(s) detected. Latest: %s',
      [Length(Files), ExtractFileName(LatestFile)]);
  end;
end;

procedure TMainForm.RefreshResultsSourceInfo;
var
  Folder: string;
  Files: TArray<string>;
  LatestFile: string;
  LatestTime: TDateTime;
  FileTime: TDateTime;
  F: string;
  DriverName: string;
begin
  DriverName := Trim(EdtPreferredDriver.Text);
  Folder := Trim(EdtResultsFolder.Text);
  if Folder = '' then
  begin
    if DriverName <> '' then
      LblResultsSourceInfo.Caption := 'No LMU results folder configured. Preferred driver: ' + DriverName
    else
      LblResultsSourceInfo.Caption := 'No LMU results folder configured. Set Preferred Driver Name to import only your laps.';
    Exit;
  end;

  if not TDirectory.Exists(Folder) then
  begin
    LblResultsSourceInfo.Caption := 'Folder not found: ' + Folder;
    Exit;
  end;

  Files := TDirectory.GetFiles(Folder, '*.xml', TSearchOption.soTopDirectoryOnly);
  if Length(Files) = 0 then
  begin
    if DriverName <> '' then
      LblResultsSourceInfo.Caption := 'No .xml result files found in results folder. Preferred driver: ' + DriverName
    else
      LblResultsSourceInfo.Caption := 'No .xml result files found in results folder. Set Preferred Driver Name to import only your laps.';
  end
  else
  begin
    LatestFile := '';
    LatestTime := 0;
    for F in Files do
    begin
      FileTime := TFile.GetLastWriteTime(F);
      if (LatestFile = '') or (FileTime > LatestTime) then
      begin
        LatestTime := FileTime;
        LatestFile := F;
      end;
    end;
    if DriverName <> '' then
      LblResultsSourceInfo.Caption := Format('%d .xml result file(s) detected. Latest: %s. Importing laps for: %s',
        [Length(Files), ExtractFileName(LatestFile), DriverName])
    else
      LblResultsSourceInfo.Caption := Format('%d .xml result file(s) detected. Latest: %s. Set Preferred Driver Name before rescanning.',
        [Length(Files), ExtractFileName(LatestFile)]);
  end;
end;

procedure TMainForm.ImportResultsFromConfiguredFolder(AShowStatus: Boolean);
var
  Folder: string;
  Summary: TResultsImportSummary;
  PreferredDriverName: string;
begin
  Folder := Trim(EdtResultsFolder.Text);
  PreferredDriverName := DetectPreferredDriverName;
  if PreferredDriverName = '' then
  begin
    try
      FDB.Connection.ExecSQL('DELETE FROM LapTimes WHERE SessionType LIKE ''LMU Results XML%''');
    except
      // Leave existing data alone if the cleanup cannot be completed.
    end;

    if AShowStatus then
      ShowMessage('Results import skipped because the Preferred Driver Name is empty.' + sLineBreak +
        'Enter your name as it appears in LMU results, then rescan.' + sLineBreak +
        'Example: Japie Bosman');
    SetStatus('LMU results import skipped until Preferred Driver Name is set.');
    Exit;
  end;

  try
    Summary := TResultsXMLImporter.ImportFolder(FDB, Folder, PreferredDriverName);
  except
    on E: Exception do
    begin
      if AShowStatus then
        ShowMessage('Results scan failed: ' + E.Message);
      Exit;
    end;
  end;

  if AShowStatus then
    ShowMessage(Format(
      'Results scan completed.' + sLineBreak +
      'Files scanned: %d' + sLineBreak +
      'Files failed: %d' + sLineBreak +
      'Laps inserted: %d' + sLineBreak +
      'Laps skipped: %d',
      [Summary.FilesScanned, Summary.FilesFailed, Summary.LapsInserted, Summary.LapsSkipped]));

  if Summary.LapsInserted > 0 then
    SetStatus(Format('Imported %d lap record(s) from LMU results XML.', [Summary.LapsInserted]));
end;

procedure TMainForm.LoadTrackCombo;
var
  I: Integer;
begin
  CboTrack.Items.BeginUpdate;
  try
    CboTrack.Items.Clear;
    FTracks := FDB.GetTracks;
    for I := 0 to High(FTracks) do
      CboTrack.Items.Add(FTracks[I].DisplayName);
  finally
    CboTrack.Items.EndUpdate;
  end;
  if CboTrack.Items.Count > 0 then
    CboTrack.ItemIndex := 0;
end;

procedure TMainForm.LoadClassCombo;
var
  I: Integer;
begin
  CboClass.Items.BeginUpdate;
  try
    CboClass.Items.Clear;
    FClasses := FDB.GetCarClasses;
    for I := 0 to High(FClasses) do
      CboClass.Items.Add(FClasses[I].Name);
  finally
    CboClass.Items.EndUpdate;
  end;
  if CboClass.Items.Count > 0 then
    CboClass.ItemIndex := 0;
end;

function TMainForm.SelectedTrackID: Integer;
begin
  if (CboTrack.ItemIndex >= 0) and (CboTrack.ItemIndex <= High(FTracks)) then
    Result := FTracks[CboTrack.ItemIndex].ID
  else
    Result := -1;
end;

function TMainForm.SelectedClassID: Integer;
begin
  if (CboClass.ItemIndex >= 0) and (CboClass.ItemIndex <= High(FClasses)) then
    Result := FClasses[CboClass.ItemIndex].ID
  else
    Result := -1;
end;

function TMainForm.SelectedSessionID: Integer;
begin
  if (LvwSessions.Selected <> nil) and
     (LvwSessions.Selected.Index <= High(FSessions)) then
    Result := FSessions[LvwSessions.Selected.Index].ID
  else
    Result := -1;
end;

function TMainForm.SelectedSourceTelemetryFile: string;
var
  Idx: Integer;
begin
  Result := '';
  if LvwSessions.Selected = nil then
    Exit;

  Idx := LvwSessions.Selected.Index - Length(FSessions);
  if (Idx >= 0) and (Idx <= High(FSourceTelemetryFiles)) then
    Result := FSourceTelemetryFiles[Idx];
end;

function TMainForm.SelectedSessionInfo(out ATrackName, ACarName,
  AClassName: string): Boolean;
var
  Idx: Integer;
  Cars: TCarArray;
begin
  Result := False;
  if LvwSessions.Selected = nil then
    Exit;

  Idx := LvwSessions.Selected.Index;
  if Idx > High(FSessions) then
    Exit;

  ATrackName := FSessions[Idx].TrackName;
  if FSessions[Idx].TrackLayout <> '' then
    ATrackName := ATrackName + ' - ' + FSessions[Idx].TrackLayout;
  ACarName   := FSessions[Idx].CarName;

  // Look up car class name
  Cars := FDB.GetCars(-1);
  var CarID := FSessions[Idx].CarID;
  AClassName := '';
  for var C in Cars do
    if C.ID = CarID then
    begin
      AClassName := C.ClassName;
      Break;
    end;

  Result := True;
end;

// ---------------------------------------------------------------------------
// Lap Times tab
// ---------------------------------------------------------------------------

procedure TMainForm.CboTrackChange(Sender: TObject);
begin
  RefreshLapTimes;
end;

procedure TMainForm.CboClassChange(Sender: TObject);
begin
  RefreshLapTimes;
end;

procedure TMainForm.RefreshLapTimes;
var
  TrackID, ClassID: Integer;
  Top10, Fastest: TLapTimeArray;
begin
  TrackID := SelectedTrackID;
  ClassID := SelectedClassID;

  if (TrackID = -1) or (ClassID = -1) then
  begin
    LvwTop10.Items.Clear;
    LvwFastest.Items.Clear;
    Exit;
  end;

  Top10   := FDB.GetTopLapTimes(TrackID, ClassID, 10);
  Fastest := FDB.GetFastestLapPerCar(TrackID, ClassID);

  PopulateLapListView(LvwTop10,   Top10);
  PopulateLapListView(LvwFastest, Fastest);

  // Update group-box captions with counts
  GrpTop10.Caption   := Format(' Your Top 10 (%d logged) ', [Length(Top10)]);
  GrpFastest.Caption := Format(' Your Best By Car (%d cars) ', [Length(Fastest)]);
end;

procedure TMainForm.PopulateLapListView(ALV: TListView;
  const ALaps: TLapTimeArray);
var
  I: Integer;
  Item: TListItem;
begin
  ALV.Items.BeginUpdate;
  try
    ALV.Items.Clear;
    for I := 0 to High(ALaps) do
    begin
      Item := ALV.Items.Add;
      Item.Caption := IntToStr(I + 1);
      Item.SubItems.Add(ALaps[I].CarName);
      Item.SubItems.Add(FormatLapTime(ALaps[I].LapTimeMs));
      Item.SubItems.Add(FormatDateTime('yyyy-MM-dd', ALaps[I].LapDate));
      Item.SubItems.Add(ALaps[I].SessionType);
      Item.Data := Pointer(ALaps[I].ID);  // Store DB ID
    end;
  finally
    ALV.Items.EndUpdate;
  end;

  SetStatus(Format('%d laps loaded for %s / %s',
    [Length(ALaps),
     CboTrack.Text,
     CboClass.Text]));
end;

procedure TMainForm.LvwTop10SelectItem(Sender: TObject; Item: TListItem;
  Selected: Boolean);
begin
  BtnDeleteLap.Enabled := (LvwTop10.Selected <> nil);
end;

procedure TMainForm.BtnAddLapClick(Sender: TObject);
var
  Dlg: TAddLapForm;
begin
  if not Assigned(FDB) then
  begin
    ShowMessage('Database is not available. Please restart the application.');
    Exit;
  end;

  Dlg := nil;
  try
    try
      Dlg := TAddLapForm.Create(Self);
      Dlg.Initialize(FDB);
      // Pre-select the currently chosen track / class
      if (CboTrack.ItemIndex >= 0) and
         (CboTrack.ItemIndex < Dlg.CboTrack.Items.Count) then
        Dlg.CboTrack.ItemIndex := CboTrack.ItemIndex;
      if (CboClass.ItemIndex >= 0) and
         (CboClass.ItemIndex < Dlg.CboClass.Items.Count) then
      begin
        Dlg.CboClass.ItemIndex := CboClass.ItemIndex;
        Dlg.CboClassChange(nil);
      end;
      if Dlg.ShowModal = mrOk then
      begin
        RefreshLapTimes;
        SetStatus('Lap time added.');
      end;
    finally
      Dlg.Free;
    end;
  except
    on E: Exception do
      ShowMessage('Could not open Add Lap dialog: ' + E.Message);
  end;
end;

procedure TMainForm.BtnDeleteLapClick(Sender: TObject);
var
  LapID: Integer;
begin
  if LvwTop10.Selected = nil then
  begin
    ShowMessage('Please select a lap time to delete.');
    Exit;
  end;

  if MessageDlg('Delete this lap time?', mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;

  LapID := Integer(LvwTop10.Selected.Data);
  if FDB.DeleteLapTime(LapID) then
  begin
    RefreshLapTimes;
    SetStatus('Lap time deleted.');
  end
  else
    ShowMessage('Could not delete lap time.');
end;

procedure TMainForm.BtnExportLapsClick(Sender: TObject);
var
  SD: TSaveDialog;
  TrackID, ClassID: Integer;
begin
  TrackID := SelectedTrackID;
  ClassID := SelectedClassID;
  if (TrackID = -1) or (ClassID = -1) then
  begin
    ShowMessage('Please select a track and car class first.');
    Exit;
  end;

  SD := TSaveDialog.Create(nil);
  try
    SD.Title      := 'Export Lap Times to CSV';
    SD.DefaultExt := 'csv';
    SD.Filter     := 'CSV Files (*.csv)|*.csv|All Files (*.*)|*.*';
    SD.FileName   := Format('LapTimes_%s_%s.csv',
      [StringReplace(CboTrack.Text, ' ', '_', [rfReplaceAll]),
       StringReplace(CboClass.Text, ' ', '_', [rfReplaceAll])]);
    SD.InitialDir := FSettings.LastExportFolder;

    if SD.Execute then
    begin
      FSettings.LastExportFolder := ExtractFilePath(SD.FileName);
      if TCSVExporter.ExportLapTimes(FDB, TrackID, ClassID, SD.FileName, 100) then
      begin
        SetStatus('Lap times exported to: ' + SD.FileName);
        if MessageDlg('Export successful. Open the file?',
                      mtInformation, [mbYes, mbNo], 0) = mrYes then
          ShellExecute(0, 'open', PChar(SD.FileName), nil, nil, SW_SHOWNORMAL);
      end
      else
        ShowMessage('Export failed. Check that the file path is writable.');
    end;
  finally
    SD.Free;
  end;
end;

// ---------------------------------------------------------------------------
// Telemetry tab
// ---------------------------------------------------------------------------

procedure TMainForm.RefreshSessions;
var
  I: Integer;
  Item: TListItem;
  SourceFolder: string;
  SourceFile: string;
  TrackName: string;
  CarName: string;
  ErrorText: string;
begin
  LvwSessions.Items.BeginUpdate;
  try
    LvwSessions.Items.Clear;
    FSessions := FDB.GetTelemetrySessions;
    FSourceTelemetryFiles := nil;

    for I := 0 to High(FSessions) do
    begin
      Item := LvwSessions.Items.Add;
      Item.Caption := FormatDateTime('yyyy-MM-dd HH:nn', FSessions[I].SessionDate);
      Item.SubItems.Add(FSessions[I].TrackName);
      Item.SubItems.Add(FSessions[I].CarName);
    end;

    SourceFolder := Trim(EdtTelemetryFolder.Text);
    if SourceFolder = '' then
      SourceFolder := Trim(FSettings.TelemetrySourceFolder);
    if (SourceFolder <> '') and TDirectory.Exists(SourceFolder) then
    begin
      FSourceTelemetryFiles :=
        TDirectory.GetFiles(SourceFolder, '*.duckdb', TSearchOption.soTopDirectoryOnly);
      for SourceFile in FSourceTelemetryFiles do
      begin
        Item := LvwSessions.Items.Add;
        Item.Caption := FormatDateTime('yyyy-MM-dd HH:nn', TFile.GetLastWriteTime(SourceFile));
        if not TCSVExporter.ReadDuckDBMetadataValue(SourceFile, 'TrackName', TrackName, ErrorText) then
          TrackName := 'LMU source file';
        if not TCSVExporter.ReadDuckDBMetadataValue(SourceFile, 'CarName', CarName, ErrorText) then
          CarName := ExtractFileName(SourceFile);
        Item.SubItems.Add(TrackName);
        Item.SubItems.Add(CarName);
      end;
    end;
  finally
    LvwSessions.Items.EndUpdate;
  end;

  MemoSessionInfo.Clear;
  MemoAIResponse.Clear;
  StatusBar.Panels[1].Text := Format('%d session(s), %d source file(s)',
    [Length(FSessions), Length(FSourceTelemetryFiles)]);
end;

procedure TMainForm.LvwSessionsSelectItem(Sender: TObject; Item: TListItem;
  Selected: Boolean);
var
  Idx: Integer;
  S: TTelemetrySession;
begin
  if (not Selected) or (LvwSessions.Selected = nil) then
  begin
    MemoSessionInfo.Clear;
    Exit;
  end;

  Idx := LvwSessions.Selected.Index;
  if Idx > High(FSessions) then
  begin
    Idx := Idx - Length(FSessions);
    MemoSessionInfo.Lines.Clear;
    if (Idx >= 0) and (Idx <= High(FSourceTelemetryFiles)) then
    begin
      MemoSessionInfo.Lines.Add('LMU telemetry source file selected:');
      MemoSessionInfo.Lines.Add(FSourceTelemetryFiles[Idx]);
      MemoSessionInfo.Lines.Add('');
      DescribeTelemetrySourceFile(FSourceTelemetryFiles[Idx], MemoSessionInfo.Lines);
      MemoSessionInfo.Lines.Add('');
      MemoSessionInfo.Lines.Add('Use "Export Telemetry CSV" to create a coachable file or "Ask Gemini for Coaching" to analyse this source directly.');
    end;
    Exit;
  end;

  S := FSessions[Idx];
  MemoSessionInfo.Lines.Clear;
  MemoSessionInfo.Lines.Add(Format('Track   : %s  %s', [S.TrackName, S.TrackLayout]));
  MemoSessionInfo.Lines.Add(Format('Car     : %s', [S.CarName]));
  MemoSessionInfo.Lines.Add(Format('Date    : %s',
    [FormatDateTime('dddd d mmmm yyyy  HH:nn:ss', S.SessionDate)]));
  MemoSessionInfo.Lines.Add(Format('Points  : %d data points', [S.DataPointCount]));
  if S.Notes <> '' then
    MemoSessionInfo.Lines.Add(Format('Notes   : %s', [S.Notes]));
end;

procedure TMainForm.BtnImportTelClick(Sender: TObject);
var
  Dlg: TImportTelemetryForm;
begin
  Dlg := TImportTelemetryForm.Create(Self);
  try
    Dlg.Initialize(FDB, FSettings.TelemetrySourceFolder);
    if Dlg.ShowModal = mrOk then
    begin
      RefreshSessions;
      SetStatus('Telemetry session imported.');
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TMainForm.BtnDeleteSessionClick(Sender: TObject);
var
  SessionID: Integer;
begin
  SessionID := SelectedSessionID;
  if SessionID = -1 then
  begin
    ShowMessage('Please select a session to delete.');
    Exit;
  end;

  if MessageDlg(
       'Delete this telemetry session and all its data points?',
       mtWarning, [mbYes, mbNo], 0) <> mrYes then
    Exit;

  if FDB.DeleteTelemetrySession(SessionID) then
  begin
    RefreshSessions;
    SetStatus('Session deleted.');
  end
  else
    ShowMessage('Could not delete session.');
end;

procedure TMainForm.BtnExportCSVClick(Sender: TObject);
var
  SessionID: Integer;
  SD: TSaveDialog;
  TrackName, CarName, ClassName: string;
  SourceFile: string;
  ErrorText: string;
begin
  SourceFile := SelectedSourceTelemetryFile;
  if SourceFile <> '' then
  begin
    SD := TSaveDialog.Create(nil);
    try
      SD.Title := 'Export LMU Source Telemetry to CSV';
      SD.DefaultExt := 'csv';
      SD.Filter := 'CSV Files (*.csv)|*.csv|All Files (*.*)|*.*';
      SD.FileName := ChangeFileExt(ExtractFileName(SourceFile), '.csv');
      SD.InitialDir := FSettings.LastExportFolder;

      if SD.Execute then
      begin
        FSettings.LastExportFolder := ExtractFilePath(SD.FileName);
        SetStatus('Exporting DuckDB telemetry...');
        Screen.Cursor := crHourGlass;
        Application.ProcessMessages;
        try
        if TCSVExporter.ExportDuckDBSourceToCSV(SourceFile, SD.FileName, ErrorText) then
        begin
          SetStatus('Source telemetry exported to: ' + SD.FileName);
          if MessageDlg('Export successful. Open the file?',
                        mtInformation, [mbYes, mbNo], 0) = mrYes then
            ShellExecute(0, 'open', PChar(SD.FileName), nil, nil, SW_SHOWNORMAL);
        end
        else
            ShowMessage('Export failed.' + sLineBreak + ErrorText);
        finally
          Screen.Cursor := crDefault;
        end;
      end;
    finally
      SD.Free;
    end;
    Exit;
  end;

  SessionID := SelectedSessionID;
  if SessionID = -1 then
  begin
    ShowMessage('Please select a telemetry session first.');
    Exit;
  end;

  SelectedSessionInfo(TrackName, CarName, ClassName);

  SD := TSaveDialog.Create(nil);
  try
    SD.Title      := 'Export Telemetry Session to CSV';
    SD.DefaultExt := 'csv';
    SD.Filter     := 'CSV Files (*.csv)|*.csv|All Files (*.*)|*.*';
    SD.FileName   := Format('Telemetry_%s_%s.csv',
      [StringReplace(TrackName, ' ', '_', [rfReplaceAll]),
       StringReplace(CarName,   ' ', '_', [rfReplaceAll])]);
    SD.InitialDir := FSettings.LastExportFolder;

    if SD.Execute then
    begin
      FSettings.LastExportFolder := ExtractFilePath(SD.FileName);
      if TCSVExporter.ExportTelemetrySession(FDB, SessionID, SD.FileName) then
      begin
        SetStatus('Session exported to: ' + SD.FileName);
        if MessageDlg('Export successful. Open the file?',
                      mtInformation, [mbYes, mbNo], 0) = mrYes then
          ShellExecute(0, 'open', PChar(SD.FileName), nil, nil, SW_SHOWNORMAL);
      end
      else
        ShowMessage('Export failed.');
    end;
  finally
    SD.Free;
  end;
end;

procedure TMainForm.BtnAnalyzeAIClick(Sender: TObject);
var
  SessionID: Integer;
  APIKey, ModelName: string;
  TrackName, CarName, ClassName: string;
  CSVData, Response: string;
  Gemini: TGeminiAPI;
  SourceFile: string;
  TempCSVPath: string;
  ErrorText: string;
begin
  APIKey := FSettings.GeminiAPIKey;
  if Trim(APIKey) = '' then
  begin
    ShowMessage('No Gemini API key found. Please add your API key in the Settings tab.');
    PageControl.ActivePage := TabSettings;
    EdtAPIKey.SetFocus;
    Exit;
  end;

  SourceFile := SelectedSourceTelemetryFile;
  SessionID := SelectedSessionID;
  if (SourceFile = '') and (SessionID = -1) then
  begin
    ShowMessage('Please select a telemetry session or source file to analyse.');
    Exit;
  end;

  // Get CSV data
  MemoAIResponse.Lines.Clear;
  MemoAIResponse.Lines.Add('Preparing telemetry data...');
  Application.ProcessMessages;

  if SourceFile <> '' then
  begin
    TempCSVPath := TPath.Combine(TPath.GetTempPath,
      'LMUTrackHarvester_SourceTelemetry_' + FormatDateTime('yyyymmdd_hhnnsszzz', Now) + '.csv');
    if not TCSVExporter.ExportDuckDBSourceToCSV(SourceFile, TempCSVPath, ErrorText) then
    begin
      ShowMessage('Could not prepare source telemetry for analysis.' + sLineBreak + ErrorText);
      MemoAIResponse.Clear;
      Exit;
    end;

    try
      CSVData := TFile.ReadAllText(TempCSVPath, TEncoding.UTF8);
    finally
      if TFile.Exists(TempCSVPath) then
        TFile.Delete(TempCSVPath);
    end;

    if not TCSVExporter.ReadDuckDBMetadataValue(SourceFile, 'TrackName', TrackName, ErrorText) then
      TrackName := ChangeFileExt(ExtractFileName(SourceFile), '');
    if not TCSVExporter.ReadDuckDBMetadataValue(SourceFile, 'CarName', CarName, ErrorText) then
      CarName := 'LMU source telemetry';
    ClassName := 'LMU telemetry source';
  end
  else
  begin
    SelectedSessionInfo(TrackName, CarName, ClassName);
    CSVData := TCSVExporter.TelemetrySessionToCSV(FDB, SessionID);
  end;

  if Trim(CSVData) = '' then
  begin
    ShowMessage('No telemetry data found for this session.');
    MemoAIResponse.Clear;
    Exit;
  end;

  ModelName := FSettings.AIModel;
  if (CboAIModel.ItemIndex >= 0) then
    ModelName := CboAIModel.Items[CboAIModel.ItemIndex];

  MemoAIResponse.Lines.Clear;
  MemoAIResponse.Lines.Add('Sending telemetry to Gemini AI (' + ModelName + ')...');
  MemoAIResponse.Lines.Add('Please wait...');
  Application.ProcessMessages;

  Gemini := TGeminiAPI.Create(APIKey, ModelName);
  try
    SetStatus('Analysing telemetry with ' + ModelName + '...');
    Screen.Cursor := crHourGlass;
    try
      Response := Gemini.GetCoachingAdvice(CSVData, TrackName, CarName, ClassName);
    finally
      Screen.Cursor := crDefault;
    end;
  finally
    Gemini.Free;
  end;

  MemoAIResponse.Lines.Clear;
  MemoAIResponse.Lines.Text := Response;
  SetStatus('AI analysis complete.');
end;

procedure TMainForm.BtnClearAIClick(Sender: TObject);
begin
  MemoAIResponse.Clear;
end;

// ---------------------------------------------------------------------------
// Settings tab
// ---------------------------------------------------------------------------

procedure TMainForm.BtnShowKeyClick(Sender: TObject);
begin
  if EdtAPIKey.PasswordChar = '*' then
  begin
    EdtAPIKey.PasswordChar := #0;
    BtnShowKey.Caption := 'Hide';
  end
  else
  begin
    EdtAPIKey.PasswordChar := '*';
    BtnShowKey.Caption := 'Show';
  end;
end;

procedure TMainForm.BtnSaveSettingsClick(Sender: TObject);
begin
  FSettings.GeminiAPIKey := Trim(EdtAPIKey.Text);
  FSettings.TelemetrySourceFolder := Trim(EdtTelemetryFolder.Text);
  FSettings.ResultsSourceFolder := Trim(EdtResultsFolder.Text);
  FSettings.PreferredDriverName := Trim(EdtPreferredDriver.Text);

  if CboAIModel.ItemIndex >= 0 then
    FSettings.AIModel := CboAIModel.Items[CboAIModel.ItemIndex];

  FSettings.Save;
  RefreshTelemetrySourceInfo;
  RefreshResultsSourceInfo;
  ImportResultsFromConfiguredFolder(False);
  RefreshLapTimes;
  RefreshSessions;
  SetStatus('Settings saved.');
  ShowMessage('Settings saved successfully.');
end;

procedure TMainForm.BtnTestAPIClick(Sender: TObject);
var
  Key, Model: string;
  Gemini: TGeminiAPI;
  Response: string;
begin
  Key := Trim(EdtAPIKey.Text);
  if Key = '' then
  begin
    ShowMessage('Please enter an API key first.');
    EdtAPIKey.SetFocus;
    Exit;
  end;

  if CboAIModel.ItemIndex >= 0 then
    Model := CboAIModel.Items[CboAIModel.ItemIndex]
  else
    Model := 'gemini-1.5-flash';

  LblTestResult.Caption := 'Testing...';
  Screen.Cursor := crHourGlass;
  Application.ProcessMessages;

  Gemini := TGeminiAPI.Create(Key, Model);
  try
    Response := Gemini.SendPrompt(
      'You are a helpful assistant.',
      'Reply with exactly: "API connection successful."');
  finally
    Gemini.Free;
    Screen.Cursor := crDefault;
  end;

  if Pos('successful', LowerCase(Response)) > 0 then
  begin
    LblTestResult.Caption := '✓ Connected';
    LblTestResult.Font.Color := clGreen;
    ShowMessage('API connection test passed!' + #13#10 + Response);
  end
  else
  begin
    LblTestResult.Caption := '✗ Failed';
    LblTestResult.Font.Color := clRed;
    ShowMessage('API test returned unexpected response:' + #13#10 + Response);
  end;
end;

procedure TMainForm.LblGetKeyClick(Sender: TObject);
begin
  ShellExecute(0, 'open', 'https://aistudio.google.com/app/apikey', nil, nil, SW_SHOWNORMAL);
end;

procedure TMainForm.BtnBrowseTelemetryFolderClick(Sender: TObject);
var
  SelectedDir: string;
begin
  SelectedDir := Trim(EdtTelemetryFolder.Text);
  if SelectDirectory('Select LMU telemetry folder', '', SelectedDir) then
  begin
    EdtTelemetryFolder.Text := SelectedDir;
    FSettings.TelemetrySourceFolder := SelectedDir;
    FSettings.Save;
    RefreshTelemetrySourceInfo;
    RefreshSessions;
  end;
end;

procedure TMainForm.BtnRescanTelemetryClick(Sender: TObject);
begin
  RefreshTelemetrySourceInfo;
  RefreshSessions;
end;

procedure TMainForm.BtnBrowseResultsFolderClick(Sender: TObject);
var
  SelectedDir: string;
begin
  SelectedDir := Trim(EdtResultsFolder.Text);
  if SelectDirectory('Select LMU results folder', '', SelectedDir) then
  begin
    EdtResultsFolder.Text := SelectedDir;
    FSettings.ResultsSourceFolder := SelectedDir;
    FSettings.Save;
    RefreshResultsSourceInfo;
    ImportResultsFromConfiguredFolder(False);
    RefreshLapTimes;
  end;
end;

procedure TMainForm.BtnRescanResultsClick(Sender: TObject);
begin
  RefreshResultsSourceInfo;
  ImportResultsFromConfiguredFolder(True);
  RefreshLapTimes;
end;

procedure TMainForm.DescribeTelemetrySourceFile(const AFilePath: string; ALines: TStrings);
var
  FileSize: Int64;
  Header: TBytes;
  HeaderHex: string;
  I: Integer;
  Stream: TFileStream;
  Conn: TFDConnection;
  Q: TFDQuery;
  TrackName: string;
  CarName: string;
  DriverName: string;
  ErrorText: string;
begin
  if not TFile.Exists(AFilePath) then
  begin
    ALines.Add('File no longer exists.');
    Exit;
  end;

  if SameText(ExtractFileExt(AFilePath), '.duckdb') then
  begin
    ALines.Add('LMU telemetry source file selected:');
    ALines.Add('This is a DuckDB telemetry database, not the app''s SQLite database.');
    if TCSVExporter.ReadDuckDBMetadataValue(AFilePath, 'TrackName', TrackName, ErrorText) then
      ALines.Add('Track   : ' + TrackName);
    if TCSVExporter.ReadDuckDBMetadataValue(AFilePath, 'CarName', CarName, ErrorText) then
      ALines.Add('Car     : ' + CarName);
    if TCSVExporter.ReadDuckDBMetadataValue(AFilePath, 'DriverName', DriverName, ErrorText) then
      ALines.Add('Driver  : ' + DriverName);
    ALines.Add('The app can export this source straight to CSV and can send that CSV to Gemini for coaching.');
    Exit;
  end;

  FileSize := TFile.GetSize(AFilePath);
  ALines.Add(Format('Modified: %s', [DateTimeToStr(TFile.GetLastWriteTime(AFilePath))]));
  ALines.Add(Format('Size: %.2f MB', [FileSize / (1024 * 1024)]));

  SetLength(Header, 16);
  HeaderHex := '';
  Stream := TFileStream.Create(AFilePath, fmOpenRead or fmShareDenyNone);
  try
    I := Stream.Read(Header, Length(Header));
    SetLength(Header, I);
  finally
    Stream.Free;
  end;

  for I := 0 to High(Header) do
    HeaderHex := HeaderHex + IntToHex(Header[I], 2) + ' ';
  if HeaderHex <> '' then
    ALines.Add('Header bytes: ' + Trim(HeaderHex));

  if (Length(Header) >= 4) and
     (Header[0] = Ord('D')) and
     (Header[1] = Ord('U')) and
     (Header[2] = Ord('C')) and
     (Header[3] = Ord('K')) then
  begin
    ALines.Add('Detected file signature: DuckDB');
    ALines.Add('This is an LMU source telemetry database, not the app''s SQLite database.');
    ALines.Add('Use Export Telemetry CSV or Ask Gemini for Coaching on the selected source file.');
    Exit;
  end;

  Conn := TFDConnection.Create(nil);
  Q := TFDQuery.Create(nil);
  try
    Conn.DriverName := 'SQLite';
    Conn.LoginPrompt := False;
    Conn.Params.Add('Database=' + AFilePath);
    Conn.Params.Add('OpenMode=ReadOnly');
    Conn.Connected := True;

    Q.Connection := Conn;
    Q.SQL.Text := 'SELECT name FROM sqlite_master WHERE type = ''table'' ORDER BY name';
    Q.Open;
    if Q.Eof then
      ALines.Add('SQLite probe: opened, but no tables found.')
    else
    begin
      ALines.Add('SQLite probe: file opened. Tables:');
      while not Q.Eof do
      begin
        ALines.Add('  - ' + Q.Fields[0].AsString);
        Q.Next;
      end;
    end;
  except
    on E: Exception do
      ALines.Add('SQLite probe failed (likely DuckDB-only format): ' + E.Message);
  end;
end;

end.
