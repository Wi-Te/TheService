unit uClient;

interface

uses
  uProto, saSock;

type
  //WParam вашего сообщения
  TClientStatus = (
    csWaiting, //Heartbeat, ожидание выполнения запроса, всё ок
    csCompleted, //Запрос выполнен успешно, всё ок
    csRetFailed,  //Запрос выполнен, но пользовательская функция вернула результат - "потрачено"
    csAbandoned,  //Произошла ошибка на стороне сервера или сервер был остановлен, и ваш запрос не будет выполнен. Или просто порвалась связь и ваш запрос (будет) выполнен
    csException); //Не используется в сервисе. Ошибка на стороне клиента. Использовать в LParamToStr(LParam) чтобы достать сообщение и освободить память

  //Поток, который отвечает за передачу запроса серверу и ожидание ответа
  //У него есть собственный буфер для данных для передачи на сервер.
  //Пользователь вызывает CallTimerProc или CallUserProc (все нужные массивы данных копируются в местный request)
  //И ловит ответы от сервера (см. TClientStatus)
  //После завершения текущего запроса можно дёргать следующий.
  //Для отмены ожидания можно вызвать AbortCall
  //Узнать занят поток или свободен через Available
  TClientThread = class(saTPublicTerminatedThread)
  protected
    e: THandle;          //На этом ивенте поток будет висеть, пока не понадобится
    running: Boolean;    //Текущее состояние
    aborted: Boolean;    //Ожидание ответа от сервера прервано пользователем

    rcap: Integer;       //Текущий размер буффера запросе
    request: TRequest;   //Данные для отправки

    address: string;     //Координаты сервера, куда слать запросы
    theport: Cardinal;   //IP-адрес и порт, например адрес '172.16.0.70'
    client: saTClient;   //Механизм-отправитель-получатель

    mhandler: THandle;   //Клиент будет отправлять отчеты на указанный хэндл с указанным сообщением
    mvalue: Cardinal;    //WParam = TClientMessage

    procedure Execute; override;
    function GetAvailability: Boolean;
  public
    //Требуется задать координаты сервера, к которому отправляются запросы. '127.0.0.1', например
    //И окно на которое будет прилетать указанное сообщение с результатом в WParam, и иногда сообщением в LParam
    constructor Create(const ipaddr: string; port: Cardinal; MsgHandler: THandle; MsgID: Cardinal);
    destructor Destroy; override;

    //Интерфейс для конечного пользователя
    procedure CallSvcRestart;
    procedure CallTimerProc(const nproc: string);
    procedure CallUserProc(const nproc: string; const buff: Pointer; bsize: Byte);
    procedure AbortCall; //прервать ожидение выполнения
    property Available: Boolean read GetAvailability;
  end;

  function LParamToStr(lparam: Integer): string;

implementation

uses
  Windows, SysUtils;

constructor TClientThread.Create(const ipaddr: string; port: Cardinal; MsgHandler: THandle; MsgID: Cardinal);
begin
  try
    inherited Create(True);
    Self.FreeOnTerminate := False;

    Self.rcap := 0;

    Self.address := ipaddr;
    Self.theport := port;

    Self.mhandler := MsgHandler;
    Self.mvalue := MsgID;

    Self.running := False;
    Self.aborted := False;

    Self.client := saTClient.Create;

    Self.e := CreateEvent(nil, False, False, nil);
    Resume;
  except on e: Exception do
    //вне потока, пользователю в харю
    raise Exception.Create('Exception in TClientThread.Create: '+e.Message);
  end;
end;

destructor TClientThread.Destroy;
begin
  try
    Terminate;
    AbortCall;
    SetEvent(Self.e);
    WaitFor;

    CloseHandle(Self.e);
    Self.client.Free;

    SetLength(request.buff, 0);
  finally
    inherited Destroy;
  end;
end;

function ResponceToWParam(cr: uProto.TClientResponse): Integer;
begin
  case cr of
    crWait: Result := Integer(csWaiting);
    crSucc: Result := Integer(csCompleted);
    crFail: Result := Integer(csRetFailed);
    crOff: Result := Integer(csAbandoned);
  end;
end;

procedure TClientThread.Execute;
var
  buff: saTArrayOfByte;
  cr: TClientResponse;
begin
  while not Terminated do try
    running := False;
    WaitForSingleObject(e, INFINITE);
    if Terminated then Exit;

    aborted := False;
    running := True;

    try
      if request.bsize > 0
      then buff := ClientMakeRequestArg(Self.request)
      else buff := ClientMakeRequest(Self.request.nproc);

      client.OpenMyClient(address, theport);
      client.SendData(Self, @buff[0], Length(buff), SOCKET_TIMEOUT_LONG, SOCKET_INTERVAL);

      while not (Terminated or aborted) do begin
        cr := ClientReadResponse(self.client, Self);
        if cr <> crWait then aborted := True;
        PostMessage(mhandler, mvalue, ResponceToWParam(cr), 0);
      end;
    finally
      client.CloseMyClient;
      SetLength(buff, 0);
    end;
  except on e: Exception do
    PostMessage(mhandler, mvalue, Integer(csException), StrToLparam('Exception in TClientThread.Execute: ' + e.Message));
  end;
end;     

function TClientThread.GetAvailability;
begin
  Result := not Self.running;
end;

procedure TClientThread.CallSvcRestart;
var buff: saTArrayOfByte;
begin                      
  if Terminated then raise Exception.Create('uProto.TClient.CallTimerProc: already terminated');
  if running then raise Exception.Create('uProto.TClient.CallTimerProc: already running');

  try
    buff := ClientMakeRequest(PROTOCOL_RESTART_REQUEST);

    client.OpenMyClient(address, theport);
    client.SendData(Self, @buff[0], Length(buff), SOCKET_TIMEOUT_LONG, SOCKET_INTERVAL);
  finally
    client.CloseMyClient;
    SetLength(buff, 0);
  end;
end;

procedure TClientThread.CallTimerProc(const nproc: string);
begin
  if Terminated then raise Exception.Create('uProto.TClient.CallTimerProc: already terminated');
  if running then raise Exception.Create('uProto.TClient.CallTimerProc: already running');

  request.bsize := 0;
  request.nproc := nproc;
  SetEvent(Self.e);
end;

procedure TClientThread.CallUserProc(const nproc: string; const buff: Pointer; bsize: Byte);
begin
  if Terminated then raise Exception.Create('uProto.TClient.CallUserProc: already terminated');
  if running then raise Exception.Create('uProto.TClient.CallUserProc: already running');

  request.nproc := nproc;
  request.bsize := bsize;
  if bsize > 0 then begin
    if bsize > rcap then begin
      SetLength(request.buff, bsize);
      rcap := bsize;
    end;
    Move(buff^, request.buff[0], bsize);
  end;
  SetEvent(Self.e);
end;

procedure TClientThread.AbortCall;
begin
  if running then
    aborted := True;
end;

function LParamToStr(lparam: Integer): string;
begin
  Result := uProto.LParamToStr(lparam);
end;

end.
