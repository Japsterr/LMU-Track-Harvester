object MainForm: TMainForm
  Left = 0
  Top = 0
  Caption = 'LMU Track Harvester - Driver Performance Hub'
  ClientHeight = 720
  ClientWidth = 1150
  Color = 1314571
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -13
  Font.Name = 'Bahnschrift'
  Font.Style = []
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  TextHeight = 17
  object StatusBar: TStatusBar
    Left = 0
    Top = 697
    Width = 1150
    Height = 23
    Panels = <
      item
        Text = 'Ready'
        Width = 500
      end
      item
        Width = 150
      end>
  end
  object PageControl: TPageControl
    Left = 0
    Top = 0
    Width = 1150
    Height = 697
    ActivePage = TabLapTimes
    Align = alClient
    TabHeight = 28
    TabOrder = 0
    object TabLapTimes: TTabSheet
      Caption = 'Lap Times'
      object PnlLTTop: TPanel
        Left = 0
        Top = 0
        Width = 1142
        Height = 64
        Align = alTop
        BevelOuter = bvNone
        Color = 2161174
        ParentBackground = False
        TabOrder = 0
        object LblTrack: TLabel
          Left = 8
          Top = 22
          Width = 33
          Height = 17
          Caption = 'Track:'
          Font.Charset = DEFAULT_CHARSET
          Font.Color = clWhite
          Font.Height = -13
          Font.Name = 'Bahnschrift'
          Font.Style = [fsBold]
          ParentFont = False
        end
        object LblClass: TLabel
          Left = 384
          Top = 22
          Width = 57
          Height = 17
          Caption = 'Car Class:'
          Font.Charset = DEFAULT_CHARSET
          Font.Color = clWhite
          Font.Height = -13
          Font.Name = 'Bahnschrift'
          Font.Style = [fsBold]
          ParentFont = False
        end
        object CboTrack: TComboBox
          Left = 52
          Top = 18
          Width = 320
          Height = 25
          Style = csDropDownList
          TabOrder = 0
          OnChange = CboTrackChange
        end
        object CboClass: TComboBox
          Left = 450
          Top = 18
          Width = 200
          Height = 25
          Style = csDropDownList
          TabOrder = 1
          OnChange = CboClassChange
        end
        object BtnAddLap: TButton
          Left = 670
          Top = 16
          Width = 120
          Height = 30
          Caption = '+ Log Lap'
          Font.Charset = DEFAULT_CHARSET
          Font.Color = clWindowText
          Font.Height = -13
          Font.Name = 'Bahnschrift'
          Font.Style = [fsBold]
          ParentFont = False
          TabOrder = 2
          OnClick = BtnAddLapClick
        end
        object BtnDeleteLap: TButton
          Left = 800
          Top = 16
          Width = 120
          Height = 30
          Caption = 'Delete Lap'
          Font.Charset = DEFAULT_CHARSET
          Font.Color = clWindowText
          Font.Height = -13
          Font.Name = 'Bahnschrift'
          Font.Style = [fsBold]
          ParentFont = False
          TabOrder = 3
          OnClick = BtnDeleteLapClick
        end
        object BtnExportLaps: TButton
          Left = 930
          Top = 16
          Width = 120
          Height = 30
          Caption = 'Export Pace'
          Font.Charset = DEFAULT_CHARSET
          Font.Color = clWindowText
          Font.Height = -13
          Font.Name = 'Bahnschrift'
          Font.Style = [fsBold]
          ParentFont = False
          TabOrder = 4
          OnClick = BtnExportLapsClick
        end
      end
      object PnlLTContent: TPanel
        Left = 0
        Top = 64
        Width = 1142
        Height = 595
        Align = alClient
        BevelOuter = bvNone
        Color = 1314571
        ParentBackground = False
        TabOrder = 1
        ExplicitHeight = 611
        object SplitterLT: TSplitter
          Left = 565
          Top = 0
          Width = 6
          Height = 611
        end
        object GrpTop10: TGroupBox
          Left = 0
          Top = 0
          Width = 548
          Height = 611
          Align = alLeft
          Caption = ' Driver Top 10 Pace '
          Color = 15002865
          Font.Charset = DEFAULT_CHARSET
          Font.Color = clWindowText
          Font.Height = -13
          Font.Name = 'Bahnschrift'
          Font.Style = [fsBold]
          ParentBackground = False
          ParentFont = False
          TabOrder = 0
          object LvwTop10: TListView
            Left = 2
            Top = 20
            Width = 544
            Height = 589
            Align = alClient
            Columns = <
              item
                Caption = '#'
                Width = 30
              end
              item
                Caption = 'Car'
                Width = 210
              end
              item
                Caption = 'Lap Time'
                Width = 95
              end
              item
                Caption = 'Date'
                Width = 110
              end
              item
                Caption = 'Session'
                Width = 90
              end>
            Color = 15921906
            GridLines = False
            ReadOnly = True
            RowSelect = True
            TabOrder = 0
            ViewStyle = vsReport
            OnSelectItem = LvwTop10SelectItem
          end
        end
        object GrpFastest: TGroupBox
          Left = 554
          Top = 0
          Width = 588
          Height = 611
          Align = alClient
          Caption = ' Best Personal Lap Per Car '
          Color = 15002865
          Font.Charset = DEFAULT_CHARSET
          Font.Color = clWindowText
          Font.Height = -13
          Font.Name = 'Bahnschrift'
          Font.Style = [fsBold]
          ParentBackground = False
          ParentFont = False
          TabOrder = 1
          object LvwFastest: TListView
            Left = 2
            Top = 20
            Width = 584
            Height = 589
            Align = alClient
            Columns = <
              item
                Caption = '#'
                Width = 30
              end
              item
                Caption = 'Car'
                Width = 220
              end
              item
                Caption = 'Best Lap'
                Width = 95
              end
              item
                Caption = 'Date'
                Width = 110
              end
              item
                Caption = 'Session'
                Width = 90
              end>
            Color = 15921906
            GridLines = False
            ReadOnly = True
            RowSelect = True
            TabOrder = 0
            ViewStyle = vsReport
          end
        end
      end
    end
    object TabTelemetry: TTabSheet
      Caption = 'Telemetry'
      object SplitterTel: TSplitter
        Left = 380
        Top = 0
        Width = 6
        Height = 669
      end
      object PnlTelLeft: TPanel
        Left = 0
        Top = 0
        Width = 380
        Height = 669
        Align = alLeft
        BevelOuter = bvNone
        TabOrder = 0
        object LblSessions: TLabel
          Left = 0
          Top = 0
          Width = 380
          Height = 22
          Align = alTop
          Alignment = taCenter
          AutoSize = False
          Caption = 'Telemetry Sessions and LMU Source Files'
          Color = clInactiveCaption
          Font.Charset = DEFAULT_CHARSET
          Font.Color = clWhite
          Font.Height = -13
          Font.Name = 'Bahnschrift'
          Font.Style = [fsBold]
          ParentColor = False
          ParentFont = False
          Transparent = False
        end
        object LvwSessions: TListView
          Left = 0
          Top = 22
          Width = 380
          Height = 607
          Align = alClient
          Columns = <
            item
              Caption = 'When'
              Width = 120
            end
            item
              Caption = 'Track / Type'
              Width = 130
            end
            item
              Caption = 'Car / File'
              Width = 120
            end>
          Color = 15921906
          GridLines = False
          ReadOnly = True
          RowSelect = True
          TabOrder = 0
          ViewStyle = vsReport
          OnSelectItem = LvwSessionsSelectItem
        end
        object PnlTelLeftButtons: TPanel
          Left = 0
          Top = 629
          Width = 380
          Height = 40
          Align = alBottom
          BevelOuter = bvNone
          TabOrder = 1
          object BtnImportTel: TButton
            Left = 4
            Top = 6
            Width = 180
            Height = 28
            Caption = 'Import Telemetry (CSV)'
            Font.Charset = DEFAULT_CHARSET
            Font.Color = clWindowText
            Font.Height = -13
            Font.Name = 'Bahnschrift'
            Font.Style = [fsBold]
            ParentFont = False
            TabOrder = 0
            OnClick = BtnImportTelClick
          end
          object BtnDeleteSession: TButton
            Left = 192
            Top = 6
            Width = 180
            Height = 28
            Caption = 'Delete Saved Session'
            Font.Charset = DEFAULT_CHARSET
            Font.Color = clWindowText
            Font.Height = -13
            Font.Name = 'Bahnschrift'
            Font.Style = [fsBold]
            ParentFont = False
            TabOrder = 1
            OnClick = BtnDeleteSessionClick
          end
        end
      end
      object PnlTelRight: TPanel
        Left = 386
        Top = 0
        Width = 756
        Height = 669
        Align = alClient
        BevelOuter = bvNone
        TabOrder = 1
        object GrpSessionInfo: TGroupBox
          Left = 0
          Top = 0
          Width = 756
          Height = 90
          Align = alTop
          Caption = ' Telemetry Deck '
          Color = 15002865
          Font.Charset = DEFAULT_CHARSET
          Font.Color = clWindowText
          Font.Height = -13
          Font.Name = 'Bahnschrift'
          Font.Style = [fsBold]
          ParentBackground = False
          ParentFont = False
          TabOrder = 0
          object MemoSessionInfo: TMemo
            Left = 2
            Top = 20
            Width = 752
            Height = 68
            Align = alClient
            BorderStyle = bsNone
            Color = 15921906
            ReadOnly = True
            ScrollBars = ssVertical
            TabOrder = 0
          end
        end
        object PnlTelActions: TPanel
          Left = 0
          Top = 90
          Width = 756
          Height = 44
          Align = alTop
          BevelOuter = bvNone
          TabOrder = 1
          object BtnExportCSV: TButton
            Left = 4
            Top = 8
            Width = 165
            Height = 28
            Caption = 'Export Telemetry CSV'
            Font.Charset = DEFAULT_CHARSET
            Font.Color = clWindowText
            Font.Height = -13
            Font.Name = 'Bahnschrift'
            Font.Style = [fsBold]
            ParentFont = False
            TabOrder = 0
            OnClick = BtnExportCSVClick
          end
          object BtnAnalyzeAI: TButton
            Left = 177
            Top = 8
            Width = 185
            Height = 28
            Caption = 'Ask Gemini for Coaching'
            Font.Charset = DEFAULT_CHARSET
            Font.Color = clWindowText
            Font.Height = -13
            Font.Name = 'Bahnschrift'
            Font.Style = [fsBold]
            ParentFont = False
            TabOrder = 1
            OnClick = BtnAnalyzeAIClick
          end
          object BtnClearAI: TButton
            Left = 370
            Top = 8
            Width = 110
            Height = 28
            Caption = 'Clear Response'
            TabOrder = 2
            OnClick = BtnClearAIClick
          end
        end
        object GrpAIResponse: TGroupBox
          Left = 0
          Top = 134
          Width = 756
          Height = 535
          Align = alClient
          Caption = ' Coaching Wall '
          Color = 15002865
          Font.Charset = DEFAULT_CHARSET
          Font.Color = clWindowText
          Font.Height = -13
          Font.Name = 'Bahnschrift'
          Font.Style = [fsBold]
          ParentBackground = False
          ParentFont = False
          TabOrder = 2
          object MemoAIResponse: TMemo
            Left = 2
            Top = 20
            Width = 752
            Height = 513
            Align = alClient
            BorderStyle = bsNone
            Color = 15921906
            Font.Charset = DEFAULT_CHARSET
            Font.Color = clWindowText
            Font.Height = -13
            Font.Name = 'Segoe UI'
            Font.Style = []
            ParentFont = False
            ReadOnly = True
            ScrollBars = ssVertical
            TabOrder = 0
          end
        end
      end
    end
    object TabSettings: TTabSheet
      Caption = 'Settings'
      object PnlSettings: TPanel
        Left = 0
        Top = 0
        Width = 1142
        Height = 659
        Align = alClient
        BevelOuter = bvNone
        TabOrder = 0
        ExplicitHeight = 669
        object LblSettingsTitle: TLabel
          Left = 24
          Top = 24
          Width = 186
          Height = 21
          Caption = 'Gemini AI Configuration'
          Font.Charset = DEFAULT_CHARSET
          Font.Color = clWindowText
          Font.Height = -16
          Font.Name = 'Segoe UI'
          Font.Style = [fsBold]
          ParentFont = False
        end
        object LblSep1: TLabel
          Left = 24
          Top = 52
          Width = 500
          Height = 2
          AutoSize = False
          Color = clSilver
          ParentColor = False
          Transparent = False
        end
        object LblAPIKey: TLabel
          Left = 24
          Top = 72
          Width = 46
          Height = 17
          Caption = 'API Key:'
        end
        object LblAPIKeyInfo: TLabel
          Left = 24
          Top = 140
          Width = 580
          Height = 34
          AutoSize = False
          Caption = 
            'Your API key is stored locally in settings.ini inside Documents\' +
            'LMUTrackHarvester\. It is never transmitted anywhere except to G' +
            'oogle'#39's Gemini API endpoint.'
          Font.Charset = DEFAULT_CHARSET
          Font.Color = clGrayText
          Font.Height = -11
          Font.Name = 'Segoe UI'
          Font.Style = []
          ParentFont = False
          WordWrap = True
        end
        object LblModel: TLabel
          Left = 24
          Top = 108
          Width = 41
          Height = 17
          Caption = 'Model:'
        end
        object LblGetKey: TLabel
          Left = 24
          Top = 184
          Width = 356
          Height = 17
          Cursor = crHandPoint
          Caption = 'Get a free API key at: https://aistudio.google.com/app/apikey'
          Font.Charset = DEFAULT_CHARSET
          Font.Color = clBlue
          Font.Height = -13
          Font.Name = 'Segoe UI'
          Font.Style = [fsUnderline]
          ParentFont = False
          OnClick = LblGetKeyClick
        end
        object LblTestResult: TLabel
          Left = 404
          Top = 219
          Width = 4
          Height = 17
        end
        object LblTelemetrySource: TLabel
          Left = 24
          Top = 278
          Width = 175
          Height = 17
          Caption = 'LMU Telemetry Source Folder:'
        end
        object LblTelemetrySourceInfo: TLabel
          Left = 24
          Top = 334
          Width = 600
          Height = 34
          AutoSize = False
          Font.Charset = DEFAULT_CHARSET
          Font.Color = clGrayText
          Font.Height = -11
          Font.Name = 'Segoe UI'
          Font.Style = []
          ParentFont = False
          WordWrap = True
        end
        object LblResultsSource: TLabel
          Left = 24
          Top = 382
          Width = 146
          Height = 17
          Caption = 'LMU Results XML Folder:'
        end
        object LblResultsSourceInfo: TLabel
          Left = 24
          Top = 438
          Width = 600
          Height = 34
          AutoSize = False
          Font.Charset = DEFAULT_CHARSET
          Font.Color = clGrayText
          Font.Height = -11
          Font.Name = 'Segoe UI'
          Font.Style = []
          ParentFont = False
          WordWrap = True
        end
        object LblPreferredDriver: TLabel
          Left = 24
          Top = 486
          Width = 146
          Height = 17
          Caption = 'Preferred Driver Name:'
        end
        object LblPreferredDriverInfo: TLabel
          Left = 24
          Top = 542
          Width = 600
          Height = 34
          AutoSize = False
          Caption = 'Use the exact name shown in LMU results XML. The app will auto-fill this from telemetry metadata when possible and only import laps for this driver.'
          Font.Charset = DEFAULT_CHARSET
          Font.Color = clGrayText
          Font.Height = -11
          Font.Name = 'Segoe UI'
          Font.Style = []
          ParentFont = False
          WordWrap = True
        end
        object EdtAPIKey: TEdit
          Left = 90
          Top = 68
          Width = 480
          Height = 25
          PasswordChar = '*'
          TabOrder = 0
        end
        object BtnShowKey: TButton
          Left = 578
          Top = 68
          Width = 60
          Height = 25
          Caption = 'Show'
          TabOrder = 1
          OnClick = BtnShowKeyClick
        end
        object CboAIModel: TComboBox
          Left = 90
          Top = 104
          Width = 300
          Height = 25
          Style = csDropDownList
          TabOrder = 2
          Items.Strings = (
            'gemini-1.5-flash'
            'gemini-1.5-pro'
            'gemini-2.0-flash'
            'gemini-2.0-flash-lite')
        end
        object BtnSaveSettings: TButton
          Left = 90
          Top = 210
          Width = 140
          Height = 34
          Caption = 'Save Settings'
          Font.Charset = DEFAULT_CHARSET
          Font.Color = clWindowText
          Font.Height = -13
          Font.Name = 'Segoe UI'
          Font.Style = [fsBold]
          ParentFont = False
          TabOrder = 3
          OnClick = BtnSaveSettingsClick
        end
        object BtnTestAPI: TButton
          Left = 246
          Top = 210
          Width = 140
          Height = 34
          Caption = 'Test Connection'
          TabOrder = 4
          OnClick = BtnTestAPIClick
        end
        object EdtTelemetryFolder: TEdit
          Left = 24
          Top = 302
          Width = 546
          Height = 25
          TabOrder = 5
        end
        object BtnBrowseTelemetryFolder: TButton
          Left = 578
          Top = 302
          Width = 60
          Height = 25
          Caption = 'Browse'
          TabOrder = 6
          OnClick = BtnBrowseTelemetryFolderClick
        end
        object BtnRescanTelemetry: TButton
          Left = 646
          Top = 302
          Width = 75
          Height = 25
          Caption = 'Rescan'
          TabOrder = 7
          OnClick = BtnRescanTelemetryClick
        end
        object EdtResultsFolder: TEdit
          Left = 24
          Top = 406
          Width = 546
          Height = 25
          TabOrder = 8
        end
        object BtnBrowseResultsFolder: TButton
          Left = 578
          Top = 406
          Width = 60
          Height = 25
          Caption = 'Browse'
          TabOrder = 9
          OnClick = BtnBrowseResultsFolderClick
        end
        object BtnRescanResults: TButton
          Left = 646
          Top = 406
          Width = 75
          Height = 25
          Caption = 'Rescan'
          TabOrder = 10
          OnClick = BtnRescanResultsClick
        end
        object EdtPreferredDriver: TEdit
          Left = 24
          Top = 510
          Width = 300
          Height = 25
          TabOrder = 11
        end
      end
    end
  end
end
