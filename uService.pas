unit uService;

interface

uses
  Windows, Messages, SysUtils, Classes, SvcMgr, uTimers, saSock, uProto;

type
  TAbortCallback = function(): Boolean of object; stdcall;  //function to call from your dll to determine if i want to abort your function execution
  TInitProc = procedure (ac: TAbortCallback); stdcall; //Service would provide you the address of that function

{  TStartProc = function(): Integer; stdcall;
  TStopProc = procedure(); stdcall;}

  TTimerProc = function(): Integer; stdcall; //procedure type in DLL set for OnStop and OnTimer
  TUserProc = function(p: Pointer; sz: Byte): Integer; stdcall; //procedure type in DLL server would call on user prompt. Data is owned by service, it will be disposed after procedure return

  TMsgProc = procedure(Msg: Cardinal; wParam: WPARAM; lParam: LPARAM); stdcall; //server report messages handler in DLL

  {��� ���������� �� ���, ����������� �� ������ ��� �����, ���������� �� WorkerThread'a
  DLLMAIN, OnInit, OnServerMessage - ���������� �� ServiceThread}

  //������������ (������-����������� �������� �� �������) ���� ������ �� �������
  //��� ������ ���� ��� ������ ������������� ������� �����
  TClientInfo = class
  protected
    e: THandle;                                 //�����, �� ������� �������� �������� ������-�� ������
    r: TClientResponse;                         //������ �������, ������� � ���� �������� ������������
    i: Integer; //reference count                 ����� ������� ����, ����� ������ �������
    w: THandle; //������� ��� ������� � reference counter'�. ���� �������������� � � ServiceThread'e, � � ServerClientThread'��
  public
    request: TRequest;                          //������ �� ����� �������

    constructor Create;
    destructor Destroy; override;
    property event: THandle read e;
    property resp: TClientResponse read r;
    procedure WakeUp(resp: TClientResponse);
    procedure Release;                          //��������� reference count
  end;

  //������. ����� ����������� �� �������, ��� �� ������� ������������. ������������ �� ����� ���������� ���������
  //��� �������, ������� �������� ��������� ��� ������, � ��� ������������, ������� ��������� ��� ������, �������� ��� � �������
  PTask = ^TTask;
  TTask = record
    next: PTask;     //������ �� ������ ������. ����������� ����������� ������
    nproc: string;   //��� ����������� ���������. ���������� ������
    pproc: Pointer;  //���������� ����� ��������� � DLL

    //�������� �������� (TClientInfo �����������)
    clients: array of TClientInfo;
    ecap, ecount: Integer;

    //�������� ��������
    tindxs: array of Integer;
    tcap, tcount: Integer;

    //��������� ������ �� ������������. ����������� ����� ������
    buff: array of Byte;
    bsize: Byte;
  end;

  //������� �����, ������� ��������� ������
  TWorkerThread = class(TThread)
  private
    parentForm: THandle;  //���� ������������ ��������� �� �������
    wakeEvent: THandle;  //�� ���� ������ ��� ����� ���� ������ ������
    uado, ubde: Boolean;

{    FOnStart: TStartProc;
    FOnStop: TStopProc; //��������� ������������� ��������� ��������� ������� / ��������� �������}
  public
    task: PTask;         //������ ��� ������

    function AbortCallback(): Boolean; stdcall;
    constructor Create(parent, event: THandle; UseADO, UseBDE: Boolean);
    destructor Destroy; override;
    procedure Execute; override;
  end;

  TAService = class(TService)
    procedure ServiceBeforeInstall(Sender: TService);
    procedure ServiceAfterInstall(Sender: TService);
    procedure ServiceBeforeUninstall(Sender: TService);
    procedure ServiceStart(Sender: TService; var Started: Boolean);
    procedure ServiceStop(Sender: TService; var Stopped: Boolean);
    procedure ServiceShutdown(Sender: TService);
  private
    Handle: THandle;                     //������ ���� ��� �������� ���������, ������� � ���� ������������
    realState: TCurrentStatus;           //������, ����� ��������, �������������� ��������� ������� ��� ��������� ��������� �� ������ ���������
    local, exename, dllname: string;     //����� ����������� ������. ��������������� ����� �� ������ �������� (��� ����� ���������, ��������)
    selfupdate, userupdate: string;      //���� ��� ������ ����������. ������ ��� ���� ���������� �������. � ���������� ��� ������� ���������� �������� ��������
    worklog, errorlog, descript: string; //������ ���� � ��� ����� ��� �������� � ���� ������; �������� ������� ��� �����������. ��� ���� ������� � ServiceThread'e
    lastupdate: TDateTime;               //����� ��������� �������� ����������. ������������, ����� ������� ����� �� ������������� ��� ����� � ������� �����
    exeupdated: Boolean;
    DllHandle: THandle;

    Timers: TTimers;                     //�������� ��������
    Server: saTServer;
    Port: Word;

    FSrvMessage: TMsgProc;               //��������� ������������� ��������� ��������� ��������� �������
    FDllInit: TInitProc;                 //��������� ������������� ���
    sDllInit, sSrvMsg: string;           //����� ���� �������� ��� ������ � ���

    bUsesADO, bUsesBDE: Boolean;         //����� ����� ������������� ���/���

    InitEvent: THandle;                  //����� ����� �������� ������. ���� �� ������, ���� �� �� ������� ��������� �������������, ��� �� ���
    InitMessage: ^string;                //����� ��� �������� ������ ������ �� �������� ������

    FirstTask, LastTask: PTask;
    //������� ����� ��� �������. ������ ��������� ������ � ��������� ������, � ����� ��������� ������.
    //�� ������ � ������� ��������, ���� ������ �����������
    //��������������, ����� ������ ���������, �������� �� �������, ��� ����� ������ ������

    WorkerThread: TWorkerThread;         //��� ����� ��������� �����, ������� ����� ������ ���������������� ������
    WorkerEvent, QueueEvent: THandle;    //������ ��� ���������� ���� �������

    novellname, novellpass: string;

    procedure InitWorkLog;

    function OnTimer(TimerID: Cardinal): Integer;
    procedure OnServerRequest(Msg: Cardinal; wParam: WPARAM; lParam: LPARAM);
    procedure OnServerLog(Msg: Cardinal; wParam: WPARAM; lParam: LPARAM);

    procedure OnTaskComplete(resp: TClientResponse);
    procedure OnThreadDead();

    procedure OnErrMsg(lparam: Integer);

    procedure StartTimers;
    procedure KillTimers;

    procedure StopAndFree;
    procedure Restart;

    procedure LoadDll;
    function FreeDll: Boolean;
    function GetProc(const naim: string): Pointer;

    procedure CheckUpdates(forced: Boolean);
    procedure CopyFiles(const src, dst: string; ur: Word);

    procedure InitTask(const p: PTask);
    procedure FreeTask(p: PTask);
    procedure FreeTasks;

    function FindTask(const nproc: string): PTask;
    function FindTaskArg(request: PRequest): PTask;
    procedure AddTaskFromTimer(const nproc: string; tmidx: Integer);
    procedure AddTimerToTask(p: PTask; tmidx: Integer);
    procedure AddTaskFromUser(const e: TClientInfo);
    procedure AddClientToTask(p: PTask; const e: TClientInfo);
    procedure SetTaskToWork(p: PTask);

    procedure TaskQueueAdd(p: PTask);
    function  TaskQueueSelect: PTask;
    procedure TaskQueueRemove(p: PTask);

    procedure WriteWorkLog(const msg: string);
  public
    function GetServiceController: TServiceController; override;
    function Init(): Boolean;
  end;

var
  AService: TAService;

implementation

{$R *.DFM}
{$R SRVCRES.RES}

uses
  saUtils, saIniLoader, Base64, Registry, ActiveX, BDE;

const
  WM_THREAD_DEAD = WM_USER + 1;
  WM_THREAD_READY = WM_USER + 2;
  WM_THREAD_ERROR = WM_USER + 3;
  WM_CLIENT_ERROR = WM_USER + 4;
  WM_SRV_REQUEST = WM_USER + 5;
  WM_SVC_RESTART = WM_USER + 6;

  MESSAGE_WINDOW_CLASS_NAME = 'SvcMsgCls';
  UPDATES_COOLDOWN = 0.007; //��� ���� ������ 10 ����� � ����

  UPDATE_EXE_NAME = 'TheService.exe';

var
  MessageWindowClass: Word;
  MyLogEvent: Cardinal;

//������� error-reporting, ���������� �������� � "������� �������" Windows
//������������ � saWriteLog.OnError
//���������� ����� �� ������ �������, ������� ���� �� ����-����
//� ������ �������, ��� ��������� ��� ��������� ������ ���� ������ ���������
procedure WindowsEventLog(const msg: string);
var p: PChar;
begin
  p := PChar(msg);
  ReportEvent(MyLogEvent, EVENTLOG_ERROR_TYPE, 0, 1, nil, 1, 0, @p, nil);
  //AService.LogMessage ���� �� ���������� ������ ��� �� ����-����
end;

//��� ��� ����, ������� ��������� � ServiceStart, �����������, ��������� � �������, � ServiceThread
//��������� ��������� �� ��������, �� �������, �� �������� �����, ����� ���������� �� ���������� �������� ������, ������ �����, ���� �����������, ��������� ������
//������� �� �������� ��� ������ ����������� � WorkerThread'e, �� ���������, � ��� ����� ���������� ������� ������ - � ���� �����
function WndProc(hWnd: THandle; Msg: Cardinal; wParam: WPARAM; lParam: LPARAM): Integer; stdcall;
begin
  try
    Result := 1;
    case Msg of
      WM_TIMER: Result := AService.OnTimer(wParam);
      WM_SRV_REQUEST: AService.OnServerRequest(Msg, wParam, lParam);
      WM_SVC_RESTART: AService.Restart;
      SASM_FIRSTMESS..
      SASM_LASTMESS: AService.OnServerLog(Msg, wParam, lParam);
      SASM_ERROR: AService.OnErrMsg(lParam);
      WM_CLIENT_ERROR: AService.OnErrMsg(lParam);
      WM_THREAD_READY: begin
        if wParam = 0
        then AService.OnTaskComplete(crSucc)
        else AService.OnTaskComplete(crFail);
      end;
      WM_THREAD_ERROR: begin
        AService.OnErrMsg(lParam);
        AService.OnTaskComplete(crOff);
      end;
      WM_THREAD_DEAD: begin
        AService.OnErrMsg(lParam);
        AService.OnThreadDead();
      end;
    else
      Result := Windows.DefWindowProc(hWnd, Msg, wParam, lParam);
    end;
  except on e: Exception do
    saWriteLog(AService.errorlog, 'Error in WndProc: '+e.Message);
  end;
end;

{$WARNINGS OFF}
function MakeWindow: THandle;
var
  wc: WNDCLASS;
begin
  try
    if MessageWindowClass = 0 then begin
      FillMemory(@wc, SizeOf(wc), 0);
      wc.lpfnWndProc := @WndProc;
      wc.hInstance := HInstance;
      wc.lpszClassName := MESSAGE_WINDOW_CLASS_NAME;
      MessageWindowClass := saCheckResult(Windows.RegisterClass(wc), 0, 'RegisterClass');
    end;
    Result := Windows.CreateWindowEx(WS_EX_TOOLWINDOW, MESSAGE_WINDOW_CLASS_NAME, nil, WS_POPUP, 0, 0, 0, 0, Cardinal(HWND_MESSAGE), 0, HInstance, nil);
    saCheckResult(Result, 0, 'CreateWindowEx');
  except on e: Exception do
    raise Exception.Create('Error on MakeWindow: '+e.Message);
  end;
end;

function DestroyWindowClass: LongBool;
begin
  if MessageWindowClass > 0 then begin
    MessageWindowClass := 0;
    Result := Windows.UnregisterClass(MESSAGE_WINDOW_CLASS_NAME, HInstance);
  end else Result := True;
end;

procedure DoNetUse(const srv, uname, upass, log: string);
const
  Flag = NORMAL_PRIORITY_CLASS or CREATE_NO_WINDOW;
var
  res: Cardinal;
  si: TStartupInfo;
  pi: TProcessInformation;
  cmd: string;
begin
  try
    FillMemory(@pi, SizeOf(pi), 0);
    FillMemory(@si, SizeOf(si), 0);
    si.cb := SizeOf(si);

    cmd := 'cmd /c net use "'+srv+'" "'+upass+'" /user:"'+uname+'" > "'+log+'" 2>&1';
    if CreateProcess(nil, PChar(cmd), nil, nil, False, Flag, nil, nil, si, pi) then try
      res := WaitForSingleObject(pi.hProcess, 10000);
      saCheckResult(res = WAIT_OBJECT_0, 'WaitFor returned '+IntToStr(res));
    finally
      CloseHandle(pi.hThread);
      CloseHandle(pi.hProcess);
    end else
      saCheckResult(False, 'CreateProcess');
  except on e: Exception do begin
    raise Exception.Create('DoNetUse: ' + e.Message);
  end; end;
end;
{$WARNINGS ON}



{ TClientInfo }

constructor TClientInfo.Create;
begin
  Self.w := Windows.CreateEvent(nil, False, True, nil);
  Self.e := Windows.CreateEvent(nil, False, False, nil);
  Self.i := 2;
end;

destructor TClientInfo.Destroy;
begin
  Windows.CloseHandle(Self.e);
  Windows.CloseHandle(Self.w);
  SetLength(Self.request.buff, 0);
end;

procedure TClientInfo.Release;
begin
  WaitForSingleObject(Self.w, 10000);
  Dec(Self.i);

  if Self.i < 1 then Self.Destroy
  else SetEvent(Self.w);
end;

procedure TClientInfo.WakeUp(resp: TClientResponse);
begin
  Self.r := resp;
  SetEvent(Self.e);
end;


{ MySockCallback }

procedure MySockCallback(const AThread: saTServerClientThread);
var inf: TClientInfo;
  req: TRequest;
begin
  try
    try
      uProto.ServerReadRequest(AThread, req);
    except on e: Exception do
      raise Exception.Create('Reading request: '+e.Message);
    end;

    if req.nproc = PROTOCOL_RESTART_REQUEST then begin
      PostMessage(AService.Handle, WM_SVC_RESTART, 0, 0);
      Exit;
    end;

    try
      try
        inf := nil;
        inf := TClientInfo.Create; //Call Release twice to auto destroy
        inf.request := req;
        PostMessage(AService.Handle, WM_SRV_REQUEST, Integer(inf), 0);
      except on e: Exception do begin
        FreeAndNil(inf); //���-�� ����� �� ���, ����� �� ������� ������ Release
        raise Exception.Create('making inf: '+e.Message);
      end end;
      //���� �� ����� �� ����, �� inf ����� �� ������, ���� � ��� �� �������
      //���� ����� � �������� ������, ����� �� ������ ���� ������, ���� �� ��� ��� �� ��������

      while not AThread.Terminated do try
        case WaitForSingleObject(inf.e, SOCKET_INTERVAL * 1000) of
          WAIT_TIMEOUT: ServerSendResponse(AThread, crWait);
          WAIT_OBJECT_0: begin
            ServerSendResponse(AThread, inf.r);
            Break;
          end;
          WAIT_ABANDONED: begin
            ServerSendResponse(AThread,  crOff);
            raise Exception.Create('WAIT_ABANDONED 0_o');
          end;
          WAIT_FAILED: begin
            ServerSendResponse(AThread,  crOff);
            raise Exception.Create('WAIT_FAILED: '+saMsgLastError);
          end;
        end;
      except on e: Exception do
        raise Exception.Create('WaitForSingleObject: '+e.Message);
      end;
    finally
      if inf <> nil then inf.Release;
    end;
  except on e: Exception do
    PostMessage(AService.Handle, WM_CLIENT_ERROR, 0, StrToLparam('Error in MySockCallback: '+e.Message));
  end;
end;


{ AService }



{ ������, ���������� �������������� }
procedure ServiceController(CtrlCode: DWord); stdcall;
begin
  AService.Controller(CtrlCode);
end;

function TAService.GetServiceController: TServiceController;
begin
  Result := ServiceController;
end;

{ ������������� }
function TAService.Init: Boolean;
begin
  Result := False;

  //����� ������ ���������� � ������ ������������, ��� �, ��� �, ���� ������ ����
  //����� ������ �������� ��������� �������� (�������) ��� ������ ��������

  try
    exename := ParamStr(0);
    local := ExtractFilePath(exename);
    exename := ExtractFileName(exename);
    errorlog := local + 'svcerror.log';

    Self.Name := ChangeFileExt(exename, '');
    MyLogEvent := RegisterEventSource(nil, PChar(Self.Name)); //"TheService"
    if MyLogEvent = 0 then saRaiseLastError('Failed to RegisterEventSource: ');
  except on e: Exception do
    Exit; //���� ������ ���, �� � ��������
  end;

  try
    lastupdate := 0;

    Self.DisplayName := Self.Name;
    Self.Handle := 0;

    Server := nil;
    Timers := nil;

    FirstTask := nil;
    LastTask := nil;

    saSock.saSockMessageHandle := 0;
    saUtils.saLogErrorCallback := WindowsEventLog;

    QueueEvent := 0;
    WorkerEvent := 0;
    InitEvent := 0;

    InitMessage := nil;
    WorkerThread := nil;
    FSrvMessage := nil;
    FDllInit := nil;

    exeupdated := False;
    DecimalSeparator := '.';

    realState := csStopped;
    Result := True;
  except on e: Exception do
    saWriteLog(errorlog, 'Exception in Init: '+e.Message);
  end;
end;

{ ����������� / ������������� }
procedure TAService.ServiceBeforeInstall(Sender: TService);
var
  err: string;
  ini: saTIniFile;
begin
  try
    try
      ini := nil;
      ini := saTIniFile.Create;
      ini.LoadSections(local + ChangeFileExt(exename, '.ini'), ['service']);
      Self.ServiceStartName := ini.AsStr('adusername', '');
      Self.Password       := ini.AsStr('password', '');
      descript          := ini.AsStr('description');
      novellname := ini.AsStr('novellname', '');
    finally
      ini.Free;
    end;

    if descript = ''
    then raise Exception.Create('description �� ������ ���� ������');

    if Self.ServiceStartName = ''
    then saWriteLog(errorlog, 'OnInstall: ����� �� �����, ��������� ����� � Novell �� ����� �������');
  except on e: Exception do begin
    err := 'Exception in BeforeInstall: '+e.Message;
    saWriteLog(errorlog, err);

    //������ ������ �������� � �������� ��������������� � ����, ��������� ��������, ������ �� ����������
    raise Exception.Create(err);
  end; end;
end;

procedure TAService.ServiceAfterInstall(Sender: TService);
var
  key: string;
  reg: TRegistry;
begin
  try
    try
      reg := nil;
      reg := TRegistry.Create(KEY_READ or KEY_WRITE);
      reg.RootKey := HKEY_LOCAL_MACHINE;

      key := '\SYSTEM\CurrentControlSet\Services\' + Self.Name; //"TheService", this is set in Init
      if Reg.OpenKey(key, False) then begin  //Created automatically, deleted automatically
        Reg.WriteString('Description', descript);
        Reg.CloseKey;
      end;

      key := key + '\Parameters';
      if reg.OpenKey(key, True) then begin  //Created here, deleted automatically
        reg.WriteString('user', EncodeB64(Self.novellname));
        reg.WriteString('pass', EncodeB64(Self.Password));
        reg.CloseKey;
      end;

      key := '\SYSTEM\CurrentControlSet\Services\Eventlog\Application\' + Self.Name; //"TheService"
      if reg.OpenKey(key, True) then begin  //Crated here, deleted manually
        Reg.WriteString('EventMessageFile', local + exename);
        Reg.WriteInteger('TypesSupported', 1);
        Reg.CloseKey;
      end;
    finally
      reg.Free;
    end;
  except on e: Exception do begin
    key := 'Exception in AfterInstall: '+e.Message;
    saWriteLog(errorlog, key);
    //������-��������, � ���� ����������������, ������, ������� ��� ����������, ��������� ������
    raise Exception.Create(key);
  end; end;
end;

procedure TAService.ServiceBeforeUninstall(Sender: TService);
var
  key: string;
  reg: TRegistry;
begin
  try
    try
      reg := nil;
      reg := TRegistry.Create(KEY_READ or KEY_WRITE);
      reg.RootKey := HKEY_LOCAL_MACHINE;

      key := '\SYSTEM\CurrentControlSet\Services\Eventlog\Application\' + Self.Name; //"TheService", this is set in Init
      if reg.KeyExists(key) then
      if not reg.DeleteKey(key) then
      saWriteLog(errorlog, 'BeforeUninstall failed to delete key ['+key+']: ' + saMsgLastError);
    finally
      reg.Free;
    end;
  except on e: Exception do begin
    key := 'Exception in BeforeUninstall: '+e.Message;
    saWriteLog(errorlog, key);
    //� ����, �� �� �����, ������ �� ���������
    raise Exception.Create(key);
  end; end;
end;

procedure TAService.InitWorkLog;
var st: TSystemTime;
begin
  if worklog = '' then Exit; //No work log

  if ExpandFileName(worklog) <> worklog then begin
    worklog := local + worklog;
    ForceDirectories(worklog);
  end else if not DirectoryExists(worklog) then
    raise Exception.Create('��� ������� ['+worklog+']: '+saMsgLastError);

  GetLocalTime(st);
  worklog := worklog + Format('%.4d%.2d', [st.wYear, st.wMonth]) + '.txt';
end;


{ ����� / ���� }
procedure TAService.ServiceStart(Sender: TService; var Started: Boolean);
var
  key: string;
  reg: TRegistry;
  ini: saTIniFile;

  ininame: string;
  sections: string;
begin
  if realState = csStopped then try
    try
      try //��������� ����� ������ ��� ����������� � �������
        reg := nil;
        reg := TRegistry.Create(KEY_READ);
        reg.RootKey := HKEY_LOCAL_MACHINE;

        key := '\SYSTEM\CurrentControlSet\Services\' + Self.Name + '\Parameters';
        if reg.OpenKeyReadOnly(key) then begin
          Self.novellname := DecodeB64(reg.ReadString('user'));
          Self.novellpass := DecodeB64(reg.ReadString('pass'));
          reg.CloseKey;
        end else
          raise Exception.Create('Cannot open key [' + key + ']');
      finally
        reg.Free;
      end;
    except on e: Exception do
      //probably service was not properly installed
      raise Exception.Create('Error reading user/pass from registry: '+e.Message);
    end;

    try
      ininame := local + ChangeFileExt(exename, '.ini');

      try //��������� ��������� �������� �� ��� �����
        ini := nil;
        ini := saTIniFile.Create;
        ini.LoadSections(ininame, ['service', 'server', 'payload']);

        ini.SetSection('service');
        selfupdate := ini.AsStr('svcUpdate', '', True);
        worklog := ini.AsStr('worklog', '', True);
        bUsesBDE := ini.AsBool('UsesBDE', False);
        bUsesADO := ini.AsBool('UsesADO', True);

        ini.SetSection('server');
        Self.Port := ini.AsInt('port', 0);
        sSrvMsg := ini.AsStr('LogMsgHandler', '');

        ini.SetSection('payload');
        userupdate := ini.AsStr('updateSrc', '', True);
        dllname  :=  ini.AsStr('dllname');

//        sOnStop := ini.AsStr('onServiceStop', '');
//        sOnStart := ini.AsStr('onServiceStart', '');
        sDllInit := ini.AsStr('DllInit');

        sections := ini.AsStr('timers', '');
      finally
        ini.Free;
      end;

      //��������� ������� �� ���� �� ��� �����
      Timers := GetTimers(ininame, sections);
    except on e: Exception do
      raise Exception.Create('Error reading settings from *.ini: '+e.Message);
    end;

    InitWorkLog;

    //��������� ����������� ����������� ��������
    if (Length(Timers) = 0) and (Self.Port = 0)
    then raise Exception.Create('No server and no timers specified');

    if not saFileExists(local + dllname)
    then raise Exception.Create('Can''t find dll ['+local+dllname+']');

    CheckTimers(Timers);

    //������������ � �������
    if Self.novellname <> '' then DoNetUse('\\fs', Self.novellname, Self.novellpass, local + 'net_use.log');

    CheckUpdates(True);
    LoadDll;

    //������� ��������� ��� ������� ���������
    Self.Handle := MakeWindow;
    saSock.saSockMessageHandle := Self.Handle;

    //������ ���� ������� ����� ���������, ��������, ������� ������
    QueueEvent := saCheckResult(CreateEvent(nil, False, True, nil), 0, 'QueueEvent.CreateEvent');

    //������������� �������� �����
    WorkerEvent := saCheckResult(CreateEvent(nil, False, False, nil), 0, 'WorkerEvent.CreateEvent');
    WorkerThread := TWorkerThread.Create(Self.Handle, WorkerEvent, bUsesADO, bUsesBDE);
    FDllInit(WorkerThread.AbortCallback);

{    if sOnStart > '' then WorkerThread.FOnStart := GetProc(sOnStart);
    if sOnStop > '' then WorkerThread.FOnStop := GetProc(sOnStop);}

    //������������� ������ ��� �������� ������������ �������������
    InitEvent := saCheckResult(Windows.CreateEvent(nil, False, False, nil), 0, 'Create InitEvent');

    WorkerThread.Resume; //� ��� �� ������ ������ ����� ������ InitEvent
    case WaitForSingleObject(InitEvent, 20000) of
      WAIT_OBJECT_0: ;
      WAIT_FAILED: raise Exception.Create('InitEvent WAIT_FAILED');
      WAIT_TIMEOUT: raise Exception.Create('InitEvent WAIT_TIMEOUT');
      WAIT_ABANDONED: raise Exception.Create('InitEvent WAIT_ABANDONED');
    end;
    if InitMessage <> nil then raise Exception.Create(InitMessage^);
    //������������� ��� ������� � StopAndFree ����� ������, ������� ����� �� ������������


    //���������� ������
    if Self.Port > 0 then begin
      Server := saTServer.Create(Port, MySockCallback);
      Server.OpenMyServer;
    end;

    if worklog > '' then begin
      WriteWorkLog('!');
      WriteWorkLog('Started Service');
    end;

    FreeTasks;
    StartTimers;

    Started := True;
    realState := csRunning;
  except on e: Exception do begin
    Started := False; ErrCode := 1;
    saWriteLog(errorlog, 'Exception in OnStart: ' + e.Message);
    StopAndFree;
  end; end;
end;

procedure TAService.StopAndFree;
var errors: string;
begin
  try
    errors := '';

    KillTimers;

    //��� ��� ����� ���� ����� ����������, ����� ��� ��� ��������, ������ ������� ������� � �����
    if QueueEvent > 0 then try
      FreeTasks;
      CloseHandle(QueueEvent);
      QueueEvent := 0;
    except on e: Exception do
      errors := errors + #13#10 + 'FreeTasks: ' + e.Message;
    end;

    if Assigned(WorkerThread) then try
      WorkerThread.Terminate;
      WorkerThread.Resume;
      SetEvent(WorkerEvent);

      try
        case WaitForSingleObject(WorkerThread.Handle, 20000) of
          WAIT_OBJECT_0:;
          WAIT_FAILED: raise Exception.Create('WAIT_FAILED');
          WAIT_TIMEOUT: raise Exception.Create('WAIT_TIMEOUT');
          WAIT_ABANDONED: raise Exception.Create('WAIT_ABANDONED');
        end;
      except on e: Exception do begin
        TerminateThread(WorkerThread.Handle, 1);
        errors := errors + #13#10 + 'WaitFor WorkerThread: ' + e.Message;
      end; end;

      FreeAndNil(WorkerThread);
    except on e: Exception do
      errors := errors + #13#10 + 'Terminate WorkerThread: ' + e.Message;
    end;

    if WorkerEvent > 0 then begin
      CloseHandle(WorkerEvent);
      WorkerEvent := 0;
    end;

    if InitEvent > 0 then begin
      CloseHandle(InitEvent);
      InitEvent := 0;
    end;

    if InitMessage <> nil then begin
      Dispose(InitMessage);
      InitMessage := nil;
    end;

    if Server <> nil then try
      Server.CloseMyServer;
      FreeAndNil(Server);
    except on e: Exception do
      errors := errors + #13#10 + 'CloseMyServer: ' + e.Message;
    end;

    if not FreeDll then
      errors := errors + #13#10 + 'FreeDll: ' + saMsgLastError;

    if Self.Handle > 0 then begin
      if not Windows.DestroyWindow(Self.Handle)
      then errors := errors + #13#10 + 'DestroyWindow: ' + saMsgLastError;
      Self.Handle := 0;
    end;

    if not DestroyWindowClass
    then errors := errors + #13#10 + 'DestroyWindowClass: ' + saMsgLastError;

    if errors <> '' then saWriteLog(errorlog, 'Errors in StopAndFree: ' + errors);
  except on e: Exception do
    saWriteLog(errorlog, 'Exception in StopAndFree: '+e.Message);
  end;
end;

procedure TAService.ServiceStop(Sender: TService; var Stopped: Boolean);
begin
  if (realState = csRunning) then begin
    StopAndFree;

    if worklog > '' then begin
      WriteWorkLog('Stopped Service');
      WriteWorkLog('!');
    end;

    CheckUpdates(True);  //�������� ��� ������, ���� �� �� ���������� �����
    realState := csStopped;
  end;

  Stopped := True;
end;

procedure TAService.ServiceShutdown(Sender: TService);
var b: Boolean;
begin
  ServiceStop(Self, b);
end;

procedure TAService.Restart;
var b: Boolean;
begin
  try
    WriteWorkLog('Restart request recieved');

    b := False;
    ServiceStop(Self, b);
    if not b then raise Exception.Create('Failed to stop');

    b := False;
    ServiceStart(Self, b);
    if not b then raise Exception.Create('Failed to start');
  except on e: Exception do begin
    saWriteLog(errorlog, 'Error in Restart: ' + e.Message);
    DoShutdown;
  end; end;
end;

procedure TAService.StartTimers;
var i: Integer;
begin
  for i := Length(Timers) - 1 downto 0 do
    Windows.SetTimer(Self.Handle, Timers[i].id, CalcInterval(Timers[i]), nil);
end;

procedure TAService.KillTimers;
var i: Integer;
begin
  for i := Length(Timers) - 1 downto 0 do
    Windows.KillTimer(Self.Handle, Timers[i].id);
end;






{ ��������� ������� }

//�������� ������, � ��� ������...
function TAService.OnTimer(TimerID: Cardinal): Integer;
var
  i: Integer;
  p: PTask;
  s: string;
begin
  Result := 0;
  Windows.KillTimer(Self.Handle, TimerID);
  //�������� ���� ������. ����� ������������ (���� ������ �������� � ������ ������ � �������)

  if realState = csRunning then begin
    //����������� ����� ���� ������ � ����� ������ ��������, ��� ��� ������ ����������
    i := FindTimer(Timers, TimerID);
    if i < 0 then
      raise Exception.Create('cant find timer ['+IntToStr(TimerID)+']')
    else begin
      s := Timers[i].nproc;

      //����������� �������������� ����� ������� � ������� �����
      WaitForSingleObject(QueueEvent, Infinite);
      try
        p := FindTask(s);
        if p = nil
        then AddTaskFromTimer(s, i)
        else AddTimerToTask(p, i);
        //���� ����� ������ ��� ���� � �������, �� ������� � �� ���� ������, ����� �������� ����� ������
      finally
        SetEvent(QueueEvent);
      end;
    end;
  end;
end;

//�������� ��������� � ������� �� ���������
//���������������� ����� QueueEvent (������� autoreset), ���������� ������ ����� ������� ������
function TAService.FindTask(const nproc: string): PTask;
begin
  Result := FirstTask;
  while (Result <> nil) and (Result.nproc <> nproc)
  do Result := Result.next;
end;

//������� ����� ����, �������� - ������
//���������������� ����� QueueEvent (������� autoreset), ���������� ������ ����� ������� ������
procedure TAService.AddTaskFromTimer(const nproc: string; tmidx: Integer);
var p: PTask;
begin
  New(p);
  InitTask(p);

  p.nproc := nproc;
  AddTimerToTask(p, tmidx);

  TaskQueueAdd(p);
end;

//���� ��� ����, �������� ����������� � ���� (������)
//���������������� ����� QueueEvent (������� autoreset), ���������� ������ ����� ������� ������
procedure TAService.AddTimerToTask(p: PTask; tmidx: Integer);
var i: Integer;
begin
  //���� ���� ������ ��� (��������) � ������ ��������, �� ������ �� ���� ������
  for i := 0 to p.tcount - 1 do
    if p.tindxs[i] = tmidx then Exit;

  //������ ������, ���� ���
  if p.tcount >= p.tcap then begin
    Inc(p.tcap, 8);
    SetLength(p.tindxs, p.tcap);
  end;

  //������� ������ � ������
  p.tindxs[p.tcount] := tmidx;
  Inc(p.tcount);
end;

//���� ������ �� ������������
//���� ��� ����������, �� ����� ������� � ����, ��������� ��������
//���� ���� ���������, �� ��� ������� ������� ������ ���������� ��������� ��������� ����
//���������� ������ � ����������� ����������� ��������� � ���� ����
procedure TAService.OnServerRequest(Msg: Cardinal; wParam: WPARAM; lParam: LPARAM);
var
  p: PTask;
  t: TClientInfo;
begin
  if realState = csRunning then begin
    t := TClientInfo(wParam);

    WriteWorkLog('User request ['+t.request.nproc+']');

    WaitForSingleObject(QueueEvent, Infinite);
    try
      p := FindTaskArg(@t.request);
      if (p = nil)
      then AddTaskFromUser(t) //��� ���������� ������, ������� �����
      else AddClientToTask(p, t); //����� ���� ��� ����, ������� �������
    finally
      SetEvent(QueueEvent);
    end;
  end;
end;

function TAService.FindTaskArg(Request: PRequest): PTask;
begin
  Result := FirstTask;
  while Result <> nil do begin
    if (Result.nproc = Request.nproc) and (Result.bsize = Request.bsize) then begin
      if Result.bsize = 0 then Exit; //�� �� ��������� ��� ����������
      if CompareMem(@(Result.buff[0]), @(request.buff[0]), Result.bsize) then Exit; //���������� ���������
    end;

    Result := Result.next;
  end;
end;

//�������� ����������� (������������) � ������������ ����
//���������������� ����� QueueEvent (������� autoreset), ���������� ������ ����� ������� ������
procedure TAService.AddClientToTask(p: PTask; const e: TClientInfo);
var i: Integer;
begin
  for i := 0 to p.ecount - 1 do
    if p.clients[i] = e then Exit; //����� �������� ���� �����-�� ��� ���������

  if p.ecount >= p.ecap then begin
    Inc(p.ecap, 8);
    SetLength(p.clients, p.ecap);
  end;

  p.clients[p.ecount] := e;
  Inc(p.ecount);
end;

//���������������� ����� QueueEvent (������� autoreset), ���������� ������ ����� ������� ������
procedure TAService.AddTaskFromUser(const e: TClientInfo);
var p: PTask;
begin
  New(p);
  InitTask(p);

  p.nproc := e.request.nproc;
  AddClientToTask(p, e);

  p.bsize := e.request.bsize;
  if p.bsize > 0 then begin
    SetLength(p.buff, p.bsize); //������ �� ������� ���������� � ����. Everyone manages it's own shit
    Move(e.request.buff[0], p.buff[0], p.bsize);
  end;

  TaskQueueAdd(p);
end;

//���������������� ����� QueueEvent (������� autoreset), ���������� ������ ����� ������� ������
procedure TAService.TaskQueueAdd(p: PTask);
begin
  if FirstTask = nil then begin
    FirstTask := p;
    LastTask := p;
    //��� �����, ������ ������ ����
    SetTaskToWork(p);
  end else begin
    LastTask^.next := p;
    LastTask := p;
  end;
end;

//������� ��������� ���� ��� ������
//���������������� ����� QueueEvent (������� autoreset), ���������� ������ ����� ������� ������
function  TAService.TaskQueueSelect: PTask;
begin
  Result := FirstTask;
  if Result = nil then Exit;

  repeat //�������� �������� ������� �� �������������
    if Result.ecount > 0 then Exit
    else Result := Result.next;
  until Result = nil;

  //�� ������������ ������ ���, ������������ � ������� �����������
  Result := FirstTask;
end;

//������ ����������� ���� �� �������. ���� �������� ���� �� ����� ���
//���������������� ����� QueueEvent (������� autoreset), ���������� ������ ����� ������� ������
procedure TAService.TaskQueueRemove(p: PTask);
var a, b: PTask;
begin
  a := nil;       //���������� ����
  b := FirstTask; //������� ����

  while b <> nil do begin
    if b = p then begin //��� ���� ������, ����� ��������
      if b.next = nil then LastTask := a; //p == b == LastTask
      if a = nil then FirstTask := b.next //p == b == FirstTask
      else a.next := b.next;
      Exit;
    end;

    a := b;
    b := b.next;
  end;

  raise Exception.Create('TaskQueueRemove ���� �� ������ � �������!');
end;

//� �������� ������� ����� MySockCallback, ����� WakeUp �� �������� � ������ ������������ �����
//������ ������ �������� ������ � MySockCallback, ��� ������ ��� ��� �������� (� � �� ��� ������, � ��� ������ ������)
procedure ReleaseClients(p: PTask; resp: TClientResponse);
var i: Integer;
begin
  for i := p.ecount - 1 downto 0 do begin
    p.clients[i].WakeUp(resp);
    p.clients[i].Release;
  end;
end;

procedure TAService.SetTaskToWork(p: PTask);
begin
  CheckUpdates(False);

  WorkerThread.task := p;
  WriteWorkLog(Format('Starting [%s]. Timers count = %d; Users count = %d', [p.nproc, p.tcount, p.ecount]));

  try
    p.pproc := nil;
    p.pproc := GetProc(p.nproc);
    SetEvent(WorkerEvent);
  except on e: Exception do
    PostMessage(Self.Handle, WM_THREAD_ERROR, 0, StrToLparam('SetTaskToWork failed: ' + e.Message));
  end;
end;

procedure TAService.OnTaskComplete(resp: TClientResponse);
var
  i: Integer;
  p, q: PTask;
  t: RTimer;
begin
  try
    p := WorkerThread.task; //����, ������� ����� ����

    WaitForSingleObject(QueueEvent, INFINITE);
    try
      TaskQueueRemove(p); //������ ���� �� �������

      q := TaskQueueSelect; //������� ��������� ���� ��� ������
      if q <> nil then SetTaskToWork(q);
    finally
      SetEvent(QueueEvent);
    end;

    ReleaseClients(p, resp);

    for i := 0 to p.tcount - 1 do begin
      t := Timers[p.tindxs[i]];
      Windows.SetTimer(Self.Handle, t.id, CalcInterval(t), nil);
    end;

    WriteWorkLog('Done ['+p.nproc+']');

    FreeTask(p);
  except on e: Exception do
    saWriteLog(errorlog, 'Exception in OnTaskComplete: '+e.Message);
  end;
end;

procedure TAService.OnErrMsg(lparam: Integer);
var emess: string;
begin
  emess := LParamToStr(lparam);
  saWriteLog(errorlog, emess);
  WriteWorkLog(emess);
end;

procedure TAService.OnThreadDead;
begin
  DoShutdown; //ServiceStop is OnShutdown
end;

procedure TAservice.InitTask(const p: PTask);
begin
  p.ecap := 0;
  p.ecount := 0;

  p.tcap := 0;
  p.tcount := 0;

  p.bsize := 0;

  p.next := nil;
end;

procedure TAService.FreeTask(p: PTask);
begin
  SetLength(p.tindxs, 0); //timers are killed another place
  SetLength(p.clients, 0); //clients are notified and released elsewhere
  SetLength(p.buff, 0);

  Dispose(p);
end;

//���������� �� ������ �������� ��� ����� ����� ��������, ������� ���������� ������ ��������
procedure TAService.FreeTasks;
var p: PTask;
begin
  WaitForSingleObject(QueueEvent, INFINITE);
  try
    while FirstTask <> nil do begin
      p := FirstTask;
      FirstTask := p^.next;
      ReleaseClients(p, crOff);
      FreeTask(p);
    end;

    FirstTask := nil;
    LastTask := nil;
  finally
    SetEvent(QueueEvent);
  end;
end;

procedure TAService.OnServerLog(Msg: Cardinal; wParam: WPARAM; lParam: LPARAM);
begin
  if @FSrvMessage <> nil then try
    FSrvMessage(Msg, wParam, lParam);
  except on e: Exception do
    saWriteLog(errorlog, 'Error in FSrvMessage was properly ignored: '+e.Message);
  end;
end;

procedure TAService.CopyFiles(const src, dst: string; ur: Word);
var
  sr: TSearchRec;
  srcfile, dstfile: string;
begin
  if SysUtils.FindFirst(src + '*.*', faAnyFile, sr) = 0 then try
    repeat
      if not ((sr.Name = '') or (sr.Name = '.') or (sr.Name = '..')) then try  //��� �� �����
        srcfile := src + sr.Name;
        dstfile := dst + sr.Name;

        if (AnsiCompareText(dstfile, local + exename) = 0)
        or (AnsiCompareText(dstfile, local + dllname) = 0)
        or (AnsiCompareText(sr.Name, UPDATE_EXE_NAME) = 0) then
          Continue; //��� �������������� �����������

        if (sr.Attr and faDirectory) > 0 then begin          //���� ��� �����, �� ������� � ��������
          if not DirectoryExists(dstfile) then begin
            if not CreateDir(dstfile)
            then saRaiseLastError('CreateDir('+dstfile+')');
          end;
          CopyFiles(srcfile + '\', dstfile + '\', ur + 1);
        end else begin                                      //��� �� �����, ������ ��� - �����
          if FileAge(srcfile) > FileAge(dstfile)
          then saCopyFileSure(srcfile, dstfile);
        end;
      except on e: Exception do
        saWriteLog(errorlog, 'Error in CopyFiles: ' + e.Message);
      end;
    until SysUtils.FindNext(sr) <> 0;
  finally
    SysUtils.FindClose(sr);
  end;
end;

//���������� onStart � onStop, ���� ��� ����������� � ���������
//���� ��� �������� ���������, ��� ������������ ����� �������� ��� ���������, �� �� ������ "������� ������������ � ������� ������". �������
procedure TAService.CheckUpdates;
var
  newupdate: TDateTime;
  src, dst: string;
  reload: Boolean;
begin
  newupdate := Now; //�������� ����������� �� ������� �����
  if (forced = True) or ((newupdate - lastupdate) > UPDATES_COOLDOWN) then begin
    lastupdate := newupdate;

    //������ ������ �������, ���� ��� ����, ������ �������, �������������� ������ ��������� ������ ����� �����������
    if selfupdate <> '' then try
      saDirectoryMustExist(selfupdate);

      dst := local + exename;
      src := selfupdate + UPDATE_EXE_NAME;
      if FileAge(src) > FileAge(dst) then begin
        if not exeupdated then begin
          saMoveFileSure(dst, dst+'.bak');
          exeupdated := True;
        end;
        saCopyFileSure(src, dst, True);
        WriteWorkLog('Updated ' + exename);
      end;

      CopyFiles(selfupdate, local, 0);
    except on e: Exception do
      saWriteLog(errorlog, '������ ��������������� ���������� �������: ' + e.Message);
    end;

    //������ ���������������� ��������. DLL ���� ��������� ��� ����������, ��������� ����� ������ ������� �����������
    if userupdate <> '' then try
      saDirectoryMustExist(userupdate);

      dst := local + dllname;
      src := userupdate + dllname;
      if FileAge(src) > FileAge(dst) then begin
        FreeDll;

        try
          saCopyFileSure(src, dst);
          WriteWorkLog('Updated ' + dllname);
        except on e: Exception do
          saWriteLog(errorlog, '������ ��������������� ���������� DLL: ' + e.Message);
        end;

        if (forced = False) then begin
          LoadDll;
          FDllInit(WorkerThread.AbortCallback);
        end;
      end;

      CopyFiles(userupdate, local, 0);
    except on e: Exception do
      saWriteLog(errorlog, '������ ��������������� ���������� ���������: ' + e.Message);
    end;
  end;
end;

function TAService.GetProc(const naim: string): Pointer;
begin
  if naim = '' then raise Exception.Create('TAService.GetProc empty procedure name');

  Result := GetProcAddress(DllHandle, PChar(naim));
  saCheckResult(Result <> nil, 'GetProcAddress ['+naim+']');
end;

procedure TAService.LoadDll;
begin
  try
    if not FreeDll then saWriteLog(errorlog, 'Failed to FreeLibrary: ' + saMsgLastError);
    DllHandle := saCheckResult(LoadLibrary(PChar(local + dllname)), 0, 'LoadLibrary ['+dllname+']');

    FDllInit := GetProc(sDllInit);
    if sSrvMsg > '' then FSrvMessage := GetProc(sSrvMsg);
  except on e: Exception do begin
    raise Exception.Create('Error in LoadDll: '+e.Message);
  end; end;
end;

function TAService.FreeDll: Boolean;
begin
  FDllInit := nil;
  FSrvMessage := nil;

  if DllHandle <> 0 then begin
    Result := FreeLibrary(DllHandle);
    DllHandle := 0;
  end else
    Result := True;
end;



{ TWorkerThread }

constructor TWorkerThread.Create;
begin
  inherited Create(True);
  parentForm := parent;
  wakeEvent := event;

  uado := UseADO;
{  FOnStart := nil;
  FOnStop := nil;}
end;

destructor TWorkerThread.Destroy;
begin
  inherited Destroy;
end;

procedure TWorkerThread.Execute;
var
  tp: TTimerProc;
  up: TUserProc;
  r: Integer;
begin
  try
{    if @FOnStart <> nil then try
      r := FOnStart();
      if r <> 0 then raise Exception.Create('Proc result = ' + IntToStr(r));}

    try
      if uado then begin
        r := CoInitializeEx(nil, COINIT_APARTMENTTHREADED);
        if r <> 0 then raise Exception.Create('CoInit = ' + IntToStr(r));
      end;
      if ubde then begin
        r := DbiInit(nil);
        if r <> 0 then raise Exception.Create('DbiInit = ' + IntToStr(r));
        r := DbiLoadDriver(szDBASE);
        if r <> 0 then raise Exception.Create('DbiLoadDriver = ' + IntToStr(r));
      end;
    except on e: Exception do begin
      New(AService.InitMessage);
      AService.InitMessage^ := 'Error in TWorkerThread.Init: '+e.Message;
    end; end;
  finally
    SetEvent(AService.InitEvent);
  end;

  try
    while True do begin
      //��� �������� �����
      case WaitForSingleObject(wakeEvent, INFINITE) of
        WAIT_OBJECT_0:;
        WAIT_FAILED: raise Exception.Create('WAIT_FAILED');
        WAIT_TIMEOUT: raise Exception.Create('WAIT_TIMEOUT');
        WAIT_ABANDONED: raise Exception.Create('WAIT_ABANDONED');
      end;
      //��� ���������

      //�����������, ���� ��� ���������
      if Self.Terminated then Break;

      try
        //���� �� ���������, ����� ��������, � ��� ���� ������. ������ ���� ��������� ����� ��������
        if task.bsize > 0 then begin
          @up := task.pproc;
          r := up(task.buff, task.bsize);
        end else begin
          @tp := task.pproc;
          r := tp();
        end;

        if not Self.Terminated
        then PostMessage(parentForm, WM_THREAD_READY, r, 0);
        //��������� � �����������, ���� ���� ����
        //���� ���� ����, �� ������� ��� ��� ���������
      except on e: Exception do
        PostMessage(parentForm, WM_THREAD_ERROR, 0, StrToLparam('Exception in Task Proc ['+task.nproc+']: '+e.Message));
      end;
    end;
  except on e: Exception do
    PostMessage(parentForm, WM_THREAD_DEAD, 0, StrToLparam('Exception in TWorkerThread.Execute: ' + e.Message));
  end;

  if ubde then try
    DbiExit;
  except
  end;
  if uado then try
    CoUninitialize;
  except
  end;
 {
  if (@FOnStop <> nil) then try
    FOnStop;
  except
    //Unhandled user exception in FOnStop is properly ignored
  end;  }
end;

function TWorkerThread.AbortCallback(): Boolean; stdcall;
begin
  Result := Self.Terminated;
end;

procedure TAService.WriteWorkLog(const msg: string);
begin
  if worklog > '' then try
    saWriteLog(worklog, msg);
  except on e: Exception do
    saWriteLog(errorlog, 'Error in WriteWorkLog: '+e.Message);
  end;
end;

initialization
  MessageWindowClass := 0;

finalization
  DestroyWindowClass;
  if MyLogEvent > 0 then DeregisterEventSource(MyLogEvent);

end.

