program Project1;

uses
  FastMM4,
  Forms,
  Unit1 in 'Unit1.pas' {Form1},
  uProto in '..\uProto.pas',
  uClient in '..\uClient.pas';

{$R *.res}
{$DEFINE NoDebugInfo}

begin
  Application.Initialize;
  Application.CreateForm(TForm1, Form1);
  Application.Run;
end.
