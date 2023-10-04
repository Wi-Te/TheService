unit uClient;

interface

uses
  uProto, saSock;

type
  //WParam ������ ���������
  TClientStatus = (
    csWaiting, //Heartbeat, �������� ���������� �������, �� ��
    csCompleted, //������ �������� �������, �� ��
    csRetFailed,  //������ ��������, �� ���������������� ������� ������� ��������� - "���������"
    csAbandoned,  //��������� ������ �� ������� ������� ��� ������ ��� ����������, � ��� ������ �� ����� ��������. ��� ������ ��������� ����� � ��� ������ (�����) ��������
    csException); //�� ������������ � �������. ������ �� ������� �������. ������������ � LParamToStr(LParam) ����� ������� ��������� � ���������� ������

  //�����, ������� �������� �� �������� ������� ������� � �������� ������
  //� ���� ���� ����������� ����� ��� ������ ��� �������� �� ������.
  //������������ �������� CallTimerProc ��� CallUserProc (��� ������ ������� ������ ���������� � ������� request)
  //� ����� ������ �� ������� (��. TClientStatus)
  //����� ���������� �������� ������� ����� ������ ���������.
  //��� ������ �������� ����� ������� AbortCall
  //������ ����� ����� ��� �������� ����� Available
  TClientThread = class(saTPublicTerminatedThread)
  protected
    e: THandle;          //�� ���� ������ ����� ����� ������, ���� �� �����������
    running: Boolean;    //������� ���������
    aborted: Boolean;    //�������� ������ �� ������� �������� �������������

    rcap: Integer;       //������� ������ ������� �������
    request: TRequest;   //������ ��� ��������

    address: string;     //���������� �������, ���� ����� �������
    theport: Cardinal;   //IP-����� � ����, �������� ����� '172.16.0.70'
    client: saTClient;   //��������-�����������-����������

    mhandler: THandle;   //������ ����� ���������� ������ �� ��������� ����� � ��������� ����������
    mvalue: Cardinal;    //WParam = TClientMessage

    procedure Execute; override;
    function GetAvailability: Boolean;
  public
    //��������� ������ ���������� �������, � �������� ������������ �������. '127.0.0.1', ��������
    //� ���� �� ������� ����� ��������� ��������� ��������� � ����������� � WParam, � ������ ���������� � LParam
    constructor Create(const ipaddr: string; port: Cardinal; MsgHandler: THandle; MsgID: Cardinal);
    destructor Destroy; override;

    //��������� ��� ��������� ������������
    procedure CallSvcRestart;
    procedure CallTimerProc(const nproc: string);
    procedure CallUserProc(const nproc: string; const buff: Pointer; bsize: Byte);
    procedure AbortCall; //�������� �������� ����������
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
    //��� ������, ������������ � ����
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
