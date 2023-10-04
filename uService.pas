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

  {все процедурки из ДЛЛ, назначенные на таймер или юзера, вызываются из WorkerThread'a
  DLLMAIN, OnInit, OnServerMessage - вызываются из ServiceThread}

  //Пользователи (потоки-обработчики запросов на сервере) ждут ответа от сервиса
  //Вся нужная инфа для ответа пользователям собрана здесь
  TClientInfo = class
  protected
    e: THandle;                                 //евент, на котором вешается ожидание какого-то овтета
    r: TClientResponse;                         //Статус запроса, который я буду отвечать пользователю
    i: Integer; //reference count                 чтобы удалить себя, когда больше ненужен
    w: THandle; //семафор для доступа к reference counter'у. Инфа обрабатывается и в ServiceThread'e, и в ServerClientThread'ах
  public
    request: TRequest;                          //запрос со всеми данными

    constructor Create;
    destructor Destroy; override;
    property event: THandle read e;
    property resp: TClientResponse read r;
    procedure WakeUp(resp: TClientResponse);
    procedure Release;                          //Уменьшить reference count
  end;

  //Задача. Может выполняться по таймеру, или по запросу пользователя. Определяется по имени вызываемой процедуры
  //Все таймеры, которые захотели выполнить эту задачу, и все пользователи, которые запросили эту задачу, хранятся тут в списках
  PTask = ^TTask;
  TTask = record
    next: PTask;     //Ссылка на другую задачу. Примитивный односвязный список
    nproc: string;   //Имя выполняемой процедуры. Определяет задачу
    pproc: Pointer;  //Конкретный адрес процедуры в DLL

    //Перечень клиентов (TClientInfo принадлежит)
    clients: array of TClientInfo;
    ecap, ecount: Integer;

    //Перечень таймеров
    tindxs: array of Integer;
    tcap, tcount: Integer;

    //Аргументы вызова от пользователя. Собственная копия данных
    buff: array of Byte;
    bsize: Byte;
  end;

  //Рабочий поток, который выполняет задачи
  TWorkerThread = class(TThread)
  private
    parentForm: THandle;  //Сюда отправляются сообщения об ошибках
    wakeEvent: THandle;  //На этом евенте оно висит пока нечего делать
    uado, ubde: Boolean;

{    FOnStart: TStartProc;
    FOnStop: TStopProc; //выбранные пользователем процедуры обработки запуска / остановки сервиса}
  public
    task: PTask;         //Задача для работы

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
    Handle: THandle;                     //Создам окно для отправки сообщений, которые я буду обрабатывать
    realState: TCurrentStatus;           //Просто, чтобы понимать, действительное состояние сервера при получении сообщений от Сервис Менеджера
    local, exename, dllname: string;     //имена исполняемых файлов. Автообновляться будут по особым правилам (длл нужно выгрузить, например)
    selfupdate, userupdate: string;      //пути для поиска обновлений. Единый для всех обновлятор сервиса. И уникальный для каждого обновлятор полезной нагрузки
    worklog, errorlog, descript: string; //полный путь и имя файла для ворклога и лога ошибок; описание сервиса для инсталляции. Все логи пишутся в ServiceThread'e
    lastupdate: TDateTime;               //время последней проверки обновлений. используется, чтобы слишком часто не перелистывать все файлы в поисках новых
    exeupdated: Boolean;
    DllHandle: THandle;

    Timers: TTimers;                     //полезная нагрузка
    Server: saTServer;
    Port: Word;

    FSrvMessage: TMsgProc;               //выбранная пользователем процедура обработки сообщений СЕРВЕРА
    FDllInit: TInitProc;                 //процедура инициализации ДЛЛ
    sDllInit, sSrvMsg: string;           //имена этих процедур для поиска в длл

    bUsesADO, bUsesBDE: Boolean;         //флаги нужды инициализации АДО/БДЕ

    InitEvent: THandle;                  //Эвент имени рабочего потока. Надо же узнать, смог ли он успешно выполнить инициализацию, или всё зря
    InitMessage: ^string;                //Место для хранения текста ошибки от рабочего потока

    FirstTask, LastTask: PTask;
    //очередь задач для запуска. Сервис запускает задачи в отдельном потоке, в одном отдельном потоке.
    //Но таймер и запросы собирает, пока задача выполняется
    //Соответственно, когда задача выполнена, выбираем из очереди, что будем делать дальше

    WorkerThread: TWorkerThread;         //тот самый отдельный поток, который будет делать пользовательские задачи
    WorkerEvent, QueueEvent: THandle;    //эвенты для управления этим потоком

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
  UPDATES_COOLDOWN = 0.007; //это чуть больше 10 минут в днях

  UPDATE_EXE_NAME = 'TheService.exe';

var
  MessageWindowClass: Word;
  MyLogEvent: Cardinal;

//Базовый error-reporting, результаты смотреть в "Журнале событий" Windows
//Используется в saWriteLog.OnError
//Планировал юзать из разных потоков, поэтому упор на тред-сейф
//С другой стороны, имя приложухи для сообщений должно быть задано правильно
procedure WindowsEventLog(const msg: string);
var p: PChar;
begin
  p := PChar(msg);
  ReportEvent(MyLogEvent, EVENTLOG_ERROR_TYPE, 0, 1, nil, 1, 0, @p, nil);
  //AService.LogMessage меня не устраивает потому что не тред-сейф
end;

//Это для окна, которое создается в ServiceStart, выполняется, насколько я высянил, в ServiceThread
//Принимает сообщения от таймеров, от сервера, от рабочего треда, здесь происходит всё управление текущими делами, разада задач, сбор результатов, обработка ошибок
//Запросы от таймеров или юзеров выполняются в WorkerThread'e, всё остальное, в том числе менеджмент очереди тасков - в этом треде
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
        FreeAndNil(inf); //что-то пошло не так, никто не вызовет второй Release
        raise Exception.Create('making inf: '+e.Message);
      end end;
      //Если мы дошли до сюда, то inf никто не удалит, пока я его не релизну
      //Тоже самое в основном потоке, никто не удалит инфо оттуда, пока он сам его не релизнет

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



{ дерьмо, навязанное разработчиками }
procedure ServiceController(CtrlCode: DWord); stdcall;
begin
  AService.Controller(CtrlCode);
end;

function TAService.GetServiceController: TServiceController;
begin
  Result := ServiceController;
end;

{ инициализация }
function TAService.Init: Boolean;
begin
  Result := False;

  //Перед любыми действиями я должен определиться, кто я, где я, куда писать логи
  //Потом просто задаются начальные значения (нулевые) для всяких объектов

  try
    exename := ParamStr(0);
    local := ExtractFilePath(exename);
    exename := ExtractFileName(exename);
    errorlog := local + 'svcerror.log';

    Self.Name := ChangeFileExt(exename, '');
    MyLogEvent := RegisterEventSource(nil, PChar(Self.Name)); //"TheService"
    if MyLogEvent = 0 then saRaiseLastError('Failed to RegisterEventSource: ');
  except on e: Exception do
    Exit; //Если сдохло тут, то я бессилен
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

{ инсталляция / деинсталляция }
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
    then raise Exception.Create('description не должен быть пустым');

    if Self.ServiceStartName = ''
    then saWriteLog(errorlog, 'OnInstall: логин не задан, настройка входа в Novell на вашей совести');
  except on e: Exception do begin
    err := 'Exception in BeforeInstall: '+e.Message;
    saWriteLog(errorlog, err);

    //словит сервис менеджер и выплюнет усанавливающему в лицо, установка фейлится, сервис не установлен
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
    //сервис-менеджер, в лицо устанавливающему, сервис, который уже установлен, удаляется кхерам
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
    //в лицо, ну ты понел, сервис не удаляется
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
    raise Exception.Create('Нет доступа ['+worklog+']: '+saMsgLastError);

  GetLocalTime(st);
  worklog := worklog + Format('%.4d%.2d', [st.wYear, st.wMonth]) + '.txt';
end;


{ старт / стоп }
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
      try //прочитать логин пароль для подключения к новеллу
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

      try //прочитать всяческие настроки из ини файла
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

      //прочитать таймера из того же ини файла
      Timers := GetTimers(ininame, sections);
    except on e: Exception do
      raise Exception.Create('Error reading settings from *.ini: '+e.Message);
    end;

    InitWorkLog;

    //проверить целостность прочитанных настроек
    if (Length(Timers) = 0) and (Self.Port = 0)
    then raise Exception.Create('No server and no timers specified');

    if not saFileExists(local + dllname)
    then raise Exception.Create('Can''t find dll ['+local+dllname+']');

    CheckTimers(Timers);

    //подключиться к новеллу
    if Self.novellname <> '' then DoNetUse('\\fs', Self.novellname, Self.novellpass, local + 'net_use.log');

    CheckUpdates(True);
    LoadDll;

    //создать чапельник для очереди сообщений
    Self.Handle := MakeWindow;
    saSock.saSockMessageHandle := Self.Handle;

    //Должно быть создано ПЕРЕД таймерами, сервером, рабочим тредом
    QueueEvent := saCheckResult(CreateEvent(nil, False, True, nil), 0, 'QueueEvent.CreateEvent');

    //Инициализация рабочего треда
    WorkerEvent := saCheckResult(CreateEvent(nil, False, False, nil), 0, 'WorkerEvent.CreateEvent');
    WorkerThread := TWorkerThread.Create(Self.Handle, WorkerEvent, bUsesADO, bUsesBDE);
    FDllInit(WorkerThread.AbortCallback);

{    if sOnStart > '' then WorkerThread.FOnStart := GetProc(sOnStart);
    if sOnStop > '' then WorkerThread.FOnStop := GetProc(sOnStop);}

    //Инициализация евента для ожидания резуьльтатов инициализации
    InitEvent := saCheckResult(Windows.CreateEvent(nil, False, False, nil), 0, 'Create InitEvent');

    WorkerThread.Resume; //Я жду от потока первым делом дёрнуть InitEvent
    case WaitForSingleObject(InitEvent, 20000) of
      WAIT_OBJECT_0: ;
      WAIT_FAILED: raise Exception.Create('InitEvent WAIT_FAILED');
      WAIT_TIMEOUT: raise Exception.Create('InitEvent WAIT_TIMEOUT');
      WAIT_ABANDONED: raise Exception.Create('InitEvent WAIT_ABANDONED');
    end;
    if InitMessage <> nil then raise Exception.Create(InitMessage^);
    //Освобождаются эти ресурсы в StopAndFree после потока, который может их использовать


    //стартануть сервер
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

    //эту всю хрень надо будет переделать, нафиг все эти проверки, просто рубанул функцию и забыл
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

    CheckUpdates(True);  //обновить сам сервис, пока не не запустился снова
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






{ обработка событий }

//Сработал таймер, а это значит...
function TAService.OnTimer(TimerID: Cardinal): Integer;
var
  i: Integer;
  p: PTask;
  s: string;
begin
  Result := 0;
  Windows.KillTimer(Self.Handle, TimerID);
  //Отключим этот таймер. Потом перезапустим (если сервер работает и таймер найден в перечне)

  if realState = csRunning then begin
    //Обязательно найдём этот таймер в нашем списке таймеров, там вся нужная информация
    i := FindTimer(Timers, TimerID);
    if i < 0 then
      raise Exception.Create('cant find timer ['+IntToStr(TimerID)+']')
    else begin
      s := Timers[i].nproc;

      //Обязательно синхронизируем любые доступы к очереди задач
      WaitForSingleObject(QueueEvent, Infinite);
      try
        p := FindTask(s);
        if p = nil
        then AddTaskFromTimer(s, i)
        else AddTimerToTask(p, i);
        //Если такая задача уже есть в очереди, то добавим в неё этот таймер, иначе создадим новую задачу
      finally
        SetEvent(QueueEvent);
      end;
    end;
  end;
end;

//поискать процедуру в очереди на обработку
//Синхронизируется через QueueEvent (который autoreset), вызывается только после захвата евента
function TAService.FindTask(const nproc: string): PTask;
begin
  Result := FirstTask;
  while (Result <> nil) and (Result.nproc <> nproc)
  do Result := Result.next;
end;

//создать новый таск, заказчик - таймер
//Синхронизируется через QueueEvent (который autoreset), вызывается только после захвата евента
procedure TAService.AddTaskFromTimer(const nproc: string; tmidx: Integer);
var p: PTask;
begin
  New(p);
  InitTask(p);

  p.nproc := nproc;
  AddTimerToTask(p, tmidx);

  TaskQueueAdd(p);
end;

//таск уже есть, добавить потребителя в него (таймер)
//Синхронизируется через QueueEvent (который autoreset), вызывается только после захвата евента
procedure TAService.AddTimerToTask(p: PTask; tmidx: Integer);
var i: Integer;
begin
  //Если этот таймер уже (внезапно) в списке клиентов, то ничего не надо делать
  for i := 0 to p.tcount - 1 do
    if p.tindxs[i] = tmidx then Exit;

  //Размер списка, если что
  if p.tcount >= p.tcap then begin
    Inc(p.tcap, 8);
    SetLength(p.tindxs, p.tcap);
  end;

  //Добавим таймер в список
  p.tindxs[p.tcount] := tmidx;
  Inc(p.tcount);
end;

//Есть запрос от пользователя
//Если нет параметров, то можно попасть в таск, созданный таймером
//Если есть параметры, то для каждого разного набора параметров создается отдельный таск
//Одинаковые вызовы с одинаковыми параметрами слипаются в один таск
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
      then AddTaskFromUser(t) //Нет подходящих тасков, сделаем новый
      else AddClientToTask(p, t); //Такой таск уже есть, добавим клиента
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
      if Result.bsize = 0 then Exit; //Та же процедура без параметров
      if CompareMem(@(Result.buff[0]), @(request.buff[0]), Result.bsize) then Exit; //Одинаковые параметры
    end;

    Result := Result.next;
  end;
end;

//Добавить потребителя (пользователя) в существующий таск
//Синхронизируется через QueueEvent (который autoreset), вызывается только после захвата евента
procedure TAService.AddClientToTask(p: PTask; const e: TClientInfo);
var i: Integer;
begin
  for i := 0 to p.ecount - 1 do
    if p.clients[i] = e then Exit; //Очень удивлюсь если когда-то это сработает

  if p.ecount >= p.ecap then begin
    Inc(p.ecap, 8);
    SetLength(p.clients, p.ecap);
  end;

  p.clients[p.ecount] := e;
  Inc(p.ecount);
end;

//Синхронизируется через QueueEvent (который autoreset), вызывается только после захвата евента
procedure TAService.AddTaskFromUser(const e: TClientInfo);
var p: PTask;
begin
  New(p);
  InitTask(p);

  p.nproc := e.request.nproc;
  AddClientToTask(p, e);

  p.bsize := e.request.bsize;
  if p.bsize > 0 then begin
    SetLength(p.buff, p.bsize); //Данные из запроса копируются в таск. Everyone manages it's own shit
    Move(e.request.buff[0], p.buff[0], p.bsize);
  end;

  TaskQueueAdd(p);
end;

//Синхронизируется через QueueEvent (который autoreset), вызывается только после захвата евента
procedure TAService.TaskQueueAdd(p: PTask);
begin
  if FirstTask = nil then begin
    FirstTask := p;
    LastTask := p;
    //Нет задач, значит воркер спит
    SetTaskToWork(p);
  end else begin
    LastTask^.next := p;
    LastTask := p;
  end;
end;

//Выбрать следующий таск для работы
//Синхронизируется через QueueEvent (который autoreset), вызывается только после захвата евента
function  TAService.TaskQueueSelect: PTask;
begin
  Result := FirstTask;
  if Result = nil then Exit;

  repeat //Попробую поискать запросы от пользователей
    if Result.ecount > 0 then Exit
    else Result := Result.next;
  until Result = nil;

  //От пользователя ничего нет, возвращаемся к первому попавшемуся
  Result := FirstTask;
end;

//Убрать выполненный таск из очереди. Буду ругаться если не найду его
//Синхронизируется через QueueEvent (который autoreset), вызывается только после захвата евента
procedure TAService.TaskQueueRemove(p: PTask);
var a, b: PTask;
begin
  a := nil;       //Предыдущий таск
  b := FirstTask; //Текущий таск

  while b <> nil do begin
    if b = p then begin //Наш таск найден, будем вырезать
      if b.next = nil then LastTask := a; //p == b == LastTask
      if a = nil then FirstTask := b.next //p == b == FirstTask
      else a.next := b.next;
      Exit;
    end;

    a := b;
    b := b.next;
  end;

  raise Exception.Create('TaskQueueRemove таск не найден в очереди!');
end;

//В ожидании клиетна висит MySockCallback, после WakeUp он отвиснет и вернет пользователю ответ
//Каждый клиент зохвачен Таском и MySockCallback, как только оба его отпустят (а я хз кто раньше, у них потоки разные)
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
    p := WorkerThread.task; //Таск, который делал тред

    WaitForSingleObject(QueueEvent, INFINITE);
    try
      TaskQueueRemove(p); //изъять таск из очереди

      q := TaskQueueSelect; //выбрать следующий таск для работы
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

//Вызывается до старта таймеров или после стопа таймеров, поэтому уведомляет только клиентов
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
      if not ((sr.Name = '') or (sr.Name = '.') or (sr.Name = '..')) then try  //это не файло
        srcfile := src + sr.Name;
        dstfile := dst + sr.Name;

        if (AnsiCompareText(dstfile, local + exename) = 0)
        or (AnsiCompareText(dstfile, local + dllname) = 0)
        or (AnsiCompareText(sr.Name, UPDATE_EXE_NAME) = 0) then
          Continue; //эти обрабатываются персонально

        if (sr.Attr and faDirectory) > 0 then begin          //если оно папко, то впадаем в рекурсию
          if not DirectoryExists(dstfile) then begin
            if not CreateDir(dstfile)
            then saRaiseLastError('CreateDir('+dstfile+')');
          end;
          CopyFiles(srcfile + '\', dstfile + '\', ur + 1);
        end else begin                                      //оно не папко, значит оно - файло
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

//Вызывается onStart и onStop, пока все остановлено и отключено
//Хочу еще вызывать регулярно, при срабатывании любых таймеров или сообщений, но хз насчет "ресурсы используются в рабочем потоке". Подумаю
procedure TAService.CheckUpdates;
var
  newupdate: TDateTime;
  src, dst: string;
  reload: Boolean;
begin
  newupdate := Now; //Пытаемся обновляться не слишком часто
  if (forced = True) or ((newupdate - lastupdate) > UPDATES_COOLDOWN) then begin
    lastupdate := newupdate;

    //Апдейт самого сервиса, один для всех, сервис запущен, соответственно апдейт сработает только после перезапуска
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
      saWriteLog(errorlog, 'Ошибка автоматического обновления сервиса: ' + e.Message);
    end;

    //Апдейт пользовательской нагрузки. DLL надо отключить для обновления, остальные файлы просто пытаюсь скопировать
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
          saWriteLog(errorlog, 'Ошибка автоматического обновления DLL: ' + e.Message);
        end;

        if (forced = False) then begin
          LoadDll;
          FDllInit(WorkerThread.AbortCallback);
        end;
      end;

      CopyFiles(userupdate, local, 0);
    except on e: Exception do
      saWriteLog(errorlog, 'Ошибка автоматического обновления программы: ' + e.Message);
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
      //Ждём зеленого гудка
      case WaitForSingleObject(wakeEvent, INFINITE) of
        WAIT_OBJECT_0:;
        WAIT_FAILED: raise Exception.Create('WAIT_FAILED');
        WAIT_TIMEOUT: raise Exception.Create('WAIT_TIMEOUT');
        WAIT_ABANDONED: raise Exception.Create('WAIT_ABANDONED');
      end;
      //Нас разбудили

      //Закрываемся, если нас выключили
      if Self.Terminated then Break;

      try
        //Если не закрылось, тогда работаем, у нас есть задача. Должна быть назначена перед побудкой
        if task.bsize > 0 then begin
          @up := task.pproc;
          r := up(task.buff, task.bsize);
        end else begin
          @tp := task.pproc;
          r := tp();
        end;

        if not Self.Terminated
        then PostMessage(parentForm, WM_THREAD_READY, r, 0);
        //Рапортуем о результатах, если есть кому
        //Если тред убит, то клиенты уже все отключены
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

