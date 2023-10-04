program TheService;

uses
  FastMM4,
  SvcMgr, SysUtils, 
  uService in 'uService.pas',
  uTimers in 'uTimers.pas',
  uProto in 'uProto.pas';

{$R *.RES}

begin
  Application.Initialize;
  Application.CreateForm(TAService, AService);
  if AService.Init
  then Application.Run;
end.
