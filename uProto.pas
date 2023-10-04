unit uProto;

//��� ������������ �������� ������� ����� ������� � ���� ��������
//� ������������� ������������� "��������� + ������ �������"
//� ��������� - ��� ���������� ����� � �������� ���

interface

uses saSock;

const
  PROTOCOL_VER: Word = 1; //������ ������� ��� ��������, ���� ������ ���� ������, ��� ������ �������� ������ � ������������ ���������
  PROTOCOL_RESTART_REQUEST = '!RESTART REQUEST!';
  SOCKET_TIMEOUT_SHORT = 10;
  SOCKET_TIMEOUT_LONG = 255;
  SOCKET_INTERVAL = 5; //��� ��� � ��������

type
  TClientResponse = (
    crWait, //Heartbeat, �������� ���������� �������, �� ��
    crSucc, //������ �������� �������, �� ��
    crFail, //������ ������ ��� ������
    crOff); //��������� ������ �� ������� ������� ��� ������ ��� ����������, � ��� ������ �� ����� ��������. ��� ������ ��������� ����� � ��� ������ (�����) ��������

  //������, ������� ����� ���������� �������
  PRequest = ^TRequest;
  TRequest = record
    bsize: Integer;      //����� ������� ������
    buff: array of Byte; //����������� ����� ������� ������
    nproc: string;       //��� ����������� ���������    
  end;

//��������� ���������. ��������� �����
procedure ServerReadRequest(const AThread: saTServerClientThread; var prq: TRequest);
procedure ServerSendResponse(const AThread: saTServerClientThread; resp: TClientResponse);

//��������� ���������. ���������� �����
function  ClientMakeRequest(const nproc: string): saTArrayOfByte;
function  ClientMakeRequestArg(const request: TRequest): saTArrayOfByte;
function  ClientReadResponse(const client: saTClient; const AThread: saTPublicTerminatedThread): TClientResponse;

//��� �������� ��������� ��������� ����� ��������
function StrToLparam(const str: string): Integer;
function LParamToStr(lparam: Integer): string;

implementation

uses SysUtils;

//������������ ������ � ����� ��� ��������. ����������� ����� ���� ������
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
    Move(ss,           Result[ps], 4);  //SS = ����� NProc
    Move(bs,           Result[ps+4], 4); //BS = ����� Args
    Move(nproc[1],     Result[ps+8], ss); //Nproc
  except on e: Exception do
    raise Exception.Create('MakeRequest: '+e.Message);
  end;
end;

//������������ ������ � ����� ��� ��������. ����������� ����� ���� ������
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
    Move(ss,               Result[ps], 4);   //SS = ����� NProc
    Move(bs,               Result[ps+4], 4);  //BS = ����� args
    Move(request.nproc[1], Result[ps+8], ss);  //Nproc
    Move(request.buff[0],  Result[ps+ss+8], bs);//Args
  except on e: Exception do
    raise Exception.Create('ClientMakeRequestArg: '+e.Message);
  end;
end;

//������ �������� ����������� ����� ������ �������
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
      AThread.RecvData(@buff[0], ps, SOCKET_TIMEOUT_LONG, SOCKET_INTERVAL); //���� ����� ������������ � ���������� ������, ������� long
      if not CompareMem(@PROTOCOL_VER, @buff[0], ps) then raise Exception.Create('wrong protocol version');

      //get nproc length and buffer size
      AThread.RecvData(@buff[0], 8, SOCKET_TIMEOUT_SHORT, SOCKET_INTERVAL);
      Move(buff[0], ss, 4);
      Move(buff[4], bs, 4);

      if (ss = 0) then raise Exception.Create('������ ������');
      if (ss < 0) or (ss > 255) then raise Exception.Create('���������������� ����� ������ = '+IntToStr(ss));
      if (bs < 0) or (bs > 255) then raise Exception.Create('�������� ����� ������ (args) = '+IntToStr(bs));

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

//�������� ������ �������. Heartbeat � ����� � ����������/������
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

//������ �������� ����� �� �������
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

      client.RecvData(AThread, @buff[0], ps, SOCKET_TIMEOUT_LONG, SOCKET_INTERVAL); //����� heartbeat ����������� ��������, ��� �������, SOCKET_INTERVAL, ������� long
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
