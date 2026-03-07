program VerifyResultsImport;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.IOUtils,
  DatabaseManager,
  LapTimeModels,
  ResultsXMLImporter;

function FindTrackID(const ADB: TDatabaseManager; const ATrackText: string): Integer;
var
  Tracks: TTrackArray;
  Track: TTrack;
begin
  Result := -1;
  Tracks := ADB.GetTracks;
  for Track in Tracks do
    if Pos(LowerCase(ATrackText), LowerCase(Track.Name + ' ' + Track.Layout)) > 0 then
      Exit(Track.ID);
end;

function FindClassID(const ADB: TDatabaseManager; const AClassName: string): Integer;
var
  Classes: TCarClassArray;
  CarClass: TCarClass;
begin
  Result := -1;
  Classes := ADB.GetCarClasses;
  for CarClass in Classes do
    if SameText(CarClass.Name, AClassName) then
      Exit(CarClass.ID);
end;

procedure PrintLaps(const ATitle: string; const ALaps: TLapTimeArray);
var
  Lap: TLapTime;
begin
  Writeln(ATitle);
  for Lap in ALaps do
    Writeln(Format('  %s | %s | %s | %s', [
      Lap.CarName,
      FormatLapTime(Lap.LapTimeMs),
      FormatDateTime('yyyy-mm-dd', Lap.LapDate),
      Lap.SessionType]));
  Writeln;
end;

var
  DBPath: string;
  DB: TDatabaseManager;
  DriverName: string;
  Summary: TResultsImportSummary;
  TrackID: Integer;
  ClassID: Integer;
begin
  try
    DBPath := TPath.Combine(TPath.GetTempPath, 'LMUTrackHarvester_verify.db');
    if TFile.Exists(DBPath) then
      TFile.Delete(DBPath);

    DB := TDatabaseManager.Create(DBPath);
    try
      DriverName := TResultsXMLImporter.DetectDominantDriverName(
        TPath.Combine(ExtractFilePath(ParamStr(0)), 'Results'));
      Writeln('Detected driver: ' + DriverName);

      Summary := TResultsXMLImporter.ImportFolder(DB,
        TPath.Combine(ExtractFilePath(ParamStr(0)), 'Results'), DriverName);
      Writeln(Format('Imported: %d, skipped: %d, failed: %d',
        [Summary.LapsInserted, Summary.LapsSkipped, Summary.FilesFailed]));
      Writeln;

      TrackID := FindTrackID(DB, 'monza');
      ClassID := FindClassID(DB, 'LMGT3');
      if (TrackID > 0) and (ClassID > 0) then
      begin
        PrintLaps('Monza Top 10', DB.GetTopLapTimes(TrackID, ClassID, 10));
        PrintLaps('Monza Fastest Per Car', DB.GetFastestLapPerCar(TrackID, ClassID));
      end
      else
        Writeln('Could not find Monza / LMGT3 in reference data.');
    finally
      DB.Free;
    end;
  except
    on E: Exception do
    begin
      Writeln(E.ClassName + ': ' + E.Message);
      Halt(1);
    end;
  end;
end.