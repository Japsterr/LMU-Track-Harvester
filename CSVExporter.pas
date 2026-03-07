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
  System.SysUtils, System.Classes, System.IOUtils,
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

    { Export an LMU DuckDB telemetry source file to CSV via the bundled Python helper. }
    class function ExportDuckDBSourceToCSV(const ASourcePath,
      AFilePath: string; out AError: string): Boolean;

    { Read a metadata value from an LMU DuckDB telemetry file via the bundled Python helper. }
    class function ReadDuckDBMetadataValue(const ASourcePath, AMetadataKey: string;
      out AValue, AError: string): Boolean;

    { Export top-N lap times for a specific track + car class. }
    class function ExportLapTimes(ADB: TDatabaseManager;
                                  ATrackID, AClassID: Integer;
                                  const AFilePath: string;
                                  ALimit: Integer = 100): Boolean;
  private
    { Locates a bundled script by name; returns '' if not found. }
    class function ResolveScriptPath(const AScriptName: string): string;

    { Runs an external process and returns its exit code.
      Raises an exception if the process cannot be launched. }
    class function RunProcessAndWait(const AExe, AParams: string): Integer;
  end;

implementation
uses
  Winapi.Windows;

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

// ---------------------------------------------------------------------------
// DuckDB source export helpers
// ---------------------------------------------------------------------------

class function TCSVExporter.ResolveScriptPath(const AScriptName: string): string;
var
  BaseDir: string;
  Candidate: string;
  I: Integer;
begin
  Result := '';
  BaseDir := ExcludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));

  for I := 0 to 5 do
  begin
    Candidate := TPath.Combine(TPath.Combine(BaseDir, 'scripts'), AScriptName);
    if TFile.Exists(Candidate) then
      Exit(Candidate);

    Candidate := TPath.Combine(BaseDir, AScriptName);
    if TFile.Exists(Candidate) then
      Exit(Candidate);

    BaseDir := ExcludeTrailingPathDelimiter(ExtractFileDir(BaseDir));
  end;
end;

class function TCSVExporter.RunProcessAndWait(const AExe,
  AParams: string): Integer;
var
  SI: TStartupInfo;
  PI: TProcessInformation;
  CmdLine: string;
  ExitCode: DWORD;
begin
  Result := -1;
  FillChar(SI, SizeOf(SI), 0);
  SI.cb := SizeOf(SI);
  SI.dwFlags := STARTF_USESHOWWINDOW;
  SI.wShowWindow := SW_HIDE;
  FillChar(PI, SizeOf(PI), 0);

  // Build the full command line
  CmdLine := '"' + AExe + '" ' + AParams;

  if not CreateProcess(nil, PChar(CmdLine), nil, nil, False,
    CREATE_NO_WINDOW, nil, nil, SI, PI) then
    raise Exception.CreateFmt('Failed to launch "%s" (Windows error %d).',
      [AExe, GetLastError]);

  try
    WaitForSingleObject(PI.hProcess, INFINITE);
    if GetExitCodeProcess(PI.hProcess, ExitCode) then
      Result := Integer(ExitCode);
  finally
    CloseHandle(PI.hProcess);
    CloseHandle(PI.hThread);
  end;
end;

class function TCSVExporter.ExportDuckDBSourceToCSV(const ASourcePath,
  AFilePath: string; out AError: string): Boolean;
var
  ScriptPath: string;
  ExitCode: Integer;
  CommandLine: string;
  Runners: array[0..2] of string;
  R: string;
  Launched: Boolean;
begin
  Result := False;
  AError := '';

  if not TFile.Exists(ASourcePath) then
  begin
    AError := 'DuckDB source file not found.';
    Exit;
  end;

  ScriptPath := ResolveScriptPath('export_duckdb_csv.py');
  if ScriptPath = '' then
  begin
    AError := 'Bundled export script not found. ' +
      'Ensure export_duckdb_csv.py is present in the scripts\ folder next to the executable.';
    Exit;
  end;

  // Try the Python Launcher for Windows first, then plain python3/python
  Runners[0] := 'py';
  Runners[1] := 'python3';
  Runners[2] := 'python';

  Launched := False;
  ExitCode := -1;
  for R in Runners do
  begin
    CommandLine := Format('-3 "%s" --input "%s" --output "%s"',
      [ScriptPath, ASourcePath, AFilePath]);
    // The '-3' flag is only valid for the 'py' launcher; omit it for python/python3
    if R <> 'py' then
      CommandLine := Format('"%s" --input "%s" --output "%s"',
        [ScriptPath, ASourcePath, AFilePath]);
    try
      ExitCode := RunProcessAndWait(R, CommandLine);
      Launched := True;
      Break;
    except
      // Try next runner
    end;
  end;

  if not Launched then
  begin
    AError := 'Could not launch Python. Ensure Python 3 is installed and on the system PATH.';
    Exit;
  end;

  Result := (ExitCode = 0) and TFile.Exists(AFilePath);
  if not Result then
    AError := 'DuckDB export failed (exit code ' + IntToStr(ExitCode) + '). ' +
      'Ensure Python 3 and the duckdb package are installed (pip install duckdb).';
end;

class function TCSVExporter.ReadDuckDBMetadataValue(const ASourcePath,
  AMetadataKey: string; out AValue, AError: string): Boolean;
var
  ScriptPath: string;
  OutputPath: string;
  ExitCode: Integer;
  CommandLine: string;
  Runners: array[0..2] of string;
  R: string;
  Launched: Boolean;
begin
  Result := False;
  AValue := '';
  AError := '';

  if not TFile.Exists(ASourcePath) then
  begin
    AError := 'DuckDB source file not found.';
    Exit;
  end;

  ScriptPath := ResolveScriptPath('read_duckdb_metadata.py');
  if ScriptPath = '' then
  begin
    AError := 'Bundled metadata helper not found.';
    Exit;
  end;

  OutputPath := TPath.GetTempFileName;
  try
    Runners[0] := 'py';
    Runners[1] := 'python3';
    Runners[2] := 'python';

    Launched := False;
    ExitCode := -1;
    for R in Runners do
    begin
      if R = 'py' then
        CommandLine := Format('-3 "%s" --input "%s" --key "%s" --output "%s"',
          [ScriptPath, ASourcePath, AMetadataKey, OutputPath])
      else
        CommandLine := Format('"%s" --input "%s" --key "%s" --output "%s"',
          [ScriptPath, ASourcePath, AMetadataKey, OutputPath]);
      try
        ExitCode := RunProcessAndWait(R, CommandLine);
        Launched := True;
        Break;
      except
        // Try next runner
      end;
    end;

    if not Launched then
    begin
      AError := 'Could not launch Python. Ensure Python 3 is installed and on the system PATH.';
      Exit;
    end;

    if (ExitCode = 0) and TFile.Exists(OutputPath) then
    begin
      AValue := Trim(TFile.ReadAllText(OutputPath, TEncoding.UTF8));
      Result := AValue <> '';
      if not Result then
        AError := 'Requested metadata value was not found in the DuckDB source file.';
    end
    else
      AError := 'DuckDB metadata lookup failed (exit code ' + IntToStr(ExitCode) + ').';
  finally
    if TFile.Exists(OutputPath) then
      TFile.Delete(OutputPath);
  end;
end;

end.
