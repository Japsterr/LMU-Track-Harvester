unit AppSettings;

{ Manages persistent application settings stored in an INI file located next
  to the executable (or in Documents\LMUTrackHarvester\ when deployed). }

interface

uses
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

constructor TAppSettings.Create;
var
  AppDir: string;
begin
  inherited;
  AppDir := TPath.Combine(TPath.GetDocumentsPath, 'LMUTrackHarvester');
  ForceDirectories(AppDir);
  FSettingsPath := TPath.Combine(AppDir, 'settings.ini');
  FIniFile := TIniFile.Create(FSettingsPath);
end;

destructor TAppSettings.Destroy;
begin
  Save;
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
