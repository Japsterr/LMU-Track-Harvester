unit AddLapForm;

{ Dialog for manually recording a personal-best lap time.
  The user selects track, car class, car, enters the lap time (M:SS.mmm),
  picks the date and session type, then clicks 'Add Lap'. }

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.SysUtils, System.Classes,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls,
  LapTimeModels, DatabaseManager;

type
  TAddLapForm = class(TForm)
    LblTrack: TLabel;
    LblClass: TLabel;
    LblCar: TLabel;
    LblLapTime: TLabel;
    LblLapTimeHint: TLabel;
    LblDate: TLabel;
    LblSession: TLabel;
    CboTrack: TComboBox;
    CboClass: TComboBox;
    CboCar: TComboBox;
    EdtLapTime: TEdit;
    DtpLapDate: TDateTimePicker;
    CboSessionType: TComboBox;
    BtnOK: TButton;
    BtnCancel: TButton;

    procedure FormCreate(Sender: TObject);
    procedure CboTrackChange(Sender: TObject);
    procedure CboClassChange(Sender: TObject);
    procedure BtnOKClick(Sender: TObject);
  private
    FDB: TDatabaseManager;
    FTracks: TTrackArray;
    FClasses: TCarClassArray;
    FCars: TCarArray;

    procedure LoadTracks;
    procedure LoadClasses;
    procedure LoadCars;
  public
    { Call Initialize(DB) after Create and before ShowModal. }
    procedure Initialize(ADB: TDatabaseManager);
    property DB: TDatabaseManager read FDB write FDB;
  end;

var
  AddLapForm: TAddLapForm;

implementation

{$R *.dfm}

procedure TAddLapForm.FormCreate(Sender: TObject);
begin
  DtpLapDate.Date := Now;
  CboSessionType.ItemIndex := 0;
end;

procedure TAddLapForm.Initialize(ADB: TDatabaseManager);
begin
  FDB := ADB;
  LoadTracks;
  LoadClasses;
  LoadCars;
end;

procedure TAddLapForm.LoadTracks;
var
  I: Integer;
begin
  CboTrack.Items.BeginUpdate;
  try
    CboTrack.Items.Clear;
    FTracks := FDB.GetTracks;
    for I := 0 to High(FTracks) do
      CboTrack.Items.Add(FTracks[I].DisplayName);
  finally
    CboTrack.Items.EndUpdate;
  end;
  if CboTrack.Items.Count > 0 then
    CboTrack.ItemIndex := 0;
end;

procedure TAddLapForm.LoadClasses;
var
  I: Integer;
begin
  CboClass.Items.BeginUpdate;
  try
    CboClass.Items.Clear;
    FClasses := FDB.GetCarClasses;
    for I := 0 to High(FClasses) do
      CboClass.Items.Add(FClasses[I].Name);
  finally
    CboClass.Items.EndUpdate;
  end;
  if CboClass.Items.Count > 0 then
    CboClass.ItemIndex := 0;
  LoadCars;
end;

procedure TAddLapForm.LoadCars;
var
  I: Integer;
  ClassID: Integer;
begin
  ClassID := -1;
  if (CboClass.ItemIndex >= 0) and (CboClass.ItemIndex <= High(FClasses)) then
    ClassID := FClasses[CboClass.ItemIndex].ID;

  CboCar.Items.BeginUpdate;
  try
    CboCar.Items.Clear;
    FCars := FDB.GetCars(ClassID);
    for I := 0 to High(FCars) do
      CboCar.Items.Add(FCars[I].Name);
  finally
    CboCar.Items.EndUpdate;
  end;
  if CboCar.Items.Count > 0 then
    CboCar.ItemIndex := 0;
end;

procedure TAddLapForm.CboTrackChange(Sender: TObject);
begin
  // Nothing extra needed – track just needs to be selected
end;

procedure TAddLapForm.CboClassChange(Sender: TObject);
begin
  LoadCars;
end;

procedure TAddLapForm.BtnOKClick(Sender: TObject);
var
  LapMs: Int64;
  TrackID, CarID: Integer;
  SessionType: string;
begin
  // Validate track
  if CboTrack.ItemIndex < 0 then
  begin
    ShowMessage('Please select a track.');
    CboTrack.SetFocus;
    Exit;
  end;

  // Validate car
  if CboCar.ItemIndex < 0 then
  begin
    ShowMessage('Please select a car.');
    CboCar.SetFocus;
    Exit;
  end;

  // Validate lap time
  LapMs := ParseLapTime(EdtLapTime.Text);
  if LapMs <= 0 then
  begin
    ShowMessage('Invalid lap time. Use format M:SS.mmm (e.g. 3:27.456).');
    EdtLapTime.SetFocus;
    Exit;
  end;

  TrackID := FTracks[CboTrack.ItemIndex].ID;
  CarID   := FCars[CboCar.ItemIndex].ID;

  if CboSessionType.ItemIndex >= 0 then
    SessionType := CboSessionType.Items[CboSessionType.ItemIndex]
  else
    SessionType := 'Practice';

  FDB.AddLapTime(TrackID, CarID, LapMs, SessionType, DtpLapDate.Date);
  ModalResult := mrOk;
end;

end.
