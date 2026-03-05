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
begin
  Imported := 0;
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
        Speed       := StrToFloat(Trim(Parts[1]));
        RPM         := StrToFloat(Trim(Parts[2]));
        Gear        := StrToInt(Trim(Parts[3]));
        Throttle    := StrToFloat(Trim(Parts[4])) / 100.0;
        Brake       := StrToFloat(Trim(Parts[5])) / 100.0;
        Steering    := StrToFloat(Trim(Parts[6])) / 100.0;
        LapDistance := StrToFloat(Trim(Parts[7]));

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

    ShowMessage(Format('Import complete. %d data points imported.', [Imported]));
    ModalResult := mrOk;
  except
    on E: Exception do
      ShowMessage('Import failed: ' + E.Message);
  end;
end;

end.
