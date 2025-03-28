library TestDll;

{$DEFINE NoDebugInfo}

uses
  FastMM4,
  SysUtils,
  Windows,
  ADODB,
  UnitWait in 'UnitWait.pas' {Form1},
  UnitLogs in 'UnitLogs.pas' {FormLogs},
  uDllHelper in '..\uDllHelper.pas';

{$R *.res}

var
  FormLogs: TFormLogs;
  AbortCallback: TAbortCallback;

//OWNED BY WORKER THREAD!!!
function TimerProc1: Integer; stdcall;
begin
  Windows.Beep(300, 100);
  Result := 0;
end;

//OWNED BY WORKER THREAD!!!
function TimerProc2: Integer; stdcall;
begin
  Windows.Beep(100, 100);
  Result := -1;
end;

//OWNED BY WORKER THREAD!!!
function UserProc(p: Pointer; size: Byte): Integer; stdcall;
var
  form: TForm1;
  s: string;

  adoq: TADOQuery;
begin
  if @AbortCallback = nil then begin
    Result := 1;
    Exit;
  end;

  SetLength(s, size);
  Move(p^, s[1], size);
  //Скопировать себе данные

  if s = 'exception' then raise Exception.Create('FU');

  try
    adoq := nil;
    adoq := TADOQuery.Create(nil);
    adoq.ConnectionString := 'Provider=Microsoft.ACE.OLEDB.12.0;Data Source=d:\0 - Sources\TheService\TestDll\;Extended Properties=dbase 5.0;Persist Security Info=True';
    adoq.EnableBCD := False;
    adoq.ParamCheck := False;

    adoq.SQL.Text := s;
    Result := adoq.ExecSQL;
  finally
    adoq.Free;
  end;

  {  try
    //Имитирую бурную деятельность
    form := nil;
    form := TForm1.Create(nil);

    form.Edit1.Text := s;
    form.abortcallback := AbortCallback;
    form.ShowModal; //будет висеть пока не закрою, или пока не сработает AbortCallback
  finally
    form.Free;
  end;
                }
 // Windows.Beep(800, 100);
  Result := 0;
end;    

//OWNED BY __!!!___SERVICE__!!!___ THREAD!!!
procedure OnInit(ac: TAbortCallback); stdcall;
begin
  AbortCallback := ac;
end;

//OWNED BY __!!!___SERVICE__!!!___ THREAD!!!
procedure SrvLog(Msg: Cardinal; wParam: WPARAM; lParam: LPARAM); stdcall;
var str: string;
begin
  str := SockMessToStr(msg, wparam, lparam);
  if Assigned(FormLogs)
  then FormLogs.Memo1.Lines.Append(str)
  else Windows.MessageBox(0, PChar(str), 'Server Message', MB_OK);
end;

//OWNED BY __!!!___SERVICE__!!!___ THREAD!!!
procedure DLLMain(dwReason: DWORD);
begin
  case dwReason of
  DLL_PROCESS_ATTACH: begin
    FormLogs := TFormLogs.Create(nil);
    FormLogs.Show;
  end;
  DLL_PROCESS_DETACH: if Assigned(FormLogs) then begin
    FormLogs.undead := False;
    FormLogs.Close;
    FreeAndNil(FormLogs);
  end;
  end;
end;

exports TimerProc1, TimerProc2, UserProc, SrvLog, OnInit;

begin
  DLLProc := @DLLMain;
  DLLMain(DLL_PROCESS_ATTACH);
end.
