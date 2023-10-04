program TimerManager;

uses
  Forms,
  TimerMgrMain in 'TimerMgrMain.pas' {Form1},
  QuickSort in '..\SA\QuickSort.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TForm1, Form1);
  Application.Run;
end.
