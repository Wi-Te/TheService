unit uTest;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls;

type
  TForm1 = class(TForm)
    Button1: TButton;
    Button2: TButton;
    procedure Button1Click(Sender: TObject);
    procedure Button2Click(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  Form1: TForm1;

implementation

{$R *.dfm}

uses
  uService;

procedure TForm1.Button1Click(Sender: TObject);
var b: Boolean;
begin
  AService.ServiceStart(AService, b);
  if b then caption := 'started' else caption := 'error';
end;

procedure TForm1.Button2Click(Sender: TObject);
var b: Boolean;
begin       
  AService.ServiceStop(AService, b);
  if b then caption := 'stopped' else caption := 'error';
end;

procedure TForm1.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  Button2Click(nil);
end;

end.
