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
  System.SysUtils, System.Classes, System.IOUtils, System.Types, System.Math,
  System.UITypes,
  System.Generics.Collections,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls,
  Vcl.FileCtrl,
  Vcl.Graphics, Vcl.ImgList,
  Vcl.Themes,
  FireDAC.Comp.Client,
  DatabaseManager, LapTimeModels, AppSettings,
  CSVExporter, GeminiAPI,
  AddLapForm, ImportTelemetryForm, ResultsXMLImporter;

const
  WM_STARTUP_RESULTS_IMPORT = WM_APP + 1;
  WM_STARTUP_TELEMETRY_SCAN = WM_APP + 2;

type
  TSectorTelemetry = record
    Name: string;
    RangeText: string;
    TimeMs: Int64;
    AvgSpeedKmh: Double;
    MinSpeedKmh: Double;
    AvgThrottlePct: Double;
    PeakBrakePct: Double;
    CoastPct: Double;
    Valid: Boolean;
  end;

  TSectorTelemetryArray = array[0..2] of TSectorTelemetry;

  TTelemetrySourceSummary = record
    FilePath: string;
    FileTime: TDateTime;
    TrackName: string;
    CarName: string;
    DriverName: string;
  end;

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
    GrpSectorScorecard: TGroupBox;
    GrpTelemetryVisual: TGroupBox;
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
    FCarBadgeImages: TImageList;
    FCarBadgeIndex: TDictionary<string, Integer>;
    FSectorPanels: array[0..2] of TPanel;
    FSectorTitleLabels: array[0..2] of TLabel;
    FSectorRangeLabels: array[0..2] of TLabel;
    FSectorTimeLabels: array[0..2] of TLabel;
    FSectorMetricLabels1: array[0..2] of TLabel;
    FSectorMetricLabels2: array[0..2] of TLabel;
    FTelemetryMapBox: TPaintBox;
    FTelemetryChartBox: TPaintBox;
    FTelemetryVisualHint: TLabel;
    FTelemetryPreviewData: TTelemetryDataArray;
    FTelemetryLapData: TTelemetryDataArray;
    FTelemetryPreviewTrackName: string;
    FTelemetryPreviewCarName: string;
    FTelemetryPreviewClassName: string;
    FActiveSectorIndex: Integer;
    FHoverLapDistance: Double;
    FTelemetrySourceSummaries: TArray<TTelemetrySourceSummary>;
    FTelemetrySourceScanInProgress: Boolean;
    FResultsImportInProgress: Boolean;

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
    procedure StartAsyncTelemetrySourceScan(AShowStatus: Boolean);
    procedure StartAsyncResultsImport(AForceRebuild, AShowStatus: Boolean);
    procedure DescribeTelemetrySourceFile(const AFilePath: string; ALines: TStrings);
    procedure InitializeCarBadges;
    procedure InitializeSectorScorecard;
    procedure ResetSectorScorecard;
    procedure UpdateSectorScorecard;
    procedure InitializeTelemetryVisuals;
    procedure RefreshTelemetryVisuals;
    procedure ConfigureStripedListView(ALV: TListView);
    procedure SectorPanelClick(Sender: TObject);
    procedure ListViewAdvancedCustomDrawItem(Sender: TCustomListView;
      Item: TListItem; State: TCustomDrawState; Stage: TCustomDrawStage;
      var DefaultDraw: Boolean);
    procedure TelemetryMapPaint(Sender: TObject);
    procedure TelemetryChartPaint(Sender: TObject);
    procedure TelemetryChartMouseMove(Sender: TObject; Shift: TShiftState; X,
      Y: Integer);
    procedure TelemetryChartMouseLeave(Sender: TObject);

    function LoadTelemetryDataForSelection(out AData: TTelemetryDataArray;
      out ATrackName, ACarName, AClassName: string): Boolean;
    function ParseTelemetryCSV(const ACSVData: string): TTelemetryDataArray;
    function ExtractRepresentativeLap(const AData: TTelemetryDataArray): TTelemetryDataArray;
    function BuildSectorTelemetry(const AData: TTelemetryDataArray): TSectorTelemetryArray;
    function FormatDurationMs(ADurationMs: Int64): string;
    function GetCarBadgeImageIndex(const ACarName: string): Integer;
    function DisplaySessionType(const ASessionType: string): string;
    function ReadDuckDBMetadataFallback(const AFilePath: string;
      const AKeys: array of string): string;
    procedure WMStartupTelemetryScan(var Msg: TMessage); message WM_STARTUP_TELEMETRY_SCAN;
    procedure WMStartupResultsImport(var Msg: TMessage); message WM_STARTUP_RESULTS_IMPORT;
  end;

var
  FrmMain: TMainForm;

implementation

{$R *.dfm}

// ---------------------------------------------------------------------------
// Form lifecycle
// ---------------------------------------------------------------------------

procedure TMainForm.FormCreate(Sender: TObject);
var
  ModelIdx: Integer;
begin
  FSettings := TAppSettings.Create;
  FDB       := TDatabaseManager.Create;
  FCarBadgeIndex := TDictionary<string, Integer>.Create;
  FCarBadgeImages := TImageList.Create(Self);
  InitializeCarBadges;
  InitializeSectorScorecard;
  InitializeTelemetryVisuals;
  ConfigureStripedListView(LvwTop10);
  ConfigureStripedListView(LvwFastest);
  ConfigureStripedListView(LvwSessions);

  FActiveSectorIndex := -1;
  FHoverLapDistance := -1;
  FTelemetrySourceScanInProgress := False;
  FResultsImportInProgress := False;

  ApplyRacingTheme;

  LoadTrackCombo;
  LoadClassCombo;
  RefreshLapTimes;
  RefreshSessions;

  EdtAPIKey.Text := FSettings.GeminiAPIKey;
  ModelIdx := CboAIModel.Items.IndexOf(FSettings.AIModel);
  if ModelIdx >= 0 then
    CboAIModel.ItemIndex := ModelIdx
  else
    CboAIModel.ItemIndex := 0;

  SetStatus('Database loaded from: ' + FDB.DatabasePath);

  if FSettings.WindowMaximized then
    WindowState := wsMaximized;

  PnlTelLeft.Width := EnsureRange(Round(ClientWidth * 0.39), 400, 460);

  EdtTelemetryFolder.Text := FSettings.TelemetrySourceFolder;
  EdtResultsFolder.Text := FSettings.ResultsSourceFolder;
  EdtPreferredDriver.Text := FSettings.PreferredDriverName;
  RefreshTelemetrySourceInfo;
  RefreshResultsSourceInfo;
  PostMessage(Handle, WM_STARTUP_TELEMETRY_SCAN, 0, 0);
  PostMessage(Handle, WM_STARTUP_RESULTS_IMPORT, 0, 0);
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
  FCarBadgeIndex.Free;
  FSettings.Free;
  FDB.Free;
end;

procedure TMainForm.SetStatus(const AMsg: string);
begin
  StatusBar.Panels[0].Text := AMsg;
end;

procedure TMainForm.WMStartupResultsImport(var Msg: TMessage);
begin
  StartAsyncResultsImport(False, False);
end;

procedure TMainForm.WMStartupTelemetryScan(var Msg: TMessage);
begin
  StartAsyncTelemetrySourceScan(False);
end;

procedure TMainForm.ApplyRacingTheme;
begin
  Caption := 'LMU Track Harvester - Driver Performance Hub';
  Font.Name := 'Bahnschrift';
  Font.Height := -15;

  Color := RGB(255, 244, 230);

  BtnAddLap.Caption := '+ Log Lap';
  BtnDeleteLap.Caption := 'Delete Lap';
  BtnExportLaps.Caption := 'Export Pace';
  BtnExportCSV.Caption := 'Export Telemetry CSV';
  BtnAnalyzeAI.Caption := 'Ask Gemini for Coaching';
  BtnImportTel.Caption := 'Import Telemetry CSV';
  BtnDeleteSession.Caption := 'Delete Saved Session';
  BtnRescanResults.Caption := 'Rescan / Rebuild Results';

  LblSettingsTitle.Caption := 'Driver and AI Control Centre';
  LblSessions.Caption := 'Telemetry Garage';
  GrpTop10.Caption := ' Driver Top 10 Pace ';
  GrpFastest.Caption := ' Fastest Personal Time Per Car ';

  BtnAddLap.Font.Style := [fsBold];
  BtnDeleteLap.Font.Style := [fsBold];
  BtnExportLaps.Font.Style := [fsBold];
  BtnExportCSV.Font.Style := [fsBold];
  BtnAnalyzeAI.Font.Style := [fsBold];
  BtnImportTel.Font.Style := [fsBold];
  BtnSaveSettings.Font.Style := [fsBold];
  BtnAddLap.Font.Height := -15;
  BtnDeleteLap.Font.Height := -15;
  BtnExportLaps.Font.Height := -15;
  BtnExportCSV.Font.Height := -15;
  BtnAnalyzeAI.Font.Height := -15;
  BtnImportTel.Font.Height := -15;
  BtnDeleteSession.Font.Height := -15;
  BtnSaveSettings.Font.Height := -15;

  CboTrack.Font.Height := -15;
  CboClass.Font.Height := -15;
  CboAIModel.Font.Height := -15;
  EdtAPIKey.Font.Height := -15;
  EdtTelemetryFolder.Font.Height := -15;
  EdtResultsFolder.Font.Height := -15;
  EdtPreferredDriver.Font.Height := -15;

  LvwTop10.HideSelection := False;
  LvwFastest.HideSelection := False;
  LvwTop10.SmallImages := FCarBadgeImages;
  LvwFastest.SmallImages := FCarBadgeImages;
  MemoSessionInfo.Font.Name := 'Bahnschrift';
  MemoAIResponse.Font.Name := 'Bahnschrift';
  MemoSessionInfo.Font.Height := -15;
  MemoAIResponse.Font.Height := -15;

  if TStyleManager.IsCustomStyleActive then
  begin
    PnlLTTop.ParentBackground := True;
    PnlLTContent.ParentBackground := True;
    GrpTop10.ParentBackground := True;
    GrpFastest.ParentBackground := True;
    PnlTelLeft.ParentBackground := True;
    PnlTelRight.ParentBackground := True;
    GrpSessionInfo.ParentBackground := True;
    GrpSectorScorecard.ParentBackground := True;
    GrpTelemetryVisual.ParentBackground := True;
    GrpAIResponse.ParentBackground := True;
    PnlTelActions.ParentBackground := True;
    PnlSettings.ParentBackground := True;
    Exit;
  end;

  PnlLTTop.ParentBackground := False;
  PnlLTTop.Color := RGB(255, 229, 201);
  PnlLTContent.ParentBackground := False;
  PnlLTContent.Color := RGB(255, 247, 237);
  LblTrack.Font.Color := RGB(111, 50, 13);
  LblClass.Font.Color := RGB(111, 50, 13);
  LblTrack.Font.Height := -15;
  LblClass.Font.Height := -15;

  GrpTop10.ParentBackground := False;
  GrpFastest.ParentBackground := False;
  GrpTop10.Color := RGB(255, 239, 221);
  GrpFastest.Color := RGB(255, 239, 221);
  GrpTop10.Font.Style := [fsBold];
  GrpFastest.Font.Style := [fsBold];
  GrpTop10.Font.Color := RGB(111, 50, 13);
  GrpFastest.Font.Color := RGB(111, 50, 13);
  GrpTop10.Font.Height := -15;
  GrpFastest.Font.Height := -15;
  LvwTop10.Color := RGB(255, 255, 252);
  LvwFastest.Color := RGB(255, 255, 252);
  LvwTop10.Font.Color := RGB(61, 45, 31);
  LvwFastest.Font.Color := RGB(61, 45, 31);
  LvwTop10.Font.Height := -16;
  LvwFastest.Font.Height := -16;

  LblSessions.Color := RGB(226, 103, 28);
  LblSessions.Font.Color := clWhite;
  LblSessions.Font.Height := -15;
  PnlTelLeft.ParentBackground := False;
  PnlTelLeft.Color := RGB(255, 244, 230);
  PnlTelRight.ParentBackground := False;
  PnlTelRight.Color := RGB(255, 244, 230);
  LvwSessions.Color := RGB(255, 255, 252);
  LvwSessions.Font.Color := RGB(61, 45, 31);
  LvwSessions.Font.Height := -16;
  GrpSessionInfo.ParentBackground := False;
  GrpSectorScorecard.ParentBackground := False;
  GrpTelemetryVisual.ParentBackground := False;
  GrpAIResponse.ParentBackground := False;
  GrpSessionInfo.Color := RGB(255, 239, 221);
  GrpSectorScorecard.Color := RGB(255, 239, 221);
  GrpTelemetryVisual.Color := RGB(255, 239, 221);
  GrpAIResponse.Color := RGB(255, 239, 221);
  GrpSessionInfo.Font.Style := [fsBold];
  GrpSectorScorecard.Font.Style := [fsBold];
  GrpTelemetryVisual.Font.Style := [fsBold];
  GrpAIResponse.Font.Style := [fsBold];
  GrpSessionInfo.Font.Color := RGB(111, 50, 13);
  GrpSectorScorecard.Font.Color := RGB(111, 50, 13);
  GrpTelemetryVisual.Font.Color := RGB(111, 50, 13);
  GrpAIResponse.Font.Color := RGB(111, 50, 13);
  GrpSessionInfo.Font.Height := -15;
  GrpSectorScorecard.Font.Height := -15;
  GrpTelemetryVisual.Font.Height := -15;
  GrpAIResponse.Font.Height := -15;
  PnlTelActions.ParentBackground := False;
  PnlTelActions.Color := RGB(255, 244, 230);
  MemoSessionInfo.Color := RGB(255, 252, 247);
  MemoAIResponse.Color := RGB(255, 252, 247);
  MemoSessionInfo.Font.Color := RGB(61, 45, 31);
  MemoAIResponse.Font.Color := RGB(61, 45, 31);

  PnlSettings.ParentBackground := False;
  PnlSettings.Color := RGB(255, 239, 221);
  LblSettingsTitle.Font.Color := RGB(111, 50, 13);
  LblAPIKey.Font.Color := RGB(111, 50, 13);
  LblAPIKeyInfo.Font.Color := RGB(157, 88, 45);
  LblModel.Font.Color := RGB(111, 50, 13);
  LblTelemetrySource.Font.Color := RGB(111, 50, 13);
  LblTelemetrySourceInfo.Font.Color := RGB(157, 88, 45);
  LblResultsSource.Font.Color := RGB(111, 50, 13);
  LblResultsSourceInfo.Font.Color := RGB(157, 88, 45);
  LblPreferredDriver.Font.Color := RGB(111, 50, 13);
  LblPreferredDriverInfo.Font.Color := RGB(157, 88, 45);
  LblTestResult.Font.Color := RGB(157, 88, 45);
  LblSep1.Color := RGB(226, 103, 28);
end;

procedure TMainForm.InitializeSectorScorecard;
const
  SectorNames: array[0..2] of string = ('Sector 1', 'Sector 2', 'Sector 3');
  SectorRanges: array[0..2] of string = ('0% - 33%', '33% - 67%', '67% - 100%');
  SectorAccents: array[0..2] of TColor = ($002F79D8, $001A936F, $001576B5);
var
  I: Integer;
  PanelWidth: Integer;
begin
  PanelWidth := 230;
  for I := 0 to 2 do
  begin
    FSectorPanels[I] := TPanel.Create(GrpSectorScorecard);
    FSectorPanels[I].Parent := GrpSectorScorecard;
    FSectorPanels[I].Tag := I;
    FSectorPanels[I].Cursor := crHandPoint;
    FSectorPanels[I].OnClick := SectorPanelClick;
    if I < 2 then
    begin
      FSectorPanels[I].Align := alLeft;
      FSectorPanels[I].Width := PanelWidth;
    end
    else
      FSectorPanels[I].Align := alClient;
    FSectorPanels[I].BevelOuter := bvNone;
    FSectorPanels[I].ParentBackground := False;
    FSectorPanels[I].BorderWidth := 1;
    FSectorPanels[I].Padding.Left := 10;
    FSectorPanels[I].Padding.Top := 10;
    FSectorPanels[I].Padding.Right := 10;
    FSectorPanels[I].Padding.Bottom := 8;

    FSectorTitleLabels[I] := TLabel.Create(FSectorPanels[I]);
    FSectorTitleLabels[I].Parent := FSectorPanels[I];
    FSectorTitleLabels[I].Left := 10;
    FSectorTitleLabels[I].Top := 8;
    FSectorTitleLabels[I].Width := PanelWidth - 18;
    FSectorTitleLabels[I].Height := 24;
    FSectorTitleLabels[I].AutoSize := False;
    FSectorTitleLabels[I].Transparent := False;
    FSectorTitleLabels[I].Color := SectorAccents[I];
    FSectorTitleLabels[I].Alignment := taCenter;
    FSectorTitleLabels[I].Layout := tlCenter;
    FSectorTitleLabels[I].Font.Name := 'Bahnschrift';
    FSectorTitleLabels[I].Font.Style := [fsBold];
    FSectorTitleLabels[I].Font.Color := clWhite;
    FSectorTitleLabels[I].Font.Height := -14;
    FSectorTitleLabels[I].Caption := SectorNames[I];
    FSectorTitleLabels[I].Tag := I;
    FSectorTitleLabels[I].Cursor := crHandPoint;
    FSectorTitleLabels[I].OnClick := SectorPanelClick;
    FSectorTitleLabels[I].Anchors := [akLeft, akTop, akRight];

    FSectorRangeLabels[I] := TLabel.Create(FSectorPanels[I]);
    FSectorRangeLabels[I].Parent := FSectorPanels[I];
    FSectorRangeLabels[I].Left := 10;
    FSectorRangeLabels[I].Top := 40;
    FSectorRangeLabels[I].Font.Name := 'Bahnschrift';
    FSectorRangeLabels[I].Font.Height := -13;
    FSectorRangeLabels[I].Caption := SectorRanges[I];
    FSectorRangeLabels[I].Tag := I;
    FSectorRangeLabels[I].Cursor := crHandPoint;
    FSectorRangeLabels[I].OnClick := SectorPanelClick;

    FSectorTimeLabels[I] := TLabel.Create(FSectorPanels[I]);
    FSectorTimeLabels[I].Parent := FSectorPanels[I];
    FSectorTimeLabels[I].Left := 10;
    FSectorTimeLabels[I].Top := 62;
    FSectorTimeLabels[I].Font.Name := 'Bahnschrift';
    FSectorTimeLabels[I].Font.Style := [fsBold];
    FSectorTimeLabels[I].Font.Height := -26;
    FSectorTimeLabels[I].Caption := '--.--s';
    FSectorTimeLabels[I].Tag := I;
    FSectorTimeLabels[I].Cursor := crHandPoint;
    FSectorTimeLabels[I].OnClick := SectorPanelClick;

    FSectorMetricLabels1[I] := TLabel.Create(FSectorPanels[I]);
    FSectorMetricLabels1[I].Parent := FSectorPanels[I];
    FSectorMetricLabels1[I].Left := 10;
    FSectorMetricLabels1[I].Top := 100;
    FSectorMetricLabels1[I].Font.Name := 'Bahnschrift';
    FSectorMetricLabels1[I].Font.Height := -12;
    FSectorMetricLabels1[I].Caption := 'Avg -- km/h | Min --';
    FSectorMetricLabels1[I].Tag := I;
    FSectorMetricLabels1[I].Cursor := crHandPoint;
    FSectorMetricLabels1[I].OnClick := SectorPanelClick;

    FSectorMetricLabels2[I] := TLabel.Create(FSectorPanels[I]);
    FSectorMetricLabels2[I].Parent := FSectorPanels[I];
    FSectorMetricLabels2[I].Left := 10;
    FSectorMetricLabels2[I].Top := 118;
    FSectorMetricLabels2[I].Font.Name := 'Bahnschrift';
    FSectorMetricLabels2[I].Font.Height := -12;
    FSectorMetricLabels2[I].Caption := 'Throttle -- | Brake -- | Coast --';
    FSectorMetricLabels2[I].Tag := I;
    FSectorMetricLabels2[I].Cursor := crHandPoint;
    FSectorMetricLabels2[I].OnClick := SectorPanelClick;
  end;

  ResetSectorScorecard;
end;

procedure TMainForm.InitializeTelemetryVisuals;
begin
  if GrpTelemetryVisual = nil then
  begin
    GrpTelemetryVisual := TGroupBox.Create(PnlTelRight);
    GrpTelemetryVisual.Parent := PnlTelRight;
    GrpTelemetryVisual.Align := alTop;
    GrpTelemetryVisual.Height := 190;
    GrpTelemetryVisual.Caption := ' Visual Analysis ';
  end;

  FTelemetryVisualHint := TLabel.Create(GrpTelemetryVisual);
  FTelemetryVisualHint.Parent := GrpTelemetryVisual;
  FTelemetryVisualHint.Align := alTop;
  FTelemetryVisualHint.Height := 24;
  FTelemetryVisualHint.AutoSize := False;
  FTelemetryVisualHint.Layout := tlCenter;
  FTelemetryVisualHint.Caption := 'Click a sector card to focus the map and telemetry trace.';
  FTelemetryVisualHint.Font.Name := 'Bahnschrift';
  FTelemetryVisualHint.Font.Height := -13;

  FTelemetryMapBox := TPaintBox.Create(GrpTelemetryVisual);
  FTelemetryMapBox.Parent := GrpTelemetryVisual;
  FTelemetryMapBox.Align := alLeft;
  FTelemetryMapBox.Width := 176;
  FTelemetryMapBox.OnPaint := TelemetryMapPaint;

  FTelemetryChartBox := TPaintBox.Create(GrpTelemetryVisual);
  FTelemetryChartBox.Parent := GrpTelemetryVisual;
  FTelemetryChartBox.Align := alClient;
  FTelemetryChartBox.OnPaint := TelemetryChartPaint;
  FTelemetryChartBox.OnMouseMove := TelemetryChartMouseMove;
  FTelemetryChartBox.OnMouseLeave := TelemetryChartMouseLeave;
end;

procedure TMainForm.ResetSectorScorecard;
var
  I: Integer;
begin
  GrpSectorScorecard.Caption := ' Sector Scorecard ';
  for I := 0 to 2 do
  begin
    FSectorPanels[I].Color := RGB(255, 252, 247);
    FSectorPanels[I].BevelOuter := bvLowered;
    FSectorTitleLabels[I].Font.Color := clWhite;
    FSectorRangeLabels[I].Font.Color := RGB(165, 108, 68);
    FSectorTimeLabels[I].Font.Color := RGB(71, 48, 33);
    FSectorMetricLabels1[I].Font.Color := RGB(94, 72, 56);
    FSectorMetricLabels2[I].Font.Color := RGB(94, 72, 56);
    FSectorTimeLabels[I].Caption := '--.--s';
    FSectorMetricLabels1[I].Caption := 'Avg -- km/h | Min --';
    FSectorMetricLabels2[I].Caption := 'Throttle -- | Brake -- | Coast --';
  end;
  FActiveSectorIndex := -1;
  FHoverLapDistance := -1;
  SetLength(FTelemetryPreviewData, 0);
  SetLength(FTelemetryLapData, 0);
  RefreshTelemetryVisuals;
end;

function TMainForm.ParseTelemetryCSV(const ACSVData: string): TTelemetryDataArray;
var
  Lines: TStringList;
  I, Count: Integer;
  Parts: TArray<string>;
  HeaderParts: TArray<string>;
  FS: TFormatSettings;
  LatitudeIndex: Integer;
  LongitudeIndex: Integer;

  function FindHeaderIndex(const ACandidates: array of string): Integer;
  var
    HeaderIndex: Integer;
    Candidate: string;
  begin
    Result := -1;
    for HeaderIndex := 0 to High(HeaderParts) do
      for Candidate in ACandidates do
        if SameText(Trim(HeaderParts[HeaderIndex]), Candidate) then
          Exit(HeaderIndex);
  end;
begin
  SetLength(Result, 0);
  Lines := TStringList.Create;
  try
    Lines.Text := ACSVData;
    FS := TFormatSettings.Invariant;
    if Lines.Count > 0 then
      HeaderParts := Lines[0].Split([','])
    else
      HeaderParts := nil;

    LatitudeIndex := FindHeaderIndex(['GPS_Latitude_deg', 'GPS Latitude']);
    LongitudeIndex := FindHeaderIndex(['GPS_Longitude_deg', 'GPS Longitude']);

    Count := 0;
    SetLength(Result, Max(Lines.Count - 1, 0));
    for I := 1 to Lines.Count - 1 do
    begin
      if Trim(Lines[I]) = '' then
        Continue;
      Parts := Lines[I].Split([',']);
      if Length(Parts) < 8 then
        Continue;

      Result[Count].TimestampMs := StrToInt64Def(Trim(Parts[0]), 0);
      Result[Count].Speed := StrToFloatDef(Trim(Parts[1]), 0, FS);
      Result[Count].RPM := StrToFloatDef(Trim(Parts[2]), 0, FS);
      Result[Count].Gear := StrToIntDef(Trim(Parts[3]), 0);
      Result[Count].Throttle := StrToFloatDef(Trim(Parts[4]), 0, FS) / 100.0;
      Result[Count].Brake := StrToFloatDef(Trim(Parts[5]), 0, FS) / 100.0;
      Result[Count].Steering := StrToFloatDef(Trim(Parts[6]), 0, FS) / 100.0;
      Result[Count].LapDistance := StrToFloatDef(Trim(Parts[7]), 0, FS);
      Result[Count].GPSLatitude := NaN;
      Result[Count].GPSLongitude := NaN;
      if (LatitudeIndex >= 0) and (LatitudeIndex < Length(Parts)) then
        Result[Count].GPSLatitude := StrToFloatDef(Trim(Parts[LatitudeIndex]), NaN, FS);
      if (LongitudeIndex >= 0) and (LongitudeIndex < Length(Parts)) then
        Result[Count].GPSLongitude := StrToFloatDef(Trim(Parts[LongitudeIndex]), NaN, FS);
      Inc(Count);
    end;
    SetLength(Result, Count);
  finally
    Lines.Free;
  end;
end;

function TMainForm.LoadTelemetryDataForSelection(out AData: TTelemetryDataArray;
  out ATrackName, ACarName, AClassName: string): Boolean;
var
  SessionID: Integer;
  SourceFile: string;
  SourceIndex: Integer;
  TempCSVPath: string;
  CSVData: string;
  ErrorText: string;
begin
  Result := False;
  SetLength(AData, 0);
  ATrackName := '';
  ACarName := '';
  AClassName := '';

  SourceFile := SelectedSourceTelemetryFile;
  SessionID := SelectedSessionID;

  if SourceFile <> '' then
  begin
    SourceIndex := -1;
    if LvwSessions.Selected <> nil then
      SourceIndex := LvwSessions.Selected.Index - Length(FSessions);

    if (SourceIndex >= 0) and (SourceIndex <= High(FTelemetrySourceSummaries)) then
    begin
      ATrackName := FTelemetrySourceSummaries[SourceIndex].TrackName;
      ACarName := FTelemetrySourceSummaries[SourceIndex].CarName;
    end;

    TempCSVPath := TPath.Combine(TPath.GetTempPath,
      'LMUTrackHarvester_SectorPreview_' + FormatDateTime('yyyymmdd_hhnnsszzz', Now) + '.csv');
    if not TCSVExporter.ExportDuckDBSourceToCSV(SourceFile, TempCSVPath, ErrorText) then
      Exit(False);
    try
      CSVData := TFile.ReadAllText(TempCSVPath, TEncoding.UTF8);
      AData := ParseTelemetryCSV(CSVData);
    finally
      if TFile.Exists(TempCSVPath) then
        TFile.Delete(TempCSVPath);
    end;

    if (ATrackName = '') and (not TCSVExporter.ReadDuckDBMetadataValue(SourceFile, 'TrackName', ATrackName, ErrorText)) then
      ATrackName := ChangeFileExt(ExtractFileName(SourceFile), '');
    if ACarName = '' then
      ACarName := ReadDuckDBMetadataFallback(SourceFile,
        ['CarType', 'VehicleName', 'VehName', 'CarModel', 'CarName']);
    if ACarName = '' then
      ACarName := 'LMU source telemetry';
    AClassName := 'LMU telemetry source';
  end
  else if SessionID <> -1 then
  begin
    AData := FDB.GetTelemetryData(SessionID);
    SelectedSessionInfo(ATrackName, ACarName, AClassName);
  end;

  Result := Length(AData) > 0;
end;

function TMainForm.ExtractRepresentativeLap(const AData: TTelemetryDataArray): TTelemetryDataArray;
var
  StartIdx, EndIdx, ScanIdx: Integer;
  CandidateStart, I: Integer;
  BestDuration, DurationMs: Int64;
  MinDistance, MaxDistance: Double;
begin
  SetLength(Result, 0);
  if Length(AData) = 0 then
    Exit;

  StartIdx := 0;
  EndIdx := High(AData);
  BestDuration := High(Int64);

  CandidateStart := 0;
  for I := 1 to High(AData) do
  begin
    if (AData[I - 1].LapDistance > 0.85) and (AData[I].LapDistance < 0.15) and
       ((I - CandidateStart) > 25) then
    begin
      MinDistance := 1.0;
      MaxDistance := 0.0;
      for ScanIdx := CandidateStart to I - 1 do
      begin
        MinDistance := Min(MinDistance, AData[ScanIdx].LapDistance);
        MaxDistance := Max(MaxDistance, AData[ScanIdx].LapDistance);
      end;
      DurationMs := AData[I - 1].TimestampMs - AData[CandidateStart].TimestampMs;
      if (MinDistance <= 0.05) and (MaxDistance >= 0.95) and (DurationMs > 0) and
         (DurationMs < BestDuration) then
      begin
        BestDuration := DurationMs;
        StartIdx := CandidateStart;
        EndIdx := I - 1;
      end;
      CandidateStart := I;
    end;
  end;

  if BestDuration = High(Int64) then
  begin
    MinDistance := 1.0;
    MaxDistance := 0.0;
    for I := 0 to High(AData) do
    begin
      MinDistance := Min(MinDistance, AData[I].LapDistance);
      MaxDistance := Max(MaxDistance, AData[I].LapDistance);
    end;
    if (MinDistance <= 0.05) and (MaxDistance >= 0.95) then
    begin
      StartIdx := 0;
      EndIdx := High(AData);
    end
    else
      Exit;
  end;

  SetLength(Result, EndIdx - StartIdx + 1);
  for I := StartIdx to EndIdx do
    Result[I - StartIdx] := AData[I];
end;

function TMainForm.BuildSectorTelemetry(const AData: TTelemetryDataArray): TSectorTelemetryArray;
const
  SectorNames: array[0..2] of string = ('Sector 1', 'Sector 2', 'Sector 3');
  SectorRanges: array[0..2] of string = ('Opening phase', 'Middle phase', 'Final phase');
  SectorStart: array[0..2] of Double = (0.0, 0.3333, 0.6666);
  SectorEnd: array[0..2] of Double = (0.3333, 0.6666, 1.0001);
var
  LapData: TTelemetryDataArray;
  I, SectorIndex, SampleCount, CoastCount: Integer;
  FirstTS, LastTS: Int64;
  LapDistance: Double;
  SumSpeed, SumThrottle, PeakBrake, MinSpeed: Double;
begin
  for SectorIndex := 0 to 2 do
  begin
    Result[SectorIndex].Name := SectorNames[SectorIndex];
    Result[SectorIndex].RangeText := SectorRanges[SectorIndex];
    Result[SectorIndex].Valid := False;
  end;

  if Length(AData) = 0 then
    Exit;

  LapData := ExtractRepresentativeLap(AData);
  if Length(LapData) = 0 then
    Exit;

  for SectorIndex := 0 to 2 do
  begin
    FirstTS := -1;
    LastTS := -1;
    SumSpeed := 0;
    SumThrottle := 0;
    PeakBrake := 0;
    MinSpeed := 1.0E12;
    SampleCount := 0;
    CoastCount := 0;

    for I := 0 to High(LapData) do
    begin
      LapDistance := LapData[I].LapDistance;
      if (LapDistance < SectorStart[SectorIndex]) or (LapDistance >= SectorEnd[SectorIndex]) then
        Continue;

      if FirstTS < 0 then
        FirstTS := LapData[I].TimestampMs;
      LastTS := LapData[I].TimestampMs;
      SumSpeed := SumSpeed + LapData[I].Speed;
      SumThrottle := SumThrottle + (LapData[I].Throttle * 100.0);
      PeakBrake := Max(PeakBrake, LapData[I].Brake * 100.0);
      MinSpeed := Min(MinSpeed, LapData[I].Speed);
      if (LapData[I].Throttle < 0.05) and (LapData[I].Brake < 0.05) then
        Inc(CoastCount);
      Inc(SampleCount);
    end;

    if SampleCount > 0 then
    begin
      Result[SectorIndex].Valid := True;
      Result[SectorIndex].TimeMs := Max(LastTS - FirstTS, 0);
      Result[SectorIndex].AvgSpeedKmh := SumSpeed / SampleCount;
      Result[SectorIndex].MinSpeedKmh := MinSpeed;
      Result[SectorIndex].AvgThrottlePct := SumThrottle / SampleCount;
      Result[SectorIndex].PeakBrakePct := PeakBrake;
      Result[SectorIndex].CoastPct := (CoastCount / SampleCount) * 100.0;
    end;
  end;
end;

procedure TMainForm.UpdateSectorScorecard;
var
  Data: TTelemetryDataArray;
  Sectors: TSectorTelemetryArray;
  TrackName: string;
  CarName: string;
  ClassName: string;
  I: Integer;
begin
  if not LoadTelemetryDataForSelection(Data, TrackName, CarName, ClassName) then
  begin
    ResetSectorScorecard;
    Exit;
  end;

  FTelemetryPreviewData := Data;
  FTelemetryLapData := ExtractRepresentativeLap(Data);
  FTelemetryPreviewTrackName := TrackName;
  FTelemetryPreviewCarName := CarName;
  FTelemetryPreviewClassName := ClassName;
  if (FActiveSectorIndex < 0) or (FActiveSectorIndex > 2) then
    FActiveSectorIndex := -1;
  FHoverLapDistance := -1;

  Sectors := BuildSectorTelemetry(Data);
  GrpSectorScorecard.Caption := ' Sector Scorecard - ' + TrackName + ' ' + CarName + ' ';

  for I := 0 to 2 do
  begin
    if not Sectors[I].Valid then
    begin
      FSectorPanels[I].Color := RGB(255, 252, 247);
      FSectorTimeLabels[I].Caption := '--.--s';
      FSectorMetricLabels1[I].Caption := 'Avg -- km/h | Min --';
      FSectorMetricLabels2[I].Caption := 'Throttle -- | Brake -- | Coast --';
      Continue;
    end;

    if Sectors[I].CoastPct <= 8.0 then
    begin
      FSectorPanels[I].Color := RGB(247, 253, 244);
      FSectorTitleLabels[I].Color := RGB(26, 147, 111);
      FSectorTimeLabels[I].Font.Color := RGB(21, 88, 67);
    end
    else if Sectors[I].CoastPct <= 15.0 then
    begin
      FSectorPanels[I].Color := RGB(255, 249, 239);
      FSectorTitleLabels[I].Color := RGB(214, 140, 54);
      FSectorTimeLabels[I].Font.Color := RGB(141, 87, 12);
    end
    else
    begin
      FSectorPanels[I].Color := RGB(255, 244, 240);
      FSectorTitleLabels[I].Color := RGB(191, 87, 67);
      FSectorTimeLabels[I].Font.Color := RGB(140, 56, 42);
    end;

    FSectorTitleLabels[I].Caption := Sectors[I].Name;
    FSectorRangeLabels[I].Caption := Sectors[I].RangeText;
    FSectorTimeLabels[I].Caption := Format('%.2fs', [Sectors[I].TimeMs / 1000.0]);
    FSectorMetricLabels1[I].Caption := Format('Avg %.0f km/h | Min %.0f',
      [Sectors[I].AvgSpeedKmh, Sectors[I].MinSpeedKmh]);
    FSectorMetricLabels2[I].Caption := Format('Throttle %.0f%% | Brake %.0f%% | Coast %.0f%%',
      [Sectors[I].AvgThrottlePct, Sectors[I].PeakBrakePct, Sectors[I].CoastPct]);
  end;

  RefreshTelemetryVisuals;
end;

procedure TMainForm.RefreshTelemetryVisuals;
const
  SectorNames: array[0..2] of string = ('Sector 1', 'Sector 2', 'Sector 3');
var
  I: Integer;
begin
  for I := 0 to 2 do
  begin
    FSectorPanels[I].BevelOuter := bvLowered;
    FSectorPanels[I].BevelWidth := 1;
    FSectorTitleLabels[I].Font.Style := [fsBold];
    if (Length(FTelemetryLapData) > 0) and (FActiveSectorIndex = I) then
    begin
      FSectorPanels[I].BevelOuter := bvRaised;
      FSectorTitleLabels[I].Font.Style := [fsBold, fsUnderline];
    end;
  end;

  if Assigned(FTelemetryVisualHint) then
  begin
    if Length(FTelemetryLapData) = 0 then
      FTelemetryVisualHint.Caption := 'Select a saved session or LMU source file to render the map and telemetry trace.'
    else if FActiveSectorIndex >= 0 then
      FTelemetryVisualHint.Caption := Format('%s focus. Hover the trace to inspect matching track position.',
        [SectorNames[FActiveSectorIndex]])
    else
      FTelemetryVisualHint.Caption := 'Full-lap view. Click a sector card to isolate one part of the lap.';
  end;

  if Assigned(FTelemetryMapBox) then
    FTelemetryMapBox.Invalidate;
  if Assigned(FTelemetryChartBox) then
    FTelemetryChartBox.Invalidate;
end;

procedure TMainForm.SectorPanelClick(Sender: TObject);
var
  ClickedSector: Integer;
begin
  if not (Sender is TControl) then
    Exit;
  if Length(FTelemetryLapData) = 0 then
    Exit;

  ClickedSector := TControl(Sender).Tag;
  if (ClickedSector < 0) or (ClickedSector > 2) then
    Exit;

  if FActiveSectorIndex = ClickedSector then
    FActiveSectorIndex := -1
  else
    FActiveSectorIndex := ClickedSector;
  RefreshTelemetryVisuals;
end;

procedure TMainForm.TelemetryMapPaint(Sender: TObject);
const
  SectorStart: array[0..2] of Double = (0.0, 0.3333, 0.6666);
  SectorEnd: array[0..2] of Double = (0.3333, 0.6666, 1.0001);
var
  Canvas: TCanvas;
  DrawRect: TRect;
  I: Integer;
  Heading, StepSize: Double;
  RawPoints: array of TPointF;
  PlotPoints: array of TPoint;
  CurrentX, CurrentY: Double;
  MinX, MaxX, MinY, MaxY: Double;
  ScaleX, ScaleY, Scale: Double;
  OffsetX, OffsetY: Double;
  ContentWidth, ContentHeight: Double;
  DistanceValue: Double;
  HighlightColor: TColor;
  MarkerIndex: Integer;
  UseGPS: Boolean;

  function HasUsableGPS: Boolean;
  var
    J: Integer;
    LatMin, LatMax, LonMin, LonMax: Double;
    ValidCount: Integer;
  begin
    LatMin := 1.0E12;
    LatMax := -1.0E12;
    LonMin := 1.0E12;
    LonMax := -1.0E12;
    ValidCount := 0;
    for J := 0 to High(FTelemetryLapData) do
      if (not IsNan(FTelemetryLapData[J].GPSLatitude)) and
         (not IsNan(FTelemetryLapData[J].GPSLongitude)) then
      begin
        LatMin := Min(LatMin, FTelemetryLapData[J].GPSLatitude);
        LatMax := Max(LatMax, FTelemetryLapData[J].GPSLatitude);
        LonMin := Min(LonMin, FTelemetryLapData[J].GPSLongitude);
        LonMax := Max(LonMax, FTelemetryLapData[J].GPSLongitude);
        Inc(ValidCount);
      end;

    Result := (ValidCount >= 8) and
      ((LatMax - LatMin) > 0.0001) and
      ((LonMax - LonMin) > 0.0001);
  end;

  function PointInActiveSector(const ALapDistance: Double): Boolean;
  begin
    if FActiveSectorIndex < 0 then
      Exit(True);
    Result := (ALapDistance >= SectorStart[FActiveSectorIndex]) and
      (ALapDistance < SectorEnd[FActiveSectorIndex]);
  end;

  function FindNearestPointIndex(const ALapDistance: Double): Integer;
  var
    J: Integer;
    BestDelta, CurrentDelta: Double;
  begin
    Result := -1;
    BestDelta := 1.0E12;
    for J := 0 to High(FTelemetryLapData) do
    begin
      CurrentDelta := Abs(FTelemetryLapData[J].LapDistance - ALapDistance);
      if CurrentDelta < BestDelta then
      begin
        BestDelta := CurrentDelta;
        Result := J;
      end;
    end;
  end;

begin
  if not Assigned(FTelemetryMapBox) then
    Exit;

  Canvas := FTelemetryMapBox.Canvas;
  DrawRect := Rect(0, 0, FTelemetryMapBox.Width, FTelemetryMapBox.Height);
  Canvas.Brush.Color := RGB(255, 252, 247);
  Canvas.FillRect(DrawRect);

  Canvas.Brush.Style := bsClear;
  Canvas.Font.Name := 'Bahnschrift';
  Canvas.Font.Color := RGB(111, 50, 13);
  Canvas.Font.Style := [fsBold];
  Canvas.TextOut(10, 8, 'Track Map');

  if Length(FTelemetryLapData) < 2 then
  begin
    Canvas.Font.Style := [];
    Canvas.Font.Color := RGB(157, 88, 45);
    Canvas.TextRect(DrawRect, 10, 32, 'No representative lap available yet.');
    Exit;
  end;

  SetLength(RawPoints, Length(FTelemetryLapData));
  CurrentX := 0;
  CurrentY := 0;
  Heading := -Pi / 2;
  MinX := 1.0E12;
  MaxX := -1.0E12;
  MinY := 1.0E12;
  MaxY := -1.0E12;
  UseGPS := HasUsableGPS;

  for I := 0 to High(FTelemetryLapData) do
  begin
    if UseGPS then
    begin
      if (not IsNan(FTelemetryLapData[I].GPSLatitude)) and
         (not IsNan(FTelemetryLapData[I].GPSLongitude)) then
      begin
        CurrentX := FTelemetryLapData[I].GPSLongitude;
        CurrentY := -FTelemetryLapData[I].GPSLatitude;
      end
      else if I > 0 then
      begin
        CurrentX := RawPoints[I - 1].X;
        CurrentY := RawPoints[I - 1].Y;
      end;
    end
    else if I > 0 then
    begin
      StepSize := 1.3 + Max(FTelemetryLapData[I].Speed / 180.0, 0.3);
      Heading := Heading + (FTelemetryLapData[I].Steering * 0.16);
      CurrentX := CurrentX + Cos(Heading) * StepSize;
      CurrentY := CurrentY + Sin(Heading) * StepSize;
    end;

    RawPoints[I] := PointF(CurrentX, CurrentY);
    MinX := Min(MinX, CurrentX);
    MaxX := Max(MaxX, CurrentX);
    MinY := Min(MinY, CurrentY);
    MaxY := Max(MaxY, CurrentY);
  end;

  DrawRect := Rect(14, 32, FTelemetryMapBox.Width - 14, FTelemetryMapBox.Height - 16);
  if (DrawRect.Right - DrawRect.Left < 10) or (DrawRect.Bottom - DrawRect.Top < 10) then
    Exit;

  ScaleX := (DrawRect.Right - DrawRect.Left) / Max(MaxX - MinX, 1.0);
  ScaleY := (DrawRect.Bottom - DrawRect.Top) / Max(MaxY - MinY, 1.0);
  Scale := Min(ScaleX, ScaleY);
  ContentWidth := (MaxX - MinX) * Scale;
  ContentHeight := (MaxY - MinY) * Scale;
  OffsetX := DrawRect.Left + ((DrawRect.Right - DrawRect.Left) - ContentWidth) / 2;
  OffsetY := DrawRect.Top + ((DrawRect.Bottom - DrawRect.Top) - ContentHeight) / 2;

  SetLength(PlotPoints, Length(RawPoints));
  for I := 0 to High(RawPoints) do
    PlotPoints[I] := Point(
      Round(OffsetX + ((RawPoints[I].X - MinX) * Scale)),
      Round(OffsetY + ((RawPoints[I].Y - MinY) * Scale)));

  Canvas.Pen.Color := RGB(212, 197, 181);
  Canvas.Pen.Width := 4;
  Canvas.Polyline(PlotPoints);

  HighlightColor := RGB(226, 103, 28);
  Canvas.Pen.Width := 5;
  Canvas.Pen.Color := HighlightColor;
  for I := 1 to High(PlotPoints) do
  begin
    DistanceValue := FTelemetryLapData[I].LapDistance;
    if PointInActiveSector(DistanceValue) then
    begin
      Canvas.MoveTo(PlotPoints[I - 1].X, PlotPoints[I - 1].Y);
      Canvas.LineTo(PlotPoints[I].X, PlotPoints[I].Y);
    end;
  end;

  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := RGB(61, 45, 31);
  Canvas.Pen.Color := clWhite;
  Canvas.Ellipse(PlotPoints[0].X - 4, PlotPoints[0].Y - 4, PlotPoints[0].X + 4, PlotPoints[0].Y + 4);

  if FHoverLapDistance >= 0 then
  begin
    MarkerIndex := FindNearestPointIndex(FHoverLapDistance);
    if MarkerIndex >= 0 then
    begin
      Canvas.Brush.Color := RGB(23, 120, 77);
      Canvas.Pen.Color := clWhite;
      Canvas.Ellipse(PlotPoints[MarkerIndex].X - 5, PlotPoints[MarkerIndex].Y - 5,
        PlotPoints[MarkerIndex].X + 5, PlotPoints[MarkerIndex].Y + 5);
    end;
  end;
end;

procedure TMainForm.TelemetryChartPaint(Sender: TObject);
const
  SectorStart: array[0..2] of Double = (0.0, 0.3333, 0.6666);
  SectorEnd: array[0..2] of Double = (0.3333, 0.6666, 1.0001);
  SectorTint: array[0..2] of TColor = (15400932, 16119285, 15528171);
var
  Canvas: TCanvas;
  ChartRect: TRect;
  I, BaseLineY: Integer;
  MaxSpeed, DistanceValue: Double;
  SpeedPoint, ThrottlePoint, BrakePoint: TPoint;
  XPos: Integer;

  function DistanceToX(const ALapDistance: Double): Integer;
  begin
    Result := ChartRect.Left + Round(EnsureRange(ALapDistance, 0.0, 1.0) * (ChartRect.Width - 1));
  end;

  function SpeedToY(const ASpeed: Double): Integer;
  begin
    Result := ChartRect.Bottom - Round((ASpeed / MaxSpeed) * (ChartRect.Height - 28)) - 18;
  end;

  function PercentToY(const AValue: Double): Integer;
  begin
    Result := ChartRect.Bottom - Round(EnsureRange(AValue, 0.0, 1.0) * (ChartRect.Height - 28)) - 18;
  end;

begin
  if not Assigned(FTelemetryChartBox) then
    Exit;

  Canvas := FTelemetryChartBox.Canvas;
  Canvas.Brush.Color := RGB(255, 252, 247);
  Canvas.FillRect(Rect(0, 0, FTelemetryChartBox.Width, FTelemetryChartBox.Height));
  Canvas.Font.Name := 'Bahnschrift';
  Canvas.Font.Color := RGB(111, 50, 13);
  Canvas.Font.Style := [fsBold];
  Canvas.TextOut(10, 8, 'Telemetry Trace');

  ChartRect := Rect(12, 30, FTelemetryChartBox.Width - 12, FTelemetryChartBox.Height - 24);
  if (Length(FTelemetryLapData) < 2) or (ChartRect.Width < 40) or (ChartRect.Height < 50) then
  begin
    Canvas.Font.Style := [];
    Canvas.Font.Color := RGB(157, 88, 45);
    Canvas.TextRect(ChartRect, 10, 34, 'Select telemetry to view speed, throttle, and brake traces.');
    Exit;
  end;

  for I := 0 to 2 do
  begin
    Canvas.Brush.Color := SectorTint[I];
    Canvas.FillRect(Rect(DistanceToX(SectorStart[I]), ChartRect.Top,
      DistanceToX(SectorEnd[I]), ChartRect.Bottom));
  end;

  if FActiveSectorIndex >= 0 then
  begin
    Canvas.Brush.Color := RGB(255, 230, 196);
    Canvas.FillRect(Rect(DistanceToX(SectorStart[FActiveSectorIndex]), ChartRect.Top,
      DistanceToX(SectorEnd[FActiveSectorIndex]), ChartRect.Bottom));
  end;

  Canvas.Pen.Color := RGB(221, 205, 187);
  Canvas.Brush.Style := bsClear;
  Canvas.Rectangle(ChartRect);
  BaseLineY := ChartRect.Bottom - 18;
  Canvas.MoveTo(ChartRect.Left, BaseLineY);
  Canvas.LineTo(ChartRect.Right, BaseLineY);

  Canvas.Font.Style := [];
  Canvas.Font.Color := RGB(157, 88, 45);
  Canvas.TextOut(ChartRect.Left, ChartRect.Bottom - 16, '0%');
  Canvas.TextOut(DistanceToX(0.3333) - 18, ChartRect.Bottom - 16, '33%');
  Canvas.TextOut(DistanceToX(0.6666) - 18, ChartRect.Bottom - 16, '67%');
  Canvas.TextOut(ChartRect.Right - 26, ChartRect.Bottom - 16, '100%');

  MaxSpeed := 1.0;
  for I := 0 to High(FTelemetryLapData) do
    MaxSpeed := Max(MaxSpeed, FTelemetryLapData[I].Speed);

  Canvas.Pen.Width := 2;
  for I := 1 to High(FTelemetryLapData) do
  begin
    DistanceValue := FTelemetryLapData[I - 1].LapDistance;
    SpeedPoint := Point(DistanceToX(DistanceValue), SpeedToY(FTelemetryLapData[I - 1].Speed));
    ThrottlePoint := Point(DistanceToX(DistanceValue), PercentToY(FTelemetryLapData[I - 1].Throttle));
    BrakePoint := Point(DistanceToX(DistanceValue), PercentToY(FTelemetryLapData[I - 1].Brake));

    Canvas.Pen.Color := RGB(226, 103, 28);
    Canvas.MoveTo(SpeedPoint.X, SpeedPoint.Y);
    Canvas.LineTo(DistanceToX(FTelemetryLapData[I].LapDistance), SpeedToY(FTelemetryLapData[I].Speed));

    Canvas.Pen.Color := RGB(23, 120, 77);
    Canvas.MoveTo(ThrottlePoint.X, ThrottlePoint.Y);
    Canvas.LineTo(DistanceToX(FTelemetryLapData[I].LapDistance), PercentToY(FTelemetryLapData[I].Throttle));

    Canvas.Pen.Color := RGB(173, 42, 42);
    Canvas.MoveTo(BrakePoint.X, BrakePoint.Y);
    Canvas.LineTo(DistanceToX(FTelemetryLapData[I].LapDistance), PercentToY(FTelemetryLapData[I].Brake));
  end;

  Canvas.Font.Color := RGB(111, 50, 13);
  Canvas.TextOut(ChartRect.Left + 4, ChartRect.Top + 4,
    Format('%s | %s', [FTelemetryPreviewTrackName, FTelemetryPreviewCarName]));
  Canvas.Font.Color := RGB(226, 103, 28);
  Canvas.TextOut(ChartRect.Right - 190, ChartRect.Top + 4, 'Speed');
  Canvas.Font.Color := RGB(23, 120, 77);
  Canvas.TextOut(ChartRect.Right - 132, ChartRect.Top + 4, 'Throttle');
  Canvas.Font.Color := RGB(173, 42, 42);
  Canvas.TextOut(ChartRect.Right - 58, ChartRect.Top + 4, 'Brake');

  if FHoverLapDistance >= 0 then
  begin
    XPos := DistanceToX(FHoverLapDistance);
    Canvas.Pen.Color := RGB(61, 45, 31);
    Canvas.Pen.Style := psDash;
    Canvas.MoveTo(XPos, ChartRect.Top);
    Canvas.LineTo(XPos, ChartRect.Bottom);
    Canvas.Pen.Style := psSolid;
  end;
end;

procedure TMainForm.TelemetryChartMouseMove(Sender: TObject; Shift: TShiftState; X,
  Y: Integer);
var
  ChartRect: TRect;
begin
  if Length(FTelemetryLapData) = 0 then
    Exit;

  ChartRect := Rect(12, 30, FTelemetryChartBox.Width - 12, FTelemetryChartBox.Height - 24);
  if PtInRect(ChartRect, Point(X, Y)) then
    FHoverLapDistance := EnsureRange((X - ChartRect.Left) / Max(ChartRect.Width - 1, 1), 0.0, 1.0)
  else
    FHoverLapDistance := -1;
  RefreshTelemetryVisuals;
end;

procedure TMainForm.TelemetryChartMouseLeave(Sender: TObject);
begin
  if FHoverLapDistance < 0 then
    Exit;
  FHoverLapDistance := -1;
  RefreshTelemetryVisuals;
end;

procedure TMainForm.ConfigureStripedListView(ALV: TListView);
begin
  ALV.ReadOnly := True;
  ALV.RowSelect := True;
  ALV.GridLines := True;
  ALV.OnAdvancedCustomDrawItem := ListViewAdvancedCustomDrawItem;
end;

procedure TMainForm.ListViewAdvancedCustomDrawItem(Sender: TCustomListView;
  Item: TListItem; State: TCustomDrawState; Stage: TCustomDrawStage;
  var DefaultDraw: Boolean);
begin
  if Stage <> cdPrePaint then
    Exit;

  if cdsSelected in State then
  begin
    Sender.Canvas.Brush.Color := RGB(255, 189, 122);
    Sender.Canvas.Font.Color := RGB(74, 36, 9);
  end
  else if Odd(Item.Index) then
  begin
    Sender.Canvas.Brush.Color := RGB(255, 246, 236);
    Sender.Canvas.Font.Color := RGB(61, 45, 31);
  end
  else
  begin
    Sender.Canvas.Brush.Color := RGB(255, 255, 252);
    Sender.Canvas.Font.Color := RGB(61, 45, 31);
  end;

  DefaultDraw := True;
end;

function TMainForm.ReadDuckDBMetadataFallback(const AFilePath: string;
  const AKeys: array of string): string;
var
  KeyName: string;
  ErrorText: string;
begin
  Result := '';
  for KeyName in AKeys do
    if TCSVExporter.ReadDuckDBMetadataValue(AFilePath, KeyName, Result, ErrorText) then
    begin
      Result := Trim(Result);
      if Result <> '' then
        Exit;
    end;
  Result := '';
end;

procedure TMainForm.InitializeCarBadges;
begin
  FCarBadgeImages.Width := 28;
  FCarBadgeImages.Height := 18;
  FCarBadgeImages.ColorDepth := cd32Bit;
  FCarBadgeImages.Masked := False;
end;

function TMainForm.GetCarBadgeImageIndex(const ACarName: string): Integer;
var
  BadgeKey: string;
  BadgeBitmap: TBitmap;
  AccentColor: TColor;
  Words: TArray<string>;
  BadgeText: string;
  BadgeRect: TRect;
begin
  BadgeKey := UpperCase(Trim(ACarName));
  if BadgeKey = '' then
    BadgeKey := 'CAR';

  if FCarBadgeIndex.TryGetValue(BadgeKey, Result) then
    Exit;

  BadgeBitmap := TBitmap.Create;
  try
    BadgeBitmap.SetSize(28, 18);
    BadgeBitmap.PixelFormat := pf32bit;
    AccentColor := RGB(70 + (Length(BadgeKey) * 9) mod 120,
      70 + (Length(BadgeKey) * 5) mod 120,
      120 + (Length(BadgeKey) * 13) mod 100);
    BadgeBitmap.Canvas.Brush.Color := AccentColor;
    BadgeBitmap.Canvas.Pen.Color := RGB(235, 235, 235);
    BadgeBitmap.Canvas.RoundRect(Rect(0, 0, 28, 18), 6, 6);

    Words := BadgeKey.Split([' ']);
    BadgeText := Copy(BadgeKey, 1, 2);
    if Length(Words) >= 2 then
      BadgeText := Copy(Words[0], 1, 1) + Copy(Words[High(Words)], 1, 1);

    BadgeBitmap.Canvas.Brush.Style := bsClear;
    BadgeBitmap.Canvas.Font.Name := 'Bahnschrift';
    BadgeBitmap.Canvas.Font.Style := [fsBold];
    BadgeBitmap.Canvas.Font.Color := clWhite;
    BadgeBitmap.Canvas.Font.Size := 8;
    BadgeRect := Rect(0, 0, 28, 18);
    DrawText(BadgeBitmap.Canvas.Handle, PChar(BadgeText), Length(BadgeText),
      BadgeRect, DT_CENTER or DT_VCENTER or DT_SINGLELINE);

    Result := FCarBadgeImages.Add(BadgeBitmap, nil);
    FCarBadgeIndex.Add(BadgeKey, Result);
  finally
    BadgeBitmap.Free;
  end;
end;

function TMainForm.FormatDurationMs(ADurationMs: Int64): string;
var
  TotalSeconds: Int64;
begin
  if ADurationMs <= 0 then
    Exit('--:--');

  TotalSeconds := ADurationMs div 1000;
  Result := Format('%d:%2.2d', [TotalSeconds div 60, TotalSeconds mod 60]);
end;

function TMainForm.DisplaySessionType(const ASessionType: string): string;
begin
  Result := Trim(StringReplace(ASessionType, 'LMU Results XML - ', '', [rfIgnoreCase]));
  if Result = '' then
    Result := 'Session';
end;

procedure TMainForm.RefreshTelemetrySourceInfo;
var
  Folder: string;
  LatestTime: TDateTime;
  LatestFile: string;
  Summary: TTelemetrySourceSummary;
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

  if FTelemetrySourceScanInProgress then
  begin
    LblTelemetrySourceInfo.Caption := 'Scanning LMU telemetry files in the background...';
    Exit;
  end;

  if Length(FTelemetrySourceSummaries) = 0 then
    LblTelemetrySourceInfo.Caption := 'No .duckdb telemetry files found in telemetry folder.'
  else
  begin
    LatestFile := '';
    LatestTime := 0;
    for Summary in FTelemetrySourceSummaries do
      if (LatestFile = '') or (Summary.FileTime > LatestTime) then
      begin
        LatestTime := Summary.FileTime;
        LatestFile := Summary.FilePath;
      end;

    LblTelemetrySourceInfo.Caption := Format('%d .duckdb telemetry file(s) detected. Latest: %s',
      [Length(FTelemetrySourceSummaries), ExtractFileName(LatestFile)]);
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
      LblResultsSourceInfo.Caption := Format('%d .xml result file(s) detected. Latest: %s. Driver will be auto-detected during background scan.',
        [Length(Files), ExtractFileName(LatestFile)]);
  end;

  if FResultsImportInProgress then
    LblResultsSourceInfo.Caption := LblResultsSourceInfo.Caption + ' Background import in progress.';
end;

procedure TMainForm.StartAsyncTelemetrySourceScan(AShowStatus: Boolean);
var
  SourceFolder: string;
  DatabasePath: string;
begin
  if FTelemetrySourceScanInProgress then
  begin
    SetStatus('LMU telemetry source scan is already running in the background.');
    Exit;
  end;

  SourceFolder := Trim(EdtTelemetryFolder.Text);
  if SourceFolder = '' then
    SourceFolder := Trim(FSettings.TelemetrySourceFolder);
  DatabasePath := FDB.DatabasePath;

  SetLength(FTelemetrySourceSummaries, 0);
  SetLength(FSourceTelemetryFiles, 0);

  if SourceFolder = '' then
  begin
    RefreshTelemetrySourceInfo;
    RefreshSessions;
    Exit;
  end;

  FTelemetrySourceScanInProgress := True;
  RefreshTelemetrySourceInfo;
  RefreshSessions;
  SetStatus('Scanning LMU telemetry sources in the background...');

  TThread.CreateAnonymousThread(
    procedure
    var
      Files: TArray<string>;
      Summaries: TArray<TTelemetrySourceSummary>;
      CachedItems: TTelemetrySourceCacheArray;
      SummaryCount: Integer;
      SourceFile: string;
      NormalizedFile: string;
      TrackName: string;
      CarName: string;
      DriverName: string;
      LocalError: string;
      ErrorText: string;
      CurrentConfiguredFolder: string;
      ThreadDB: TDatabaseManager;
      CacheLookup: TDictionary<string, TTelemetrySourceCacheItem>;
      SeenFiles: TDictionary<string, Byte>;
      CachedItem: TTelemetrySourceCacheItem;

      function FileStampText(const AValue: TDateTime): string;
      begin
        Result := FormatDateTime('yyyy-mm-dd hh:nn:ss', AValue);
      end;

      function ReadMetadataWithFallback(const AKeyName, AFallback: string): string;
      begin
        LocalError := '';
        if not TCSVExporter.ReadDuckDBMetadataValue(SourceFile, AKeyName, Result, LocalError) then
          Result := AFallback;
        Result := Trim(Result);
      end;

      function ReadMetadataFallback(const AKeys: array of string; const AFallback: string): string;
      var
        KeyName: string;
      begin
        Result := '';
        for KeyName in AKeys do
        begin
          LocalError := '';
          if TCSVExporter.ReadDuckDBMetadataValue(SourceFile, KeyName, Result, LocalError) then
          begin
            Result := Trim(Result);
            if Result <> '' then
              Exit;
          end;
        end;
        Result := AFallback;
      end;
    begin
      ErrorText := '';
      ThreadDB := nil;
      CacheLookup := nil;
      SeenFiles := nil;
      try
        ThreadDB := TDatabaseManager.Create(DatabasePath);
        CachedItems := ThreadDB.GetTelemetrySourceCache;
        CacheLookup := TDictionary<string, TTelemetrySourceCacheItem>.Create;
        SeenFiles := TDictionary<string, Byte>.Create;
        for CachedItem in CachedItems do
          CacheLookup.AddOrSetValue(ExpandFileName(CachedItem.FilePath), CachedItem);

        if TDirectory.Exists(SourceFolder) then
          Files := TDirectory.GetFiles(SourceFolder, '*.duckdb', TSearchOption.soTopDirectoryOnly)
        else
          Files := nil;

        SetLength(Summaries, Length(Files));
        SummaryCount := 0;
        for SourceFile in Files do
        begin
          NormalizedFile := ExpandFileName(SourceFile);
          SeenFiles.AddOrSetValue(NormalizedFile, 0);
          Summaries[SummaryCount].FilePath := SourceFile;
          Summaries[SummaryCount].FileTime := TFile.GetLastWriteTime(SourceFile);

          if CacheLookup.TryGetValue(NormalizedFile, CachedItem) and
             SameText(FileStampText(CachedItem.FileModified), FileStampText(Summaries[SummaryCount].FileTime)) then
          begin
            TrackName := CachedItem.TrackName;
            CarName := CachedItem.CarName;
            DriverName := CachedItem.DriverName;
          end
          else
          begin
            TrackName := ReadMetadataWithFallback('TrackName', ChangeFileExt(ExtractFileName(SourceFile), ''));
            CarName := ReadMetadataFallback(
              ['CarType', 'VehicleName', 'VehName', 'CarModel', 'CarName'],
              ChangeFileExt(ExtractFileName(SourceFile), ''));
            DriverName := ReadMetadataWithFallback('DriverName', 'Driver unknown');
            ThreadDB.UpsertTelemetrySourceCache(SourceFile, Summaries[SummaryCount].FileTime,
              TrackName, CarName, DriverName);
          end;

          Summaries[SummaryCount].TrackName := TrackName;
          Summaries[SummaryCount].CarName := CarName;
          Summaries[SummaryCount].DriverName := DriverName;
          Inc(SummaryCount);
        end;
        SetLength(Summaries, SummaryCount);

        for CachedItem in CachedItems do
          if not SeenFiles.ContainsKey(ExpandFileName(CachedItem.FilePath)) then
            ThreadDB.DeleteTelemetrySourceCache(CachedItem.FilePath);
      except
        on E: Exception do
          ErrorText := E.Message;
      end;

      SeenFiles.Free;
      CacheLookup.Free;
      ThreadDB.Free;

      TThread.Synchronize(nil,
        procedure
        var
          I: Integer;
        begin
          FTelemetrySourceScanInProgress := False;
          CurrentConfiguredFolder := Trim(EdtTelemetryFolder.Text);
          if CurrentConfiguredFolder = '' then
            CurrentConfiguredFolder := Trim(FSettings.TelemetrySourceFolder);

          if not SameText(ExpandFileName(CurrentConfiguredFolder), ExpandFileName(SourceFolder)) then
            Exit;

          if ErrorText = '' then
          begin
            FTelemetrySourceSummaries := Copy(Summaries);
            SetLength(FSourceTelemetryFiles, Length(FTelemetrySourceSummaries));
            for I := 0 to High(FTelemetrySourceSummaries) do
              FSourceTelemetryFiles[I] := FTelemetrySourceSummaries[I].FilePath;
            SetStatus(Format('Telemetry source scan complete: %d LMU file(s) detected.',
              [Length(FTelemetrySourceSummaries)]));
          end
          else
          begin
            SetLength(FTelemetrySourceSummaries, 0);
            SetLength(FSourceTelemetryFiles, 0);
            SetStatus('Telemetry source scan failed: ' + ErrorText);
            if AShowStatus then
              ShowMessage('Telemetry source scan failed: ' + ErrorText);
          end;

          RefreshTelemetrySourceInfo;
          RefreshSessions;
        end);
    end).Start;
end;

procedure TMainForm.StartAsyncResultsImport(AForceRebuild, AShowStatus: Boolean);
var
  ResultsFolder: string;
  PreferredDriverName: string;
  DatabasePath: string;
begin
  if FResultsImportInProgress then
  begin
    SetStatus('LMU results import is already running in the background.');
    Exit;
  end;

  ResultsFolder := Trim(EdtResultsFolder.Text);
  if ResultsFolder = '' then
    Exit;

  PreferredDriverName := Trim(EdtPreferredDriver.Text);
  DatabasePath := FDB.DatabasePath;

  FResultsImportInProgress := True;
  BtnRescanResults.Enabled := False;
  RefreshResultsSourceInfo;
  SetStatus('Scanning LMU results in the background...');

  TThread.CreateAnonymousThread(
    procedure
    var
      ThreadDB: TDatabaseManager;
      Summary: TResultsImportSummary;
      EffectiveDriverName: string;
      ErrorMessage: string;
      StatusMessage: string;
    begin
      FillChar(Summary, SizeOf(Summary), 0);
      EffectiveDriverName := PreferredDriverName;
      ErrorMessage := '';
      StatusMessage := 'LMU results scan skipped.';
      ThreadDB := nil;
      try
        if (EffectiveDriverName = '') and TDirectory.Exists(ResultsFolder) then
          EffectiveDriverName := Trim(TResultsXMLImporter.DetectDominantDriverName(ResultsFolder));

        if EffectiveDriverName = '' then
          StatusMessage := 'LMU results scan skipped until a preferred driver name can be detected.'
        else
        begin
          ThreadDB := TDatabaseManager.Create(DatabasePath);
          if AForceRebuild then
          begin
            ThreadDB.Connection.ExecSQL('DELETE FROM ResultImportFiles');
            ThreadDB.Connection.ExecSQL(
              'DELETE FROM LapTimes WHERE SourceType = ''LMU_RESULTS_XML'' ' +
              '   OR SessionType LIKE ''LMU Results XML%''');
          end;

          Summary := TResultsXMLImporter.ImportFolder(ThreadDB, ResultsFolder, EffectiveDriverName);
          if AForceRebuild then
            StatusMessage := Format('Results rebuild complete: %d imported, %d skipped, %d failed.',
              [Summary.LapsInserted, Summary.LapsSkipped, Summary.FilesFailed])
          else
            StatusMessage := Format('Results scan complete: %d imported, %d skipped, %d failed.',
              [Summary.LapsInserted, Summary.LapsSkipped, Summary.FilesFailed]);
        end;
      except
        on E: Exception do
          ErrorMessage := E.Message;
      end;
      ThreadDB.Free;

      TThread.Synchronize(nil,
        procedure
        begin
          FResultsImportInProgress := False;
          BtnRescanResults.Enabled := True;

          if (Trim(EdtPreferredDriver.Text) = '') and (EffectiveDriverName <> '') then
          begin
            EdtPreferredDriver.Text := EffectiveDriverName;
            FSettings.PreferredDriverName := EffectiveDriverName;
            FSettings.Save;
          end;

          RefreshResultsSourceInfo;
          if ErrorMessage <> '' then
          begin
            SetStatus('Results import failed: ' + ErrorMessage);
            if AShowStatus then
              ShowMessage('Results import failed: ' + ErrorMessage);
            Exit;
          end;

          RefreshLapTimes;
          SetStatus(StatusMessage);
          if AShowStatus then
          begin
            if EffectiveDriverName = '' then
              ShowMessage(StatusMessage)
            else if AForceRebuild then
              ShowMessage(Format(
                'Clean results rebuild completed.' + sLineBreak +
                'Driver: %s' + sLineBreak +
                'Files scanned: %d' + sLineBreak +
                'Files failed: %d' + sLineBreak +
                'Laps inserted: %d' + sLineBreak +
                'Laps skipped: %d',
                [EffectiveDriverName, Summary.FilesScanned, Summary.FilesFailed,
                 Summary.LapsInserted, Summary.LapsSkipped]))
            else
              ShowMessage(Format(
                'Results scan completed.' + sLineBreak +
                'Driver: %s' + sLineBreak +
                'Files scanned: %d' + sLineBreak +
                'Files failed: %d' + sLineBreak +
                'Laps inserted: %d' + sLineBreak +
                'Laps skipped: %d',
                [EffectiveDriverName, Summary.FilesScanned, Summary.FilesFailed,
                 Summary.LapsInserted, Summary.LapsSkipped]));
          end;
        end);
    end).Start;
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

  GrpTop10.Caption   := Format(' Your Top 10 (%d logged) ', [Length(Top10)]);
  GrpFastest.Caption := Format(' Your Best By Car (%d cars) ', [Length(Fastest)]);
  SetStatus(Format('%d ranked laps and %d car-best laps loaded for %s / %s',
    [Length(Top10), Length(Fastest), CboTrack.Text, CboClass.Text]));
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
      Item.ImageIndex := GetCarBadgeImageIndex(ALaps[I].CarName);
      Item.SubItems.Add(ALaps[I].CarName);
      Item.SubItems.Add(FormatLapTime(ALaps[I].LapTimeMs));
      Item.SubItems.Add(FormatDateTime('yyyy-MM-dd', ALaps[I].LapDate));
      Item.SubItems.Add(DisplaySessionType(ALaps[I].SessionType));
      Item.Data := Pointer(ALaps[I].ID);  // Store DB ID
    end;
  finally
    ALV.Items.EndUpdate;
  end;
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
  TrackLabel: string;
  DetailText: string;
  SourceSummary: TTelemetrySourceSummary;
begin
  LvwSessions.Items.BeginUpdate;
  try
    LvwSessions.Items.Clear;
    FSessions := FDB.GetTelemetrySessions;
    SetLength(FSourceTelemetryFiles, Length(FTelemetrySourceSummaries));
    for I := 0 to High(FTelemetrySourceSummaries) do
      FSourceTelemetryFiles[I] := FTelemetrySourceSummaries[I].FilePath;

    for I := 0 to High(FSessions) do
    begin
      Item := LvwSessions.Items.Add;
      Item.Caption := FormatDateTime('yyyy-MM-dd HH:nn', FSessions[I].SessionDate);
      Item.SubItems.Add('Saved');
      TrackLabel := FSessions[I].TrackName;
      if FSessions[I].TrackLayout <> '' then
        TrackLabel := TrackLabel + ' - ' + FSessions[I].TrackLayout;
      Item.SubItems.Add(TrackLabel);
      Item.SubItems.Add(FSessions[I].CarName);
      DetailText := Format('%d laps | %d pts | %s',
        [FSessions[I].EstimatedLaps, FSessions[I].DataPointCount,
         FormatDurationMs(FSessions[I].DurationMs)]);
      Item.SubItems.Add(DetailText);
    end;

    for SourceSummary in FTelemetrySourceSummaries do
    begin
      Item := LvwSessions.Items.Add;
      Item.Caption := FormatDateTime('yyyy-MM-dd HH:nn', SourceSummary.FileTime);
      Item.SubItems.Add('LMU');
      Item.SubItems.Add(SourceSummary.TrackName);
      Item.SubItems.Add(SourceSummary.CarName);
      Item.SubItems.Add('Driver: ' + SourceSummary.DriverName);
    end;

    if FTelemetrySourceScanInProgress then
    begin
      Item := LvwSessions.Items.Add;
      Item.Caption := 'Scanning...';
      Item.SubItems.Add('LMU');
      Item.SubItems.Add('Telemetry source scan in progress');
      Item.SubItems.Add('');
      Item.SubItems.Add('Background refresh');
    end;
  finally
    LvwSessions.Items.EndUpdate;
  end;

  MemoSessionInfo.Clear;
  MemoAIResponse.Clear;
  ResetSectorScorecard;
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
    ResetSectorScorecard;
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
    UpdateSectorScorecard;
    Exit;
  end;

  S := FSessions[Idx];
  MemoSessionInfo.Lines.Clear;
  MemoSessionInfo.Lines.Add(Format('Track   : %s  %s', [S.TrackName, S.TrackLayout]));
  MemoSessionInfo.Lines.Add(Format('Car     : %s', [S.CarName]));
  MemoSessionInfo.Lines.Add(Format('Date    : %s',
    [FormatDateTime('dddd d mmmm yyyy  HH:nn:ss', S.SessionDate)]));
  MemoSessionInfo.Lines.Add(Format('Points  : %d data points', [S.DataPointCount]));
  MemoSessionInfo.Lines.Add(Format('Laps    : %d estimated lap(s)', [S.EstimatedLaps]));
  MemoSessionInfo.Lines.Add(Format('Length  : %s', [FormatDurationMs(S.DurationMs)]));
  if S.Notes <> '' then
    MemoSessionInfo.Lines.Add(Format('Notes   : %s', [S.Notes]));
  UpdateSectorScorecard;
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
    CarName := ReadDuckDBMetadataFallback(SourceFile,
      ['CarType', 'VehicleName', 'VehName', 'CarModel', 'CarName']);
    if CarName = '' then
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
  RefreshLapTimes;
  StartAsyncTelemetrySourceScan(False);
  StartAsyncResultsImport(False, False);
  SetStatus('Settings saved. Background results scan started.');
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
    StartAsyncTelemetrySourceScan(False);
  end;
end;

procedure TMainForm.BtnRescanTelemetryClick(Sender: TObject);
begin
  StartAsyncTelemetrySourceScan(True);
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
    StartAsyncResultsImport(False, False);
  end;
end;

procedure TMainForm.BtnRescanResultsClick(Sender: TObject);
begin
  RefreshResultsSourceInfo;
  case MessageDlg(
    'Choose the LMU results refresh mode:' + sLineBreak +
    'Yes = clean rebuild of imported LMU XML laps' + sLineBreak +
    'No = incremental rescan only' + sLineBreak +
    'Cancel = do nothing',
    mtConfirmation, [mbYes, mbNo, mbCancel], 0) of
    mrYes:
      StartAsyncResultsImport(True, True);
    mrNo:
      StartAsyncResultsImport(False, True);
  else
    Exit;
  end;
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
  SourceSummary: TTelemetrySourceSummary;
  HasSummary: Boolean;
begin
  if not TFile.Exists(AFilePath) then
  begin
    ALines.Add('File no longer exists.');
    Exit;
  end;

  if SameText(ExtractFileExt(AFilePath), '.duckdb') then
  begin
    HasSummary := False;
    for SourceSummary in FTelemetrySourceSummaries do
      if SameText(SourceSummary.FilePath, AFilePath) then
      begin
        TrackName := Trim(SourceSummary.TrackName);
        CarName := Trim(SourceSummary.CarName);
        DriverName := Trim(SourceSummary.DriverName);
        HasSummary := True;
        Break;
      end;

    ALines.Add('LMU telemetry source file selected:');
    ALines.Add('This is a DuckDB telemetry database, not the app''s SQLite database.');
    if (not HasSummary) and TCSVExporter.ReadDuckDBMetadataValue(AFilePath, 'TrackName', TrackName, ErrorText) then
      ALines.Add('Track   : ' + TrackName);
    if TrackName <> '' then
      ALines.Add('Track   : ' + TrackName);
    if not HasSummary then
      CarName := ReadDuckDBMetadataFallback(AFilePath,
        ['CarType', 'VehicleName', 'VehName', 'CarModel', 'CarName']);
    if CarName <> '' then
      ALines.Add('Car     : ' + CarName);
    if (not HasSummary) and TCSVExporter.ReadDuckDBMetadataValue(AFilePath, 'DriverName', DriverName, ErrorText) then
      ;
    if DriverName <> '' then
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
