unit uProto;

//Мой персональный протокол общения моего сервера и моих клиентов
//У пользователей универсальный "указатель + размер буффера"
//А остальное - моя внутренняя кухня и крутится тут

interface

uses saSock;

const
  PROTOCOL_VER: Word = 1; //просто увеличь это значение, если хочешь быть уверен, что сервер работает только с обновленными клиентами
  PROTOCOL_RESTART_REQUEST = '!RESTART REQUEST!';
  SOCKET_TIMEOUT_SHORT = 10;
  SOCKET_TIMEOUT_LONG = 255;
  SOCKET_INTERVAL = 5; //это все в секундах

type
  TClientResponse = (
    crWait, //Heartbeat, ожидание выполнения запроса, всё ок
    crSucc, //Запрос выполнен успешно, всё ок
    crFail, //Запрос вернул код ошибки
    crOff); //Произошла ошибка на стороне сервера или сервер был остановлен, и ваш запрос не будет выполнен. Или просто порвалась связь и ваш запрос (будет) выполнен

  //Данные, которые будут отправлены серверу
  PRequest = ^TRequest;
  TRequest = record
    bsize: Integer;      //длина массива данных
    buff: array of Byte; //собственная копия массива данных
    nproc: string;       //имя запрошенной процедуры    
  end;

//Интерфейс протокола. Серверная часть
procedure ServerReadRequest(const AThread: saTServerClientThread; var prq: TRequest);
procedure ServerSendResponse(const AThread: saTServerClientThread; resp: TClientResponse);

//Интерфейс протокола. Клиентская часть
function  ClientMakeRequest(const nproc: string): saTArrayOfByte;
function  ClientMakeRequestArg(const request: TRequest): saTArrayOfByte;
function  ClientReadResponse(const client: saTClient; const AThread: saTPublicTerminatedThread): TClientResponse;

//Для передачи строковых сообщений между потоками
function StrToLparam(const str: string): Integer;
function LParamToStr(lparam: Integer): string;

implementation

uses SysUtils;

//Запаковывает запрос в пакет для отправки. Собственная копия всех данных
{PROT_VERS|  SS   | BS        | NPROC     }
{  0, ps  | ps, 4 | ps + 4, 4 | ps + 8, ss}
{  0..1   | 2..5  | 6..9      | 10..19    }
function ClientMakeRequest(const nproc: string): saTArrayOfByte;
var ss, bs, ps: Integer;
begin
  try
    bs := 0;
    ss := Length(nproc);
    ps := SizeOf(PROTOCOL_VER);

    SetLength(Result, ss + ps + 8);

    Move(PROTOCOL_VER, Result[0], ps); //PROTOCOL_VER
    Move(ss,           Result[ps], 4);  //SS = Длина NProc
    Move(bs,           Result[ps+4], 4); //BS = Длина Args
    Move(nproc[1],     Result[ps+8], ss); //Nproc
  except on e: Exception do
    raise Exception.Create('MakeRequest: '+e.Message);
  end;
end;

//Запаковывает запрос в пакет для отправки. Собственная копия всех данных
{PROT_VERS|  SS   |   BS      | NPROC      | BUFF            }
{  0, ps  | ps, 4 | ps + 4, 4 | ps + 8, ss | ps + ss + 8, bs }
{  0..1   | 2..5  |   6..9    | 10..19     |   20 ...        }
function ClientMakeRequestArg(const request: TRequest): saTArrayOfByte;
var ss, bs, ps: Integer;
begin
  try
    ps := SizeOf(PROTOCOL_VER);
    ss := Length(request.nproc);
    bs := request.bsize;

    SetLength(Result, ss + bs + ps + 8);
                                   
    Move(PROTOCOL_VER,     Result[0], ps);  //PROTOCOL_VER
    Move(ss,               Result[ps], 4);   //SS = Длина NProc
    Move(bs,               Result[ps+4], 4);  //BS = длина args
    Move(request.nproc[1], Result[ps+8], ss);  //Nproc
    Move(request.buff[0],  Result[ps+ss+8], bs);//Args
  except on e: Exception do
    raise Exception.Create('ClientMakeRequestArg: '+e.Message);
  end;
end;

//Сервер получает собственную копию данных запроса
{ prot | ss | bs | nproc | buff }
{  ps     4    4    ss     bs   }
procedure ServerReadRequest(const AThread: saTServerClientThread; var prq: TRequest);
var
  a: Byte;       
  ps: Cardinal;
  ss, bs: Integer;
  buff: array of Byte;
begin
  try
    try
      SetLength(buff, 255);

      ps := SizeOf(PROTOCOL_VER);
      AThread.RecvData(@buff[0], ps, SOCKET_TIMEOUT_LONG, SOCKET_INTERVAL); //ждем между подключением и пересылкой данных, поэтому long
      if not CompareMem(@PROTOCOL_VER, @buff[0], ps) then raise Exception.Create('wrong protocol version');

      //get nproc length and buffer size
      AThread.RecvData(@buff[0], 8, SOCKET_TIMEOUT_SHORT, SOCKET_INTERVAL);
      Move(buff[0], ss, 4);
      Move(buff[4], bs, 4);

      if (ss = 0) then raise Exception.Create('пустая строка');
      if (ss < 0) or (ss > 255) then raise Exception.Create('неправдоподобная длина строки = '+IntToStr(ss));
      if (bs < 0) or (bs > 255) then raise Exception.Create('упоротый объем данных (args) = '+IntToStr(bs));

      //get nproc
      AThread.RecvData(@buff[0], ss, SOCKET_TIMEOUT_LONG, SOCKET_INTERVAL);
      SetLength(prq.nproc, ss);
      Move(buff[0], prq.nproc[1], ss);

      //get args
      prq.bsize := bs;
      if bs > 0 then begin
        AThread.RecvData(@buff[0], bs, SOCKET_TIMEOUT_LONG, SOCKET_INTERVAL);
        SetLength(prq.buff, bs);
        Move(buff[0], prq.buff[0], bs);
      end;
    finally
      SetLength(buff, 0);
    end;
  except on e: Exception do
    raise Exception.Create('ServerReadRequest: '+e.Message);
  end;
end;

//Отправка ответа клиенту. Heartbeat и отчет о выполеннии/ошибке
procedure ServerSendResponse(const AThread: saTServerClientThread; resp: TClientResponse);
var
  buff: array of Byte;
  ps, rs: Integer;
  val: Cardinal;
begin
  try
    try
      ps := SizeOf(PROTOCOL_VER);
      rs := sizeOf(TClientResponse);
      val := Cardinal(resp);

      SetLength(buff, ps + rs);
      Move(PROTOCOL_VER, buff[0], ps);
      Move(val, buff[ps], rs);

      AThread.SendData(@buff[0], ps + rs, SOCKET_TIMEOUT_SHORT, SOCKET_INTERVAL);
    finally
      SetLength(buff, 0);
    end;    
  except on e: Exception do
    raise Exception.Create('ServerSendResponse: '+e.Message);
  end;
end;

//Клиент получает ответ от сервера
{ prot | resp }
{  ps  |  rs  }
function ClientReadResponse(const client: saTClient; const AThread: saTPublicTerminatedThread): TClientResponse;
var
  buff: array of Byte;
  ps, rs: Integer;
begin
  try
    try
      ps := SizeOf(PROTOCOL_VER);
      rs := SizeOf(TClientResponse);

      if ps > rs
      then SetLength(buff, ps)
      else SetLength(buff, rs);

      client.RecvData(AThread, @buff[0], ps, SOCKET_TIMEOUT_LONG, SOCKET_INTERVAL); //между heartbeat сообщениями проходит, как минимум, SOCKET_INTERVAL, поэтому long
      if not CompareMem(@PROTOCOL_VER, @buff[0], ps) then raise Exception.Create('wrong protocol version');

      client.RecvData(AThread, @buff[0], rs, SOCKET_TIMEOUT_SHORT, SOCKET_INTERVAL);
      Move(buff[0], Result, rs);
    finally
      SetLength(buff, 0);
    end;
  except on e: Exception do
    raise Exception.Create('ReadResponse: '+e.Message);
  end;
end;

function StrToLparam(const str: string): Integer;
var ptr: ^string;
begin
  New(ptr);
  ptr^ := str;
  Result := Integer(ptr);
end;

function LParamToStr(lparam: Integer): string;
var ptr: ^string;
begin
  ptr := Pointer(lparam);
  Result := ptr^;
  Dispose(ptr);
end;

end.
