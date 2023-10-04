unit uDllHelper;

interface

const
  {копия из saSock}
  SASM_FIRSTMESS = {WM_USER} $0400 + 5376;  //сообщения от сервера
  SASM_STARTLISTEN = saSM_FirstMess + 0;    //ListenSocket  | PORT_Server
  SASM_STOPLISTEN  = saSM_FirstMess + 1;    //ListenSocket  | PORT_Server
  SASM_INCOMMING   = saSM_FirstMess + 2;    //ClientSocket  | IPADDR_Client
  SASM_SOCKCLOSED  = saSM_FirstMess + 3;    //Socket        | 0
  SASM_SOCKERROR   = saSM_FirstMess + 4;    //Socket        | Errorcode
  SASM_THREADCOUNT = saSM_FirstMess + 5;    //thread count  | 0
  SASM_LASTMESS    = saSM_ThreadCount;      //wParam        | lParam

type
  TAbortCallback = function(): Boolean of object; stdcall; //If this return true, then your procedure must close, cause i will kill thread otherwise
  TInitProc = procedure (ac: TAbortCallback); stdcall; //Service would provide you the address of that function; sh - is the handler of service window

  TTimerProc = function(): Integer; stdcall; //procedure type in DLL set for OnStop and OnTimer
  TUserProc = function(p: Pointer; sz: Byte): Integer; stdcall; //procedure type in DLL server would call on user prompt. Data is owned by service, it will be disposed after procedure return
  
  TMsgProc = procedure(Msg: Cardinal; wParam: Integer; lParam: Integer); stdcall; //server report messages handler in DLL

function SockMessToStr(Msg: Cardinal; wParam, lParam: Integer): string;
function IpToStr(ip: Integer): string;

implementation

uses SysUtils;

type
  T_IP_ADDR = packed record
    a, b, c, d: Byte;
  end;

function IpToStr(ip: Integer): string;
begin
  with T_IP_ADDR(ip) do
    Result := Format('%d.%d.%d.%d', [a, b, c, d]);
end;

function SockMessToStr(Msg: Cardinal; wParam, lParam: Integer): string;
begin
  case Msg of
    saSM_StartListen: Result := Format('Server started on %u (socket = %u)', [lParam, wParam]);
    saSM_StopListen:  Result := Format('Server stopped on %u (socket = %u)', [lParam, wParam]);
    saSM_SockClosed:  Result := Format('Socket closed: %u', [wParam]);
    saSM_Incomming:   Result := Format('Incomming from %s (socket = %u)', [IpToStr(lParam), wParam]);
    saSM_SockError:   Result := Format('Socket error %u (socket = %u): %s', [lParam, wParam, SysErrorMessage(lParam)]);
    saSM_ThreadCount: Result := Format('Total thread count: %u', [wParam]);
    else Result := 'Unknown message: '+IntToStr(Msg);
  end;
end;

end.
