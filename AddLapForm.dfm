object AddLapForm: TAddLapForm
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Add Lap Time'
  ClientHeight = 310
  ClientWidth = 430
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
  object LblClass: TLabel
    Left = 16
    Top = 62
    Width = 57
    Height = 17
    Caption = 'Car Class:'
  end
  object LblCar: TLabel
    Left = 16
    Top = 102
    Width = 24
    Height = 17
    Caption = 'Car:'
  end
  object LblLapTime: TLabel
    Left = 16
    Top = 142
    Width = 55
    Height = 17
    Caption = 'Lap Time:'
  end
  object LblLapTimeHint: TLabel
    Left = 310
    Top = 145
    Width = 105
    Height = 17
    Caption = 'Format: M:SS.mmm'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clGrayText
    Font.Height = -11
    Font.Name = 'Segoe UI'
    Font.Style = []
    ParentFont = False
  end
  object LblDate: TLabel
    Left = 16
    Top = 182
    Width = 28
    Height = 17
    Caption = 'Date:'
  end
  object LblSession: TLabel
    Left = 16
    Top = 222
    Width = 73
    Height = 17
    Caption = 'Session Type:'
  end
  object CboTrack: TComboBox
    Left = 100
    Top = 18
    Width = 314
    Height = 25
    Style = csDropDownList
    TabOrder = 0
    OnChange = CboTrackChange
  end
  object CboClass: TComboBox
    Left = 100
    Top = 58
    Width = 314
    Height = 25
    Style = csDropDownList
    TabOrder = 1
    OnChange = CboClassChange
  end
  object CboCar: TComboBox
    Left = 100
    Top = 98
    Width = 314
    Height = 25
    Style = csDropDownList
    TabOrder = 2
  end
  object EdtLapTime: TEdit
    Left = 100
    Top = 138
    Width = 200
    Height = 25
    TabOrder = 3
    Text = '0:00.000'
  end
  object DtpLapDate: TDateTimePicker
    Left = 100
    Top = 178
    Width = 200
    Height = 25
    Date = 45000.0
    Time = 0.0
    TabOrder = 4
  end
  object CboSessionType: TComboBox
    Left = 100
    Top = 218
    Width = 200
    Height = 25
    Style = csDropDownList
    TabOrder = 5
    Items.Strings = (
      'Practice'
      'Qualifying'
      'Race'
      'Time Attack'
      'Hot Lap')
  end
  object BtnOK: TButton
    Left = 238
    Top = 268
    Width = 80
    Height = 30
    Caption = 'Add Lap'
    Default = True
    ModalResult = 0
    TabOrder = 6
    OnClick = BtnOKClick
  end
  object BtnCancel: TButton
    Left = 334
    Top = 268
    Width = 80
    Height = 30
    Cancel = True
    Caption = 'Cancel'
    ModalResult = mrCancel
    TabOrder = 7
  end
end
