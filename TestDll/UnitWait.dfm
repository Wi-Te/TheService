object Form1: TForm1
  Left = 270
  Top = 157
  Width = 406
  Height = 128
  Caption = 'Form1'
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'MS Sans Serif'
  Font.Style = []
  OldCreateOrder = False
  DesignSize = (
    398
    97)
  PixelsPerInch = 96
  TextHeight = 13
  object Label1: TLabel
    Left = 8
    Top = 8
    Width = 62
    Height = 13
    Caption = 'Data As Text'
  end
  object Edit1: TEdit
    Left = 8
    Top = 24
    Width = 385
    Height = 21
    Anchors = [akLeft, akTop, akRight]
    ReadOnly = True
    TabOrder = 0
    Text = '456'
  end
  object Button1: TButton
    Left = 150
    Top = 64
    Width = 75
    Height = 25
    Anchors = [akTop]
    Caption = #1054#1050
    TabOrder = 1
    OnClick = Button1Click
  end
  object Timer1: TTimer
    OnTimer = Timer1Timer
    Left = 248
    Top = 56
  end
end
