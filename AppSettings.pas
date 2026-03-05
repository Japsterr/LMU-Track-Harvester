unit AppSettings;

{ Manages persistent application settings stored in an INI file.
  Preferred location is Documents\LMUTrackHarvester\, with writable
  fallback locations if Documents is unavailable. }

interface

uses
  Winapi.Windows,
  System.SysUtils, System.IniFiles, System.IOUtils;

type
  TAppSettings = class
  private
    FIniFile: TIniFile;
    FSettingsPath: string;

    function GetGeminiAPIKey: string;
    procedure SetGeminiAPIKey(const Value: string);
    function GetAIModel: string;
    procedure SetAIModel(const Value: string);
    function GetLastExportFolder: string;
    procedure SetLastExportFolder(const Value: string);
    function GetWindowMaximized: Boolean;
    procedure SetWindowMaximized(const Value: Boolean);
    function GetTelemetrySourceFolder: string;
    procedure SetTelemetrySourceFolder(const Value: string);
  public
    constructor Create;
    destructor Destroy; override;

    procedure Save;

    property GeminiAPIKey: string read GetGeminiAPIKey write SetGeminiAPIKey;
    property AIModel: string read GetAIModel write SetAIModel;
    property LastExportFolder: string read GetLastExportFolder write SetLastExportFolder;
    property WindowMaximized: Boolean read GetWindowMaximized write SetWindowMaximized;
    property TelemetrySourceFolder: string read GetTelemetrySourceFolder write SetTelemetrySourceFolder;
  end;

implementation

const
  CWriteProbePrefix = '.__lth_writeprobe_';

constructor TAppSettings.Create;
var
  AppDir: string;
  function EnsureWritableDir(const APath: string): Boolean;
  var
    ProbeFile: string;
    ProbeGuid: string;
  begin
    Result := (APath <> '') and (DirectoryExists(APath) or ForceDirectories(APath));
    if not Result then
      Exit;

    ProbeGuid := GUIDToString(TGUID.NewGuid).Replace('{', '').Replace('}', '');
    ProbeFile := TPath.Combine(APath, CWriteProbePrefix + ProbeGuid + '.tmp');
    try
      TFile.WriteAllText(ProbeFile, 'ok');
      try
        TFile.Delete(ProbeFile);
      except
        // Ignore cleanup failures for temporary writability probe file.
      end;
      Result := True;
    except
      Result := False;
    end;
  end;
begin
  inherited;
  AppDir := TPath.Combine(TPath.GetDocumentsPath, 'LMUTrackHarvester');
  if not EnsureWritableDir(AppDir) then
  begin
    AppDir := TPath.Combine(TPath.GetHomePath, 'LMUTrackHarvester');
    if not EnsureWritableDir(AppDir) then
    begin
      AppDir := TPath.Combine(ExtractFilePath(ParamStr(0)), 'LMUTrackHarvester');
      if not EnsureWritableDir(AppDir) then
        raise Exception.CreateFmt(
          'Unable to create writable settings directory after trying fallback locations. Last attempt: %s',
          [AppDir]
        );
    end;
  end;

  FSettingsPath := TPath.Combine(AppDir, 'settings.ini');
  FIniFile := TIniFile.Create(FSettingsPath);
end;

destructor TAppSettings.Destroy;
begin
  try
    Save;
  except
    on E: Exception do
      OutputDebugString(PChar('LMU Track Harvester: Failed to persist settings during shutdown: ' + E.Message));
  end;
  FIniFile.Free;
  inherited;
end;

procedure TAppSettings.Save;
begin
  FIniFile.UpdateFile;
end;

// ---------------------------------------------------------------------------
// API settings
// ---------------------------------------------------------------------------

function TAppSettings.GetGeminiAPIKey: string;
begin
  Result := FIniFile.ReadString('API', 'GeminiKey', '');
end;

procedure TAppSettings.SetGeminiAPIKey(const Value: string);
begin
  FIniFile.WriteString('API', 'GeminiKey', Value);
end;

function TAppSettings.GetAIModel: string;
begin
  Result := FIniFile.ReadString('API', 'Model', 'gemini-1.5-flash');
end;

procedure TAppSettings.SetAIModel(const Value: string);
begin
  FIniFile.WriteString('API', 'Model', Value);
end;

// ---------------------------------------------------------------------------
// UI / UX settings
// ---------------------------------------------------------------------------

function TAppSettings.GetLastExportFolder: string;
begin
  Result := FIniFile.ReadString('UI', 'LastExportFolder', TPath.GetDocumentsPath);
end;

procedure TAppSettings.SetLastExportFolder(const Value: string);
begin
  FIniFile.WriteString('UI', 'LastExportFolder', Value);
end;

function TAppSettings.GetWindowMaximized: Boolean;
begin
  Result := FIniFile.ReadBool('UI', 'Maximized', False);
end;

procedure TAppSettings.SetWindowMaximized(const Value: Boolean);
begin
  FIniFile.WriteBool('UI', 'Maximized', Value);
end;

function TAppSettings.GetTelemetrySourceFolder: string;
var
  StoredPath: string;
  ProgramFilesX86Path, ProgramFilesPath: string;
  SteamPFx86Path: string;
  SteamPFPath: string;
  SteamCDrivePath: string;
  SteamHomePath: string;
begin
  StoredPath := Trim(FIniFile.ReadString('Telemetry', 'SourceFolder', ''));
  if StoredPath <> '' then
    Exit(StoredPath);

  ProgramFilesX86Path := Trim(GetEnvironmentVariable('ProgramFiles(x86)'));
  ProgramFilesPath := Trim(GetEnvironmentVariable('ProgramFiles'));

  SteamPFx86Path := TPath.Combine(ProgramFilesX86Path,
    'Steam\steamapps\common\Le Mans Ultimate\UserData\Telemetry');
  SteamPFPath := TPath.Combine(ProgramFilesPath,
    'Steam\steamapps\common\Le Mans Ultimate\UserData\Telemetry');
  SteamCDrivePath := 'C:\SteamLibrary\steamapps\common\Le Mans Ultimate\UserData\Telemetry';
  SteamHomePath := TPath.Combine(TPath.GetHomePath,
    'SteamLibrary\steamapps\common\Le Mans Ultimate\UserData\Telemetry');

  if (SteamPFx86Path <> '') and TDirectory.Exists(SteamPFx86Path) then
    Exit(SteamPFx86Path);
  if (SteamPFPath <> '') and TDirectory.Exists(SteamPFPath) then
    Exit(SteamPFPath);
  if (SteamCDrivePath <> '') and TDirectory.Exists(SteamCDrivePath) then
    Exit(SteamCDrivePath);
  if (SteamHomePath <> '') and TDirectory.Exists(SteamHomePath) then
    Exit(SteamHomePath);

  if SteamCDrivePath <> '' then
    Result := SteamCDrivePath
  else if SteamPFx86Path <> '' then
    Result := SteamPFx86Path
  else if SteamHomePath <> '' then
    Result := SteamHomePath
  else
    Result := SteamPFPath;
end;

procedure TAppSettings.SetTelemetrySourceFolder(const Value: string);
begin
  FIniFile.WriteString('Telemetry', 'SourceFolder', Trim(Value));
end;

end.
