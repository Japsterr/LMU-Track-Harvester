object ImportTelemetryForm: TImportTelemetryForm
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Import Telemetry Session'
  ClientHeight = 258
  ClientWidth = 460
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -13
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poOwnerFormCenter
  OnCreate = FormCreate
  PixelsPerInch = 96
  TextHeight = 17
  object LblTrack: TLabel
    Left = 16
    Top = 22
    Width = 35
    Height = 17
    Caption = 'Track:'
  end
  object LblCar: TLabel
    Left = 16
    Top = 62
    Width = 24
    Height = 17
    Caption = 'Car:'
  end
  object LblCSV: TLabel
    Left = 16
    Top = 102
    Width = 47
    Height = 17
    Caption = 'CSV File:'
  end
  object LblNotes: TLabel
    Left = 16
    Top = 152
    Width = 36
    Height = 17
    Caption = 'Notes:'
  end
  object LblCSVNote: TLabel
    Left = 16
    Top = 126
    Width = 428
    Height = 34
    AutoSize = False
    Caption = 'CSV must have columns: TimestampMs, Speed_kmh, RPM, Gear, Throttle_pct, Brake_pct, Steering_pct, LapDistance_pct'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clGrayText
    Font.Height = -11
    Font.Name = 'Segoe UI'
    Font.Style = []
    ParentFont = False
    WordWrap = True
  end
  object CboTrack: TComboBox
    Left = 100
    Top = 18
    Width = 344
    Height = 25
    Style = csDropDownList
    TabOrder = 0
  end
  object CboCar: TComboBox
    Left = 100
    Top = 58
    Width = 344
    Height = 25
    Style = csDropDownList
    TabOrder = 1
  end
  object EdtCSVFile: TEdit
    Left = 100
    Top = 98
    Width = 290
    Height = 25
    ReadOnly = True
    TabOrder = 2
  end
  object BtnBrowse: TButton
    Left = 398
    Top = 98
    Width = 46
    Height = 25
    Caption = '...'
    TabOrder = 3
    OnClick = BtnBrowseClick
  end
  object EdtNotes: TEdit
    Left = 100
    Top = 148
    Width = 344
    Height = 25
    MaxLength = 200
    TabOrder = 4
  end
  object BtnImport: TButton
    Left = 268
    Top = 216
    Width = 80
    Height = 30
    Caption = 'Import'
    Default = True
    ModalResult = mrNone
    TabOrder = 5
    OnClick = BtnImportClick
  end
  object BtnCancel: TButton
    Left = 364
    Top = 216
    Width = 80
    Height = 30
    Cancel = True
    Caption = 'Cancel'
    ModalResult = mrCancel
    TabOrder = 6
  end
end
