unit ResultsXMLImporter;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.StrUtils, System.DateUtils,
  System.Generics.Collections, System.Variants,
  Xml.XMLIntf, Xml.XMLDoc,
  FireDAC.Comp.Client,
  DatabaseManager, LapTimeModels;

type
  TResultsImportSummary = record
    FilesScanned: Integer;
    FilesFailed: Integer;
    LapsInserted: Integer;
    LapsSkipped: Integer;
  end;

  TResultsXMLImporter = class
  public
    class function ImportFolder(ADB: TDatabaseManager;
      const AFolder: string; const APreferredDriverName: string = ''): TResultsImportSummary;
  end;

implementation

type
  TLapCandidate = record
    TrackHint: string;
    CarHint: string;
    SessionType: string;
    LapTimeMs: Int64;
    LapDate: TDateTime;
  end;

procedure AddLapCandidate(const ATrackHint, ACarHint, ASessionType: string;
  ALapTimeMs: Int64; ALapDate: TDateTime; ACandidates: TList<TLapCandidate>);
var
  LapCandidate: TLapCandidate;
begin
  if (ACandidates = nil) or (ALapTimeMs <= 0) then
    Exit;

  LapCandidate.TrackHint := ATrackHint;
  LapCandidate.CarHint := ACarHint;
  LapCandidate.SessionType := ASessionType;
  LapCandidate.LapTimeMs := ALapTimeMs;
  LapCandidate.LapDate := ALapDate;
  ACandidates.Add(LapCandidate);
end;

function NormalizeKey(const S: string): string;
var
  Normalized: string;
  C: Char;
begin
  Normalized := LowerCase(S);
  Normalized := StringReplace(Normalized, #$00E1, 'a', [rfReplaceAll]);
  Normalized := StringReplace(Normalized, #$00E0, 'a', [rfReplaceAll]);
  Normalized := StringReplace(Normalized, #$00E2, 'a', [rfReplaceAll]);
  Normalized := StringReplace(Normalized, #$00E4, 'a', [rfReplaceAll]);
  Normalized := StringReplace(Normalized, #$00E3, 'a', [rfReplaceAll]);
  Normalized := StringReplace(Normalized, #$00E5, 'a', [rfReplaceAll]);
  Normalized := StringReplace(Normalized, #$00E7, 'c', [rfReplaceAll]);
  Normalized := StringReplace(Normalized, #$00E9, 'e', [rfReplaceAll]);
  Normalized := StringReplace(Normalized, #$00E8, 'e', [rfReplaceAll]);
  Normalized := StringReplace(Normalized, #$00EA, 'e', [rfReplaceAll]);
  Normalized := StringReplace(Normalized, #$00EB, 'e', [rfReplaceAll]);
  Normalized := StringReplace(Normalized, #$00ED, 'i', [rfReplaceAll]);
  Normalized := StringReplace(Normalized, #$00EC, 'i', [rfReplaceAll]);
  Normalized := StringReplace(Normalized, #$00EE, 'i', [rfReplaceAll]);
  Normalized := StringReplace(Normalized, #$00EF, 'i', [rfReplaceAll]);
  Normalized := StringReplace(Normalized, #$00F1, 'n', [rfReplaceAll]);
  Normalized := StringReplace(Normalized, #$00F3, 'o', [rfReplaceAll]);
  Normalized := StringReplace(Normalized, #$00F2, 'o', [rfReplaceAll]);
  Normalized := StringReplace(Normalized, #$00F4, 'o', [rfReplaceAll]);
  Normalized := StringReplace(Normalized, #$00F6, 'o', [rfReplaceAll]);
  Normalized := StringReplace(Normalized, #$00F5, 'o', [rfReplaceAll]);
  Normalized := StringReplace(Normalized, #$00FA, 'u', [rfReplaceAll]);
  Normalized := StringReplace(Normalized, #$00F9, 'u', [rfReplaceAll]);
  Normalized := StringReplace(Normalized, #$00FB, 'u', [rfReplaceAll]);
  Normalized := StringReplace(Normalized, #$00FC, 'u', [rfReplaceAll]);
  Normalized := StringReplace(Normalized, #$00FD, 'y', [rfReplaceAll]);
  Normalized := StringReplace(Normalized, #$00FF, 'y', [rfReplaceAll]);

  Result := '';
  for C in Normalized do
    if CharInSet(C, ['a'..'z', '0'..'9']) then
      Result := Result + C;
end;

function SimplifyTrackKey(const S: string): string;
begin
  Result := NormalizeKey(S);
  Result := StringReplace(Result, 'autodromo', '', [rfReplaceAll]);
  Result := StringReplace(Result, 'internacional', '', [rfReplaceAll]);
  Result := StringReplace(Result, 'international', '', [rfReplaceAll]);
  Result := StringReplace(Result, 'circuit', '', [rfReplaceAll]);
  Result := StringReplace(Result, 'course', '', [rfReplaceAll]);
  Result := StringReplace(Result, 'venue', '', [rfReplaceAll]);
  Result := StringReplace(Result, 'track', '', [rfReplaceAll]);
  Result := StringReplace(Result, 'full', '', [rfReplaceAll]);
  Result := StringReplace(Result, 'layout', '', [rfReplaceAll]);
  Result := StringReplace(Result, 'nazionale', '', [rfReplaceAll]);
  Result := StringReplace(Result, 'de', '', [rfReplaceAll]);
  Result := StringReplace(Result, 'do', '', [rfReplaceAll]);
  Result := StringReplace(Result, 'la', '', [rfReplaceAll]);

  if (Pos('portimao', Result) > 0) or (Pos('algarve', Result) > 0) then
    Result := 'portimao'
  else if Pos('monza', Result) > 0 then
    Result := 'monza'
  else if Pos('spa', Result) > 0 then
    Result := 'spa'
  else if Pos('fuji', Result) > 0 then
    Result := 'fuji'
  else if Pos('bahrain', Result) > 0 then
    Result := 'bahrain'
  else if Pos('sebring', Result) > 0 then
    Result := 'sebring'
  else if Pos('roadatlanta', Result) > 0 then
    Result := 'roadatlanta'
  else if Pos('lusail', Result) > 0 then
    Result := 'lusail'
  else if Pos('interlagos', Result) > 0 then
    Result := 'interlagos'
  else if Pos('imola', Result) > 0 then
    Result := 'imola'
  else if Pos('yasmarina', Result) > 0 then
    Result := 'yasmarina'
  else if (Pos('barcelona', Result) > 0) or (Pos('catalunya', Result) > 0) then
    Result := 'barcelona'
  else if Pos('ledenon', Result) > 0 then
    Result := 'ledenon'
  else if (Pos('sarthe', Result) > 0) or (Pos('lemans', Result) > 0) then
    Result := 'lemans';
end;

function SimplifyCarKey(const S: string): string;
begin
  Result := NormalizeKey(S);
  Result := StringReplace(Result, 'lmgt3', '', [rfReplaceAll]);
  Result := StringReplace(Result, 'gt3', '', [rfReplaceAll]);
  Result := StringReplace(Result, 'evo2', '', [rfReplaceAll]);
  Result := StringReplace(Result, 'evo', '', [rfReplaceAll]);
  Result := StringReplace(Result, 'hypercar', '', [rfReplaceAll]);
  Result := StringReplace(Result, 'lmp2', '', [rfReplaceAll]);

  if Pos('ferrari499p', Result) > 0 then Result := 'ferrari499p'
  else if Pos('toyotagr010', Result) > 0 then Result := 'toyotagr010'
  else if Pos('porsche963', Result) > 0 then Result := 'porsche963'
  else if Pos('cadillacvseriesr', Result) > 0 then Result := 'cadillacvseriesr'
  else if Pos('bmwmhybridv8', Result) > 0 then Result := 'bmwmhybridv8'
  else if Pos('peugeot9x8', Result) > 0 then Result := 'peugeot9x8'
  else if Pos('alpinea424', Result) > 0 then Result := 'alpinea424'
  else if Pos('lamborghinisc63', Result) > 0 then Result := 'lamborghinisc63'
  else if Pos('isottafraschini', Result) > 0 then Result := 'isottafraschini'
  else if Pos('acuraarx06', Result) > 0 then Result := 'acuraarx06'
  else if Pos('oreca07', Result) > 0 then Result := 'oreca07'
  else if Pos('ferrari296', Result) > 0 then Result := 'ferrari296'
  else if Pos('porsche911', Result) > 0 then Result := 'porsche911'
  else if Pos('bmwm4', Result) > 0 then Result := 'bmwm4'
  else if Pos('astonmartinvantage', Result) > 0 then Result := 'astonmartinvantage'
  else if Pos('mustang', Result) > 0 then Result := 'mustang'
  else if Pos('mclaren720s', Result) > 0 then Result := 'mclaren720s'
  else if Pos('huracan', Result) > 0 then Result := 'huracan'
  else if Pos('corvettez06', Result) > 0 then Result := 'corvettez06'
  else if Pos('lexusrcf', Result) > 0 then Result := 'lexusrcf'
  else if Pos('mercedesamg', Result) > 0 then Result := 'mercedesamg';
end;

function ParseLapTimeMs(const S: string): Int64;
var
  Raw, SecStr, MsStr: string;
  ColonPos, DotPos: Integer;
  Minutes, Seconds, Millis: Integer;
  ValueFloat: Double;
  InvariantFS: TFormatSettings;
begin
  Result := -1;
  Raw := Trim(StringReplace(S, ',', '.', [rfReplaceAll]));
  if Raw = '' then
    Exit;

  ColonPos := LastDelimiter(':', Raw);
  DotPos := LastDelimiter('.', Raw);

  if ColonPos > 0 then
  begin
    SecStr := Copy(Raw, ColonPos + 1, MaxInt);
    Raw := Copy(Raw, 1, ColonPos - 1);
    DotPos := LastDelimiter('.', SecStr);
    try
      if DotPos > 0 then
      begin
        Seconds := StrToInt(Copy(SecStr, 1, DotPos - 1));
        MsStr := Copy(SecStr, DotPos + 1, MaxInt);
      end
      else
      begin
        Seconds := StrToInt(SecStr);
        MsStr := '0';
      end;

      while Length(MsStr) < 3 do
        MsStr := MsStr + '0';
      if Length(MsStr) > 3 then
        MsStr := Copy(MsStr, 1, 3);
      Millis := StrToIntDef(MsStr, 0);

      Minutes := StrToInt(Raw);
      Result := (Int64(Minutes) * 60000) + (Int64(Seconds) * 1000) + Millis;
      Exit;
    except
      Exit;
    end;
  end;

  InvariantFS := TFormatSettings.Invariant;
  if TryStrToFloat(Raw, ValueFloat, InvariantFS) then
  begin
    if ValueFloat > 100000 then
      Result := Round(ValueFloat)
    else
      Result := Round(ValueFloat * 1000);
  end
  else
    Result := StrToInt64Def(Raw, -1);
end;

function SafeVariantToString(const AValue: Variant): string;
begin
  Result := '';
  try
    if VarIsNull(AValue) or VarIsClear(AValue) then
      Exit;
    Result := Trim(VarToStr(AValue));
  except
    Result := '';
  end;
end;

function SafeNodeText(const ANode: IXMLNode): string;
var
  Child: IXMLNode;
  I: Integer;
begin
  Result := '';
  if ANode = nil then
    Exit;

  if Assigned(ANode.ChildNodes) then
    for I := 0 to ANode.ChildNodes.Count - 1 do
    begin
      Child := ANode.ChildNodes[I];
      if Child = nil then
        Continue;

      if Child.NodeType in [ntText, ntCData] then
        Result := SafeVariantToString(Child.NodeValue)
      else
        Result := '';

      if Result <> '' then
        Exit;
    end;

  if not Assigned(ANode.ChildNodes) or (ANode.ChildNodes.Count = 0) then
    if ANode.NodeType in [ntText, ntCData, ntAttribute] then
      Result := SafeVariantToString(ANode.NodeValue);
end;

function IsLapTimeLikeName(const AName: string): Boolean;
var
  Name: string;
begin
  Name := NormalizeKey(AName);
  Result :=
    (Name = 'lap') or
    (Name = 'laptime') or
    (Name = 'bestlap') or
    (Name = 'bestlaptime') or
    (Pos('bestlap', Name) > 0) or
    (Pos('laptime', Name) > 0);
end;

function NormalizeImportedSessionType(const S: string): string;
var
  Key: string;
  LabelText: string;
begin
  Key := NormalizeKey(S);
  if Pos('practice', Key) > 0 then
    LabelText := 'Practice'
  else if (Pos('qual', Key) > 0) or (Pos('qualify', Key) > 0) then
    LabelText := 'Qualifying'
  else if Pos('race', Key) > 0 then
    LabelText := 'Race'
  else if Pos('warm', Key) > 0 then
    LabelText := 'Warmup'
  else if Pos('timeattack', Key) > 0 then
    LabelText := 'Time Attack'
  else if Trim(S) <> '' then
    LabelText := Trim(S)
  else
    LabelText := 'Session';

  Result := 'LMU Results XML - ' + LabelText;
end;

function TryParseDateFromFilename(const AFileName: string;
  out ALapDate: TDateTime): Boolean;
var
  Base: string;
  YearNum, MonthNum, DayNum, HourNum, MinNum, SecNum: Integer;
  Parts: TArray<string>;
begin
  Result := False;
  ALapDate := 0;

  Base := TPath.GetFileNameWithoutExtension(AFileName);
  Parts := Base.Split(['_']);
  if Length(Parts) < 6 then
    Exit;

  YearNum := StrToIntDef(Parts[0], 0);
  MonthNum := StrToIntDef(Parts[1], 0);
  DayNum := StrToIntDef(Parts[2], 0);
  HourNum := StrToIntDef(Parts[3], 0);
  MinNum := StrToIntDef(Parts[4], 0);
  SecNum := StrToIntDef(Copy(Parts[5], 1, 2), 0);

  try
    ALapDate := EncodeDateTime(YearNum, MonthNum, DayNum, HourNum, MinNum, SecNum, 0);
    Result := True;
  except
    Result := False;
  end;
end;

function FindBestTrackID(const ADB: TDatabaseManager;
  const AHint: string): Integer;
var
  Tracks: TTrackArray;
  NormalizedHint: string;
  T: TTrack;
  Candidate: string;
begin
  Result := -1;
  NormalizedHint := SimplifyTrackKey(AHint);
  if NormalizedHint = '' then
    Exit;

  Tracks := ADB.GetTracks;
  for T in Tracks do
  begin
    Candidate := SimplifyTrackKey(T.Name + ' ' + T.Layout);
    if Candidate = NormalizedHint then
      Exit(T.ID);
  end;

  for T in Tracks do
  begin
    Candidate := SimplifyTrackKey(T.Name + ' ' + T.Layout);
    if (Pos(NormalizedHint, Candidate) > 0) or (Pos(Candidate, NormalizedHint) > 0) then
      Exit(T.ID);
  end;
end;

function FindBestCarID(const ADB: TDatabaseManager;
  const AHint: string): Integer;
var
  Cars: TCarArray;
  NormalizedHint: string;
  C: TCar;
  Candidate: string;
begin
  Result := -1;
  NormalizedHint := SimplifyCarKey(AHint);
  if NormalizedHint = '' then
    Exit;

  Cars := ADB.GetCars(-1);
  for C in Cars do
  begin
    Candidate := SimplifyCarKey(C.Name);
    if Candidate = NormalizedHint then
      Exit(C.ID);
  end;

  for C in Cars do
  begin
    Candidate := SimplifyCarKey(C.Name);
    if (Pos(NormalizedHint, Candidate) > 0) or (Pos(Candidate, NormalizedHint) > 0) then
      Exit(C.ID);
  end;
end;

function ReadNodeValue(const ANode: IXMLNode;
  const ANameFragments: array of string): string;
var
  Attr: IXMLNode;
  Child: IXMLNode;
  Frag: string;
  MatchName: string;
  I: Integer;
begin
  Result := '';

  if ANode = nil then
    Exit;

  if Assigned(ANode.AttributeNodes) then
    for I := 0 to ANode.AttributeNodes.Count - 1 do
    begin
      Attr := ANode.AttributeNodes[I];
      MatchName := LowerCase(Attr.NodeName);
      for Frag in ANameFragments do
        if Pos(LowerCase(Frag), MatchName) > 0 then
          Exit(SafeVariantToString(Attr.NodeValue));
    end;

  for I := 0 to ANode.ChildNodes.Count - 1 do
  begin
    Child := ANode.ChildNodes[I];
    MatchName := LowerCase(Child.NodeName);
    for Frag in ANameFragments do
      if Pos(LowerCase(Frag), MatchName) > 0 then
      begin
        Result := SafeNodeText(Child);
        if Result <> '' then
          Exit;
      end;
  end;
end;

function IsPlayerDriverNode(const ANode: IXMLNode): Boolean;
begin
  Result :=
    (ANode <> nil) and
    (NormalizeKey(ANode.NodeName) = 'driver') and
    (SameText(ReadNodeValue(ANode, ['isplayer']), '1') or
     SameText(ReadNodeValue(ANode, ['serverscored']), '1'));
end;

procedure CollectPlayerDriverLaps(const ADriverNode: IXMLNode;
  const ATrackHint, ASessionTypeHint: string; const ADefaultDate: TDateTime;
  ACandidates: TList<TLapCandidate>);
var
  Child: IXMLNode;
  I: Integer;
  CarHint: string;
  SessionType: string;
  LapMs: Int64;
  NodeName: string;
begin
  if ADriverNode = nil then
    Exit;

  CarHint := ReadNodeValue(ADriverNode, ['cartype']);
  if CarHint = '' then
    CarHint := ReadNodeValue(ADriverNode, ['vehname']);
  if CarHint = '' then
    CarHint := ReadNodeValue(ADriverNode, ['vehicle', 'car']);

  SessionType := Trim(ASessionTypeHint);
  if SessionType = '' then
  begin
    if Assigned(ADriverNode.ParentNode) then
    SessionType := NormalizeImportedSessionType(ADriverNode.ParentNode.NodeName)
    else
      SessionType := NormalizeImportedSessionType('');
  end;

  for I := 0 to ADriverNode.ChildNodes.Count - 1 do
  begin
    Child := ADriverNode.ChildNodes[I];
    if Child = nil then
      Continue;

    NodeName := NormalizeKey(Child.NodeName);
    if (NodeName = 'lap') or IsLapTimeLikeName(Child.NodeName) then
    begin
      LapMs := ParseLapTimeMs(SafeNodeText(Child));
      AddLapCandidate(ATrackHint, CarHint, SessionType, LapMs, ADefaultDate, ACandidates);
    end;
  end;
end;

function IsPreferredDriverNode(const ANode: IXMLNode;
  const APreferredDriverName: string): Boolean;
var
  DriverName: string;
  PreferredKey: string;
  DriverKey: string;
begin
  Result := False;
  if (ANode = nil) or (NormalizeKey(ANode.NodeName) <> 'driver') then
    Exit;

  PreferredKey := NormalizeKey(APreferredDriverName);
  if PreferredKey = '' then
    Exit;

  DriverName := ReadNodeValue(ANode, ['name']);
  DriverKey := NormalizeKey(DriverName);
  Result := (DriverKey <> '') and
    ((DriverKey = PreferredKey) or (Pos(PreferredKey, DriverKey) > 0) or
     (Pos(DriverKey, PreferredKey) > 0));
end;

function CollectPreferredDriverLapCandidates(const ARoot: IXMLNode;
  const APreferredDriverName: string; const ADefaultDate: TDateTime;
  ACandidates: TList<TLapCandidate>; const ACurrentTrack: string = '';
  const ACurrentSession: string = ''): Boolean;
var
  Child: IXMLNode;
  TrackHint: string;
  SessionType: string;
  I: Integer;
begin
  Result := False;
  if ARoot = nil then
    Exit;

  TrackHint := Trim(ACurrentTrack);
  if TrackHint = '' then
    TrackHint := ReadNodeValue(ARoot, ['trackcourse']);
  if TrackHint = '' then
    TrackHint := ReadNodeValue(ARoot, ['trackvenue']);
  if TrackHint = '' then
    TrackHint := ReadNodeValue(ARoot, ['track', 'circuit', 'venue']);

  SessionType := Trim(ACurrentSession);
  if SessionType = '' then
  begin
    if SameText(ARoot.NodeName, 'Qualify') or SameText(ARoot.NodeName, 'Practice') or
       SameText(ARoot.NodeName, 'Race') or SameText(ARoot.NodeName, 'Warmup') then
      SessionType := NormalizeImportedSessionType(ARoot.NodeName);
  end;

  if IsPreferredDriverNode(ARoot, APreferredDriverName) then
  begin
    CollectPlayerDriverLaps(ARoot, TrackHint, SessionType, ADefaultDate, ACandidates);
    Exit(True);
  end;

  if Assigned(ARoot.ChildNodes) then
    for I := 0 to ARoot.ChildNodes.Count - 1 do
    begin
      Child := ARoot.ChildNodes[I];
      if CollectPreferredDriverLapCandidates(Child, APreferredDriverName,
           ADefaultDate, ACandidates, TrackHint, SessionType) then
        Result := True;
    end;
end;

function CollectPlayerLapCandidates(const ARoot: IXMLNode;
  const ADefaultDate: TDateTime; ACandidates: TList<TLapCandidate>;
  const ACurrentTrack: string = ''; const ACurrentSession: string = ''): Boolean;
var
  Child: IXMLNode;
  TrackHint: string;
  SessionType: string;
  I: Integer;
begin
  Result := False;
  if ARoot = nil then
    Exit;

  TrackHint := Trim(ACurrentTrack);
  if TrackHint = '' then
    TrackHint := ReadNodeValue(ARoot, ['trackcourse']);
  if TrackHint = '' then
    TrackHint := ReadNodeValue(ARoot, ['trackvenue']);
  if TrackHint = '' then
    TrackHint := ReadNodeValue(ARoot, ['track', 'circuit', 'venue']);

  SessionType := Trim(ACurrentSession);
  if SessionType = '' then
  begin
    if SameText(ARoot.NodeName, 'Qualify') or SameText(ARoot.NodeName, 'Practice') or
       SameText(ARoot.NodeName, 'Race') or SameText(ARoot.NodeName, 'Warmup') then
      SessionType := NormalizeImportedSessionType(ARoot.NodeName);
  end;

  if IsPlayerDriverNode(ARoot) then
  begin
    CollectPlayerDriverLaps(ARoot, TrackHint, SessionType, ADefaultDate, ACandidates);
    Exit(True);
  end;

  if Assigned(ARoot.ChildNodes) then
    for I := 0 to ARoot.ChildNodes.Count - 1 do
    begin
      Child := ARoot.ChildNodes[I];
      if CollectPlayerLapCandidates(Child, ADefaultDate, ACandidates, TrackHint, SessionType) then
        Result := True;
    end;
end;

procedure WalkNodeForLaps(const ANode: IXMLNode;
  const ACurrentTrack, ACurrentCar, ACurrentSession: string;
  const ADefaultDate: TDateTime; const ACandidates: TList<TLapCandidate>);
var
  TrackCtx, CarCtx, SessionCtx: string;
  Attr: IXMLNode;
  Child: IXMLNode;
  LapMs: Int64;
  AttrName: string;
  NodeText: string;
  NodeTrackValue, NodeCarValue, NodeSessionValue: string;
  I: Integer;
begin
  if ANode = nil then
    Exit;

  TrackCtx := ACurrentTrack;
  CarCtx := ACurrentCar;
  SessionCtx := ACurrentSession;

  NodeText := SafeNodeText(ANode);

  NodeTrackValue := ReadNodeValue(ANode, ['track', 'circuit', 'venue']);
  if NodeTrackValue <> '' then
    TrackCtx := NodeTrackValue;
  NodeCarValue := ReadNodeValue(ANode, ['car', 'vehicle', 'model']);
  if NodeCarValue <> '' then
    CarCtx := NodeCarValue;
  NodeSessionValue := ReadNodeValue(ANode, ['session', 'type']);
  if NodeSessionValue <> '' then
    SessionCtx := NodeSessionValue;

  AttrName := LowerCase(ANode.NodeName);
  if IsLapTimeLikeName(AttrName) then
  begin
    LapMs := ParseLapTimeMs(NodeText);
    AddLapCandidate(TrackCtx, CarCtx, SessionCtx, LapMs, ADefaultDate, ACandidates);
  end;

  if Assigned(ANode.AttributeNodes) then
    for I := 0 to ANode.AttributeNodes.Count - 1 do
    begin
      Attr := ANode.AttributeNodes[I];
      AttrName := LowerCase(Attr.NodeName);
      if IsLapTimeLikeName(AttrName) then
      begin
        LapMs := ParseLapTimeMs(SafeVariantToString(Attr.NodeValue));
        AddLapCandidate(TrackCtx, CarCtx, SessionCtx, LapMs, ADefaultDate, ACandidates);
      end;
    end;

  if Assigned(ANode.ChildNodes) then
    for I := 0 to ANode.ChildNodes.Count - 1 do
    begin
      Child := ANode.ChildNodes[I];
      try
        WalkNodeForLaps(Child, TrackCtx, CarCtx, SessionCtx, ADefaultDate, ACandidates);
      except
        on Exception do
          Continue;
      end;
    end;
end;

function LapAlreadyExists(const ADB: TDatabaseManager;
  ATrackID, ACarID: Integer; ALapTimeMs: Int64; ALapDate: TDateTime;
  const ASessionType: string): Boolean;
var
  Q: TFDQuery;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := ADB.Connection;
    Q.SQL.Text :=
      'SELECT 1 FROM LapTimes ' +
      'WHERE TrackID = :TrackID AND CarID = :CarID AND LapTimeMs = :LapTimeMs ' +
      '  AND date(LapDate) = date(:LapDate) AND ifnull(SessionType, '''') = :SessionType ' +
      'LIMIT 1';
    Q.ParamByName('TrackID').AsInteger := ATrackID;
    Q.ParamByName('CarID').AsInteger := ACarID;
    Q.ParamByName('LapTimeMs').AsLargeInt := ALapTimeMs;
    Q.ParamByName('LapDate').AsDateTime := ALapDate;
    Q.ParamByName('SessionType').AsString := ASessionType;
    Q.Open;
    Result := not Q.Eof;
  finally
    Q.Free;
  end;
end;

function StripDoctypeDeclaration(const AXml: string): string;
var
  StartPos, I, BracketDepth: Integer;
  InQuote: Char;
  C: Char;
  function IsDoctypeAt(const S: string; AIndex: Integer): Boolean;
  begin
    Result :=
      (AIndex > 0) and
      (AIndex + 8 <= Length(S)) and
      (S[AIndex] = '<') and
      (S[AIndex + 1] = '!') and
      (UpCase(S[AIndex + 2]) = 'D') and
      (UpCase(S[AIndex + 3]) = 'O') and
      (UpCase(S[AIndex + 4]) = 'C') and
      (UpCase(S[AIndex + 5]) = 'T') and
      (UpCase(S[AIndex + 6]) = 'Y') and
      (UpCase(S[AIndex + 7]) = 'P') and
      (UpCase(S[AIndex + 8]) = 'E');
  end;
begin
  Result := AXml;
  if Result = '' then
    Exit;

  StartPos := 0;
  for I := 1 to Length(Result) do
    if (Result[I] = '<') and IsDoctypeAt(Result, I) then
    begin
      StartPos := I;
      Break;
    end;
  if StartPos = 0 then
    Exit;

  I := StartPos + Length('<!DOCTYPE');
  BracketDepth := 0;
  InQuote := #0;

  while I <= Length(Result) do
  begin
    C := Result[I];
    if InQuote <> #0 then
    begin
      if C = InQuote then
        InQuote := #0;
    end
    else
    begin
      if (C = '''') or (C = '"') then
        InQuote := C
      else if C = '[' then
        Inc(BracketDepth)
      else if (C = ']') and (BracketDepth > 0) then
        Dec(BracketDepth)
      else if (C = '>') and (BracketDepth = 0) then
      begin
        Delete(Result, StartPos, I - StartPos + 1);
        Break;
      end;
    end;
    Inc(I);
  end;
end;

class function TResultsXMLImporter.ImportFolder(ADB: TDatabaseManager;
  const AFolder: string; const APreferredDriverName: string = ''): TResultsImportSummary;
var
  Files: TArray<string>;
  FilePath: string;
  XmlDoc: IXMLDocument;
  Candidates: TList<TLapCandidate>;
  Candidate: TLapCandidate;
  TrackID, CarID: Integer;
  LapDate: TDateTime;
  SessionType: string;
  XmlText: string;
  UsedPlayerOnlyImport: Boolean;
begin
  Result.FilesScanned := 0;
  Result.FilesFailed := 0;
  Result.LapsInserted := 0;
  Result.LapsSkipped := 0;

  if (AFolder = '') or (not TDirectory.Exists(AFolder)) then
    Exit;

  Files := TDirectory.GetFiles(AFolder, '*.xml', TSearchOption.soTopDirectoryOnly);
  if Length(Files) > 0 then
    ADB.Connection.ExecSQL('DELETE FROM LapTimes WHERE SessionType LIKE ''LMU Results XML%''');

  for FilePath in Files do
  begin
    Inc(Result.FilesScanned);
    Candidates := TList<TLapCandidate>.Create;
    try
      try
        XmlDoc := TXMLDocument.Create(nil);
        XmlDoc.Options := [doNodeAutoCreate, doNodeAutoIndent];
        XmlText := TFile.ReadAllText(FilePath, TEncoding.UTF8);
        XmlText := StripDoctypeDeclaration(XmlText);
        XmlDoc.LoadFromXML(XmlText);
        XmlDoc.Active := True;

        if not TryParseDateFromFilename(TPath.GetFileName(FilePath), LapDate) then
          LapDate := TFile.GetLastWriteTime(FilePath);

        UsedPlayerOnlyImport := False;
        if Trim(APreferredDriverName) <> '' then
          UsedPlayerOnlyImport := CollectPreferredDriverLapCandidates(
            XmlDoc.DocumentElement, APreferredDriverName, LapDate, Candidates)
        else
          UsedPlayerOnlyImport := CollectPlayerLapCandidates(XmlDoc.DocumentElement, LapDate, Candidates);

        if not UsedPlayerOnlyImport then
        begin
          if Trim(APreferredDriverName) <> '' then
            Continue;

          WalkNodeForLaps(XmlDoc.DocumentElement,
            TPath.GetFileNameWithoutExtension(FilePath), '', 'LMU Results XML', LapDate, Candidates);
        end;

        for Candidate in Candidates do
        begin
          if (Candidate.LapTimeMs < 30000) or (Candidate.LapTimeMs > 1200000) then
          begin
            Inc(Result.LapsSkipped);
            Continue;
          end;

          TrackID := FindBestTrackID(ADB, Candidate.TrackHint);
          CarID := FindBestCarID(ADB, Candidate.CarHint);
          if (TrackID <= 0) or (CarID <= 0) then
          begin
            Inc(Result.LapsSkipped);
            Continue;
          end;

          SessionType := Trim(Candidate.SessionType);
          if SessionType = '' then
            SessionType := 'LMU Results XML - Session';

          if LapAlreadyExists(ADB, TrackID, CarID, Candidate.LapTimeMs, Candidate.LapDate, SessionType) then
          begin
            Inc(Result.LapsSkipped);
            Continue;
          end;

          ADB.AddLapTime(TrackID, CarID, Candidate.LapTimeMs, SessionType, Candidate.LapDate);
          Inc(Result.LapsInserted);
        end;
      except
        Inc(Result.FilesFailed);
      end;
    finally
      Candidates.Free;
    end;
  end;
end;

end.
