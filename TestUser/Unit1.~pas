unit Unit1;

interface

uses
  Windows, Messages, Dialogs, Forms, uClient, StdCtrls, Classes, Controls, SysUtils;

const
  WM_CLIENT_THREAD = WM_USER + 1;

type
  TForm1 = class(TForm)
    Button1: TButton;
    bAbort: TButton;
    Button3: TButton;
    Edit1: TEdit;
    Button5: TButton;
    Button2: TButton;
    Button4: TButton;
    procedure FormCreate(Sender: TObject);
    procedure Button1Click(Sender: TObject);
    procedure Button3Click(Sender: TObject);
    procedure bAbortClick(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure Button5Click(Sender: TObject);
    procedure Button2Click(Sender: TObject);
    procedure Button4Click(Sender: TObject);
  private
    ClientThread: TClientThread;              
    procedure ClientThreadResponceHandler(var Msg: TMessage); message WM_CLIENT_THREAD;

    procedure RequestDone(const msg: string);
    function RequestInit(const capt: string): Boolean;
  end;

var
  Form1: TForm1;

implementation

{$R *.dfm}

procedure TForm1.FormCreate(Sender: TObject);
begin
  ClientThread := TClientThread.Create('127.0.0.1', 53760, Self.Handle, WM_CLIENT_THREAD);
end;

procedure TForm1.ClientThreadResponceHandler;
begin
  case TClientStatus(Msg.WParam) of
    csWaiting: Windows.Beep(50, 50);
    csCompleted: RequestDone('Выполнено');
    csRetFailed: RequestDone('Провалено');
    csAbandoned: RequestDone('Ошибка на стороне сервера');
    csException: RequestDone(LParamToStr(Msg.LParam));
  end;
end;

procedure TForm1.Button1Click(Sender: TObject);
begin
  if RequestInit('Running Request1')
  then ClientThread.CallTimerProc('TimerProc1')
  else ShowMessage('Занято');
end;  

procedure TForm1.Button5Click(Sender: TObject);
begin
  if RequestInit('Running Request2')
  then ClientThread.CallTimerProc('TimerProc2')
  else ShowMessage('Занято');
end;

procedure TForm1.Button3Click(Sender: TObject);
begin
  if RequestInit('Running Request2')
  then ClientThread.CallUserProc('UserProc', @Edit1.Text[1], Length(Edit1.Text))
  else ShowMessage('Занято');
end;    

procedure TForm1.bAbortClick(Sender: TObject);
begin
  ClientThread.AbortCall;
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
  ClientThread.Free;
end;

procedure TForm1.RequestDone;
begin
  ShowMessage(msg);
  bAbort.Enabled := False;
  Caption := 'Form1';
end;

function TForm1.RequestInit(const capt: string): Boolean;
begin
  Result := ClientThread.Available;
  if Result then begin
    Caption := capt;
    bAbort.Enabled := True;
  end;
end;

procedure TForm1.Button2Click(Sender: TObject);
begin
  if ClientThread.Available
  then ClientThread.CallSvcRestart;
end;

procedure TForm1.Button4Click(Sender: TObject);
begin
  if ClientThread.Available then
  ClientThread.CallTimerProc('fu bitch');
end;

end.
