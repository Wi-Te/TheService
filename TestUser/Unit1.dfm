object Form1: TForm1
  Left = 270
  Top = 157
  Width = 493
  Height = 242
  Caption = 'Form1'
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'MS Sans Serif'
  Font.Style = []
  OldCreateOrder = False
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  PixelsPerInch = 96
  TextHeight = 13
  object Button1: TButton
    Left = 8
    Top = 8
    Width = 75
    Height = 25
    Caption = 'request1'
    TabOrder = 0
    OnClick = Button1Click
  end
  object bAbort: TButton
    Left = 208
    Top = 40
    Width = 75
    Height = 25
    Caption = 'abort'
    Enabled = False
    TabOrder = 1
    OnClick = bAbortClick
  end
  object Button3: TButton
    Left = 8
    Top = 72
    Width = 75
    Height = 25
    Caption = 'request3'
    TabOrder = 2
    OnClick = Button3Click
  end
  object Edit1: TEdit
    Left = 8
    Top = 104
    Width = 329
    Height = 21
    TabOrder = 3
    Text = 'INSERT INTO [TEST] (WHAT) VALUES ("Hello " + CStr(NOW()))'
  end
  object Button5: TButton
    Left = 88
    Top = 8
    Width = 75
    Height = 25
    Caption = 'request2'
    TabOrder = 4
    OnClick = Button5Click
  end
  object Button2: TButton
    Left = 208
    Top = 8
    Width = 75
    Height = 25
    Caption = 'Restart'
    TabOrder = 5
    OnClick = Button2Click
  end
  object Button4: TButton
    Left = 8
    Top = 144
    Width = 75
    Height = 25
    Caption = 'FailRequest'
    TabOrder = 6
    OnClick = Button4Click
  end
end
