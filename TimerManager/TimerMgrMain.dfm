object Form1: TForm1
  Left = 278
  Top = 175
  Width = 941
  Height = 593
  Caption = #1056#1077#1076#1072#1082#1090#1086#1088' '#1090#1072#1081#1084#1077#1088#1086#1074
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'MS Sans Serif'
  Font.Style = []
  OldCreateOrder = False
  OnCreate = FormCreate
  DesignSize = (
    933
    562)
  PixelsPerInch = 96
  TextHeight = 13
  object DBGridEh1: TDBGridEh
    Left = 288
    Top = 64
    Width = 638
    Height = 491
    Anchors = [akLeft, akTop, akRight, akBottom]
    AutoFitColWidths = True
    Ctl3D = False
    DataGrouping.GroupLevels = <>
    DataSource = DataSource1
    Flat = True
    FooterColor = clWindow
    FooterFont.Charset = DEFAULT_CHARSET
    FooterFont.Color = clWindowText
    FooterFont.Height = -11
    FooterFont.Name = 'MS Sans Serif'
    FooterFont.Style = []
    ParentCtl3D = False
    RowDetailPanel.Color = clBtnFace
    TabOrder = 1
    TitleFont.Charset = DEFAULT_CHARSET
    TitleFont.Color = clWindowText
    TitleFont.Height = -11
    TitleFont.Name = 'MS Sans Serif'
    TitleFont.Style = []
    UseMultiTitle = True
    Columns = <
      item
        AutoFitColWidth = False
        EditButtons = <>
        FieldName = 'ID'
        Footers = <>
        Title.Caption = #8470
        Width = 40
      end
      item
        AutoFitColWidth = False
        EditButtons = <>
        FieldName = 'Foo'
        Footers = <>
        Title.Caption = #1060#1091#1085#1082#1094#1080#1103
        Width = 200
      end
      item
        EditButtons = <>
        FieldName = 'Bar'
        Footers = <>
        Title.Caption = #1058#1072#1081#1084#1077#1088
        Width = 175
      end>
    object RowDetailData: TRowDetailPanelControlEh
    end
  end
  object PageControl1: TPageControl
    Left = 8
    Top = 134
    Width = 273
    Height = 392
    ActivePage = TabSheet1
    Anchors = [akLeft, akTop, akBottom]
    TabOrder = 0
    object TabSheet1: TTabSheet
      Caption = #1055#1086#1074#1090#1086#1088#1103#1090#1100' '#1088#1077#1075#1091#1083#1103#1088#1085#1086
      DesignSize = (
        265
        364)
      object edFrom: TsEdit
        Left = 1
        Top = 16
        Width = 128
        Height = 21
        TabOrder = 0
        Text = 'edFrom'
        OnExit = EditChange
        OnKeyPress = EditKeyPress
        SkinData.SkinSection = 'EDIT'
        BoundLabel.Active = True
        BoundLabel.Caption = #1042#1088#1077#1084#1103' '#1085#1072#1095#1072#1083#1072':'
        BoundLabel.Indent = 0
        BoundLabel.Font.Charset = DEFAULT_CHARSET
        BoundLabel.Font.Color = clWindowText
        BoundLabel.Font.Height = -11
        BoundLabel.Font.Name = 'MS Sans Serif'
        BoundLabel.Font.Style = []
        BoundLabel.Layout = sclTopLeft
        BoundLabel.MaxWidth = 0
        BoundLabel.UseSkinColor = True
      end
      object edUntil: TsEdit
        Left = 133
        Top = 16
        Width = 128
        Height = 21
        TabOrder = 1
        Text = 'edUntil'
        OnExit = EditChange
        OnKeyPress = EditKeyPress
        SkinData.SkinSection = 'EDIT'
        BoundLabel.Active = True
        BoundLabel.Caption = #1042#1088#1077#1084#1103' '#1086#1082#1086#1085#1095#1072#1085#1080#1103':'
        BoundLabel.Indent = 0
        BoundLabel.Font.Charset = DEFAULT_CHARSET
        BoundLabel.Font.Color = clWindowText
        BoundLabel.Font.Height = -11
        BoundLabel.Font.Name = 'MS Sans Serif'
        BoundLabel.Font.Style = []
        BoundLabel.Layout = sclTopLeft
        BoundLabel.MaxWidth = 0
        BoundLabel.UseSkinColor = True
      end
      object edEvery: TsEdit
        Left = 1
        Top = 56
        Width = 128
        Height = 21
        TabOrder = 2
        Text = 'edEvery'
        OnExit = EditChange
        OnKeyPress = EditKeyPress
        SkinData.SkinSection = 'EDIT'
        BoundLabel.Active = True
        BoundLabel.Caption = #1048#1085#1090#1077#1088#1074#1072#1083' '#1087#1086#1074#1090#1086#1088#1077#1085#1080#1081':'
        BoundLabel.Indent = 0
        BoundLabel.Font.Charset = DEFAULT_CHARSET
        BoundLabel.Font.Color = clWindowText
        BoundLabel.Font.Height = -11
        BoundLabel.Font.Name = 'MS Sans Serif'
        BoundLabel.Font.Style = []
        BoundLabel.Layout = sclTopLeft
        BoundLabel.MaxWidth = 0
        BoundLabel.UseSkinColor = True
      end
      object check: TsCheckBox
        Left = 133
        Top = 56
        Width = 130
        Height = 20
        Caption = #1054#1078#1080#1076#1072#1090#1100' '#1074#1099#1087#1086#1083#1085#1077#1085#1080#1103
        TabOrder = 3
        OnClick = EditChange
        SkinData.SkinSection = 'CHECKBOX'
        ImgChecked = 0
        ImgUnchecked = 0
      end
      object edTest: TsMemo
        Left = 0
        Top = 96
        Width = 261
        Height = 265
        Anchors = [akLeft, akTop, akBottom]
        Color = clBtnFace
        Lines.Strings = (
          'edTest')
        ReadOnly = True
        TabOrder = 4
        Text = 'edTest'
        BoundLabel.Active = True
        BoundLabel.Caption = #1055#1088#1080#1084#1077#1088#1085#1086#1077' '#1088#1072#1089#1087#1080#1089#1072#1085#1080#1077':'
        BoundLabel.Indent = 0
        BoundLabel.Font.Charset = DEFAULT_CHARSET
        BoundLabel.Font.Color = clWindowText
        BoundLabel.Font.Height = -11
        BoundLabel.Font.Name = 'MS Sans Serif'
        BoundLabel.Font.Style = []
        BoundLabel.Layout = sclTopLeft
        BoundLabel.MaxWidth = 0
        BoundLabel.UseSkinColor = True
        SkinData.CustomColor = True
        SkinData.SkinSection = 'EDIT'
      end
    end
    object TabSheet2: TTabSheet
      Caption = #1042#1099#1087#1086#1083#1085#1103#1090#1100' '#1087#1086' '#1088#1072#1089#1087#1080#1089#1072#1085#1080#1102
      ImageIndex = 1
      DesignSize = (
        265
        364)
      object edSched: TsMemo
        Left = 1
        Top = 16
        Width = 260
        Height = 345
        Anchors = [akLeft, akTop, akBottom]
        Lines.Strings = (
          'edSched')
        TabOrder = 0
        OnExit = edSchedChange
        Text = 'edSched'
        BoundLabel.Active = True
        BoundLabel.Caption = #1056#1072#1089#1087#1080#1089#1072#1085#1080#1077' '#1079#1072#1087#1091#1089#1082#1072':'
        BoundLabel.Indent = 0
        BoundLabel.Font.Charset = DEFAULT_CHARSET
        BoundLabel.Font.Color = clWindowText
        BoundLabel.Font.Height = -11
        BoundLabel.Font.Name = 'MS Sans Serif'
        BoundLabel.Font.Style = []
        BoundLabel.Layout = sclTopLeft
        BoundLabel.MaxWidth = 0
        BoundLabel.UseSkinColor = True
        SkinData.SkinSection = 'EDIT'
      end
    end
  end
  object eddll: TsFilenameEdit
    Left = 9
    Top = 64
    Width = 272
    Height = 21
    AutoSize = False
    MaxLength = 255
    TabOrder = 2
    BoundLabel.Active = True
    BoundLabel.Caption = #1056#1072#1089#1087#1086#1083#1086#1078#1077#1085#1080#1077' DLL:'
    BoundLabel.Indent = 0
    BoundLabel.Font.Charset = DEFAULT_CHARSET
    BoundLabel.Font.Color = clWindowText
    BoundLabel.Font.Height = -11
    BoundLabel.Font.Name = 'MS Sans Serif'
    BoundLabel.Font.Style = []
    BoundLabel.Layout = sclTopLeft
    BoundLabel.MaxWidth = 0
    BoundLabel.UseSkinColor = True
    SkinData.SkinSection = 'EDIT'
    GlyphMode.Blend = 0
    GlyphMode.Grayed = False
    Filter = 'DLL files (*.*)|*.dll'
    DialogOptions = [ofPathMustExist, ofFileMustExist, ofNoNetworkButton, ofEnableSizing, ofDontAddToRecent]
  end
  object combo: TsComboBox
    Left = 9
    Top = 104
    Width = 272
    Height = 22
    Alignment = taLeftJustify
    BoundLabel.Active = True
    BoundLabel.Caption = #1055#1088#1086#1094#1077#1076#1091#1088#1072' '#1086#1073#1088#1072#1073#1086#1090#1082#1080' '#1089#1086#1073#1099#1090#1080#1103' '#1090#1072#1081#1084#1077#1088#1072
    BoundLabel.Indent = 0
    BoundLabel.Font.Charset = DEFAULT_CHARSET
    BoundLabel.Font.Color = clWindowText
    BoundLabel.Font.Height = -11
    BoundLabel.Font.Name = 'MS Sans Serif'
    BoundLabel.Font.Style = []
    BoundLabel.Layout = sclTopLeft
    BoundLabel.MaxWidth = 0
    BoundLabel.UseSkinColor = True
    SkinData.SkinSection = 'COMBOBOX'
    ItemHeight = 16
    ItemIndex = -1
    TabOrder = 3
    Text = 'combo'
  end
  object edini: TsFilenameEdit
    Left = 9
    Top = 24
    Width = 272
    Height = 21
    AutoSize = False
    MaxLength = 255
    TabOrder = 4
    BoundLabel.Active = True
    BoundLabel.Caption = #1060#1072#1081#1083' '#1085#1072#1089#1090#1088#1086#1077#1082':'
    BoundLabel.Indent = 0
    BoundLabel.Font.Charset = DEFAULT_CHARSET
    BoundLabel.Font.Color = clWindowText
    BoundLabel.Font.Height = -11
    BoundLabel.Font.Name = 'MS Sans Serif'
    BoundLabel.Font.Style = []
    BoundLabel.Layout = sclTopLeft
    BoundLabel.MaxWidth = 0
    BoundLabel.UseSkinColor = True
    SkinData.SkinSection = 'EDIT'
    GlyphMode.Blend = 0
    GlyphMode.Grayed = False
    Filter = 'INI files (*.*)|*.ini'
    DialogOptions = [ofPathMustExist, ofFileMustExist, ofNoNetworkButton, ofEnableSizing, ofDontAddToRecent]
  end
  object Button1: TButton
    Left = 8
    Top = 533
    Width = 75
    Height = 22
    Anchors = [akLeft, akBottom]
    Caption = #1057#1086#1093#1088#1072#1085#1080#1090#1100
    TabOrder = 5
  end
  object Button2: TButton
    Left = 208
    Top = 532
    Width = 73
    Height = 22
    Anchors = [akLeft, akBottom]
    Caption = #1044#1086#1073#1072#1074#1080#1090#1100
    TabOrder = 6
    OnClick = Button2Click
  end
  object Button3: TButton
    Left = 128
    Top = 532
    Width = 73
    Height = 22
    Anchors = [akLeft, akBottom]
    Caption = #1059#1076#1072#1083#1080#1090#1100
    TabOrder = 7
  end
  object sButton1: TsButton
    Left = 288
    Top = 23
    Width = 129
    Height = 23
    Caption = #1047#1072#1075#1088#1091#1079#1080#1090#1100' '#1080#1079' '#1092#1072#1081#1083#1072
    TabOrder = 8
    OnClick = sButton1Click
    SkinData.SkinSection = 'BUTTON'
  end
  object sBitBtn1: TsBitBtn
    Left = 424
    Top = 23
    Width = 129
    Height = 23
    Caption = #1057#1086#1093#1088#1072#1085#1080#1090#1100' '#1074' '#1092#1072#1081#1083
    TabOrder = 9
    SkinData.SkinSection = 'BUTTON'
  end
  object DataSource1: TDataSource
    DataSet = MemTableEh1
    Left = 528
    Top = 144
  end
  object MemTableEh1: TMemTableEh
    FetchAllOnOpen = True
    Params = <>
    AfterScroll = MemTableEh1AfterScroll
    Left = 560
    Top = 144
  end
end
