unit ImportTelemetryForm;

{ Dialog for importing a telemetry session from a CSV file.
  Expected CSV column order (first row = header):
    TimestampMs, Speed_kmh, RPM, Gear, Throttle_pct, Brake_pct,
    Steering_pct, LapDistance_pct

  Values:
    Throttle_pct / Brake_pct  – 0..100 (converted to 0..1 on import)
    Steering_pct              – -100..100 (converted to -1..1 on import)
    LapDistance_pct           – 0..1 (fraction of lap)
}

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.SysUtils, System.Classes, System.IOUtils,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  Vcl.StdCtrls, Vcl.ExtCtrls,
  LapTimeModels, DatabaseManager;

type
  TImportTelemetryForm = class(TForm)
    LblTrack: TLabel;
    LblCar: TLabel;
    LblCSV: TLabel;
    LblNotes: TLabel;
    LblCSVNote: TLabel;
    CboTrack: TComboBox;
    CboCar: TComboBox;
    EdtCSVFile: TEdit;
    BtnBrowse: TButton;
    EdtNotes: TEdit;
    BtnImport: TButton;
    BtnCancel: TButton;

    procedure FormCreate(Sender: TObject);
    procedure BtnBrowseClick(Sender: TObject);
    procedure BtnImportClick(Sender: TObject);
  private
    FDB: TDatabaseManager;
    FTracks: TTrackArray;
    FCars: TCarArray;
    FInitialTelemetryFolder: string;

    procedure LoadTracks;
    procedure LoadCars;
    function ValidateCSVFile(const AFilePath: string; out AValidRows: Integer;
      out ADurationMs: Int64; out ALapSpan: Double; out AError: string): Boolean;
    function ImportCSV(const AFilePath: string; ASessionID: Integer): Integer;
  public
    { Call Initialize(DB) after Create and before ShowModal. }
    procedure Initialize(ADB: TDatabaseManager; const AInitialTelemetryFolder: string = '');
    property DB: TDatabaseManager read FDB write FDB;
  end;

  // No global form variable: the dialog is created locally where needed.
  implementation

{$R *.dfm}

procedure TImportTelemetryForm.FormCreate(Sender: TObject);
begin
  // Nothing to do at create time – call Initialize(DB) before ShowModal
end;

procedure TImportTelemetryForm.Initialize(ADB: TDatabaseManager;
  const AInitialTelemetryFolder: string = '');
begin
  FDB := ADB;
  FInitialTelemetryFolder := Trim(AInitialTelemetryFolder);
  LoadTracks;
  LoadCars;
end;

procedure TImportTelemetryForm.LoadTracks;
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

procedure TImportTelemetryForm.LoadCars;
var
  I: Integer;
begin
  CboCar.Items.BeginUpdate;
  try
    CboCar.Items.Clear;
    FCars := FDB.GetCars;
    for I := 0 to High(FCars) do
      CboCar.Items.Add(FCars[I].Name + ' (' + FCars[I].ClassName + ')');
  finally
    CboCar.Items.EndUpdate;
  end;
  if CboCar.Items.Count > 0 then
    CboCar.ItemIndex := 0;
end;

procedure TImportTelemetryForm.BtnBrowseClick(Sender: TObject);
var
  OD: TOpenDialog;
begin
  OD := TOpenDialog.Create(nil);
  try
    OD.Title  := 'Select Telemetry CSV File';
    OD.Filter := 'CSV Files (*.csv)|*.csv|All Files (*.*)|*.*';
    if TDirectory.Exists(FInitialTelemetryFolder) then
      OD.InitialDir := FInitialTelemetryFolder;
    if OD.Execute then
      EdtCSVFile.Text := OD.FileName;
  finally
    OD.Free;
  end;
end;

function TImportTelemetryForm.ValidateCSVFile(const AFilePath: string;
  out AValidRows: Integer; out ADurationMs: Int64; out ALapSpan: Double;
  out AError: string): Boolean;
const
  MIN_DURATION_MS = 80000;
  MIN_LAP_SPAN = 0.80;
  MIN_VALID_ROWS = 4000;
var
  Lines: TStringList;
  I: Integer;
  Parts: TArray<string>;
  TimestampMs: Int64;
  LapDistance: Double;
  FirstTimestamp: Int64;
  LastTimestamp: Int64;
  MinLapDistance: Double;
  MaxLapDistance: Double;
  FirstRow: Boolean;
  InvariantFS: TFormatSettings;
begin
  Result := False;
  AError := '';
  AValidRows := 0;
  ADurationMs := 0;
  ALapSpan := 0;
  FirstTimestamp := 0;
  LastTimestamp := 0;
  MinLapDistance := 0;
  MaxLapDistance := 0;
  InvariantFS := TFormatSettings.Invariant;

  if not TFile.Exists(AFilePath) then
  begin
    AError := 'CSV file not found.';
    Exit;
  end;

  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(AFilePath, TEncoding.UTF8);
    if Lines.Count <= 1 then
    begin
      AError := 'The CSV contains no telemetry rows.';
      Exit;
    end;

    FirstRow := True;
    for I := 1 to Lines.Count - 1 do
    begin
      if Trim(Lines[I]) = '' then
        Continue;

      Parts := Lines[I].Split([',']);
      if Length(Parts) < 8 then
        Continue;

      if not TryStrToInt64(Trim(Parts[0]), TimestampMs) then
        Continue;
      if not TryStrToFloat(Trim(Parts[7]), LapDistance, InvariantFS) then
        Continue;

      if FirstRow then
      begin
        FirstTimestamp := TimestampMs;
        LastTimestamp := TimestampMs;
        MinLapDistance := LapDistance;
        MaxLapDistance := LapDistance;
        FirstRow := False;
      end
      else
      begin
        if TimestampMs < FirstTimestamp then
          FirstTimestamp := TimestampMs;
        if TimestampMs > LastTimestamp then
          LastTimestamp := TimestampMs;
        if LapDistance < MinLapDistance then
          MinLapDistance := LapDistance;
        if LapDistance > MaxLapDistance then
          MaxLapDistance := LapDistance;
      end;

      Inc(AValidRows);
    end;
  finally
    Lines.Free;
  end;

  if AValidRows = 0 then
  begin
    AError := 'No valid telemetry rows were found in the CSV.';
    Exit;
  end;

  ADurationMs := LastTimestamp - FirstTimestamp;
  ALapSpan := MaxLapDistance - MinLapDistance;

  if (AValidRows < MIN_VALID_ROWS) or
     ((ADurationMs < MIN_DURATION_MS) and (ALapSpan < MIN_LAP_SPAN)) then
  begin
    AError := Format(
      'Telemetry clip is too short to be useful.' + #13#10 +
      'Valid rows: %d' + #13#10 +
      'Duration: %.1f seconds' + #13#10 +
      'Lap coverage: %.0f%%' + #13#10 +
      'Import at least roughly one lap of telemetry.',
      [AValidRows, ADurationMs / 1000.0, ALapSpan * 100.0]);
    Exit;
  end;

  Result := True;
end;

function TImportTelemetryForm.ImportCSV(const AFilePath: string;
  ASessionID: Integer): Integer;
var
  Lines: TStringList;
  I: Integer;
  Parts: TArray<string>;
  TimestampMs: Int64;
  Speed, RPM, Throttle, Brake, Steering, LapDistance: Double;
  Gear: Integer;
  Imported: Integer;
  InvariantFS: TFormatSettings;
begin
  Imported := 0;
  InvariantFS := TFormatSettings.Invariant;
  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(AFilePath, TEncoding.UTF8);

    // Skip header row
    for I := 1 to Lines.Count - 1 do
    begin
      if Trim(Lines[I]) = '' then
        Continue;

      Parts := Lines[I].Split([',']);
      if Length(Parts) < 8 then
        Continue;

      try
        TimestampMs := StrToInt64(Trim(Parts[0]));
        Speed       := StrToFloat(Trim(Parts[1]), InvariantFS);
        RPM         := StrToFloat(Trim(Parts[2]), InvariantFS);
        Gear        := StrToInt(Trim(Parts[3]));
        Throttle    := StrToFloat(Trim(Parts[4]), InvariantFS) / 100.0;
        Brake       := StrToFloat(Trim(Parts[5]), InvariantFS) / 100.0;
        Steering    := StrToFloat(Trim(Parts[6]), InvariantFS) / 100.0;
        LapDistance := StrToFloat(Trim(Parts[7]), InvariantFS);

        FDB.AddTelemetryDataPoint(ASessionID, TimestampMs, Speed, RPM,
                                  Gear, Throttle, Brake, Steering, LapDistance);
        Inc(Imported);
      except
        // Skip malformed lines
      end;
    end;
  finally
    Lines.Free;
  end;
  Result := Imported;
end;

procedure TImportTelemetryForm.BtnImportClick(Sender: TObject);
var
  TrackID, CarID, SessionID, Imported: Integer;
  Notes: string;
  ValidRows: Integer;
  DurationMs: Int64;
  LapSpan: Double;
  ValidationError: string;
begin
  if CboTrack.ItemIndex < 0 then
  begin
    ShowMessage('Please select a track.');
    CboTrack.SetFocus;
    Exit;
  end;
  if CboCar.ItemIndex < 0 then
  begin
    ShowMessage('Please select a car.');
    CboCar.SetFocus;
    Exit;
  end;
  if Trim(EdtCSVFile.Text) = '' then
  begin
    ShowMessage('Please choose a CSV file.');
    BtnBrowse.SetFocus;
    Exit;
  end;
  if not TFile.Exists(EdtCSVFile.Text) then
  begin
    ShowMessage('CSV file not found: ' + EdtCSVFile.Text);
    Exit;
  end;

  TrackID := FTracks[CboTrack.ItemIndex].ID;
  CarID   := FCars[CboCar.ItemIndex].ID;
  Notes   := Trim(EdtNotes.Text);

  if not ValidateCSVFile(EdtCSVFile.Text, ValidRows, DurationMs, LapSpan,
    ValidationError) then
  begin
    ShowMessage(ValidationError);
    Exit;
  end;

  try
    SessionID := FDB.AddTelemetrySession(TrackID, CarID, Notes, Now);
    Imported  := ImportCSV(EdtCSVFile.Text, SessionID);

    if Imported = 0 then
    begin
      // Roll back the empty session
      FDB.DeleteTelemetrySession(SessionID);
      ShowMessage('No data rows were imported. Check that the CSV format matches:' +
        #13#10 +
        'TimestampMs, Speed_kmh, RPM, Gear, Throttle_pct, Brake_pct, ' +
        'Steering_pct, LapDistance_pct');
      Exit;
    end;

    ShowMessage(Format(
      'Import complete. %d data points imported.' + #13#10 +
      'Clip length: %.1f seconds' + #13#10 +
      'Lap coverage: %.0f%%',
      [Imported, DurationMs / 1000.0, LapSpan * 100.0]));
    ModalResult := mrOk;
  except
    on E: Exception do
      ShowMessage('Import failed: ' + E.Message);
  end;
end;

end.
