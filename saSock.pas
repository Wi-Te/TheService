unit saSock;
{сверер шлёт логи, перехватывайте сообщения (строка 91..96, или поиск по saSM_First)
для получения логов на имя вашей формы, сделайте saSockMessageHandle := Form1.Handle
SASM_FIRSTMESS .. SASM_LASTMESS - логи сервера, call saMessToStr to get string message
SASM_ERROR - general error. Must call saLParamToStr to get message and release memory}
{ThreadCallback - для сервера надо обязательно указать процедуру (в конструкторе),
которая выполняется в теле каждого потока, общающегося на стороне сервера с клиентом}

interface

uses
  SysUtils, Classes, WinSock, SyncObjs;

type
  TSocket = WinSock.TSocket;

  saTArrayOfByte = array of Byte;
  saTPublicTerminatedThread = class;
  saTServerClientThread = class;
  saTServer = class;

  saTServerCallback = procedure (const AThread: saTServerClientThread);

  saTPublicTerminatedThread = class(TThread)
  protected 
    function getTerminated: Boolean;
  public
    property Terminated: Boolean read getTerminated;
  end;

  saTServerClientThread = class(saTPublicTerminatedThread)
  protected
    FSocket: TSocket;
    FEvent: TSimpleEvent;
    FServer: saTServer;
    
    procedure Execute; override;
    procedure Terminate;
    procedure ReActivate(ASocket: TSocket);
  public
    constructor Create(Server: saTServer);
    destructor Destroy; override;
                                                                                            
//    property Socket: TSocket read FSocket;
    procedure SendData(pData: Pointer; DataSize: Integer; ATimeout: Byte; AInterval: Byte);
    procedure RecvData(pData: Pointer; DataSize: Integer; ATimeout: Byte; AInterval: Byte);
    function RecvHasData: Boolean;
  end;

  saTListenThread = class(TThread)
  protected
    FServer: saTServer;
  public
    constructor Create(AServer: saTServer);
    procedure Execute; override;
  end;

  saTServer = class
    protected
      FListenSocket: TSocket;
      FListenThread: saTListenThread;
      FPort: Word;
      FThreadCache: Byte;
      FThreadList: TList;        //вызовы методов, связанных с этим списком должны быть сихнронизированы (FCloseEvent)
      FCloseEvent: THandle;       //всего таких вызовов - три. Создание нового TMyClientServerThread, смерть старого, и общее закрытие сервера.
      //Создание нового потока и закрытие сервера, по идее, никогда не будут пересекаться между собой
      //так как, к тому моменту, как закрытие сервера доберется до FCloseEvent'а, принимающий поток уже будет завершен.
      //Смерть старого потока, наоборот, может случиться как во время создания нового, так и во время закрытия сервера.
      //Первые два - действия обязательные. Поэтому, они, если что, ждут (FCloseEvent.WaitFor(INFINITE)), пока умирающий поток уберет себя из списка.
      //Третье действие - самоубийство потока - опционально, поэтому оно только проверяет состояние евента (FCloseEvent.WaitFor(0))
      //и, если евент занят, не выполняется
      FThreadCallback: saTServerCallback;

      function getActive: Boolean;
      function getFull: Boolean;
      procedure addThread(t: saTServerClientThread);
      procedure removeThread(t: saTServerClientThread);
    public
      constructor Create(port: word; callback: saTServerCallback; cache: Byte = 20);
      destructor Destroy; override;
      procedure OpenMyServer;
      procedure CloseMyServer;
      function GetThread: saTServerClientThread;

      property Active: Boolean read getActive;
      property Port: Word read FPort;
      property ListenSocket: TSocket read FListenSocket;
      property Full: Boolean read GetFull;
  end;

  saTClient = class
    protected
      FSocket: TSocket;
      FTimeout: Byte;
    public
      constructor Create(Timeout: Byte = 60);
      destructor Destroy; override;
      procedure OpenMyClient(ip: string; port: cardinal);
      procedure CloseMyClient;

//      property Socket: TSocket read FSocket;
      procedure SendData(const AThread: saTPublicTerminatedThread; pData: Pointer; DataSize: Integer; ATimeout: Byte; AInterval: Byte);
      procedure RecvData(const AThread: saTPublicTerminatedThread; pData: Pointer; DataSize: Integer; ATimeout: Byte; AInterval: Byte);
      function RecvHasData: Boolean;
  end;

  saESockException = class(Exception)
  private
    FSocket,
    FCode: Integer;
  public
    constructor Create(ASocket, ACode: Integer; const errmsg: string);
    property Socket: TSocket read FSocket;
    property Code: Integer read FCode;
  end;

  function saIpToStr(ip: integer): string;
  function saLParamToStr(lparam: Integer): string;
  function saStrToLparam(const str: string): Integer;
  function saMessToStr(Msg: Cardinal; wParam, lParam: Integer): string;

const
  SASM_FIRSTMESS = {WM_USER} $0400 + 5376;  //сообщения от сервера, задайте хэндл вашей формы как MySock.MySockLogHandle и перехватывайте
  SASM_STARTLISTEN = saSM_FirstMess + 0;    //ListenSocket  | PORT_Server
  SASM_STOPLISTEN  = saSM_FirstMess + 1;    //ListenSocket  | PORT_Server
  SASM_INCOMMING   = saSM_FirstMess + 2;    //ClientSocket  | IPADDR_Client
  SASM_SOCKCLOSED  = saSM_FirstMess + 3;    //Socket        | 0
  SASM_SOCKETERROR = saSM_FirstMess + 4;    //Socket        | ErrorCode
  SASM_THREADCOUNT = saSM_FirstMess + 5;    //thread count  | 0
  SASM_LASTMESS    = saSM_ThreadCount;      //wParam        | lParam
  SASM_ERROR       = SASM_LASTMESS + 1;     //Socket / 0    | message, use LParamToStr 

var saSockMessageHandle: LongInt;

implementation

uses
  Windows, Forms;

var
  WSAData: TWSAData;
  WSAInit: Boolean;

constructor saESockException.Create(ASocket, ACode: Integer; const errmsg: string);
begin
  inherited Create(errmsg);
  FSocket := ASocket;
  FCode := ACode;
end;

procedure ReportMess(Msg: Cardinal; wParam, lParam: Integer);
begin
  if saSockMessageHandle > 0 then PostMessage(saSockMessageHandle, Msg, wParam, lParam);
end;

procedure ReportError(wParam: Cardinal; const mess: string);
begin
  if saSockMessageHandle > 0 then PostMessage(saSockMessageHandle, SASM_ERROR, wParam, saStrToLparam(mess));
end;

procedure RaiseSockError(ASocket, Err: Integer; const Operation: string); overload;
var msg: string;
begin
  msg := Format(
    'WindSock error [%d] on [%s]: %s',
    [Err, Operation, SysErrorMessage(Err)]);
  
  if ASocket > 0 then raise saESockException.Create(ASocket, Err, msg)
  else raise Exception.Create(msg);
end;     

procedure RaiseSockError(Err: Integer; const Operation: string); overload;
begin
  RaiseSockError(0, Err, Operation);
end;

procedure Startup;
var err: Cardinal;
begin
  if WSAInit = False then begin
    err := WSAStartup($0202, WSAData);
    if (err <> 0) then RaiseSockError(err, 'WSAStartup');
    WSAInit := True;
  end;
end;

procedure Cleanup;
begin
  if WSAInit = True then begin
    if (WSACleanup <> 0) then RaiseSockError(WSAGetLastError, 'WSACleanup');
    WSAInit := False;
  end;
end;

procedure SocketClose(var ASocket: TSocket; Report: Boolean);
var success: Boolean;
begin
  if ASocket <> INVALID_SOCKET then try
    success := closesocket(ASocket) = 0;
    
    if Report then begin
      if success then ReportMess(saSM_SockClosed, ASocket, 0)
      else ReportMess(SASM_SOCKETERROR, ASocket, WSAGetLastError);
    end;
  except
  end;
  
  ASocket := INVALID_SOCKET;
end;

procedure SetFDSet(var AFdSet: TFDSet; var ATime: TTimeVal; ASocket: TSocket; ASeconds: Byte);
begin
  FD_ZERO(AFdSet);
  FD_SET(ASocket, AFdSet);
  ATime.tv_sec := ASeconds;
  ATime.tv_usec := 0;
end;

procedure SendAll(ASocket: TSocket; pData: Pointer; len: Integer; const AThread: saTPublicTerminatedThread; ATimeout: Byte; AInterval: Byte);
var
  fdset: TFDSet;
  time: TTimeVal;
  sent: integer;
begin
  try
    if (AThread = nil) or (AInterval = 0) then begin
      if ATimeout = 0 then begin                                                  //блокирующий вызов
        while (len > 0) do begin                                                  //just send! to victory or death! no timeout, no interval, no thread
          sent := send(ASocket, pData^, len, 0);
          if sent < 0 then
            RaiseSockError(ASocket, WSAGetLastError, 'send')
          else if sent < len then begin
            pData := Pointer(Integer(pData) + sent);
            Dec(len, sent);
          end else Break;
        end;

        Exit;
      end else begin
        AInterval := ATimeout;
      end;
    end;

    //к этому моменту, я уверен, что у меня или есть ( Таймаут = Интервал != 0 ), в этом случае у селекта будет ровно столько попыток, сколько заходов понадобится сенду
    //или есть Трэд и Интервал (а таймаута может и не быть). В этом случае мы крутимся, пока живет поток, или пока не истечет таймаут (которого может и не быть)
    while (len > 0) do begin
      if (AThread <> nil) then if AThread.Terminated then
        Exit;  {raise EMySocketError.Create('send', WSAEINTR);}

      SetFDSet(fdset, time, ASocket, AInterval);
      case select(0, nil, @fdset, nil, @time) of                                  //ожидание свободного системного буфера для отправки
      0:  begin
            if (ATimeout > 0) then begin                                          //if timeout was set
              if (ATimeout > AInterval)                                           //if timeout still > time spent
              then Dec(ATimeout, AInterval)                                       //then we decrease timeout (will stay > 0, but may become lower than the interval)
              else RaiseSockError(ASocket, ERROR_TIMEOUT, 'select timeout');      //in that case we just raise timeout error next time
            end;                                                                  //or in case, atimeout <= ainterval initially
          end;
      1:  begin
            sent := send(ASocket, pData^, len, 0);
            if sent < 0 then
              RaiseSockError(ASocket, WSAGetLastError, 'send')
            else if sent < len then begin
              pData := Pointer(Integer(pData) + sent);
              Dec(len, sent);
            end else Break;
          end;
      else
        RaiseSockError(ASocket, WSAGetLastError, 'select');
      end;
    end;
  except
    on es: saESockException do begin
      ReportMess(SASM_SOCKETERROR, es.Socket, es.Code);
      raise Exception.Create('SendAll: ' + es.Message);
    end;
    on ee: Exception do
      raise Exception.Create('Exception in SendAll: ' + ee.Message);
  end;
end;

procedure RecvAll(ASocket: TSocket; pData: Pointer; len: Integer; const AThread: saTPublicTerminatedThread; ATimeout: Byte; AInterval: Byte);
var
  fdset: TFDSet;
  time: TTimeVal;
  recd: Integer;
begin
  try
    if (AThread = nil) or (AInterval = 0) then begin
      if ATimeout = 0 then begin
        while (len > 0) do begin
          recd := recv(ASocket, pData^, len, 0);
          if recd < 0 then      
            RaiseSockError(ASocket,WSAGetLastError, 'recv')
          else if recd < len then begin
            pData := Pointer(Integer(pData) + recd);
            Dec(len, recd);
          end else Break;
        end;

        Exit;
      end else begin
        AInterval := ATimeout;
      end;
    end;

    while (len > 0) do begin
      if (AThread <> nil) then if AThread.Terminated then
        Exit;  {raise EMySocketError.Create('send', WSAEINTR);}

      SetFDSet(fdset, time, ASocket, AInterval);
      case select(0, @fdset, nil, nil, @time) of
      0:  begin
            if (ATimeout > 0) then begin
              if (ATimeout > AInterval)
              then Dec(ATimeout, AInterval)
              else RaiseSockError(ASocket, ERROR_TIMEOUT, 'select timeout');
            end;
          end;
      1:  begin
            if ioctlsocket(ASocket, FIONREAD, recd) <> 0 then RaiseSockError(ASocket, WSAGetLastError, 'ioctlsocket fionread');
            if recd <= 0 then RaiseSockError(ASocket, WSAEDISCON, 'zero bytes available');

            recd := recv(ASocket, pData^, len, 0);
            if recd < 0 then
              RaiseSockError(ASocket, WSAGetLastError, 'recv')
            else if recd < len then begin
              pData := Pointer(Integer(pData) + recd);
              Dec(len, recd);
            end else Break;
          end;
      else
        RaiseSockError(ASocket, WSAGetLastError, 'select');
      end;
    end; 
  except
    on es: saESockException do begin
      ReportMess(SASM_SOCKETERROR, es.Socket, es.Code);
      raise Exception.Create('RecvAll: ' + es.Message);
    end;
    on ee: Exception do
      raise Exception.Create('Exception in RecvAll: ' + ee.Message);
  end;
end;

function IOCtlFIOnRead(ASocket: TSocket): Integer;
begin
  if ioctlsocket(ASocket, FIONREAD, Result) <> 0 then RaiseSockError(ASocket, WSAGetLastError, 'ioctlsocket fionread');
end;

function saIpToStr(ip: Integer): string;
var
  a: in_addr;
begin
  a.S_addr := ip;
  result := inet_ntoa(a);
end;




{TMySrever}

constructor saTServer.Create(port: word; callback: saTServerCallback; cache: Byte = 20);
begin
  FThreadList := TList.Create;
  FCloseEvent := CreateMutex(nil, False, nil);
  FPort := port;
  FListenSocket := INVALID_SOCKET;
  FListenThread := nil;
  FThreadCache := cache;
  FThreadCallback := callback;
end;

destructor saTServer.Destroy;
begin
  CloseMyServer;
  FThreadList.Free;
  CloseHandle(FCloseEvent);
  inherited;
end;

procedure saTServer.OpenMyServer;
var
  Addr: TSockAddrIn;
begin
  if FListenSocket = INVALID_SOCKET then try
    Startup;                                                                    //инициализация WSA

    FListenSocket := WinSock.socket(PF_INET, SOCK_STREAM, IPPROTO_IP);          //получаем сокет
    if FListenSocket = INVALID_SOCKET
    then RaiseSockError(WSAGetLastError, 'make socket');                     //or [invalid handle + exception]

    try
      Addr.sin_family := PF_INET;
      Addr.sin_port   := htons(port);
      Addr.sin_addr.S_addr := INADDR_ANY;

      if bind(FListenSocket, Addr, SizeOf(Addr)) <> 0 then RaiseSockError(WSAGetLastError, 'bind');

      //CheckSocketResult(WSAAsyncSelect(FListenSocket, 0, 0, 0), 'WSAAsyncSelect');//deny socket from sending any async messages
      if listen(FListenSocket, SOMAXCONN) <> 0 then RaiseSockError(WSAGetLastError, 'listen'); //begin listen
      FListenThread := saTListenThread.Create(Self);
      ReportMess(saSM_StartListen, FListenSocket, port);
    except
      SocketClose(FListenSocket, True);
      raise;
    end;
  except on e: Exception do  //Юзеру в харю
    raise Exception.Create('Error in OpenMyServer: ' + e.Message);
  end;
end;

procedure saTServer.CloseMyServer;
var
  thread: saTServerClientThread;
  i: Integer;
begin
  try
    ReportMess(saSM_StopListen, FListenSocket, port);

    if Assigned(FListenThread) then
      FListenThread.Terminate;

    SocketClose(FListenSocket, True);               //закрыли принимающий сокет. В этот момент accept должен прерваться, и принимающий тред отлипнет
    if Assigned(FListenThread) then begin
      FListenThread.Terminate;
      FListenThread.WaitFor;
      FListenThread.Free;
      FListenThread := nil;
    end;

    try
      WaitForSingleObject(FCloseEvent, INFINITE);

      for i := 0 to  FThreadList.Count - 1 do     //уведомим все имеющиеся клиентские треды о завершении
        saTServerClientThread(FThreadList[i]).Terminate;
      while FThreadList.Count > 0 do begin      //освобождаем ресурсы
        thread := FThreadList.Last;             //Все треды уже уведомлены о завершении
        thread.WaitFor;                         //и, даже если самый первый тред будет закрываться дольше всех,
        thread.Free;                            //это только означает, что WaitFor для всех остальных будем мнгновенным
        FThreadList.Remove(thread);
      end;                                      //хотя, может и залипнуть, конечно =)
    finally
      ReleaseMutex(FCloseEvent);
    end;

    Cleanup;
  except
    on es: saESockException do begin
      ReportMess(SASM_SOCKETERROR, es.Socket, es.Code);
      ReportError(0, 'CloseMyServer: ' + es.Message); //Надеюсь, кто-то перехватит
    end;
    on ee: Exception do
      ReportError(1, 'Error in CloseMyServer: ' + ee.Message);
  end;
end;

function saTServer.getActive: Boolean;
begin
  Result := FListenSocket <> INVALID_SOCKET;
end;

function saTServer.getFull: Boolean;
begin
  Result := FThreadList.Count > FThreadCache;
end;

procedure saTServer.addThread(t: saTServerClientThread);
begin
  FThreadList.Add(t);
end;

procedure saTServer.removeThread(t: saTServerClientThread);
begin
  FThreadList.Remove(t);
end;                           

function saTServer.GetThread: saTServerClientThread;
var
  i: integer;
begin
  try
    for i:=0 to FThreadList.Count - 1 do begin                                  //Поиск отработавшего, но спящего потока
      Result := FThreadList[i];
      if Result.FSocket = INVALID_SOCKET then
        Exit;
    end;
    Result := nil;
  except
    Result := nil;
  end;
end;





{TMyListenThread}

constructor saTListenThread.Create(AServer: saTServer);
begin
  FServer := AServer;
  FreeOnTerminate := False;

  inherited Create(False);
end;

procedure saTListenThread.Execute;
var
//  r: integer;
//  Len: integer;
//  OldOpenType, NewOpenType: Integer;

  clientsocket: TSocket;
  Addr: TSockAddrIn;
  addrlen: integer;
  thread: saTServerClientThread;
begin
//  Len := SizeOf(OldOpenType);
//  NewOpenType := SO_SYNCHRONOUS_NONALERT;
  addrlen := SizeOf(Addr);
  while (not Self.Terminated) and FServer.Active do try
    //r := getsockopt(INVALID_SOCKET, SOL_SOCKET, SO_OPENTYPE, PChar(@OldOpenType), Len);
    //r := setsockopt(INVALID_SOCKET, SOL_SOCKET, SO_OPENTYPE, PChar(@NewOpenType), Len);

    clientsocket := accept(FServer.ListenSocket, @Addr, @addrlen);
    if (not Self.Terminated) then
    if (clientsocket <> INVALID_SOCKET) then begin
      ReportMess(saSM_Incomming, clientsocket, Addr.sin_addr.S_addr);
 //  'Incomming connection on '+inet_ntoa(Addr.sin_addr)+': '+IntToStr(ntohs(Addr.sin_port))+' = '+inttostr(clientsocket);
      try
        WaitForSingleObject(FServer.FCloseEvent, INFINITE);             //Synchronized access to TServer.ThreadList
        thread := FServer.GetThread;                       //Wait for TClientServerThread removes itself from the list
        if thread = nil then begin                         //no conflict with CloseMyServer, because this part is unreachable when listensocket is closed
          thread := saTServerClientThread.Create(FServer);
          FServer.addThread(thread);
        end;
        thread.ReActivate(clientsocket);
      finally
        ReleaseMutex(FServer.FCloseEvent);
      end;
      ReportMess(saSM_ThreadCount, FServer.FThreadList.Count, 0);
    end else
      RaiseSockError(FServer.ListenSocket, WSAGetLastError, 'accept');

   // r := setsockopt(INVALID_SOCKET, SOL_SOCKET, SO_OPENTYPE, PChar(@OldOpenType), Len);
  except 
    on es: saESockException do begin
      ReportMess(SASM_SOCKETERROR, es.Socket, es.Code);
      ReportError(2, 'saTListenThread.Execute: ' + es.Message);
    end;
    on ee: Exception do
      ReportError(3, 'saTListenThread.Execute: ' + ee.Message);
  end;
end;



{TMyPublicTerminatedThread}

function saTPublicTerminatedThread.getTerminated: Boolean;
begin
  Result := inherited Terminated;
end;


{TMyClientServerThread}

constructor saTServerClientThread.Create(Server: saTServer);
begin
  inherited Create(True);

  FSocket := INVALID_SOCKET;
  FreeOnTerminate := False;
  FEvent := TSimpleEvent.Create;
  FServer := Server;

  Resume;
end;

destructor saTServerClientThread.Destroy;
begin
  FEvent.Free;

  inherited Destroy;
end;

procedure saTServerClientThread.ReActivate(ASocket: TSocket);
begin
  SocketClose(FSocket, True);
  FSocket := ASocket;
  FEvent.SetEvent;
end;

procedure saTServerClientThread.Terminate;
begin
  inherited Terminate;
  FEvent.SetEvent;
end;

procedure saTServerClientThread.Execute;
begin
  while not Terminated do try
    FEvent.WaitFor(INFINITE);
    FEvent.ResetEvent;
    if Terminated then Break;

    try
      if Assigned(FServer.FThreadCallback) then try
        FServer.FThreadCallback(Self);
      finally
        SocketClose(FSocket, True);
      end;
    except on e: Exception do
      ReportError(4, 'Unhandled exception in FServer is user CallBack: ' + e.Message);
    end;

    if WaitForSingleObject(FServer.FCloseEvent, 0) <> WAIT_TIMEOUT then try
      if FServer.Full then begin
        FServer.removeThread(Self);
        FreeOnTerminate := True;
        Terminate;
        Break;
      end;
    finally
      ReleaseMutex(FServer.FCloseEvent);
    end;
  except on e: Exception do
    ReportError(5, 'Exception in saTServerClientThread.Execute: '+e.Message);
  end;
end;

procedure saTServerClientThread.SendData(pData: Pointer; DataSize: Integer; ATimeout: Byte; AInterval: Byte);
begin
  SendAll(FSocket, pData, DataSize, Self, atimeout, ainterval);
end;

procedure saTServerClientThread.RecvData(pData: Pointer; DataSize: Integer; ATimeout: Byte; AInterval: Byte);
begin
  RecvAll(FSocket, pData, DataSize, Self, atimeout, ainterval);
end;

function saTServerClientThread.RecvHasData: Boolean;
begin
  Result := IOCtlFIOnRead(FSocket) > 0;
end;





{TMyClient}

constructor saTClient.Create(Timeout: Byte = 60);
begin
  FSocket := INVALID_SOCKET;
  FTimeout := Timeout;
end;

destructor saTClient.Destroy;
begin
  CloseMyClient;
  inherited;
end;

procedure saTClient.OpenMyClient(ip: string; port: cardinal);
var
  Addr: TSockAddrIn;
begin
  if FSocket = INVALID_SOCKET then try
    Startup;                                                                    //Ensure WSAStartup was called

    FSocket := WinSock.socket(PF_INET, SOCK_STREAM, IPPROTO_IP);                //asquire socket handle
    if FSocket = INVALID_SOCKET then
      RaiseSockError(WSAGetLastError, 'socket');                                //or [invalid handle + exception]

    try
      Addr.sin_family := PF_INET;
      Addr.sin_port   := htons(port);
      Addr.sin_addr.S_addr := inet_addr(PChar(ip));

      if connect(FSocket, Addr, SizeOf(Addr)) <> 0
      then RaiseSockError(WSAGetLastError,  'connect');
    except
      SocketClose(FSocket, False);
      raise;
    end;
  except on e: Exception do //Юзеру в харю
    raise Exception.Create('Error in OpenMyClient: ' + e.Message);
  end;
end;

procedure saTClient.CloseMyClient;
begin
  SocketClose(FSocket, False);
  Cleanup;
end;

procedure saTClient.SendData(const AThread: saTPublicTerminatedThread; pData: Pointer; DataSize: Integer; ATimeout: Byte; AInterval: Byte);
begin
  SendAll(FSocket, pData, DataSize, AThread, ATimeout, AInterval);
end;

procedure saTClient.RecvData(const AThread: saTPublicTerminatedThread; pData: Pointer; DataSize: Integer; ATimeout: Byte; AInterval: Byte);
begin
  RecvAll(FSocket, pData, DataSize, AThread, ATimeout, AInterval);
end;      

function saTClient.RecvHasData: Boolean;
begin
  Result := IOCtlFIOnRead(FSocket) > 0;
end;





function saStrToLparam(const str: string): Integer;
var ptr: ^string;
begin
  New(ptr);
  ptr^ := str;
  Result := Integer(ptr);
end;

function saLParamToStr(lparam: Integer): string;
var ptr: ^string;
begin
  ptr := Pointer(lparam);
  Result := ptr^;
  Dispose(ptr);
end;

function saMessToStr(Msg: Cardinal; wParam, lParam: Integer): string;
begin
  case Msg of
    saSM_StartListen: Result := Format('Server started on %u (socket = %u)', [lParam, wParam]);
    saSM_StopListen:  Result := Format('Server stopped on %u (socket = %u)', [lParam, wParam]);
    saSM_SockClosed:  Result := Format('Socket closed: %u', [wParam]);
    saSM_SocketError: Result := Format('Socket error %u (socket = %u): %s', [lParam, wParam, SysErrorMessage(lParam)]);
    saSM_Incomming:   Result := Format('Incomming from %s (socket = %u)', [saSock.saIpToStr(lParam), wParam]);
    saSM_ThreadCount: Result := Format('Total thread count: %u', [wParam]);
  else Result := 'Unknown message: '+IntToStr(Msg);
  end;
end;

initialization
  WSAInit := False;
  saSockMessageHandle := 0;

finalization
  Cleanup;
  
end.
