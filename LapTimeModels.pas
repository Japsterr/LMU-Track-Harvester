unit LapTimeModels;

{ Data models (records) and helper utilities for LMU Track Harvester. }

interface

uses
  System.SysUtils;

type
  TTrack = record
    ID: Integer;
    Name: string;
    Layout: string;
    function DisplayName: string;
  end;

  TCarClass = record
    ID: Integer;
    Name: string;
  end;

  TCar = record
    ID: Integer;
    Name: string;
    ClassID: Integer;
    ClassName: string;
  end;

  TLapTime = record
    ID: Integer;
    TrackID: Integer;
    TrackName: string;
    TrackLayout: string;
    CarID: Integer;
    CarName: string;
    ClassID: Integer;
    ClassName: string;
    LapTimeMs: Int64;
    LapDate: TDateTime;
    SessionType: string;
  end;

  TTelemetrySession = record
    ID: Integer;
    TrackID: Integer;
    TrackName: string;
    TrackLayout: string;
    CarID: Integer;
    CarName: string;
    SessionDate: TDateTime;
    Notes: string;
    DataPointCount: Integer;
  end;

  TTelemetryDataPoint = record
    ID: Integer;
    SessionID: Integer;
    TimestampMs: Int64;
    Speed: Double;        // km/h
    RPM: Double;
    Gear: Integer;
    Throttle: Double;     // 0.0–1.0
    Brake: Double;        // 0.0–1.0
    Steering: Double;     // -1.0–1.0
    LapDistance: Double;  // 0.0–1.0 (fraction of full lap)
  end;

  TTrackArray            = array of TTrack;
  TCarClassArray         = array of TCarClass;
  TCarArray              = array of TCar;
  TLapTimeArray          = array of TLapTime;
  TTelemetrySessionArray = array of TTelemetrySession;
  TTelemetryDataArray    = array of TTelemetryDataPoint;

{ Convert milliseconds to M:SS.mmm string. }
function FormatLapTime(LapTimeMs: Int64): string;

{ Parse a M:SS.mmm string back to milliseconds. Returns -1 on parse failure. }
function ParseLapTime(const S: string): Int64;

implementation

function NormalizeDisplayText(const S: string): string;
begin
  Result := S;
  Result := StringReplace(Result, 'â€“', ' - ', [rfReplaceAll]);
  Result := StringReplace(Result, '–', ' - ', [rfReplaceAll]);
  Result := StringReplace(Result, '—', ' - ', [rfReplaceAll]);
  Result := StringReplace(Result, 'Autódromo', 'Autodromo', [rfReplaceAll]);
  Result := StringReplace(Result, 'José', 'Jose', [rfReplaceAll]);
  Result := StringReplace(Result, 'Portimão', 'Portimao', [rfReplaceAll]);
  Result := StringReplace(Result, 'Lédenon', 'Ledenon', [rfReplaceAll]);
  Result := StringReplace(Result, 'Huracán', 'Huracan', [rfReplaceAll]);
end;

function EnglishTrackName(const AName: string): string;
begin
  if SameText(NormalizeDisplayText(AName), 'Circuit de la Sarthe') then
    Exit('Le Mans (Circuit de la Sarthe)');
  if SameText(NormalizeDisplayText(AName), 'Autodromo Nazionale Monza') then
    Exit('Monza');
  if SameText(NormalizeDisplayText(AName), 'Circuit de Spa-Francorchamps') then
    Exit('Spa-Francorchamps');
  if SameText(NormalizeDisplayText(AName), 'Autodromo Internacional do Algarve (Portimao)') then
    Exit('Algarve (Portimao)');
  if SameText(NormalizeDisplayText(AName), 'Autodromo Jose Carlos Pace (Interlagos)') then
    Exit('Interlagos');
  if SameText(NormalizeDisplayText(AName), 'Autodromo Enzo e Dino Ferrari (Imola)') then
    Exit('Imola');
  if SameText(NormalizeDisplayText(AName), 'Circuit de Catalunya') then
    Exit('Circuit de Barcelona-Catalunya');
  if SameText(NormalizeDisplayText(AName), 'Circuit de Ledenon') then
    Exit('Ledenon');
  Result := NormalizeDisplayText(AName);
end;

function TTrack.DisplayName: string;
begin
  if Layout <> '' then
    Result := EnglishTrackName(Name) + ' - ' + NormalizeDisplayText(Layout)
  else
    Result := EnglishTrackName(Name);
end;

function FormatLapTime(LapTimeMs: Int64): string;
var
  Minutes, Seconds, Millis: Int64;
begin
  if LapTimeMs < 0 then
  begin
    Result := '--:---.---';
    Exit;
  end;
  Minutes := LapTimeMs div 60000;
  Seconds := (LapTimeMs mod 60000) div 1000;
  Millis  := LapTimeMs mod 1000;
  Result  := Format('%d:%02d.%03d', [Minutes, Seconds, Millis]);
end;

function ParseLapTime(const S: string): Int64;
{ Accepts formats: M:SS.mmm  or  SS.mmm }
var
  ColPos, DotPos: Integer;
  MinPart, SecPart, MsPart: Int64;
  Main: string;
begin
  Result := -1;
  Main := Trim(S);
  ColPos := Pos(':', Main);
  DotPos := Pos('.', Main);

  try
    if DotPos = 0 then
    begin
      // No decimal – treat whole string as seconds
      if ColPos > 0 then
      begin
        MinPart := StrToInt(Copy(Main, 1, ColPos - 1));
        SecPart := StrToInt(Copy(Main, ColPos + 1, MaxInt));
      end
      else
      begin
        MinPart := 0;
        SecPart := StrToInt(Main);
      end;
      MsPart := 0;
    end
    else
    begin
      MsPart := StrToInt(Copy(Main, DotPos + 1, MaxInt));
      if ColPos > 0 then
      begin
        MinPart := StrToInt(Copy(Main, 1, ColPos - 1));
        SecPart := StrToInt(Copy(Main, ColPos + 1, DotPos - ColPos - 1));
      end
      else
      begin
        MinPart := 0;
        SecPart := StrToInt(Copy(Main, 1, DotPos - 1));
      end;
    end;
    Result := (MinPart * 60000) + (SecPart * 1000) + MsPart;
  except
    Result := -1;
  end;
end;

end.
