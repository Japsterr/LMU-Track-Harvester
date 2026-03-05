unit DatabaseManager;

{ SQLite data-access layer using FireDAC.
  All database objects are stored in %DOCUMENTS%\LMUTrackHarvester\data.db

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
  System.SysUtils, System.Classes, System.IOUtils,
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
    procedure SeedReferenceData;
    function LastInsertID: Integer;
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
                        ALapDate: TDateTime): Integer;
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

// ---------------------------------------------------------------------------
// Constructor / Destructor
// ---------------------------------------------------------------------------

constructor TDatabaseManager.Create(const ADatabasePath: string = '');
var
  AppDir: string;
begin
  inherited Create;

  if ADatabasePath = '' then
  begin
    AppDir := TPath.Combine(TPath.GetDocumentsPath, 'LMUTrackHarvester');
    ForceDirectories(AppDir);
    FDatabasePath := TPath.Combine(AppDir, 'data.db');
  end
  else
    FDatabasePath := ADatabasePath;

  FConnection := TFDConnection.Create(nil);
  FConnection.DriverName := 'SQLite';
  FConnection.Params.Add('Database=' + FDatabasePath);
  FConnection.Params.Add('LockingMode=Normal');
  FConnection.Params.Add('Synchronous=Normal');
  FConnection.LoginPrompt := False;
  FConnection.Connected := True;

  CreateSchema;
  SeedReferenceData;
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
    '  FOREIGN KEY (TrackID) REFERENCES Tracks(ID),' +
    '  FOREIGN KEY (CarID)   REFERENCES Cars(ID)' +
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
    FConnection.ExecSQL('INSERT INTO Tracks (Name, Layout) VALUES (''Autódromo Internacional do Algarve (Portimão)'', ''Full Circuit'')');
    FConnection.ExecSQL('INSERT INTO Tracks (Name, Layout) VALUES (''Sebring International Raceway'', ''Full Circuit'')');
    FConnection.ExecSQL('INSERT INTO Tracks (Name, Layout) VALUES (''Road Atlanta'', ''Full Circuit'')');
    FConnection.ExecSQL('INSERT INTO Tracks (Name, Layout) VALUES (''Lusail International Circuit'', ''Full Circuit'')');
    FConnection.ExecSQL('INSERT INTO Tracks (Name, Layout) VALUES (''Autódromo José Carlos Pace (Interlagos)'', ''Full Circuit'')');
    FConnection.ExecSQL('INSERT INTO Tracks (Name, Layout) VALUES (''Autodromo Enzo e Dino Ferrari (Imola)'', ''Full Circuit'')');
    FConnection.ExecSQL('INSERT INTO Tracks (Name, Layout) VALUES (''Yas Marina Circuit'', ''Full Circuit'')');
    FConnection.ExecSQL('INSERT INTO Tracks (Name, Layout) VALUES (''Circuit de Catalunya'', ''Full Circuit'')');
    FConnection.ExecSQL('INSERT INTO Tracks (Name, Layout) VALUES (''Circuit de Lédenon'', ''Full Circuit'')');

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
    FConnection.ExecSQL('INSERT INTO Cars (Name, ClassID) VALUES (''ORECA 07 – Gibson'', 2)');

    // ----- LMGT3 (ClassID = 3) -----
    FConnection.ExecSQL('INSERT INTO Cars (Name, ClassID) VALUES (''Ferrari 296 GT3'', 3)');
    FConnection.ExecSQL('INSERT INTO Cars (Name, ClassID) VALUES (''Porsche 911 GT3 R (992)'', 3)');
    FConnection.ExecSQL('INSERT INTO Cars (Name, ClassID) VALUES (''BMW M4 GT3'', 3)');
    FConnection.ExecSQL('INSERT INTO Cars (Name, ClassID) VALUES (''Aston Martin Vantage AMR GT3'', 3)');
    FConnection.ExecSQL('INSERT INTO Cars (Name, ClassID) VALUES (''Ford Mustang GT3'', 3)');
    FConnection.ExecSQL('INSERT INTO Cars (Name, ClassID) VALUES (''McLaren 720S GT3 EVO'', 3)');
    FConnection.ExecSQL('INSERT INTO Cars (Name, ClassID) VALUES (''Lamborghini Huracán GT3 EVO2'', 3)');
    FConnection.ExecSQL('INSERT INTO Cars (Name, ClassID) VALUES (''Corvette Z06 GT3.R'', 3)');
    FConnection.ExecSQL('INSERT INTO Cars (Name, ClassID) VALUES (''Lexus RC F GT3'', 3)');
    FConnection.ExecSQL('INSERT INTO Cars (Name, ClassID) VALUES (''Mercedes-AMG GT3 EVO'', 3)');
  finally
    Q.Free;
  end;
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
      Result[Count].LapDate     := Q.FieldByName('LapDate').AsDateTime;
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
      '       MIN(lt.LapTimeMs) AS LapTimeMs, lt.LapDate, lt.SessionType,' +
      '       lt.ID, lt.TrackID, t.Name AS TrackName, t.Layout AS TrackLayout ' +
      'FROM LapTimes lt ' +
      'JOIN Tracks t     ON t.ID  = lt.TrackID ' +
      'JOIN Cars c       ON c.ID  = lt.CarID ' +
      'LEFT JOIN CarClasses cc ON cc.ID = c.ClassID ' +
      'WHERE lt.TrackID = :TrackID AND c.ClassID = :ClassID ' +
      'GROUP BY lt.CarID ' +
      'ORDER BY LapTimeMs ASC';
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
      Result[Count].LapDate     := Q.FieldByName('LapDate').AsDateTime;
      Result[Count].SessionType := Q.FieldByName('SessionType').AsString;
      Inc(Count);
      Q.Next;
    end;
  finally
    Q.Free;
  end;
end;

function TDatabaseManager.AddLapTime(ATrackID, ACarID: Integer; ALapTimeMs: Int64;
  const ASessionType: string; ALapDate: TDateTime): Integer;
var
  Q: TFDQuery;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FConnection;
    Q.SQL.Text :=
      'INSERT INTO LapTimes (TrackID, CarID, LapTimeMs, LapDate, SessionType) ' +
      'VALUES (:TrackID, :CarID, :LapTimeMs, :LapDate, :SessionType)';
    Q.ParamByName('TrackID').AsInteger     := ATrackID;
    Q.ParamByName('CarID').AsInteger       := ACarID;
    Q.ParamByName('LapTimeMs').AsLargeInt  := ALapTimeMs;
    Q.ParamByName('LapDate').AsDateTime    := ALapDate;
    Q.ParamByName('SessionType').AsString  := ASessionType;
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
      '         AS DataPointCount ' +
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
      Result[Count].SessionDate    := Q.FieldByName('SessionDate').AsDateTime;
      Result[Count].Notes          := Q.FieldByName('Notes').AsString;
      Result[Count].DataPointCount := Q.FieldByName('DataPointCount').AsInteger;
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
    Q.ParamByName('SessionDate').AsDateTime := ASessionDate;
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
