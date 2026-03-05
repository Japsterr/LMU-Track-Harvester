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
  public
    constructor Create;
    destructor Destroy; override;

    procedure Save;

    property GeminiAPIKey: string read GetGeminiAPIKey write SetGeminiAPIKey;
    property AIModel: string read GetAIModel write SetAIModel;
    property LastExportFolder: string read GetLastExportFolder write SetLastExportFolder;
    property WindowMaximized: Boolean read GetWindowMaximized write SetWindowMaximized;
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

end.
