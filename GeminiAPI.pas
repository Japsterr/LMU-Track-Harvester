unit GeminiAPI;

{ Wraps the Google Gemini generative language REST API.
  Uses System.Net.HttpClient which ships with Delphi 10.3+.
  No third-party libraries required.

  Supported models (Gemini 1.5 family, current at time of writing):
    gemini-1.5-flash   – fast, cost-effective
    gemini-1.5-pro     – higher quality, slower
    gemini-2.0-flash   – next-gen fast model
}

interface

uses
  System.SysUtils, System.Classes,
  System.Net.HttpClient, System.Net.URLClient,
  System.JSON;

type
  TGeminiAPI = class
  private
    FAPIKey: string;
    FModel: string;
    FBaseURL: string;

    function BuildRequestJSON(const APrompt: string): string;
    function ParseResponseJSON(const AResponseText: string): string;
  public
    constructor Create(const AAPIKey: string;
                       const AModel: string = 'gemini-1.5-flash');

    { Send CSV telemetry data and receive coaching feedback. }
    function GetCoachingAdvice(const ACSVData: string;
                               const ATrackName, ACarName,
                               AClassName: string): string;

    { Generic prompt – caller supplies both system instructions and user text. }
    function SendPrompt(const ASystemInstruction,
                        AUserText: string): string;

    property APIKey: string read FAPIKey write FAPIKey;
    property Model: string  read FModel  write FModel;
  end;

implementation

// ---------------------------------------------------------------------------
// Constructor
// ---------------------------------------------------------------------------

constructor TGeminiAPI.Create(const AAPIKey: string;
  const AModel: string = 'gemini-1.5-flash');
begin
  inherited Create;
  FAPIKey   := AAPIKey;
  FModel    := AModel;
  FBaseURL  := 'https://generativelanguage.googleapis.com/v1beta/models/';
end;

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

function TGeminiAPI.BuildRequestJSON(const APrompt: string): string;
var
  Root, GenCfg: TJSONObject;
  Contents: TJSONArray;
  Content, Part: TJSONObject;
  Parts: TJSONArray;
begin
  Root := TJSONObject.Create;
  try
    Contents := TJSONArray.Create;
    Content  := TJSONObject.Create;
    Parts    := TJSONArray.Create;
    Part     := TJSONObject.Create;

    Part.AddPair('text', APrompt);
    Parts.Add(Part);
    Content.AddPair('parts', Parts);
    Contents.Add(Content);
    Root.AddPair('contents', Contents);

    GenCfg := TJSONObject.Create;
    GenCfg.AddPair('temperature', TJSONNumber.Create(0.7));
    GenCfg.AddPair('maxOutputTokens', TJSONNumber.Create(8192));
    Root.AddPair('generationConfig', GenCfg);

    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function TGeminiAPI.ParseResponseJSON(const AResponseText: string): string;
var
  Root: TJSONValue;
  Candidates: TJSONArray;
  Candidate, Content, Part: TJSONObject;
  Parts: TJSONArray;
  ErrorObj: TJSONObject;
begin
  Result := '';
  Root := TJSONObject.ParseJSONValue(AResponseText);
  if Root = nil then
  begin
    Result := 'Error: Could not parse API response.';
    Exit;
  end;
  try
    // Check for API-level error
    ErrorObj := (Root as TJSONObject).GetValue<TJSONObject>('error');
    if Assigned(ErrorObj) then
    begin
      Result := 'API Error: ' + ErrorObj.GetValue<string>('message');
      Exit;
    end;

    Candidates := (Root as TJSONObject).GetValue<TJSONArray>('candidates');
    if (not Assigned(Candidates)) or (Candidates.Count = 0) then
    begin
      Result := 'Error: No candidates returned by API.';
      Exit;
    end;

    Candidate := Candidates.Items[0] as TJSONObject;
    Content   := Candidate.GetValue<TJSONObject>('content');
    if not Assigned(Content) then
    begin
      Result := 'Error: No content in candidate.';
      Exit;
    end;

    Parts := Content.GetValue<TJSONArray>('parts');
    if (not Assigned(Parts)) or (Parts.Count = 0) then
    begin
      Result := 'Error: No parts in content.';
      Exit;
    end;

    Part   := Parts.Items[0] as TJSONObject;
    Result := Part.GetValue<string>('text');
  finally
    Root.Free;
  end;
end;

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

function TGeminiAPI.SendPrompt(const ASystemInstruction, AUserText: string): string;
var
  HTTP: THTTPClient;
  RequestBody: string;
  Stream: TStringStream;
  Response: IHTTPResponse;
  URL: string;
begin
  Result := '';

  if FAPIKey.IsEmpty then
  begin
    Result := 'Error: No Gemini API key configured. ' +
              'Please add your API key in the Settings tab.';
    Exit;
  end;

  URL := FBaseURL + FModel + ':generateContent?key=' + FAPIKey;

  HTTP := THTTPClient.Create;
  try
    RequestBody := BuildRequestJSON(ASystemInstruction + #13#10 + AUserText);
    Stream := TStringStream.Create(RequestBody, TEncoding.UTF8);
    try
      HTTP.ContentType := 'application/json';
      try
        Response := HTTP.Post(URL, Stream);
        if Response.StatusCode = 200 then
          Result := ParseResponseJSON(Response.ContentAsString(TEncoding.UTF8))
        else
          Result := Format('HTTP %d: %s',
            [Response.StatusCode,
             Response.ContentAsString(TEncoding.UTF8)]);
      except
        on E: Exception do
          Result := 'Network error: ' + E.Message;
      end;
    finally
      Stream.Free;
    end;
  finally
    HTTP.Free;
  end;
end;

function TGeminiAPI.GetCoachingAdvice(const ACSVData: string;
  const ATrackName, ACarName, AClassName: string): string;
const
  SystemInstruction =
    'You are an expert motorsport driving coach specialising in endurance ' +
    'racing and the Le Mans Ultimate simulation. ' +
    'Analyse the telemetry data provided and give detailed, actionable ' +
    'coaching feedback. Structure your response with these sections:' + #13#10 +
    '1. Overall Summary' + #13#10 +
    '2. Track Breakdown Map' + #13#10 +
    '3. Braking Analysis – braking points, pressure, and release' + #13#10 +
    '4. Throttle Application – trail-braking, rotation, and exit drive' + #13#10 +
    '5. Gear Selection – any missed or suboptimal gear changes' + #13#10 +
    '6. Steering Inputs – smoothness, corrections, and scrub' + #13#10 +
    '7. Focus Corners – top 3 corners or sections to attack next' + #13#10 +
    'For each focus corner or section, include:' + #13#10 +
    '- sector or lap-distance range' + #13#10 +
    '- corner name if known, otherwise a plain-language label' + #13#10 +
    '- where it is on track in simple map language such as first heavy stop, uphill blind right, final long sweeper' + #13#10 +
    '- what the telemetry suggests is wrong' + #13#10 +
    '- one concrete driving goal' + #13#10 +
    'If the track corner names are not obvious from telemetry alone, do not invent official names. Use sector plus lap-distance ranges and a simple description instead. Be specific and reference lap-distance values where relevant.';
var
  UserText: string;
begin
  UserText :=
    'Track: ' + ATrackName + #13#10 +
    'Car: ' + ACarName + ' (' + AClassName + ')' + #13#10 +
    #13#10 +
    'CSV column definitions:' + #13#10 +
    '  TimestampMs     – milliseconds from session start' + #13#10 +
    '  Speed_kmh       – speed in km/h' + #13#10 +
    '  RPM             – engine RPM' + #13#10 +
    '  Gear            – gear position (0=neutral)' + #13#10 +
    '  Throttle_pct    – throttle 0–100 %' + #13#10 +
    '  Brake_pct       – brake pressure 0–100 %' + #13#10 +
    '  Steering_pct    – steering -100 % (full left) to +100 % (full right)' + #13#10 +
    '  LapDistance_pct – fraction of lap completed 0.0–1.0' + #13#10 +
    #13#10 +
    'Telemetry data:' + #13#10 +
    ACSVData;

  Result := SendPrompt(SystemInstruction, UserText);
end;

end.
