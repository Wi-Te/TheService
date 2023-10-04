library SampleDll;

{$DEFINE NoDebugInfo}

{По хорошему, Exceptions, как и любые другие объекты (строки, например), созданные в ДЛЛ должны быть уничтожены в ДЛЛ.
Ты можешь передать адрес памяти для чтения содержимого в основной программе, но освободить память обязан внутри ДЛЛ
Так что кидать исключения, которые будут перехвачены в сервисе - это очень плохая идея. Если не хочешь проблем, перехватывай все исключения внутри ДЛЛ и возвращай код ошибки
НО. Если у сервиса с ДЛЛ одинаковый MemoryManager, в нашем случае FastMM4, и одинаковый SysUtils, то передача исключений из ДЛЛ наружу будет работать ок.
Строки и динамические переменные все равно передавать нельзя}

uses
  FastMM4,
  SysUtils,
  Windows,
  ADODB,
  saUtils,
  uDllHelper in 'D:\0 - Sources\TheService\uDllHelper.pas';

{$R *.res}

var
  AbortCallback: TAbortCallback;
  ServerLog: string;

//OWNED BY WORKER THREAD!!!
//RAISE ERRORS WILE NOT INITIALIZED (SEE SERVICELOG FOR DETAILS)
//WRITE YOUR OWN ERRORLOG AFTER SUCCESSFULL INITIALIZATION
function TimerProc: Integer; stdcall;
begin
  Windows.Beep(300, 100);
  Result := 0;
end;

//OWNED BY WORKER THREAD!!!
//RAISE ERRORS WILE NOT INITIALIZED (SEE SERVICELOG FOR DETAILS)
//WRITE YOUR OWN ERRORLOG AFTER SUCCESSFULL INITIALIZATION
function UserProc(p: Pointer; size: Byte): Integer; stdcall;
var s: string;
begin
  if @AbortCallback = nil then begin
    Result := 1;
    Exit;
  end;

  if (p = nil) or (size < 1) then raise Exception.Create('UserProc: (P = nil) or (Size = 0)');

  SetLength(s, size);
  Move(p^, s[1], size);
  //Скопировать себе данные

  //Имитирую бурную деятельность
  Windows.MessageBox(0, PChar(s), 'UserProc Param', MB_OK);

  Windows.Beep(800, 100);
  Result := 0;
end;



//OWNED BY __!!!___SERVICE__!!!___ THREAD!!!
procedure OnInit(ac: TAbortCallback); stdcall;
begin
  AbortCallback := ac;
end;

//OWNED BY __!!!___SERVICE__!!!___ THREAD!!!
//UNHANDLED EXCEPTIONS ARE PROPERLY IGNORED
procedure SrvLog(Msg: Cardinal; wParam: WPARAM; lParam: LPARAM); stdcall;
var s: string;
begin
  s := SockMessToStr(Msg, wParam, lParam);
  saWriteLog(ServerLog, s);
end;

procedure salogerror(const msg: string);
begin
  raise Exception.Create('Error writing ServerLog ['+ServerLog+']: ' + msg);
end;

//OWNED BY __!!!___SERVICE__!!!___ THREAD!!!
procedure DLLMain(dwReason: DWORD);
begin
  case dwReason of
    DLL_PROCESS_ATTACH: begin
      //DO SOME INIT FOR SrvLog
      ServerLog := ExtractFilePath(ParamStr(0)) + 'LOG_SRV.LOG';
      saLogErrorCallback := salogerror; //if failed to write log, by default saWriteLog uses Windows.Messagebox, and this is a service
    end;
    DLL_PROCESS_DETACH: begin
      //DO SOME FINIT
    end;
  end;
end;

exports TimerProc, UserProc, SrvLog, OnInit;

begin
  DLLProc := @DLLMain;
  DLLMain(DLL_PROCESS_ATTACH);
end.
