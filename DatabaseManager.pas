unit DatabaseManager;

{ SQLite data-access layer using FireDAC.
  Database storage defaults to data.db next to the executable so the active
  file is easy to inspect and stays aligned with the running build.

  Schema
  ------
  Tracks            – circuits available in Le Mans Ultimate
  CarClasses        – Hypercar, LMP2, LMGT3
  Cars              – individual car models linked to a CarClass
  LapTimes          – personal best laps (TrackID + CarID + ms + date + session)
  TelemetrySessions – header record for a recorded telemetry session
  TelemetryData     – per-frame telemetry data points
}

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, Data.DB,
  FireDAC.Comp.Client,
  FireDAC.Stan.ExprFuncs,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Option,
  FireDAC.Stan.Error,
  FireDAC.Stan.Def,
  FireDAC.Stan.Pool,
  FireDAC.Stan.Async,
  FireDAC.Stan.Param,
  FireDAC.Phys,
  FireDAC.Phys.Intf,
  FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteDef,
  FireDAC.DApt,
  FireDAC.UI.Intf,
  FireDAC.VCLUI.Wait,
  FireDAC.Comp.UI,
  LapTimeModels;

type
  TDatabaseManager = class
  private
    FConnection: TFDConnection;
    FDatabasePath: string;

    procedure CreateSchema;
    procedure EnsureColumnExists(const ATableName, AColumnName, AColumnDefinition: string);
    procedure SeedReferenceData;
    procedure NormalizeReferenceData;
    function LastInsertID: Integer;
    function EstimateTelemetrySessionLapCount(ASessionID: Integer): Integer;
  public
    constructor Create(const ADatabasePath: string = '');
    destructor Destroy; override;

    // -----------------------------------------------------------------------
    // Tracks
    // -----------------------------------------------------------------------
    function GetTracks: TTrackArray;
    function AddTrack(const AName, ALayout: string): Integer;
    function DeleteTrack(AID: Integer): Boolean;

    // -----------------------------------------------------------------------
    // Car classes
    // -----------------------------------------------------------------------
    function GetCarClasses: TCarClassArray;
    function AddCarClass(const AName: string): Integer;

    // -----------------------------------------------------------------------
    // Cars
    // -----------------------------------------------------------------------
    function GetCars(AClassID: Integer = -1): TCarArray;
    function AddCar(const AName: string; AClassID: Integer): Integer;

    // -----------------------------------------------------------------------
    // Lap times
    // -----------------------------------------------------------------------
    function GetTopLapTimes(ATrackID, AClassID: Integer;
                            ALimit: Integer = 10): TLapTimeArray;
    function GetFastestLapPerCar(ATrackID, AClassID: Integer): TLapTimeArray;
    function AddLapTime(ATrackID, ACarID: Integer; ALapTimeMs: Int64;
                        const ASessionType: string;
                        ALapDate: TDateTime;
                        const ASourceType: string = '';
                        const ASourceFile: string = '';
                        const ASourceDriver: string = '';
                        const ASourceRowKey: string = ''): Integer;
    function DeleteLapTime(AID: Integer): Boolean;

    // -----------------------------------------------------------------------
    // Telemetry sessions
    // -----------------------------------------------------------------------
    function GetTelemetrySessions: TTelemetrySessionArray;
    function AddTelemetrySession(ATrackID, ACarID: Integer;
                                 const ANotes: string;
                                 ASessionDate: TDateTime): Integer;
    function DeleteTelemetrySession(AID: Integer): Boolean;

    // -----------------------------------------------------------------------
    // Telemetry data points
    // -----------------------------------------------------------------------
    function GetTelemetryData(ASessionID: Integer): TTelemetryDataArray;
    function AddTelemetryDataPoint(ASessionID: Integer;
                                   ATimestampMs: Int64;
                                   ASpeed, ARPM: Double;
                                   AGear: Integer;
                                   AThrottle, ABrake, ASteering,
                                   ALapDistance: Double): Integer;

    property Connection: TFDConnection read FConnection;
    property DatabasePath: string read FDatabasePath;
  end;

implementation

function DateTimeToDBText(const AValue: TDateTime): string;
begin
  Result := FormatDateTime('yyyy-mm-dd hh:nn:ss', AValue);
end;

function TryParseDBDateTime(const S: string; out AValue: TDateTime): Boolean;
var
  FS: TFormatSettings;
  Raw: string;
begin
  Raw := Trim(S);
  AValue := 0;
  if Raw = '' then
    Exit(False);

  FS := TFormatSettings.Create;
  FS.DateSeparator := '-';
  FS.TimeSeparator := ':';
  FS.ShortDateFormat := 'yyyy-mm-dd';
  FS.LongDateFormat := 'yyyy-mm-dd';
  FS.ShortTimeFormat := 'hh:nn:ss';
  FS.LongTimeFormat := 'hh:nn:ss';

  Result :=
    TryStrToDateTime(Raw, AValue, FS) or
    TryStrToDateTime(StringReplace(Raw, 'T', ' ', [rfReplaceAll]), AValue, FS) or
    TryStrToDateTime(Raw, AValue, TFormatSettings.Invariant);
end;

function FieldToDateTime(AField: TField): TDateTime;
var
  Parsed: TDateTime;
  Raw: string;
begin
  Result := 0;
  if (AField = nil) or AField.IsNull then
    Exit;

  Raw := Trim(AField.AsString);
  if TryParseDBDateTime(Raw, Parsed) then
    Result := Parsed;
end;

// ---------------------------------------------------------------------------
// Constructor / Destructor
// ---------------------------------------------------------------------------

constructor TDatabaseManager.Create(const ADatabasePath: string = '');
var
  AppDir: string;
  function EnsureWritableDir(const APath: string): Boolean;
  var
    ProbeFile: string;
    ProbeGuid: string;
  begin
    Result := (APath <> '') and (DirectoryExists(APath) or ForceDirectories(APath));
    if not Result then
      Exit;

    ProbeGuid := GUIDToString(TGUID.NewGuid).Replace('{', '').Replace('}', '');
    ProbeFile := TPath.Combine(APath, '.__lth_dbprobe_' + ProbeGuid + '.tmp');
    try
      TFile.WriteAllText(ProbeFile, 'ok');
      try
        TFile.Delete(ProbeFile);
      except
        // Ignore cleanup failures for the writability probe.
      end;
      Result := True;
    except
      Result := False;
    end;
  end;
begin
  inherited Create;

  if ADatabasePath = '' then
  begin
    AppDir := ExcludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));
    if not EnsureWritableDir(AppDir) then
    begin
      AppDir := TPath.Combine(TPath.GetDocumentsPath, 'LMUTrackHarvester');
      if not EnsureWritableDir(AppDir) then
      begin
        AppDir := TPath.Combine(TPath.GetHomePath, 'LMUTrackHarvester');
        if not EnsureWritableDir(AppDir) then
          raise Exception.CreateFmt(
            'Unable to create application data directory after trying fallback locations. Last attempt: %s',
            [AppDir]
          );
      end;
    end;
    FDatabasePath := TPath.Combine(AppDir, 'data.db');
  end
  else
  begin
    AppDir := ExtractFileDir(ADatabasePath);
    if (AppDir <> '') and (not EnsureWritableDir(AppDir)) then
      raise Exception.CreateFmt('Unable to create database directory: %s', [AppDir]);
    FDatabasePath := ADatabasePath;
  end;

  FConnection := TFDConnection.Create(nil);
  FConnection.DriverName := 'SQLite';
  FConnection.Params.Add('Database=' + FDatabasePath);
  FConnection.Params.Add('OpenMode=CreateUTF8');
  FConnection.Params.Add('LockingMode=Normal');
  FConnection.Params.Add('Synchronous=Normal');
  FConnection.LoginPrompt := False;
  FConnection.Connected := True;

  CreateSchema;
  SeedReferenceData;
  NormalizeReferenceData;
end;

destructor TDatabaseManager.Destroy;
begin
  if Assigned(FConnection) then
  begin
    FConnection.Connected := False;
    FConnection.Free;
  end;
  inherited;
end;

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

function TDatabaseManager.LastInsertID: Integer;
var
  Q: TFDQuery;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FConnection;
    Q.SQL.Text := 'SELECT last_insert_rowid()';
    Q.Open;
    Result := Q.Fields[0].AsInteger;
  finally
    Q.Free;
  end;
end;

procedure TDatabaseManager.EnsureColumnExists(const ATableName, AColumnName,
  AColumnDefinition: string);
var
  Q: TFDQuery;
  ColumnName: string;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FConnection;
    Q.SQL.Text := 'PRAGMA table_info(' + ATableName + ')';
    Q.Open;
    while not Q.Eof do
    begin
      ColumnName := Trim(Q.FieldByName('name').AsString);
      if SameText(ColumnName, AColumnName) then
        Exit;
      Q.Next;
    end;
    Q.Close;

    FConnection.ExecSQL(Format('ALTER TABLE %s ADD COLUMN %s %s',
      [ATableName, AColumnName, AColumnDefinition]));
  finally
    Q.Free;
  end;
end;

function TDatabaseManager.EstimateTelemetrySessionLapCount(ASessionID: Integer): Integer;
var
  Q: TFDQuery;
  PreviousLapDistance: Double;
  CurrentLapDistance: Double;
  HasData: Boolean;
begin
  Result := 0;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FConnection;
    Q.SQL.Text :=
      'SELECT LapDistance FROM TelemetryData ' +
      'WHERE SessionID = :SessionID ' +
      'ORDER BY TimestampMs';
    Q.ParamByName('SessionID').AsInteger := ASessionID;
    Q.Open;

    HasData := False;
    PreviousLapDistance := 0;
    while not Q.Eof do
    begin
      CurrentLapDistance := Q.Fields[0].AsFloat;
      if not HasData then
      begin
        HasData := True;
        Result := 1;
      end
      else if (PreviousLapDistance > 0.75) and (CurrentLapDistance < 0.25) then
        Inc(Result);

      PreviousLapDistance := CurrentLapDistance;
      Q.Next;
    end;
  finally
    Q.Free;
  end;
end;

procedure TDatabaseManager.CreateSchema;
begin
  FConnection.ExecSQL(
    'CREATE TABLE IF NOT EXISTS Tracks (' +
    '  ID     INTEGER PRIMARY KEY AUTOINCREMENT,' +
    '  Name   TEXT NOT NULL,' +
    '  Layout TEXT' +
    ')');

  FConnection.ExecSQL(
    'CREATE TABLE IF NOT EXISTS CarClasses (' +
    '  ID   INTEGER PRIMARY KEY AUTOINCREMENT,' +
    '  Name TEXT NOT NULL' +
    ')');

  FConnection.ExecSQL(
    'CREATE TABLE IF NOT EXISTS Cars (' +
    '  ID      INTEGER PRIMARY KEY AUTOINCREMENT,' +
    '  Name    TEXT NOT NULL,' +
    '  ClassID INTEGER NOT NULL,' +
    '  FOREIGN KEY (ClassID) REFERENCES CarClasses(ID)' +
    ')');

  FConnection.ExecSQL(
    'CREATE TABLE IF NOT EXISTS LapTimes (' +
    '  ID          INTEGER PRIMARY KEY AUTOINCREMENT,' +
    '  TrackID     INTEGER NOT NULL,' +
    '  CarID       INTEGER NOT NULL,' +
    '  LapTimeMs   INTEGER NOT NULL,' +
    '  LapDate     TEXT    NOT NULL,' +
    '  SessionType TEXT,' +
    '  SourceType  TEXT,' +
    '  SourceFile  TEXT,' +
    '  SourceDriver TEXT,' +
    '  SourceRowKey TEXT,' +
    '  FOREIGN KEY (TrackID) REFERENCES Tracks(ID),' +
    '  FOREIGN KEY (CarID)   REFERENCES Cars(ID)' +
    ')');

  EnsureColumnExists('LapTimes', 'SourceType', 'TEXT');
  EnsureColumnExists('LapTimes', 'SourceFile', 'TEXT');
  EnsureColumnExists('LapTimes', 'SourceDriver', 'TEXT');
  EnsureColumnExists('LapTimes', 'SourceRowKey', 'TEXT');

  FConnection.ExecSQL(
    'CREATE TABLE IF NOT EXISTS ResultImportFiles (' +
    '  FilePath       TEXT NOT NULL,' +
    '  DriverName     TEXT NOT NULL,' +
    '  FileModified   TEXT NOT NULL,' +
    '  ImportVersion  INTEGER NOT NULL,' +
    '  LastImportedAt TEXT NOT NULL,' +
    '  PRIMARY KEY (FilePath, DriverName)' +
    ')');

  FConnection.ExecSQL(
    'CREATE TABLE IF NOT EXISTS TelemetrySessions (' +
    '  ID          INTEGER PRIMARY KEY AUTOINCREMENT,' +
    '  TrackID     INTEGER,' +
    '  CarID       INTEGER,' +
    '  SessionDate TEXT NOT NULL,' +
    '  Notes       TEXT,' +
    '  FOREIGN KEY (TrackID) REFERENCES Tracks(ID),' +
    '  FOREIGN KEY (CarID)   REFERENCES Cars(ID)' +
    ')');

  FConnection.ExecSQL(
    'CREATE TABLE IF NOT EXISTS TelemetryData (' +
    '  ID          INTEGER PRIMARY KEY AUTOINCREMENT,' +
    '  SessionID   INTEGER NOT NULL,' +
    '  TimestampMs INTEGER NOT NULL,' +
    '  Speed       REAL,' +
    '  RPM         REAL,' +
    '  Gear        INTEGER,' +
    '  Throttle    REAL,' +
    '  Brake       REAL,' +
    '  Steering    REAL,' +
    '  LapDistance REAL,' +
    '  FOREIGN KEY (SessionID) REFERENCES TelemetrySessions(ID)' +
    ')');

  // Index for fast lap-time lookups
  FConnection.ExecSQL(
    'CREATE INDEX IF NOT EXISTS idx_laptimes_track_car ' +
    'ON LapTimes (TrackID, CarID)');

  FConnection.ExecSQL(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_laptimes_source_unique ' +
    'ON LapTimes (SourceType, SourceRowKey) ' +
    'WHERE SourceType IS NOT NULL AND SourceRowKey IS NOT NULL ' +
    '  AND SourceType <> '''' AND SourceRowKey <> ''''');

  // Index for telemetry data lookups
  FConnection.ExecSQL(
    'CREATE INDEX IF NOT EXISTS idx_teldata_session ' +
    'ON TelemetryData (SessionID, TimestampMs)');
end;

procedure TDatabaseManager.SeedReferenceData;
var
  Q: TFDQuery;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FConnection;
    Q.SQL.Text := 'SELECT COUNT(*) FROM Tracks';
    Q.Open;
    if Q.Fields[0].AsInteger > 0 then
      Exit; // Already seeded
    Q.Close;

    // ----- Tracks (WEC 2024 calendar circuits) -----
    FConnection.ExecSQL('INSERT INTO Tracks (Name, Layout) VALUES (''Circuit de la Sarthe'', ''Full Circuit'')');
    FConnection.ExecSQL('INSERT INTO Tracks (Name, Layout) VALUES (''Circuit de la Sarthe'', ''Bugatti Circuit'')');
    FConnection.ExecSQL('INSERT INTO Tracks (Name, Layout) VALUES (''Autodromo Nazionale Monza'', ''Full Circuit'')');
    FConnection.ExecSQL('INSERT INTO Tracks (Name, Layout) VALUES (''Circuit de Spa-Francorchamps'', ''Full Circuit'')');
    FConnection.ExecSQL('INSERT INTO Tracks (Name, Layout) VALUES (''Fuji Speedway'', ''Full Circuit'')');
    FConnection.ExecSQL('INSERT INTO Tracks (Name, Layout) VALUES (''Bahrain International Circuit'', ''Full Circuit'')');
    FConnection.ExecSQL('INSERT INTO Tracks (Name, Layout) VALUES (''Autodromo Internacional do Algarve (Portimao)'', ''Full Circuit'')');
    FConnection.ExecSQL('INSERT INTO Tracks (Name, Layout) VALUES (''Sebring International Raceway'', ''Full Circuit'')');
    FConnection.ExecSQL('INSERT INTO Tracks (Name, Layout) VALUES (''Road Atlanta'', ''Full Circuit'')');
    FConnection.ExecSQL('INSERT INTO Tracks (Name, Layout) VALUES (''Lusail International Circuit'', ''Full Circuit'')');
    FConnection.ExecSQL('INSERT INTO Tracks (Name, Layout) VALUES (''Autodromo Jose Carlos Pace (Interlagos)'', ''Full Circuit'')');
    FConnection.ExecSQL('INSERT INTO Tracks (Name, Layout) VALUES (''Autodromo Enzo e Dino Ferrari (Imola)'', ''Full Circuit'')');
    FConnection.ExecSQL('INSERT INTO Tracks (Name, Layout) VALUES (''Yas Marina Circuit'', ''Full Circuit'')');
    FConnection.ExecSQL('INSERT INTO Tracks (Name, Layout) VALUES (''Circuit de Catalunya'', ''Full Circuit'')');
    FConnection.ExecSQL('INSERT INTO Tracks (Name, Layout) VALUES (''Circuit de Ledenon'', ''Full Circuit'')');

    // ----- Car Classes -----
    FConnection.ExecSQL('INSERT INTO CarClasses (Name) VALUES (''Hypercar'')');
    FConnection.ExecSQL('INSERT INTO CarClasses (Name) VALUES (''LMP2'')');
    FConnection.ExecSQL('INSERT INTO CarClasses (Name) VALUES (''LMGT3'')');

    // ----- Hypercars (ClassID = 1) -----
    FConnection.ExecSQL('INSERT INTO Cars (Name, ClassID) VALUES (''Ferrari 499P'', 1)');
    FConnection.ExecSQL('INSERT INTO Cars (Name, ClassID) VALUES (''Toyota GR010 Hybrid'', 1)');
    FConnection.ExecSQL('INSERT INTO Cars (Name, ClassID) VALUES (''Porsche 963'', 1)');
    FConnection.ExecSQL('INSERT INTO Cars (Name, ClassID) VALUES (''Cadillac V-Series.R'', 1)');
    FConnection.ExecSQL('INSERT INTO Cars (Name, ClassID) VALUES (''BMW M Hybrid V8'', 1)');
    FConnection.ExecSQL('INSERT INTO Cars (Name, ClassID) VALUES (''Peugeot 9X8'', 1)');
    FConnection.ExecSQL('INSERT INTO Cars (Name, ClassID) VALUES (''Alpine A424'', 1)');
    FConnection.ExecSQL('INSERT INTO Cars (Name, ClassID) VALUES (''Lamborghini SC63'', 1)');
    FConnection.ExecSQL('INSERT INTO Cars (Name, ClassID) VALUES (''Isotta Fraschini Tipo6 Competizione'', 1)');
    FConnection.ExecSQL('INSERT INTO Cars (Name, ClassID) VALUES (''Acura ARX-06'', 1)');

    // ----- LMP2 (ClassID = 2) -----
    FConnection.ExecSQL('INSERT INTO Cars (Name, ClassID) VALUES (''ORECA 07 - Gibson'', 2)');

    // ----- LMGT3 (ClassID = 3) -----
    FConnection.ExecSQL('INSERT INTO Cars (Name, ClassID) VALUES (''Ferrari 296 GT3'', 3)');
    FConnection.ExecSQL('INSERT INTO Cars (Name, ClassID) VALUES (''Porsche 911 GT3 R (992)'', 3)');
    FConnection.ExecSQL('INSERT INTO Cars (Name, ClassID) VALUES (''BMW M4 GT3'', 3)');
    FConnection.ExecSQL('INSERT INTO Cars (Name, ClassID) VALUES (''Aston Martin Vantage AMR GT3'', 3)');
    FConnection.ExecSQL('INSERT INTO Cars (Name, ClassID) VALUES (''Ford Mustang GT3'', 3)');
    FConnection.ExecSQL('INSERT INTO Cars (Name, ClassID) VALUES (''McLaren 720S GT3 EVO'', 3)');
    FConnection.ExecSQL('INSERT INTO Cars (Name, ClassID) VALUES (''Lamborghini Huracan GT3 EVO2'', 3)');
    FConnection.ExecSQL('INSERT INTO Cars (Name, ClassID) VALUES (''Corvette Z06 GT3.R'', 3)');
    FConnection.ExecSQL('INSERT INTO Cars (Name, ClassID) VALUES (''Lexus RC F GT3'', 3)');
    FConnection.ExecSQL('INSERT INTO Cars (Name, ClassID) VALUES (''Mercedes-AMG GT3 EVO'', 3)');
  finally
    Q.Free;
  end;
end;

procedure TDatabaseManager.NormalizeReferenceData;
begin
  FConnection.ExecSQL(
    'UPDATE Tracks SET Name = ''Autodromo Internacional do Algarve (Portimao)'' WHERE ID = 7');
  FConnection.ExecSQL(
    'UPDATE Tracks SET Name = ''Autodromo Jose Carlos Pace (Interlagos)'' WHERE ID = 11');
  FConnection.ExecSQL(
    'UPDATE Tracks SET Name = ''Circuit de Ledenon'' WHERE ID = 15');
  FConnection.ExecSQL(
    'UPDATE Cars SET Name = ''ORECA 07 - Gibson'' WHERE ID = 11');
  FConnection.ExecSQL(
    'UPDATE Cars SET Name = ''Lamborghini Huracan GT3 EVO2'' WHERE ID = 18');
end;

// ---------------------------------------------------------------------------
// Tracks
// ---------------------------------------------------------------------------

function TDatabaseManager.GetTracks: TTrackArray;
var
  Q: TFDQuery;
  Count: Integer;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FConnection;
    Q.SQL.Text := 'SELECT ID, Name, Layout FROM Tracks ORDER BY Name, Layout';
    Q.Open;
    SetLength(Result, 0);
    Count := 0;
    while not Q.Eof do
    begin
      SetLength(Result, Count + 1);
      Result[Count].ID     := Q.FieldByName('ID').AsInteger;
      Result[Count].Name   := Q.FieldByName('Name').AsString;
      Result[Count].Layout := Q.FieldByName('Layout').AsString;
      Inc(Count);
      Q.Next;
    end;
  finally
    Q.Free;
  end;
end;

function TDatabaseManager.AddTrack(const AName, ALayout: string): Integer;
var
  Q: TFDQuery;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FConnection;
    Q.SQL.Text := 'INSERT INTO Tracks (Name, Layout) VALUES (:Name, :Layout)';
    Q.ParamByName('Name').AsString   := AName;
    Q.ParamByName('Layout').AsString := ALayout;
    Q.ExecSQL;
    Result := LastInsertID;
  finally
    Q.Free;
  end;
end;

function TDatabaseManager.DeleteTrack(AID: Integer): Boolean;
var
  Q: TFDQuery;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FConnection;
    Q.SQL.Text := 'DELETE FROM Tracks WHERE ID = :ID';
    Q.ParamByName('ID').AsInteger := AID;
    Q.ExecSQL;
    Result := True;
  except
    Result := False;
  end;
  Q.Free;
end;

// ---------------------------------------------------------------------------
// Car Classes
// ---------------------------------------------------------------------------

function TDatabaseManager.GetCarClasses: TCarClassArray;
var
  Q: TFDQuery;
  Count: Integer;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FConnection;
    Q.SQL.Text := 'SELECT ID, Name FROM CarClasses ORDER BY Name';
    Q.Open;
    SetLength(Result, 0);
    Count := 0;
    while not Q.Eof do
    begin
      SetLength(Result, Count + 1);
      Result[Count].ID   := Q.FieldByName('ID').AsInteger;
      Result[Count].Name := Q.FieldByName('Name').AsString;
      Inc(Count);
      Q.Next;
    end;
  finally
    Q.Free;
  end;
end;

function TDatabaseManager.AddCarClass(const AName: string): Integer;
var
  Q: TFDQuery;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FConnection;
    Q.SQL.Text := 'INSERT INTO CarClasses (Name) VALUES (:Name)';
    Q.ParamByName('Name').AsString := AName;
    Q.ExecSQL;
    Result := LastInsertID;
  finally
    Q.Free;
  end;
end;

// ---------------------------------------------------------------------------
// Cars
// ---------------------------------------------------------------------------

function TDatabaseManager.GetCars(AClassID: Integer = -1): TCarArray;
var
  Q: TFDQuery;
  Count: Integer;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FConnection;
    if AClassID = -1 then
    begin
      Q.SQL.Text :=
        'SELECT c.ID, c.Name, c.ClassID, cc.Name AS ClassName ' +
        'FROM Cars c LEFT JOIN CarClasses cc ON cc.ID = c.ClassID ' +
        'ORDER BY cc.Name, c.Name';
    end
    else
    begin
      Q.SQL.Text :=
        'SELECT c.ID, c.Name, c.ClassID, cc.Name AS ClassName ' +
        'FROM Cars c LEFT JOIN CarClasses cc ON cc.ID = c.ClassID ' +
        'WHERE c.ClassID = :ClassID ' +
        'ORDER BY c.Name';
      Q.ParamByName('ClassID').AsInteger := AClassID;
    end;
    Q.Open;
    SetLength(Result, 0);
    Count := 0;
    while not Q.Eof do
    begin
      SetLength(Result, Count + 1);
      Result[Count].ID        := Q.FieldByName('ID').AsInteger;
      Result[Count].Name      := Q.FieldByName('Name').AsString;
      Result[Count].ClassID   := Q.FieldByName('ClassID').AsInteger;
      Result[Count].ClassName := Q.FieldByName('ClassName').AsString;
      Inc(Count);
      Q.Next;
    end;
  finally
    Q.Free;
  end;
end;

function TDatabaseManager.AddCar(const AName: string; AClassID: Integer): Integer;
var
  Q: TFDQuery;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FConnection;
    Q.SQL.Text :=
      'INSERT INTO Cars (Name, ClassID) VALUES (:Name, :ClassID)';
    Q.ParamByName('Name').AsString     := AName;
    Q.ParamByName('ClassID').AsInteger := AClassID;
    Q.ExecSQL;
    Result := LastInsertID;
  finally
    Q.Free;
  end;
end;

// ---------------------------------------------------------------------------
// Lap Times
// ---------------------------------------------------------------------------

function TDatabaseManager.GetTopLapTimes(ATrackID, AClassID: Integer;
  ALimit: Integer = 10): TLapTimeArray;
var
  Q: TFDQuery;
  Count: Integer;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FConnection;
    Q.SQL.Text :=
      'SELECT lt.ID, lt.TrackID, t.Name AS TrackName, t.Layout AS TrackLayout,' +
      '       lt.CarID, c.Name AS CarName, c.ClassID, cc.Name AS ClassName,' +
      '       lt.LapTimeMs, lt.LapDate, lt.SessionType ' +
      'FROM LapTimes lt ' +
      'JOIN Tracks t     ON t.ID  = lt.TrackID ' +
      'JOIN Cars c       ON c.ID  = lt.CarID ' +
      'LEFT JOIN CarClasses cc ON cc.ID = c.ClassID ' +
      'WHERE lt.TrackID = :TrackID AND c.ClassID = :ClassID ' +
      'ORDER BY lt.LapTimeMs ASC ' +
      'LIMIT :Lim';
    Q.ParamByName('TrackID').AsInteger := ATrackID;
    Q.ParamByName('ClassID').AsInteger := AClassID;
    Q.ParamByName('Lim').AsInteger     := ALimit;
    Q.Open;

    SetLength(Result, 0);
    Count := 0;
    while not Q.Eof do
    begin
      SetLength(Result, Count + 1);
      Result[Count].ID          := Q.FieldByName('ID').AsInteger;
      Result[Count].TrackID     := Q.FieldByName('TrackID').AsInteger;
      Result[Count].TrackName   := Q.FieldByName('TrackName').AsString;
      Result[Count].TrackLayout := Q.FieldByName('TrackLayout').AsString;
      Result[Count].CarID       := Q.FieldByName('CarID').AsInteger;
      Result[Count].CarName     := Q.FieldByName('CarName').AsString;
      Result[Count].ClassID     := Q.FieldByName('ClassID').AsInteger;
      Result[Count].ClassName   := Q.FieldByName('ClassName').AsString;
      Result[Count].LapTimeMs   := Q.FieldByName('LapTimeMs').AsLargeInt;
      Result[Count].LapDate     := FieldToDateTime(Q.FieldByName('LapDate'));
      Result[Count].SessionType := Q.FieldByName('SessionType').AsString;
      Inc(Count);
      Q.Next;
    end;
  finally
    Q.Free;
  end;
end;

function TDatabaseManager.GetFastestLapPerCar(ATrackID, AClassID: Integer): TLapTimeArray;
var
  Q: TFDQuery;
  Count: Integer;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FConnection;
    Q.SQL.Text :=
      'SELECT lt.CarID, c.Name AS CarName, c.ClassID, cc.Name AS ClassName,' +
      '       lt.LapTimeMs, lt.LapDate, lt.SessionType,' +
      '       lt.ID, lt.TrackID, t.Name AS TrackName, t.Layout AS TrackLayout ' +
      'FROM LapTimes lt ' +
      'JOIN Tracks t     ON t.ID  = lt.TrackID ' +
      'JOIN Cars c       ON c.ID  = lt.CarID ' +
      'LEFT JOIN CarClasses cc ON cc.ID = c.ClassID ' +
      'JOIN (' +
      '  SELECT lt2.CarID, MIN(lt2.LapTimeMs) AS MinLapTime ' +
      '  FROM LapTimes lt2 ' +
      '  JOIN Cars c2 ON c2.ID = lt2.CarID ' +
      '  WHERE lt2.TrackID = :TrackID AND c2.ClassID = :ClassID ' +
      '  GROUP BY lt2.CarID' +
      ') best ON best.CarID = lt.CarID AND best.MinLapTime = lt.LapTimeMs ' +
      'WHERE lt.TrackID = :TrackID AND c.ClassID = :ClassID ' +
      'GROUP BY lt.CarID ' +
      'ORDER BY lt.LapTimeMs ASC';
    Q.ParamByName('TrackID').AsInteger := ATrackID;
    Q.ParamByName('ClassID').AsInteger := AClassID;
    Q.Open;

    SetLength(Result, 0);
    Count := 0;
    while not Q.Eof do
    begin
      SetLength(Result, Count + 1);
      Result[Count].ID          := Q.FieldByName('ID').AsInteger;
      Result[Count].TrackID     := Q.FieldByName('TrackID').AsInteger;
      Result[Count].TrackName   := Q.FieldByName('TrackName').AsString;
      Result[Count].TrackLayout := Q.FieldByName('TrackLayout').AsString;
      Result[Count].CarID       := Q.FieldByName('CarID').AsInteger;
      Result[Count].CarName     := Q.FieldByName('CarName').AsString;
      Result[Count].ClassID     := Q.FieldByName('ClassID').AsInteger;
      Result[Count].ClassName   := Q.FieldByName('ClassName').AsString;
      Result[Count].LapTimeMs   := Q.FieldByName('LapTimeMs').AsLargeInt;
      Result[Count].LapDate     := FieldToDateTime(Q.FieldByName('LapDate'));
      Result[Count].SessionType := Q.FieldByName('SessionType').AsString;
      Inc(Count);
      Q.Next;
    end;
  finally
    Q.Free;
  end;
end;

function TDatabaseManager.AddLapTime(ATrackID, ACarID: Integer; ALapTimeMs: Int64;
  const ASessionType: string; ALapDate: TDateTime;
  const ASourceType: string = ''; const ASourceFile: string = '';
  const ASourceDriver: string = ''; const ASourceRowKey: string = ''): Integer;
var
  Q: TFDQuery;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FConnection;
    Q.SQL.Text :=
      'INSERT INTO LapTimes (' +
      '  TrackID, CarID, LapTimeMs, LapDate, SessionType, SourceType, SourceFile, SourceDriver, SourceRowKey' +
      ') VALUES (' +
      '  :TrackID, :CarID, :LapTimeMs, :LapDate, :SessionType, :SourceType, :SourceFile, :SourceDriver, :SourceRowKey' +
      ')';
    Q.ParamByName('TrackID').AsInteger     := ATrackID;
    Q.ParamByName('CarID').AsInteger       := ACarID;
    Q.ParamByName('LapTimeMs').AsLargeInt  := ALapTimeMs;
    Q.ParamByName('LapDate').AsString      := DateTimeToDBText(ALapDate);
    Q.ParamByName('SessionType').AsString  := ASessionType;
    Q.ParamByName('SourceType').AsString   := ASourceType;
    Q.ParamByName('SourceFile').AsString   := ASourceFile;
    Q.ParamByName('SourceDriver').AsString := ASourceDriver;
    Q.ParamByName('SourceRowKey').AsString := ASourceRowKey;
    Q.ExecSQL;
    Result := LastInsertID;
  finally
    Q.Free;
  end;
end;

function TDatabaseManager.DeleteLapTime(AID: Integer): Boolean;
var
  Q: TFDQuery;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FConnection;
    Q.SQL.Text := 'DELETE FROM LapTimes WHERE ID = :ID';
    Q.ParamByName('ID').AsInteger := AID;
    Q.ExecSQL;
    Result := True;
  except
    Result := False;
  end;
  Q.Free;
end;

// ---------------------------------------------------------------------------
// Telemetry Sessions
// ---------------------------------------------------------------------------

function TDatabaseManager.GetTelemetrySessions: TTelemetrySessionArray;
var
  Q: TFDQuery;
  Count: Integer;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FConnection;
    Q.SQL.Text :=
      'SELECT ts.ID, ts.TrackID, t.Name AS TrackName, t.Layout AS TrackLayout,' +
      '       ts.CarID, c.Name AS CarName, ts.SessionDate, ts.Notes,' +
      '       (SELECT COUNT(*) FROM TelemetryData td WHERE td.SessionID = ts.ID)' +
      '         AS DataPointCount,' +
      '       COALESCE((SELECT MAX(td.TimestampMs) - MIN(td.TimestampMs) ' +
      '                 FROM TelemetryData td WHERE td.SessionID = ts.ID), 0)' +
      '         AS DurationMs ' +
      'FROM TelemetrySessions ts ' +
      'LEFT JOIN Tracks t ON t.ID = ts.TrackID ' +
      'LEFT JOIN Cars   c ON c.ID = ts.CarID ' +
      'ORDER BY ts.SessionDate DESC';
    Q.Open;

    SetLength(Result, 0);
    Count := 0;
    while not Q.Eof do
    begin
      SetLength(Result, Count + 1);
      Result[Count].ID             := Q.FieldByName('ID').AsInteger;
      Result[Count].TrackID        := Q.FieldByName('TrackID').AsInteger;
      Result[Count].TrackName      := Q.FieldByName('TrackName').AsString;
      Result[Count].TrackLayout    := Q.FieldByName('TrackLayout').AsString;
      Result[Count].CarID          := Q.FieldByName('CarID').AsInteger;
      Result[Count].CarName        := Q.FieldByName('CarName').AsString;
      Result[Count].SessionDate    := FieldToDateTime(Q.FieldByName('SessionDate'));
      Result[Count].Notes          := Q.FieldByName('Notes').AsString;
      Result[Count].DataPointCount := Q.FieldByName('DataPointCount').AsInteger;
      Result[Count].DurationMs     := Q.FieldByName('DurationMs').AsLargeInt;
      Result[Count].EstimatedLaps  := EstimateTelemetrySessionLapCount(Result[Count].ID);
      Inc(Count);
      Q.Next;
    end;
  finally
    Q.Free;
  end;
end;

function TDatabaseManager.AddTelemetrySession(ATrackID, ACarID: Integer;
  const ANotes: string; ASessionDate: TDateTime): Integer;
var
  Q: TFDQuery;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FConnection;
    Q.SQL.Text :=
      'INSERT INTO TelemetrySessions (TrackID, CarID, SessionDate, Notes) ' +
      'VALUES (:TrackID, :CarID, :SessionDate, :Notes)';
    Q.ParamByName('TrackID').AsInteger    := ATrackID;
    Q.ParamByName('CarID').AsInteger      := ACarID;
    Q.ParamByName('SessionDate').AsString  := DateTimeToDBText(ASessionDate);
    Q.ParamByName('Notes').AsString       := ANotes;
    Q.ExecSQL;
    Result := LastInsertID;
  finally
    Q.Free;
  end;
end;

function TDatabaseManager.DeleteTelemetrySession(AID: Integer): Boolean;
var
  Q: TFDQuery;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FConnection;
    Q.SQL.Text := 'DELETE FROM TelemetryData WHERE SessionID = :ID';
    Q.ParamByName('ID').AsInteger := AID;
    Q.ExecSQL;
    Q.SQL.Text := 'DELETE FROM TelemetrySessions WHERE ID = :ID';
    Q.ParamByName('ID').AsInteger := AID;
    Q.ExecSQL;
    Result := True;
  except
    Result := False;
  end;
  Q.Free;
end;

// ---------------------------------------------------------------------------
// Telemetry Data Points
// ---------------------------------------------------------------------------

function TDatabaseManager.GetTelemetryData(ASessionID: Integer): TTelemetryDataArray;
var
  Q: TFDQuery;
  Count: Integer;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FConnection;
    Q.SQL.Text :=
      'SELECT ID, SessionID, TimestampMs, Speed, RPM, Gear, ' +
      '       Throttle, Brake, Steering, LapDistance ' +
      'FROM TelemetryData ' +
      'WHERE SessionID = :SessionID ' +
      'ORDER BY TimestampMs ASC';
    Q.ParamByName('SessionID').AsInteger := ASessionID;
    Q.Open;

    SetLength(Result, 0);
    Count := 0;
    while not Q.Eof do
    begin
      SetLength(Result, Count + 1);
      Result[Count].ID          := Q.FieldByName('ID').AsInteger;
      Result[Count].SessionID   := Q.FieldByName('SessionID').AsInteger;
      Result[Count].TimestampMs := Q.FieldByName('TimestampMs').AsLargeInt;
      Result[Count].Speed       := Q.FieldByName('Speed').AsFloat;
      Result[Count].RPM         := Q.FieldByName('RPM').AsFloat;
      Result[Count].Gear        := Q.FieldByName('Gear').AsInteger;
      Result[Count].Throttle    := Q.FieldByName('Throttle').AsFloat;
      Result[Count].Brake       := Q.FieldByName('Brake').AsFloat;
      Result[Count].Steering    := Q.FieldByName('Steering').AsFloat;
      Result[Count].LapDistance := Q.FieldByName('LapDistance').AsFloat;
      Inc(Count);
      Q.Next;
    end;
  finally
    Q.Free;
  end;
end;

function TDatabaseManager.AddTelemetryDataPoint(ASessionID: Integer;
  ATimestampMs: Int64; ASpeed, ARPM: Double; AGear: Integer;
  AThrottle, ABrake, ASteering, ALapDistance: Double): Integer;
var
  Q: TFDQuery;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FConnection;
    Q.SQL.Text :=
      'INSERT INTO TelemetryData ' +
      '  (SessionID, TimestampMs, Speed, RPM, Gear, Throttle, Brake, Steering, LapDistance) ' +
      'VALUES ' +
      '  (:SessionID, :TimestampMs, :Speed, :RPM, :Gear, :Throttle, :Brake, :Steering, :LapDistance)';
    Q.ParamByName('SessionID').AsInteger    := ASessionID;
    Q.ParamByName('TimestampMs').AsLargeInt := ATimestampMs;
    Q.ParamByName('Speed').AsFloat          := ASpeed;
    Q.ParamByName('RPM').AsFloat            := ARPM;
    Q.ParamByName('Gear').AsInteger         := AGear;
    Q.ParamByName('Throttle').AsFloat       := AThrottle;
    Q.ParamByName('Brake').AsFloat          := ABrake;
    Q.ParamByName('Steering').AsFloat       := ASteering;
    Q.ParamByName('LapDistance').AsFloat    := ALapDistance;
    Q.ExecSQL;
    Result := LastInsertID;
  finally
    Q.Free;
  end;
end;

end.
