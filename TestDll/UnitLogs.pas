unit UnitLogs;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls;

type
  TFormLogs = class(TForm)
    Memo1: TMemo;
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormCreate(Sender: TObject);
  private
    { Private declarations }
  public
    undead: Boolean;
  end;

implementation

{$R *.dfm}

procedure TFormLogs.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := not undead;
end;

procedure TFormLogs.FormCreate(Sender: TObject);
begin
  undead := True;
end;

end.
