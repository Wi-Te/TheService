program Test;

uses
  FastMM4, Forms,
  uTest in 'uTest.pas' {Form1},
  uService in 'uService.pas' {AService: TService};

{$R *.res}
{$define NoDebugInfo}

begin
  Application.Initialize;
  Application.CreateForm(TForm1, Form1);
  Application.CreateForm(TAService, AService);
  if not AService.Init then begin
    Application.Terminate;
    Application.ShowMainForm := False;
  end;
  Application.Run;
end.
