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
  System.SysUtils, System.Classes,
  LapTimeModels, DatabaseManager;

type
  TCSVExporter = class
  public
    { Export all telemetry data points for a session to a CSV file. }
    class function ExportTelemetrySession(ADB: TDatabaseManager;
                                          ASessionID: Integer;
                                          const AFilePath: string): Boolean;

    { Returns the telemetry CSV content as a string (used for AI upload). }
    class function TelemetrySessionToCSV(ADB: TDatabaseManager;
                                         ASessionID: Integer): string;

    { Export top-N lap times for a specific track + car class. }
    class function ExportLapTimes(ADB: TDatabaseManager;
                                  ATrackID, AClassID: Integer;
                                  const AFilePath: string;
                                  ALimit: Integer = 100): Boolean;
  end;

implementation

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

end.
