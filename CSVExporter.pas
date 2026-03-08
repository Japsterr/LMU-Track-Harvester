unit CSVExporter;

{ Exports telemetry and lap-time data to CSV files.
  Telemetry CSV format:
    TimestampMs, Speed_kmh, RPM, Gear, Throttle_pct, Brake_pct, Steering_pct,
    LapDistance_pct
  Lap-time CSV format:
    Rank, Track, Layout, Car, Class, LapTime, LapDate, SessionType
}

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Math,
  LapTimeModels, DatabaseManager, DuckDBNative;

type
  TCSVExporter = class
  public
    { Parse canonical telemetry CSV text into telemetry data points. }
    class function ParseTelemetryCSVData(const ACSVData: string): TTelemetryDataArray;

    { Export all telemetry data points for a session to a CSV file. }
    class function ExportTelemetrySession(ADB: TDatabaseManager;
                                          ASessionID: Integer;
                                          const AFilePath: string): Boolean;

    { Returns the telemetry CSV content as a string (used for AI upload). }
    class function TelemetrySessionToCSV(ADB: TDatabaseManager;
                                         ASessionID: Integer): string;

    { Export an LMU DuckDB telemetry source file to CSV via the bundled DuckDB runtime. }
    class function ExportDuckDBSourceToCSV(const ASourcePath,
      AFilePath: string; out AError: string): Boolean;

    { Read a bounded telemetry preview from an LMU DuckDB telemetry file without full export. }
    class function LoadDuckDBPreviewCSV(const ASourcePath: string;
      out ACSVData, AError: string): Boolean;

    { Read a metadata value from an LMU DuckDB telemetry file via the bundled DuckDB runtime. }
    class function ReadDuckDBMetadataValue(const ASourcePath, AMetadataKey: string;
      out AValue, AError: string): Boolean;

    { Export top-N lap times for a specific track + car class. }
    class function ExportLapTimes(ADB: TDatabaseManager;
                                  ATrackID, AClassID: Integer;
                                  const AFilePath: string;
                                  ALimit: Integer = 100): Boolean;
  private
  end;

implementation

class function TCSVExporter.ParseTelemetryCSVData(
  const ACSVData: string): TTelemetryDataArray;
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

class function TCSVExporter.TelemetrySessionToCSV(ADB: TDatabaseManager;
  ASessionID: Integer): string;
var
  SB: TStringBuilder;
  DataPoints: TTelemetryDataArray;
  I: Integer;
  DP: TTelemetryDataPoint;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine(
      'TimestampMs,Speed_kmh,RPM,Gear,Throttle_pct,Brake_pct,Steering_pct,' +
      'LapDistance_pct');

    DataPoints := ADB.GetTelemetryData(ASessionID);
    for I := 0 to High(DataPoints) do
    begin
      DP := DataPoints[I];
      SB.AppendLine(Format('%d,%.2f,%.0f,%d,%.1f,%.1f,%.1f,%.4f',
        [DP.TimestampMs,
         DP.Speed,
         DP.RPM,
         DP.Gear,
         DP.Throttle    * 100.0,
         DP.Brake       * 100.0,
         DP.Steering    * 100.0,
         DP.LapDistance]));
    end;

    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TCSVExporter.ExportTelemetrySession(ADB: TDatabaseManager;
  ASessionID: Integer; const AFilePath: string): Boolean;
var
  CSVContent: string;
  SL: TStringList;
begin
  Result := False;
  try
    CSVContent := TelemetrySessionToCSV(ADB, ASessionID);
    SL := TStringList.Create;
    try
      SL.Text := CSVContent;
      SL.SaveToFile(AFilePath, TEncoding.UTF8);
      Result := True;
    finally
      SL.Free;
    end;
  except
    on E: Exception do
      ; // Caller will see Result = False
  end;
end;

class function TCSVExporter.ExportLapTimes(ADB: TDatabaseManager;
  ATrackID, AClassID: Integer; const AFilePath: string;
  ALimit: Integer = 100): Boolean;
var
  LapTimes: TLapTimeArray;
  SB: TStringBuilder;
  SL: TStringList;
  I: Integer;
  LT: TLapTime;
begin
  Result := False;
  try
    SB := TStringBuilder.Create;
    SL := TStringList.Create;
    try
      SB.AppendLine('Rank,Track,Layout,Car,Class,LapTime,LapDate,SessionType');

      LapTimes := ADB.GetTopLapTimes(ATrackID, AClassID, ALimit);
      for I := 0 to High(LapTimes) do
      begin
        LT := LapTimes[I];
        SB.AppendLine(Format('%d,"%s","%s","%s","%s","%s","%s","%s"',
          [I + 1,
           LT.TrackName,
           LT.TrackLayout,
           LT.CarName,
           LT.ClassName,
           FormatLapTime(LT.LapTimeMs),
           FormatDateTime('yyyy-MM-dd HH:nn:ss', LT.LapDate),
           LT.SessionType]));
      end;

      SL.Text := SB.ToString;
      SL.SaveToFile(AFilePath, TEncoding.UTF8);
      Result := True;
    finally
      SB.Free;
      SL.Free;
    end;
  except
    Result := False;
  end;
end;

class function TCSVExporter.ExportDuckDBSourceToCSV(const ASourcePath,
  AFilePath: string; out AError: string): Boolean;
begin
  Result := TDuckDBNative.ExportTelemetryToCSV(ASourcePath, AFilePath, AError);
end;

class function TCSVExporter.LoadDuckDBPreviewCSV(const ASourcePath: string;
  out ACSVData, AError: string): Boolean;
begin
  Result := TDuckDBNative.LoadTelemetryPreviewCSV(ASourcePath, ACSVData, AError);
end;

class function TCSVExporter.ReadDuckDBMetadataValue(const ASourcePath,
  AMetadataKey: string; out AValue, AError: string): Boolean;
begin
  Result := TDuckDBNative.ReadMetadataValue(ASourcePath, AMetadataKey, AValue, AError);
end;

end.
