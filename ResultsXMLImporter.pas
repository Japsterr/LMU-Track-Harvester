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
      const AFolder: string): TResultsImportSummary;
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

function NormalizeKey(const S: string): string;
var
  C: Char;
begin
  Result := '';
  for C in LowerCase(S) do
    if CharInSet(C, ['a'..'z', '0'..'9']) then
      Result := Result + C;
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
  NormalizedHint := NormalizeKey(AHint);
  if NormalizedHint = '' then
    Exit;

  Tracks := ADB.GetTracks;
  for T in Tracks do
  begin
    Candidate := NormalizeKey(T.Name + T.Layout);
    if Candidate = NormalizedHint then
      Exit(T.ID);
  end;

  for T in Tracks do
  begin
    Candidate := NormalizeKey(T.Name + T.Layout);
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
  NormalizedHint := NormalizeKey(AHint);
  if NormalizedHint = '' then
    Exit;

  Cars := ADB.GetCars(-1);
  for C in Cars do
  begin
    Candidate := NormalizeKey(C.Name);
    if Candidate = NormalizedHint then
      Exit(C.ID);
  end;

  for C in Cars do
  begin
    Candidate := NormalizeKey(C.Name);
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
          Exit(Trim(VarToStr(Attr.NodeValue)));
    end;

  for I := 0 to ANode.ChildNodes.Count - 1 do
  begin
    Child := ANode.ChildNodes[I];
    MatchName := LowerCase(Child.NodeName);
    for Frag in ANameFragments do
      if Pos(LowerCase(Frag), MatchName) > 0 then
      begin
        try
          Result := Trim(Child.Text);
        except
          on E: EXMLDocError do
            Result := '';
        end;
        if Result <> '' then
          Exit;
      end;
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
  LapCandidate: TLapCandidate;
  NodeText: string;
  NodeTrackValue, NodeCarValue, NodeSessionValue: string;
  I: Integer;
begin
  if ANode = nil then
    Exit;

  TrackCtx := ACurrentTrack;
  CarCtx := ACurrentCar;
  SessionCtx := ACurrentSession;

  try
    NodeText := Trim(ANode.Text);
  except
    on E: EXMLDocError do
      NodeText := '';
  end;

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
  if ((Pos('lap', AttrName) > 0) and (Pos('time', AttrName) > 0)) or
     (Pos('bestlap', AttrName) > 0) then
  begin
    LapMs := ParseLapTimeMs(NodeText);
    if LapMs > 0 then
    begin
      LapCandidate.TrackHint := TrackCtx;
      LapCandidate.CarHint := CarCtx;
      LapCandidate.SessionType := SessionCtx;
      LapCandidate.LapTimeMs := LapMs;
      LapCandidate.LapDate := ADefaultDate;
      ACandidates.Add(LapCandidate);
    end;
  end;

  if Assigned(ANode.AttributeNodes) then
    for I := 0 to ANode.AttributeNodes.Count - 1 do
    begin
      Attr := ANode.AttributeNodes[I];
      AttrName := LowerCase(Attr.NodeName);
      if ((Pos('lap', AttrName) > 0) and (Pos('time', AttrName) > 0)) or
         (Pos('bestlap', AttrName) > 0) then
      begin
        LapMs := ParseLapTimeMs(Trim(VarToStr(Attr.NodeValue)));
        if LapMs > 0 then
        begin
          LapCandidate.TrackHint := TrackCtx;
          LapCandidate.CarHint := CarCtx;
          LapCandidate.SessionType := SessionCtx;
          LapCandidate.LapTimeMs := LapMs;
          LapCandidate.LapDate := ADefaultDate;
          ACandidates.Add(LapCandidate);
        end;
      end;
    end;

  for I := 0 to ANode.ChildNodes.Count - 1 do
  begin
    Child := ANode.ChildNodes[I];
    WalkNodeForLaps(Child, TrackCtx, CarCtx, SessionCtx, ADefaultDate, ACandidates);
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
  const AFolder: string): TResultsImportSummary;
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
begin
  Result.FilesScanned := 0;
  Result.FilesFailed := 0;
  Result.LapsInserted := 0;
  Result.LapsSkipped := 0;

  if (AFolder = '') or (not TDirectory.Exists(AFolder)) then
    Exit;

  Files := TDirectory.GetFiles(AFolder, '*.xml', TSearchOption.soTopDirectoryOnly);
  for FilePath in Files do
  begin
    Inc(Result.FilesScanned);
    Candidates := TList<TLapCandidate>.Create;
    try
      XmlDoc := TXMLDocument.Create(nil);
      XmlDoc.Options := [doNodeAutoCreate, doNodeAutoIndent];
      XmlText := TFile.ReadAllText(FilePath, TEncoding.UTF8);
      XmlText := StripDoctypeDeclaration(XmlText);
      XmlDoc.LoadFromXML(XmlText);
      XmlDoc.Active := True;

      if not TryParseDateFromFilename(TPath.GetFileName(FilePath), LapDate) then
        LapDate := TFile.GetLastWriteTime(FilePath);

      WalkNodeForLaps(XmlDoc.DocumentElement,
        TPath.GetFileNameWithoutExtension(FilePath), '', 'LMU Results XML', LapDate, Candidates);

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
          SessionType := 'LMU Results XML';

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
  end;
end;

end.
