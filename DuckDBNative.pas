unit DuckDBNative;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Math,
  System.Generics.Collections;

type
  TDuckDBNative = class
  public
    class function ExportTelemetryToCSV(const ASourcePath, AOutputPath: string;
      out AError: string): Boolean;
    class function LoadTelemetryPreviewCSV(const ASourcePath: string;
      out ACSVData, AError: string): Boolean;
    class function ReadMetadataValue(const ASourcePath, AMetadataKey: string;
      out AValue, AError: string): Boolean;
    class function IsAvailable(out AError: string): Boolean;
  end;

implementation

uses
  Winapi.Windows;

type
  duckdb_state = Integer;
  duckdb_idx_t = UInt64;
  duckdb_database = Pointer;
  duckdb_connection = Pointer;

  duckdb_result = record
    deprecated_column_count: duckdb_idx_t;
    deprecated_row_count: duckdb_idx_t;
    deprecated_rows_changed: duckdb_idx_t;
    deprecated_columns: Pointer;
    deprecated_error_message: PAnsiChar;
    internal_data: Pointer;
  end;

  Pduckdb_result = ^duckdb_result;

  TStringArray = TArray<string>;

  TExtraSingleChannel = record
    Header: string;
    Alias1: string;
    Alias2: string;
  end;

  TExtraMultiChannel = record
    Header: string;
    Alias1: string;
    Alias2: string;
    ColumnName: string;
    PercentMode: Boolean;
  end;

  TTableSeries = class
  private
    FColumns: TDictionary<string, TStringArray>;
  public
    constructor Create;
    destructor Destroy; override;
    function GetColumn(const AName: string; out AValues: TStringArray): Boolean;
    function LongestSeriesLength: Integer;
    property Columns: TDictionary<string, TStringArray> read FColumns;
  end;

  TDuckDBApi = class
  strict private
    class var FLibraryHandle: HMODULE;
    class var FLibraryPath: string;
    class var FLoadAttempted: Boolean;
    class var FLoadError: string;
    class function ResolveLibraryPath: string; static;
  public
    class function EnsureLoaded(out AError: string): Boolean; static;
    class function LibraryPath: string; static;
    class function Open(const ADatabasePath: string; out ADatabase: duckdb_database;
      out AError: string): Boolean; static;
    class function Connect(ADatabase: duckdb_database; out AConnection: duckdb_connection;
      out AError: string): Boolean; static;
    class function Query(AConnection: duckdb_connection; const ASQL: string;
      out AResult: duckdb_result; out AError: string): Boolean; static;
    class procedure Close(var ADatabase: duckdb_database); static;
    class procedure Disconnect(var AConnection: duckdb_connection); static;
    class procedure DestroyResult(var AResult: duckdb_result); static;
    class function ColumnCount(var AResult: duckdb_result): Integer; static;
    class function RowCount(var AResult: duckdb_result): Integer; static;
    class function ValueAsString(var AResult: duckdb_result; AColumn, ARow: Integer): string; static;
  end;

  TDuckDBSession = class
  private
    FDatabase: duckdb_database;
    FConnection: duckdb_connection;
  public
    constructor Create(const ASourcePath: string);
    destructor Destroy; override;
    function QuerySingleColumn(const ASQL: string): TStringArray;
    function QueryScalar(const ASQL: string): string;
    function ReadSampledSingleColumn(const ATableName, AColumnName: string;
      ATargetSamples: Integer): TStringArray;
    function ReadTableSeries(const ATableName: string): TTableSeries;
    function TryGetChannelFrequency(const AChannelName: string; ADefault: Integer): Integer;
  end;

const
  DuckDBSuccess = 0;
  BASE_FREQ_FALLBACK = 100;
  PREVIEW_SAMPLE_TARGET = 5000;

  BASE_CHANNEL_COUNT = 7;
  BASE_CHANNEL_NAMES: array[0..BASE_CHANNEL_COUNT] of string = (
    'TimestampMs',
    'Speed_kmh',
    'RPM',
    'Gear',
    'Throttle_pct',
    'Brake_pct',
    'Steering_pct',
    'LapDistance_pct'
  );
  BASE_CHANNEL_ALIASES: array[0..BASE_CHANNEL_COUNT] of string = (
    'GPS Time',
    'Ground Speed',
    'Engine RPM',
    'Gear',
    'Throttle Pos',
    'Brake Pos',
    'Steering Pos',
    'Lap Dist'
  );

  EXTRA_SINGLE_CHANNELS: array[0..5] of TExtraSingleChannel = (
    (Header: 'GPS_Latitude_deg'; Alias1: 'GPS Latitude'; Alias2: ''),
    (Header: 'GPS_Longitude_deg'; Alias1: 'GPS Longitude'; Alias2: ''),
    (Header: 'GForceLat_g'; Alias1: 'G Force Lat'; Alias2: ''),
    (Header: 'GForceLong_g'; Alias1: 'G Force Long'; Alias2: ''),
    (Header: 'GForceVert_g'; Alias1: 'G Force Vert'; Alias2: ''),
    (Header: 'FuelLevel'; Alias1: 'Fuel Level'; Alias2: '')
  );

  EXTRA_MULTI_CHANNELS: array[0..19] of TExtraMultiChannel = (
    (Header: 'BrakeTemp_FL_C'; Alias1: 'Brakes Temp'; Alias2: ''; ColumnName: 'value1'; PercentMode: False),
    (Header: 'BrakeTemp_FR_C'; Alias1: 'Brakes Temp'; Alias2: ''; ColumnName: 'value2'; PercentMode: False),
    (Header: 'BrakeTemp_RL_C'; Alias1: 'Brakes Temp'; Alias2: ''; ColumnName: 'value3'; PercentMode: False),
    (Header: 'BrakeTemp_RR_C'; Alias1: 'Brakes Temp'; Alias2: ''; ColumnName: 'value4'; PercentMode: False),
    (Header: 'TyreTempL_FL_C'; Alias1: 'TyresTempLeft'; Alias2: ''; ColumnName: 'value1'; PercentMode: False),
    (Header: 'TyreTempL_FR_C'; Alias1: 'TyresTempLeft'; Alias2: ''; ColumnName: 'value2'; PercentMode: False),
    (Header: 'TyreTempL_RL_C'; Alias1: 'TyresTempLeft'; Alias2: ''; ColumnName: 'value3'; PercentMode: False),
    (Header: 'TyreTempL_RR_C'; Alias1: 'TyresTempLeft'; Alias2: ''; ColumnName: 'value4'; PercentMode: False),
    (Header: 'TyreTempC_FL_C'; Alias1: 'TyresTempCentre'; Alias2: ''; ColumnName: 'value1'; PercentMode: False),
    (Header: 'TyreTempC_FR_C'; Alias1: 'TyresTempCentre'; Alias2: ''; ColumnName: 'value2'; PercentMode: False),
    (Header: 'TyreTempC_RL_C'; Alias1: 'TyresTempCentre'; Alias2: ''; ColumnName: 'value3'; PercentMode: False),
    (Header: 'TyreTempC_RR_C'; Alias1: 'TyresTempCentre'; Alias2: ''; ColumnName: 'value4'; PercentMode: False),
    (Header: 'TyreTempR_FL_C'; Alias1: 'TyresTempRight'; Alias2: ''; ColumnName: 'value1'; PercentMode: False),
    (Header: 'TyreTempR_FR_C'; Alias1: 'TyresTempRight'; Alias2: ''; ColumnName: 'value2'; PercentMode: False),
    (Header: 'TyreTempR_RL_C'; Alias1: 'TyresTempRight'; Alias2: ''; ColumnName: 'value3'; PercentMode: False),
    (Header: 'TyreTempR_RR_C'; Alias1: 'TyresTempRight'; Alias2: ''; ColumnName: 'value4'; PercentMode: False),
    (Header: 'TyrePressure_FL'; Alias1: 'TyresPressure'; Alias2: ''; ColumnName: 'value1'; PercentMode: False),
    (Header: 'TyrePressure_FR'; Alias1: 'TyresPressure'; Alias2: ''; ColumnName: 'value2'; PercentMode: False),
    (Header: 'TyrePressure_RL'; Alias1: 'TyresPressure'; Alias2: ''; ColumnName: 'value3'; PercentMode: False),
    (Header: 'TyrePressure_RR'; Alias1: 'TyresPressure'; Alias2: ''; ColumnName: 'value4'; PercentMode: False)
  );

  EXTRA_MULTI_CHANNELS_2: array[0..3] of TExtraMultiChannel = (
    (Header: 'TyreWear_FL_pct'; Alias1: 'Tyres Wear'; Alias2: 'TyresWear'; ColumnName: 'value1'; PercentMode: True),
    (Header: 'TyreWear_FR_pct'; Alias1: 'Tyres Wear'; Alias2: 'TyresWear'; ColumnName: 'value2'; PercentMode: True),
    (Header: 'TyreWear_RL_pct'; Alias1: 'Tyres Wear'; Alias2: 'TyresWear'; ColumnName: 'value3'; PercentMode: True),
    (Header: 'TyreWear_RR_pct'; Alias1: 'Tyres Wear'; Alias2: 'TyresWear'; ColumnName: 'value4'; PercentMode: True)
  );

function duckdb_open(path: PAnsiChar; out out_database: duckdb_database): duckdb_state; cdecl; external 'duckdb.dll' delayed;
procedure duckdb_close(var database: duckdb_database); cdecl; external 'duckdb.dll' delayed;
function duckdb_connect(database: duckdb_database; out out_connection: duckdb_connection): duckdb_state; cdecl; external 'duckdb.dll' delayed;
procedure duckdb_disconnect(var connection: duckdb_connection); cdecl; external 'duckdb.dll' delayed;
function duckdb_query(connection: duckdb_connection; query: PAnsiChar; out out_result: duckdb_result): duckdb_state; cdecl; external 'duckdb.dll' delayed;
procedure duckdb_destroy_result(var result: duckdb_result); cdecl; external 'duckdb.dll' delayed;
function duckdb_column_count(var result: duckdb_result): duckdb_idx_t; cdecl; external 'duckdb.dll' delayed;
function duckdb_row_count(var result: duckdb_result): duckdb_idx_t; cdecl; external 'duckdb.dll' delayed;
function duckdb_value_varchar(var result: duckdb_result; col, row: duckdb_idx_t): PAnsiChar; cdecl; external 'duckdb.dll' delayed;
function duckdb_result_error(var result: duckdb_result): PAnsiChar; cdecl; external 'duckdb.dll' delayed;
procedure duckdb_free(ptr: Pointer); cdecl; external 'duckdb.dll' delayed;

function InvariantFS: TFormatSettings;
begin
  Result := TFormatSettings.Invariant;
end;

procedure InitDuckDBResult(out AResult: duckdb_result);
begin
  FillChar(AResult, SizeOf(AResult), 0);
end;

function QuoteIdentifier(const AName: string): string;
begin
  Result := '"' + StringReplace(AName, '"', '""', [rfReplaceAll]) + '"';
end;

function QuoteSQLLiteral(const AValue: string): string;
begin
  Result := '''' + StringReplace(AValue, '''', '''''', [rfReplaceAll]) + '''';
end;

function CsvEscape(const AValue: string): string;
begin
  Result := AValue;
  if (Pos('"', Result) > 0) or (Pos(',', Result) > 0) or (Pos(#13, Result) > 0) or
     (Pos(#10, Result) > 0) then
    Result := '"' + StringReplace(Result, '"', '""', [rfReplaceAll]) + '"';
end;

function FloatToInvariant(const AValue: Double; const AFormat: string): string;
begin
  Result := FormatFloat(AFormat, AValue, InvariantFS);
end;

function TryParseInvariantFloat(const AValue: string; out AParsed: Double): Boolean;
var
  Trimmed: string;
begin
  Trimmed := Trim(AValue);
  if Trimmed = '' then
    Exit(False);
  Result := TryStrToFloat(Trimmed, AParsed, InvariantFS);
end;

function StringArrayContains(const AValues: TStringArray; const AValue: string): Boolean;
var
  Item: string;
begin
  for Item in AValues do
    if SameText(Item, AValue) then
      Exit(True);
  Result := False;
end;

function FindTableName(const ATables: TStringArray; const ACandidate1: string;
  const ACandidate2: string = ''): string;
var
  TableName: string;
begin
  for TableName in ATables do
    if SameText(TableName, ACandidate1) or ((ACandidate2 <> '') and SameText(TableName, ACandidate2)) then
      Exit(TableName);
  Result := '';
end;

function ResampleSeries(const AValues: TStringArray; ASrcFreq, ABaseCount,
  ABaseFreq: Integer): TStringArray;
var
  Ratio: Double;
  Index: Integer;
  SourceIndex: Integer;
begin
  if ABaseCount <= 0 then
    Exit(nil);

  SetLength(Result, ABaseCount);
  if Length(AValues) = 0 then
    Exit;

  if Length(AValues) = ABaseCount then
  begin
    for Index := 0 to ABaseCount - 1 do
      Result[Index] := AValues[Index];
    Exit;
  end;

  if (ASrcFreq <= 0) or (ABaseFreq <= 0) then
    Ratio := Length(AValues) / ABaseCount
  else
    Ratio := ASrcFreq / ABaseFreq;

  for Index := 0 to ABaseCount - 1 do
  begin
    SourceIndex := Floor(Index * Ratio);
    if SourceIndex < 0 then
      SourceIndex := 0;
    if SourceIndex >= Length(AValues) then
      SourceIndex := Length(AValues) - 1;
    Result[Index] := AValues[SourceIndex];
  end;
end;

function ResampleSeriesByCount(const AValues: TStringArray;
  ABaseCount: Integer): TStringArray;
var
  Ratio: Double;
  Index: Integer;
  SourceIndex: Integer;
begin
  if ABaseCount <= 0 then
    Exit(nil);

  SetLength(Result, ABaseCount);
  if Length(AValues) = 0 then
    Exit;

  if Length(AValues) = ABaseCount then
  begin
    for Index := 0 to ABaseCount - 1 do
      Result[Index] := AValues[Index];
    Exit;
  end;

  Ratio := Length(AValues) / ABaseCount;
  for Index := 0 to ABaseCount - 1 do
  begin
    SourceIndex := Floor(Index * Ratio);
    if SourceIndex < 0 then
      SourceIndex := 0;
    if SourceIndex >= Length(AValues) then
      SourceIndex := Length(AValues) - 1;
    Result[Index] := AValues[SourceIndex];
  end;
end;

function NormalizePercentSeries(const AValues: TStringArray): TStringArray;
var
  Value: string;
  Parsed: Double;
  MaxAbs: Double;
  Scale: Double;
  Index: Integer;
begin
  SetLength(Result, Length(AValues));
  MaxAbs := 0.0;
  for Value in AValues do
    if TryParseInvariantFloat(Value, Parsed) then
      MaxAbs := Max(MaxAbs, Abs(Parsed));

  if (MaxAbs > 0) and (MaxAbs <= 1.5) then
    Scale := 100.0
  else
    Scale := 1.0;

  for Index := 0 to High(AValues) do
    if TryParseInvariantFloat(AValues[Index], Parsed) then
      Result[Index] := FloatToInvariant(RoundTo(Parsed * Scale, -3), '0.###')
    else
      Result[Index] := '';
end;

function BuildClampedUnitSeries(const AValues: TStringArray): TStringArray;
var
  Parsed: Double;
  Index: Integer;
begin
  SetLength(Result, Length(AValues));
  for Index := 0 to High(AValues) do
    if TryParseInvariantFloat(AValues[Index], Parsed) then
      Result[Index] := FloatToInvariant(RoundTo(EnsureRange(Parsed, 0.0, 1.0), -6), '0.######')
    else
      Result[Index] := '';
end;

function BuildFractionalLapSeries(const AValues: TStringArray): TStringArray;
var
  Parsed: Double;
  Normalized: Double;
  Index: Integer;
begin
  SetLength(Result, Length(AValues));
  for Index := 0 to High(AValues) do
  begin
    if not TryParseInvariantFloat(AValues[Index], Parsed) then
      Continue;

    if Parsed < 0.0 then
      Parsed := 0.0;
    Normalized := Parsed - Floor(Parsed);
    if SameValue(Normalized, 0.0, 1.0E-6) and (Parsed > 0.0) then
      Normalized := 1.0;
    Result[Index] := FloatToInvariant(RoundTo(EnsureRange(Normalized, 0.0, 1.0), -6), '0.######');
  end;
end;

function BuildModuloPercentLapSeries(const AValues: TStringArray): TStringArray;
var
  Parsed: Double;
  Normalized: Double;
  Index: Integer;
begin
  SetLength(Result, Length(AValues));
  for Index := 0 to High(AValues) do
  begin
    if not TryParseInvariantFloat(AValues[Index], Parsed) then
      Continue;

    if Parsed < 0.0 then
      Parsed := 0.0;
    Normalized := Frac(Parsed / 100.0);
    if SameValue(Normalized, 0.0, 1.0E-6) and (Parsed > 0.0) then
      Normalized := 1.0;
    Result[Index] := FloatToInvariant(RoundTo(EnsureRange(Normalized, 0.0, 1.0), -6), '0.######');
  end;
end;

function TryBuildSegmentNormalizedLapSeries(const AValues: TStringArray;
  out ANormalized: TStringArray): Boolean;
type
  TSegmentInfo = record
    StartIndex: Integer;
    EndIndex: Integer;
    MaxValue: Double;
  end;
var
  ParsedValues: TArray<Double>;
  ValidValues: TArray<Boolean>;
  Segments: TArray<TSegmentInfo>;
  SegmentStart: Integer;
  SegmentMax: Double;
  PreviousValue: Double;
  Parsed: Double;
  Index: Integer;
  SegmentCount: Integer;
  CurrentSegment: Integer;
  function IsLapReset(APrevious, ACurrent, ACurrentSegmentMax: Double): Boolean;
  begin
    Result := False;
    if (APrevious <= 0.0) or (ACurrent < 0.0) then
      Exit;

    Result :=
      ((APrevious >= Max(1.0, ACurrentSegmentMax * 0.50)) and (ACurrent <= (APrevious * 0.35))) or
      ((APrevious - ACurrent) >= Max(5.0, ACurrentSegmentMax * 0.40));
  end;
  procedure AddSegment(AStartIndex, AEndIndex: Integer; AMaxValue: Double);
  begin
    if (AStartIndex < 0) or (AEndIndex < AStartIndex) then
      Exit;
    SetLength(Segments, SegmentCount + 1);
    Segments[SegmentCount].StartIndex := AStartIndex;
    Segments[SegmentCount].EndIndex := AEndIndex;
    Segments[SegmentCount].MaxValue := AMaxValue;
    Inc(SegmentCount);
  end;
begin
  Result := False;
  SetLength(ANormalized, Length(AValues));
  SetLength(ParsedValues, Length(AValues));
  SetLength(ValidValues, Length(AValues));
  SegmentStart := -1;
  SegmentMax := 0.0;
  PreviousValue := 0.0;
  SegmentCount := 0;

  for Index := 0 to High(AValues) do
  begin
    if TryParseInvariantFloat(AValues[Index], Parsed) and (Parsed >= 0.0) then
    begin
      ParsedValues[Index] := Parsed;
      ValidValues[Index] := True;
    end
    else
      ValidValues[Index] := False;
  end;

  for Index := 0 to High(AValues) do
  begin
    if not ValidValues[Index] then
      Continue;

    if SegmentStart < 0 then
    begin
      SegmentStart := Index;
      SegmentMax := ParsedValues[Index];
      PreviousValue := ParsedValues[Index];
      Continue;
    end;

    if IsLapReset(PreviousValue, ParsedValues[Index], SegmentMax) then
    begin
      AddSegment(SegmentStart, Index - 1, SegmentMax);
      SegmentStart := Index;
      SegmentMax := ParsedValues[Index];
    end
    else
      SegmentMax := Max(SegmentMax, ParsedValues[Index]);

    PreviousValue := ParsedValues[Index];
  end;

  if SegmentStart >= 0 then
    AddSegment(SegmentStart, High(AValues), SegmentMax);

  if SegmentCount = 0 then
    Exit(False);

  if (SegmentCount = 1) and (Segments[0].MaxValue > 1.05) and (Segments[0].MaxValue > 100.5) then
    Exit(False);

  for CurrentSegment := 0 to High(Segments) do
  begin
    if Segments[CurrentSegment].MaxValue <= 0.0 then
      Continue;

    for Index := Segments[CurrentSegment].StartIndex to Segments[CurrentSegment].EndIndex do
    begin
      if not ValidValues[Index] then
        Continue;

      if Segments[CurrentSegment].MaxValue <= 1.05 then
        ANormalized[Index] := FloatToInvariant(RoundTo(EnsureRange(ParsedValues[Index], 0.0, 1.0), -6), '0.######')
      else if Segments[CurrentSegment].MaxValue <= 100.5 then
        ANormalized[Index] := FloatToInvariant(RoundTo(EnsureRange(ParsedValues[Index] / 100.0, 0.0, 1.0), -6), '0.######')
      else
        ANormalized[Index] := FloatToInvariant(RoundTo(EnsureRange(ParsedValues[Index] / Segments[CurrentSegment].MaxValue, 0.0, 1.0), -6), '0.######');
    end;
  end;

  Result := True;
end;

function ScoreLapDistanceCandidate(const AValues: TStringArray;
  const ATimestamps: TArray<Int64>): Integer;
var
  Parsed: Double;
  MinValue: Double;
  MaxValue: Double;
  PreviousValue: Double;
  Coverage: Double;
  Wraps: Integer;
  InvalidCount: Integer;
  Index: Integer;
  HasPrevious: Boolean;
  PreviousWrapTimestamp: Int64;
  WrapTimestamp: Int64;
  BestLapDurationMs: Int64;
  TotalLapDurationMs: Int64;
  AvgLapDurationMs: Double;
begin
  MinValue := 1.0E12;
  MaxValue := -1.0E12;
  PreviousValue := 0.0;
  Wraps := 0;
  InvalidCount := 0;
  HasPrevious := False;
  PreviousWrapTimestamp := -1;
  BestLapDurationMs := High(Int64);
  TotalLapDurationMs := 0;

  for Index := 0 to High(AValues) do
  begin
    if not TryParseInvariantFloat(AValues[Index], Parsed) then
    begin
      Inc(InvalidCount);
      Continue;
    end;

    if (Parsed < -0.05) or (Parsed > 1.05) then
    begin
      Inc(InvalidCount);
      Continue;
    end;

    MinValue := Min(MinValue, Parsed);
    MaxValue := Max(MaxValue, Parsed);

    if (Index <= High(ATimestamps)) and (ATimestamps[Index] >= 0) then
      WrapTimestamp := ATimestamps[Index]
    else
      WrapTimestamp := Index;

    if HasPrevious and (PreviousValue > 0.85) and (Parsed < 0.15) then
    begin
      Inc(Wraps);
      if PreviousWrapTimestamp >= 0 then
      begin
        BestLapDurationMs := Min(BestLapDurationMs, WrapTimestamp - PreviousWrapTimestamp);
        Inc(TotalLapDurationMs, WrapTimestamp - PreviousWrapTimestamp);
      end;
      PreviousWrapTimestamp := WrapTimestamp;
    end
    else if PreviousWrapTimestamp < 0 then
      PreviousWrapTimestamp := WrapTimestamp;

    PreviousValue := Parsed;
    HasPrevious := True;
  end;

  if not HasPrevious then
    Exit(-1000);

  Coverage := MaxValue - MinValue;
  Result := Round(Coverage * 100.0) - (InvalidCount * 3);
  if Coverage >= 0.80 then
    Inc(Result, 100)
  else if Coverage >= 0.50 then
    Inc(Result, 40);

  if Wraps > 0 then
  begin
    AvgLapDurationMs := TotalLapDurationMs / Wraps;
    if (AvgLapDurationMs >= 40000.0) and (AvgLapDurationMs <= 240000.0) then
      Inc(Result, 200)
    else if (AvgLapDurationMs < 15000.0) or (AvgLapDurationMs > 400000.0) then
      Dec(Result, 250)
    else
      Dec(Result, 40);

    if (BestLapDurationMs >= 40000) and (BestLapDurationMs <= 240000) then
      Inc(Result, 120)
    else if BestLapDurationMs < 15000 then
      Dec(Result, 200);

    Inc(Result, 200 + (Wraps * 20));
  end;
end;

function NormalizeLapDistance(const AValues: TStringArray;
  const ATimestamps: TArray<Int64>): TStringArray;
var
  Parsed: Double;
  MinValue: Double;
  MaxValue: Double;
  ParsedCount: Integer;
  AboveOneCount: Integer;
  Index: Integer;
  PreservedCandidate: TStringArray;
  FractionalCandidate: TStringArray;
  PercentCandidate: TStringArray;
  BestScore: Integer;
  CandidateScore: Integer;
begin
  SetLength(Result, Length(AValues));
  MinValue := 1.0E12;
  MaxValue := -1.0E12;
  ParsedCount := 0;
  AboveOneCount := 0;

  for Index := 0 to High(AValues) do
    if TryParseInvariantFloat(AValues[Index], Parsed) and (Parsed >= 0.0) then
    begin
      Inc(ParsedCount);
      MinValue := Min(MinValue, Parsed);
      MaxValue := Max(MaxValue, Parsed);
      if Parsed > 1.05 then
        Inc(AboveOneCount);
    end;

  if ParsedCount = 0 then
    Exit;

  if TryBuildSegmentNormalizedLapSeries(AValues, Result) then
    Exit;

  if (MinValue >= -0.05) and (MaxValue <= 1.05) then
    Exit(BuildClampedUnitSeries(AValues));

  if (MinValue >= -0.05) and (MaxValue <= 100.5) and (AboveOneCount > (ParsedCount div 4)) then
  begin
    PercentCandidate := BuildModuloPercentLapSeries(AValues);
    CandidateScore := ScoreLapDistanceCandidate(PercentCandidate, ATimestamps);
    if CandidateScore >= 80 then
      Exit(PercentCandidate);
  end;

  PreservedCandidate := BuildClampedUnitSeries(AValues);
  BestScore := ScoreLapDistanceCandidate(PreservedCandidate, ATimestamps);
  Result := PreservedCandidate;

  if AboveOneCount > 0 then
  begin
    FractionalCandidate := BuildFractionalLapSeries(AValues);
    CandidateScore := ScoreLapDistanceCandidate(FractionalCandidate, ATimestamps);
    if CandidateScore > BestScore then
    begin
      Result := FractionalCandidate;
      BestScore := CandidateScore;
    end;

    if MaxValue > 20.0 then
    begin
      PercentCandidate := BuildModuloPercentLapSeries(AValues);
      CandidateScore := ScoreLapDistanceCandidate(PercentCandidate, ATimestamps);
      if CandidateScore > BestScore then
      begin
        Result := PercentCandidate;
        BestScore := CandidateScore;
      end;
    end;
  end;
end;

function NormalizePassthrough(const AValues: TStringArray): TStringArray;
var
  Parsed: Double;
  Index: Integer;
begin
  SetLength(Result, Length(AValues));
  for Index := 0 to High(AValues) do
    if TryParseInvariantFloat(AValues[Index], Parsed) then
      Result[Index] := FloatToInvariant(RoundTo(Parsed, -6), '0.######')
    else
      Result[Index] := '';
end;

function BuildSampleClockTimestamps(ABaseCount, ABaseFreq,
  ASourceSampleCount: Integer): TArray<Int64>;
var
  Index: Integer;
  IntervalMs: Double;
  SampleScale: Double;
begin
  SetLength(Result, ABaseCount);
  if (ABaseCount > 0) and (ASourceSampleCount > ABaseCount) then
    SampleScale := ASourceSampleCount / ABaseCount
  else
    SampleScale := 1.0;
  IntervalMs := (1000.0 / Max(ABaseFreq, 1)) * SampleScale;
  for Index := 0 to ABaseCount - 1 do
    Result[Index] := Round(Index * IntervalMs);
end;

function BuildTimestampMs(const AGPSTimes: TStringArray; ABaseCount,
  ABaseFreq, ASourceSampleCount: Integer): TArray<Int64>;
var
  StartTime: Double;
  Parsed: Double;
  PreviousTime: Double;
  DerivedTimestamps: TArray<Int64>;
  ExpectedDurationMs: Double;
  SourceDurationMs: Double;
  UseSourceTime: Boolean;
  Index: Integer;
begin
  DerivedTimestamps := BuildSampleClockTimestamps(ABaseCount, ABaseFreq, ASourceSampleCount);
  if (Length(AGPSTimes) < ABaseCount) or (Length(AGPSTimes) = 0) or
     (not TryParseInvariantFloat(AGPSTimes[0], StartTime)) then
    Exit(DerivedTimestamps);

  UseSourceTime := True;
  PreviousTime := StartTime;
  for Index := 1 to ABaseCount - 1 do
  begin
    if not TryParseInvariantFloat(AGPSTimes[Index], Parsed) then
    begin
      UseSourceTime := False;
      Break;
    end;
    if Parsed < PreviousTime then
    begin
      UseSourceTime := False;
      Break;
    end;
    PreviousTime := Parsed;
  end;

  if not UseSourceTime then
    Exit(DerivedTimestamps);

  SourceDurationMs := (PreviousTime - StartTime) * 1000.0;
  ExpectedDurationMs := DerivedTimestamps[High(DerivedTimestamps)];
  if (SourceDurationMs <= 0.0) or
     ((ExpectedDurationMs > 0.0) and (SourceDurationMs < (ExpectedDurationMs * 0.25))) then
    Exit(DerivedTimestamps);

  SetLength(Result, ABaseCount);

  for Index := 0 to ABaseCount - 1 do
    if TryParseInvariantFloat(AGPSTimes[Index], Parsed) then
      Result[Index] := Round((Parsed - StartTime) * 1000.0)
    else
      Result[Index] := DerivedTimestamps[Index];
end;

function GetSeriesLongestLength(ATableSeries: TTableSeries): Integer;
begin
  if ATableSeries = nil then
    Exit(0);
  Result := ATableSeries.LongestSeriesLength;
end;

function LimitSeriesSampleCount(const AValues: TStringArray;
  ATargetSamples: Integer): TStringArray;
begin
  if (ATargetSamples > 0) and (Length(AValues) > ATargetSamples) then
  begin
    Result := ResampleSeries(AValues, 0, ATargetSamples, 0);
    Exit;
  end;
  Result := Copy(AValues);
end;

function BuildTelemetryCSV(const ASourcePath: string; AIncludeExtraChannels: Boolean;
  ATargetSamples: Integer; out ACSVData, AError: string): Boolean; forward;

constructor TTableSeries.Create;
begin
  inherited Create;
  FColumns := TDictionary<string, TStringArray>.Create;
end;

destructor TTableSeries.Destroy;
begin
  FColumns.Free;
  inherited;
end;

function TTableSeries.GetColumn(const AName: string; out AValues: TStringArray): Boolean;
begin
  Result := FColumns.TryGetValue(AName, AValues);
end;

function TTableSeries.LongestSeriesLength: Integer;
var
  Pair: TPair<string, TStringArray>;
begin
  Result := 0;
  for Pair in FColumns do
    Result := Max(Result, Length(Pair.Value));
end;

class function TDuckDBApi.ResolveLibraryPath: string;
var
  BaseDir: string;
  Candidate: string;
  I: Integer;
begin
  BaseDir := ExcludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));
  for I := 0 to 5 do
  begin
    Candidate := TPath.Combine(BaseDir, 'duckdb.dll');
    if TFile.Exists(Candidate) then
      Exit(Candidate);

    Candidate := TPath.Combine(TPath.Combine(BaseDir, 'runtime'), 'duckdb.dll');
    if TFile.Exists(Candidate) then
      Exit(Candidate);

    Candidate := TPath.Combine(TPath.Combine(BaseDir, 'download'), 'duckdb_lib\duckdb.dll');
    if TFile.Exists(Candidate) then
      Exit(Candidate);

    BaseDir := ExcludeTrailingPathDelimiter(ExtractFileDir(BaseDir));
  end;
  Result := '';
end;

class function TDuckDBApi.EnsureLoaded(out AError: string): Boolean;
begin
  if FLibraryHandle <> 0 then
  begin
    AError := '';
    Exit(True);
  end;

  if FLoadAttempted then
  begin
    AError := FLoadError;
    Exit(False);
  end;

  FLoadAttempted := True;
  FLibraryPath := ResolveLibraryPath;
  if FLibraryPath = '' then
  begin
    FLoadError := 'duckdb.dll was not found. Bundle duckdb.dll beside the executable.';
    AError := FLoadError;
    Exit(False);
  end;

  FLibraryHandle := LoadLibrary(PChar(FLibraryPath));
  if FLibraryHandle = 0 then
  begin
    FLoadError := Format('Failed to load duckdb.dll from %s (Windows error %d).',
      [FLibraryPath, GetLastError]);
    AError := FLoadError;
    Exit(False);
  end;

  AError := '';
  Result := True;
end;

class function TDuckDBApi.LibraryPath: string;
begin
  Result := FLibraryPath;
end;

class function TDuckDBApi.Open(const ADatabasePath: string; out ADatabase: duckdb_database;
  out AError: string): Boolean;
var
  ErrorText: string;
  Utf8Path: UTF8String;
begin
  ADatabase := nil;
  if not EnsureLoaded(ErrorText) then
  begin
    AError := 'DuckDB load failed: ' + ErrorText;
    Exit(False);
  end;

  Utf8Path := UTF8String(ADatabasePath);
  Result := duckdb_open(PAnsiChar(Utf8Path), ADatabase) = DuckDBSuccess;
  if not Result then
    AError := 'DuckDB open failed.'
  else
    AError := '';
end;

class function TDuckDBApi.Connect(ADatabase: duckdb_database; out AConnection: duckdb_connection;
  out AError: string): Boolean;
begin
  AConnection := nil;
  Result := duckdb_connect(ADatabase, AConnection) = DuckDBSuccess;
  if not Result then
    AError := 'DuckDB connect failed.'
  else
    AError := '';
end;

class function TDuckDBApi.Query(AConnection: duckdb_connection; const ASQL: string;
  out AResult: duckdb_result; out AError: string): Boolean;
var
  Utf8SQL: UTF8String;
  ErrorPtr: PAnsiChar;
begin
  InitDuckDBResult(AResult);
  Utf8SQL := UTF8String(ASQL);
  Result := duckdb_query(AConnection, PAnsiChar(Utf8SQL), AResult) = DuckDBSuccess;
  if Result then
  begin
    AError := '';
    Exit;
  end;

  ErrorPtr := duckdb_result_error(AResult);
  if Assigned(ErrorPtr) then
    AError := string(UTF8String(ErrorPtr))
  else
    AError := 'DuckDB query failed.';
end;

class procedure TDuckDBApi.Close(var ADatabase: duckdb_database);
begin
  if (FLibraryHandle <> 0) and (ADatabase <> nil) then
    duckdb_close(ADatabase);
  ADatabase := nil;
end;

class procedure TDuckDBApi.Disconnect(var AConnection: duckdb_connection);
begin
  if (FLibraryHandle <> 0) and (AConnection <> nil) then
    duckdb_disconnect(AConnection);
  AConnection := nil;
end;

class procedure TDuckDBApi.DestroyResult(var AResult: duckdb_result);
begin
  if FLibraryHandle <> 0 then
    duckdb_destroy_result(AResult)
  else
    InitDuckDBResult(AResult);
end;

class function TDuckDBApi.ColumnCount(var AResult: duckdb_result): Integer;
begin
  Result := Integer(duckdb_column_count(AResult));
end;

class function TDuckDBApi.RowCount(var AResult: duckdb_result): Integer;
begin
  Result := Integer(duckdb_row_count(AResult));
end;

class function TDuckDBApi.ValueAsString(var AResult: duckdb_result; AColumn,
  ARow: Integer): string;
var
  RawValue: PAnsiChar;
begin
  RawValue := duckdb_value_varchar(AResult, AColumn, ARow);
  try
    if Assigned(RawValue) then
      Result := string(UTF8String(RawValue))
    else
      Result := '';
  finally
    if Assigned(RawValue) then
      duckdb_free(RawValue);
  end;
end;

constructor TDuckDBSession.Create(const ASourcePath: string);
var
  ErrorText: string;
begin
  inherited Create;
  try
    if not TDuckDBApi.Open(ASourcePath, FDatabase, ErrorText) then
      raise Exception.Create(ErrorText);
  except
    on E: Exception do
      raise Exception.Create('Open stage failed: ' + E.Message);
  end;
  try
    if not TDuckDBApi.Connect(FDatabase, FConnection, ErrorText) then
    begin
      TDuckDBApi.Close(FDatabase);
      raise Exception.Create(ErrorText);
    end;
  except
    on E: Exception do
    begin
      TDuckDBApi.Close(FDatabase);
      raise Exception.Create('Connect stage failed: ' + E.Message);
    end;
  end;
end;

destructor TDuckDBSession.Destroy;
begin
  TDuckDBApi.Disconnect(FConnection);
  TDuckDBApi.Close(FDatabase);
  inherited;
end;

function TDuckDBSession.QuerySingleColumn(const ASQL: string): TStringArray;
var
  QueryResult: duckdb_result;
  ErrorText: string;
  RowIndex: Integer;
begin
  InitDuckDBResult(QueryResult);
  if not TDuckDBApi.Query(FConnection, ASQL, QueryResult, ErrorText) then
    raise Exception.Create(ErrorText);
  try
    SetLength(Result, TDuckDBApi.RowCount(QueryResult));
    for RowIndex := 0 to High(Result) do
      Result[RowIndex] := TDuckDBApi.ValueAsString(QueryResult, 0, RowIndex);
  finally
    TDuckDBApi.DestroyResult(QueryResult);
  end;
end;

function TDuckDBSession.QueryScalar(const ASQL: string): string;
var
  Values: TStringArray;
begin
  Values := QuerySingleColumn(ASQL);
  if Length(Values) > 0 then
    Result := Values[0]
  else
    Result := '';
end;

function TDuckDBSession.ReadSampledSingleColumn(const ATableName, AColumnName: string;
  ATargetSamples: Integer): TStringArray;
var
  TotalCount: Integer;
  StepSize: Integer;
  SQL: string;
begin
  TotalCount := StrToIntDef(QueryScalar(
    'SELECT COUNT(*) FROM ' + QuoteIdentifier(ATableName)), 0);
  if TotalCount <= 0 then
    Exit(nil);

  if (ATargetSamples <= 0) or (TotalCount <= ATargetSamples) then
    Exit(QuerySingleColumn(
      'SELECT ' + QuoteIdentifier(AColumnName) + ' FROM ' + QuoteIdentifier(ATableName)));

  StepSize := Max(1, Ceil(TotalCount / ATargetSamples));
  SQL := Format(
    'WITH numbered AS (' +
    ' SELECT %s AS value, row_number() OVER () AS rn FROM %s' +
    ') SELECT value FROM numbered WHERE ((rn - 1) %% %d) = 0 ORDER BY rn',
    [QuoteIdentifier(AColumnName), QuoteIdentifier(ATableName), StepSize]);
  Result := QuerySingleColumn(SQL);
  if Length(Result) > ATargetSamples then
    SetLength(Result, ATargetSamples);
end;

function TDuckDBSession.ReadTableSeries(const ATableName: string): TTableSeries;
var
  ColumnNames: TStringArray;
  DescriptionResult: duckdb_result;
  TableResult: duckdb_result;
  ErrorText: string;
  ColumnIndex: Integer;
  RowIndex: Integer;
  Values: TStringArray;
  SQL: string;
  SelectList: TStringBuilder;
begin
  Result := TTableSeries.Create;
  InitDuckDBResult(DescriptionResult);
  InitDuckDBResult(TableResult);
  try
    if not TDuckDBApi.Query(FConnection, 'DESCRIBE ' + QuoteIdentifier(ATableName), DescriptionResult, ErrorText) then
      raise Exception.Create(ErrorText);

    SetLength(ColumnNames, TDuckDBApi.RowCount(DescriptionResult));
    for RowIndex := 0 to High(ColumnNames) do
      ColumnNames[RowIndex] := TDuckDBApi.ValueAsString(DescriptionResult, 0, RowIndex);

    if Length(ColumnNames) = 0 then
      Exit;

    SelectList := TStringBuilder.Create;
    try
      for ColumnIndex := 0 to High(ColumnNames) do
      begin
        if ColumnIndex > 0 then
          SelectList.Append(', ');
        SelectList.Append(QuoteIdentifier(ColumnNames[ColumnIndex]));
      end;
      SQL := 'SELECT ' + SelectList.ToString + ' FROM ' + QuoteIdentifier(ATableName);
    finally
      SelectList.Free;
    end;

    if not TDuckDBApi.Query(FConnection, SQL, TableResult, ErrorText) then
      raise Exception.Create(ErrorText);

    for ColumnIndex := 0 to High(ColumnNames) do
    begin
      SetLength(Values, TDuckDBApi.RowCount(TableResult));
      for RowIndex := 0 to High(Values) do
        Values[RowIndex] := TDuckDBApi.ValueAsString(TableResult, ColumnIndex, RowIndex);
      Result.Columns.AddOrSetValue(ColumnNames[ColumnIndex], Values);
    end;
  finally
    TDuckDBApi.DestroyResult(TableResult);
    TDuckDBApi.DestroyResult(DescriptionResult);
  end;
end;

function TDuckDBSession.TryGetChannelFrequency(const AChannelName: string;
  ADefault: Integer): Integer;
var
  RawValue: string;
begin
  Result := ADefault;
  try
    RawValue := QueryScalar('SELECT frequency FROM channelsList WHERE channelName = ' +
      QuoteSQLLiteral(AChannelName));
    if RawValue <> '' then
      Result := StrToIntDef(RawValue, ADefault);
    if Result <= 0 then
      Result := ADefault;
  except
    Result := ADefault;
  end;
end;

class function TDuckDBNative.IsAvailable(out AError: string): Boolean;
begin
  Result := TDuckDBApi.EnsureLoaded(AError);
end;

class function TDuckDBNative.ReadMetadataValue(const ASourcePath,
  AMetadataKey: string; out AValue, AError: string): Boolean;
var
  Session: TDuckDBSession;
begin
  Result := False;
  AValue := '';
  AError := '';

  if not TFile.Exists(ASourcePath) then
  begin
    AError := 'DuckDB source file not found.';
    Exit;
  end;

  try
    try
      Session := TDuckDBSession.Create(ASourcePath);
    except
      on E: Exception do
      begin
        AError := 'DuckDB open/connect failed: ' + E.Message;
        Exit(False);
      end;
    end;
    try
      try
        AValue := Trim(Session.QueryScalar(
          'SELECT value FROM metadata WHERE key = ' + QuoteSQLLiteral(AMetadataKey)));
      except
        on E: Exception do
        begin
          AError := 'DuckDB metadata query failed: ' + E.Message;
          Exit(False);
        end;
      end;
      Result := AValue <> '';
      if not Result then
        AError := 'Requested metadata value was not found in the DuckDB source file.';
    finally
      Session.Free;
    end;
  except
    on E: Exception do
    begin
      AError := E.Message;
      Result := False;
    end;
  end;
end;

class function TDuckDBNative.ExportTelemetryToCSV(const ASourcePath,
  AOutputPath: string; out AError: string): Boolean;
var
  FullCSVData: string;
begin
  Result := False;
  if not BuildTelemetryCSV(ASourcePath, True, 0, FullCSVData, AError) then
    Exit(False);

  try
    if ExtractFileDir(AOutputPath) <> '' then
      ForceDirectories(ExtractFileDir(AOutputPath));
    TFile.WriteAllText(AOutputPath, FullCSVData, TEncoding.UTF8);
    Result := TFile.Exists(AOutputPath);
    if not Result then
      AError := 'DuckDB export did not produce a CSV file.';
  except
    on E: Exception do
    begin
      AError := E.Message;
      Result := False;
    end;
  end;
end;

function BuildTelemetryCSV(const ASourcePath: string; AIncludeExtraChannels: Boolean;
  ATargetSamples: Integer; out ACSVData, AError: string): Boolean;
var
  Session: TDuckDBSession;
  Tables: TStringArray;
  TableCache: TObjectDictionary<string, TTableSeries>;
  ResolvedBaseTables: array[0..BASE_CHANNEL_COUNT] of string;
  GPSTable: string;
  GPSSeries: TTableSeries;
  GPSTimeValues: TStringArray;
  BaseFreq: Integer;
  BaseCount: Integer;
  TableName: string;
  I: Integer;
  RowIndex: Integer;
  LongestSeries: Integer;
  SrcFreq: Integer;
  EstimatedCount: Integer;
  SpeedSeries: TStringArray;
  RPMSeries: TStringArray;
  GearSeries: TStringArray;
  ThrottleSeries: TStringArray;
  BrakeSeries: TStringArray;
  SteeringSeries: TStringArray;
  LapDistanceSeries: TStringArray;
  ResampledGPS: TStringArray;
  Timestamps: TArray<Int64>;
  SB: TStringBuilder;
  HeaderList: TStringList;
  ExtraValues: TObjectList<TStringList>;
  ExtraSingle: TExtraSingleChannel;
  ExtraMulti: TExtraMultiChannel;
  CurrentSeries: TTableSeries;
  ColumnValues: TStringArray;
  OutputCount: Integer;
  ForcePreviewGPS: Boolean;
  HasTimeBase: Boolean;
  function EnsureSeries(const ATableName: string): TTableSeries;
  begin
    Result := nil;
    if ATableName = '' then
      Exit;
    if not TableCache.TryGetValue(ATableName, Result) then
    begin
      Result := Session.ReadTableSeries(ATableName);
      TableCache.Add(ATableName, Result);
    end;
  end;
  function BaseColumnValues(const ATableName: string): TStringArray;
  begin
    if ATableName = '' then
      Exit(nil);
    if ATargetSamples > 0 then
      Exit(Session.ReadSampledSingleColumn(ATableName, 'value', ATargetSamples));
    CurrentSeries := EnsureSeries(ATableName);
    if (CurrentSeries = nil) or (not CurrentSeries.GetColumn('value', Result)) then
      Result := nil;
  end;

  procedure UpdateBaseCount(const ATableName, AChannelName: string);
  begin
    if ATableName = '' then
      Exit;
    if ATargetSamples > 0 then
      LongestSeries := Length(BaseColumnValues(ATableName))
    else
    begin
      CurrentSeries := EnsureSeries(ATableName);
      LongestSeries := GetSeriesLongestLength(CurrentSeries);
    end;
    if LongestSeries <= 0 then
      Exit;
    SrcFreq := Max(Session.TryGetChannelFrequency(AChannelName, BaseFreq), 1);
    EstimatedCount := Ceil(LongestSeries * (BaseFreq / SrcFreq));
    BaseCount := Max(BaseCount, EstimatedCount);
  end;

  function ResampleColumn(const ATableName, AChannelName: string;
    const AColumnName: string = ''): TStringArray;
  var
    SelectedColumn: string;
  begin
    if ATableName = '' then
      Exit(nil);

    if (ATargetSamples > 0) and ((AColumnName = '') or SameText(AColumnName, 'value')) then
    begin
      ColumnValues := BaseColumnValues(ATableName);
      if Length(ColumnValues) = 0 then
        Exit(nil);
      if HasTimeBase then
        Result := ResampleSeriesByCount(ColumnValues, OutputCount)
      else
        Result := ResampleSeries(ColumnValues,
          Session.TryGetChannelFrequency(AChannelName, BaseFreq), OutputCount, BaseFreq);
      Exit;
    end;

    CurrentSeries := EnsureSeries(ATableName);
    if CurrentSeries = nil then
      Exit(nil);

    SelectedColumn := AColumnName;
    if SelectedColumn = '' then
    begin
      if not CurrentSeries.GetColumn('value', ColumnValues) then
      begin
        if CurrentSeries.Columns.Count = 0 then
          Exit(nil);
        SelectedColumn := CurrentSeries.Columns.Keys.ToArray[0];
      end
      else
        SelectedColumn := 'value';
    end;

    if not CurrentSeries.GetColumn(SelectedColumn, ColumnValues) then
      Exit(nil);

    if HasTimeBase then
      Result := ResampleSeriesByCount(ColumnValues, OutputCount)
    else
      Result := ResampleSeries(ColumnValues,
        Session.TryGetChannelFrequency(AChannelName, BaseFreq), OutputCount, BaseFreq);
  end;

  procedure AppendSeries(const AHeader: string; const AValues: TStringArray);
  var
    Lines: TStringList;
    Index: Integer;
  begin
    HeaderList.Add(AHeader);
    Lines := TStringList.Create;
    for Index := 0 to OutputCount - 1 do
    begin
      if Index <= High(AValues) then
        Lines.Add(AValues[Index])
      else
        Lines.Add('');
    end;
    ExtraValues.Add(Lines);
  end;

  procedure AppendExtraMultiSeries(const AItem: TExtraMultiChannel);
  var
    AliasTable: string;
    Values: TStringArray;
  begin
    AliasTable := FindTableName(Tables, AItem.Alias1, AItem.Alias2);
    Values := ResampleColumn(AliasTable, AItem.Alias1, AItem.ColumnName);
    if AItem.PercentMode then
      Values := NormalizePercentSeries(Values)
    else
      Values := NormalizePassthrough(Values);
    AppendSeries(AItem.Header, Values);
  end;

begin
  Result := False;
  ACSVData := '';
  AError := '';
  ForcePreviewGPS := not AIncludeExtraChannels;
  HasTimeBase := False;

  if not TFile.Exists(ASourcePath) then
  begin
    AError := 'DuckDB source file not found.';
    Exit;
  end;

  try
    Session := TDuckDBSession.Create(ASourcePath);
    TableCache := TObjectDictionary<string, TTableSeries>.Create([doOwnsValues]);
    HeaderList := TStringList.Create;
    ExtraValues := TObjectList<TStringList>.Create(True);
    try
      Tables := Session.QuerySingleColumn('SHOW TABLES');
      if Length(Tables) = 0 then
      begin
        AError := 'No exportable tables found in the DuckDB source file.';
        Exit;
      end;

      for I := 0 to BASE_CHANNEL_COUNT do
        ResolvedBaseTables[I] := FindTableName(Tables, BASE_CHANNEL_ALIASES[I]);

      GPSTable := ResolvedBaseTables[0];
      BaseFreq := BASE_FREQ_FALLBACK;
      BaseCount := 0;
      SetLength(GPSTimeValues, 0);

      if GPSTable <> '' then
      begin
        if ATargetSamples > 0 then
          GPSTimeValues := BaseColumnValues(GPSTable)
        else
        begin
          GPSSeries := EnsureSeries(GPSTable);
          if (GPSSeries <> nil) and GPSSeries.GetColumn('value', GPSTimeValues) then
            GPSTimeValues := LimitSeriesSampleCount(GPSTimeValues, ATargetSamples);
        end;
        if Length(GPSTimeValues) > 0 then
        begin
          BaseFreq := Session.TryGetChannelFrequency(BASE_CHANNEL_ALIASES[0], BASE_FREQ_FALLBACK);
          BaseCount := Length(GPSTimeValues);
          HasTimeBase := True;
        end;
      end;

      if not HasTimeBase then
      begin
        for I := 0 to BASE_CHANNEL_COUNT do
          UpdateBaseCount(ResolvedBaseTables[I], BASE_CHANNEL_ALIASES[I]);
        if AIncludeExtraChannels then
        begin
          for ExtraSingle in EXTRA_SINGLE_CHANNELS do
            UpdateBaseCount(FindTableName(Tables, ExtraSingle.Alias1, ExtraSingle.Alias2), ExtraSingle.Alias1);
          for ExtraMulti in EXTRA_MULTI_CHANNELS do
            UpdateBaseCount(FindTableName(Tables, ExtraMulti.Alias1, ExtraMulti.Alias2), ExtraMulti.Alias1);
          for ExtraMulti in EXTRA_MULTI_CHANNELS_2 do
            UpdateBaseCount(FindTableName(Tables, ExtraMulti.Alias1, ExtraMulti.Alias2), ExtraMulti.Alias1);
        end;
      end;

      if BaseCount <= 0 then
      begin
        AError := 'No telemetry samples found in mapped channels.';
        Exit;
      end;

      OutputCount := BaseCount;
      if (ATargetSamples > 0) and (OutputCount > ATargetSamples) then
        OutputCount := ATargetSamples;

      if ATargetSamples > 0 then
        ResampledGPS := LimitSeriesSampleCount(GPSTimeValues, OutputCount)
      else
        ResampledGPS := ResampleColumn(GPSTable, BASE_CHANNEL_ALIASES[0]);
      Timestamps := BuildTimestampMs(ResampledGPS, OutputCount, BaseFreq, BaseCount);
      SpeedSeries := NormalizePassthrough(ResampleColumn(ResolvedBaseTables[1], BASE_CHANNEL_ALIASES[1]));
      RPMSeries := NormalizePassthrough(ResampleColumn(ResolvedBaseTables[2], BASE_CHANNEL_ALIASES[2]));
      GearSeries := ResampleColumn(ResolvedBaseTables[3], BASE_CHANNEL_ALIASES[3]);
      ThrottleSeries := NormalizePercentSeries(ResampleColumn(ResolvedBaseTables[4], BASE_CHANNEL_ALIASES[4]));
      BrakeSeries := NormalizePercentSeries(ResampleColumn(ResolvedBaseTables[5], BASE_CHANNEL_ALIASES[5]));
      SteeringSeries := NormalizePercentSeries(ResampleColumn(ResolvedBaseTables[6], BASE_CHANNEL_ALIASES[6]));
      LapDistanceSeries := NormalizeLapDistance(ResampleColumn(ResolvedBaseTables[7], BASE_CHANNEL_ALIASES[7]), Timestamps);

      for I := 0 to BASE_CHANNEL_COUNT do
        HeaderList.Add(BASE_CHANNEL_NAMES[I]);

      if ForcePreviewGPS then
      begin
        for I := 0 to 1 do
        begin
          TableName := FindTableName(Tables, EXTRA_SINGLE_CHANNELS[I].Alias1, EXTRA_SINGLE_CHANNELS[I].Alias2);
          AppendSeries(EXTRA_SINGLE_CHANNELS[I].Header,
            NormalizePassthrough(ResampleColumn(TableName, EXTRA_SINGLE_CHANNELS[I].Alias1)));
        end;
      end;

      if AIncludeExtraChannels then
      begin
        for ExtraSingle in EXTRA_SINGLE_CHANNELS do
        begin
          TableName := FindTableName(Tables, ExtraSingle.Alias1, ExtraSingle.Alias2);
          AppendSeries(ExtraSingle.Header,
            NormalizePassthrough(ResampleColumn(TableName, ExtraSingle.Alias1)));
        end;
        for ExtraMulti in EXTRA_MULTI_CHANNELS do
          AppendExtraMultiSeries(ExtraMulti);
        for ExtraMulti in EXTRA_MULTI_CHANNELS_2 do
          AppendExtraMultiSeries(ExtraMulti);
      end;

      SB := TStringBuilder.Create;
      try
        SB.AppendLine(StringReplace(HeaderList.CommaText, '"', '', [rfReplaceAll]));
        for RowIndex := 0 to OutputCount - 1 do
        begin
          SB.Append(IntToStr(Timestamps[RowIndex]));
          SB.Append(',');
          if RowIndex <= High(SpeedSeries) then SB.Append(CsvEscape(SpeedSeries[RowIndex]));
          SB.Append(',');
          if RowIndex <= High(RPMSeries) then SB.Append(CsvEscape(RPMSeries[RowIndex]));
          SB.Append(',');
          if (RowIndex <= High(GearSeries)) and (Trim(GearSeries[RowIndex]) <> '') then
            SB.Append(IntToStr(Trunc(StrToFloatDef(GearSeries[RowIndex], 0, InvariantFS))));
          SB.Append(',');
          if RowIndex <= High(ThrottleSeries) then SB.Append(CsvEscape(ThrottleSeries[RowIndex]));
          SB.Append(',');
          if RowIndex <= High(BrakeSeries) then SB.Append(CsvEscape(BrakeSeries[RowIndex]));
          SB.Append(',');
          if RowIndex <= High(SteeringSeries) then SB.Append(CsvEscape(SteeringSeries[RowIndex]));
          SB.Append(',');
          if RowIndex <= High(LapDistanceSeries) then SB.Append(CsvEscape(LapDistanceSeries[RowIndex]));
          for I := 0 to ExtraValues.Count - 1 do
          begin
            SB.Append(',');
            SB.Append(CsvEscape(ExtraValues[I][RowIndex]));
          end;
          SB.AppendLine;
        end;
        ACSVData := SB.ToString;
      finally
        SB.Free;
      end;
    finally
      ExtraValues.Free;
      HeaderList.Free;
      TableCache.Free;
      Session.Free;
    end;
    Result := ACSVData <> '';
    if not Result then
      AError := 'DuckDB export did not produce any CSV data.';
  except
    on E: Exception do
    begin
      AError := E.Message;
      Result := False;
    end;
  end;
end;

class function TDuckDBNative.LoadTelemetryPreviewCSV(const ASourcePath: string;
  out ACSVData, AError: string): Boolean;
begin
  Result := BuildTelemetryCSV(ASourcePath, False, PREVIEW_SAMPLE_TARGET, ACSVData, AError);
end;

end.