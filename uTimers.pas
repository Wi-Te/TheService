unit uTimers;

interface

//�� ��������� � �������

type
  TMinutes = Cardinal;
  TTimes = array of TMinutes;
  RTimer = record
    id: Cardinal;
    naim: string;
    nproc: string;
    sched: Integer;
    times: TTimes;
    start: TMinutes;
    untyl: TMinutes;
    every: TMinutes;
    exact: Boolean;
  end;
  TTimers = array of RTimer;

  function CalcInterval(Timer: RTimer): Integer;
  function FindTimer(const Timers: TTimers; ID: Cardinal): Integer;
  function GetTimers(const ininame, secnames: string): TTimers;
  procedure CheckTimers(const timers: TTimers);

implementation

uses saIniLoader, QuickSort, Math, SysUtils, Windows;

const
  TM_ID_OFFSET = 5376;

//converts timer value from floating point number to time in minutes. Like "15.40" -> "940"
function SexToMin(val: Double): TMinutes;
begin
  Result := Trunc(val + 0.0001) * 60 + Trunc(Frac(val)*100 + 0.0001); //dirty and dumb fix of floating point precision issue
end;

//converts a line from ini file to array of times
//input be like "7.30; 7.50; 8.10"
function StrToTimes(const inp: string; out times: TTimes): Integer;
var
  i: Integer;
  str: string;
  val: Double;
  vals: saTSorterCardinal;
  strings: TStringArray;
begin
  str := Trim(inp);   
  vals := nil;

  //replace time separators to floating point separator
  for i := 1 to Length(str) do
    if str[i] in [':', ','] then
      str[i] := '.';

  try
    //splits separated string into array of strings
    Result := saStringToArray(str, strings, [';', ' ', #9]);

    if Result > 0 then begin
      SetLength(times, Result);

      vals := saTSorterCardinal.Create(Result);

      //reads timers, converts to time in minutes and store in sorter
      for i := Result - 1 downto 0 do begin
        if TryStrToFloat(strings[i], val) then
          if (val >= 0) and (val < 23.60) then begin
            vals[i] := SexToMin(val);
            Continue;
          end;
        raise Exception.Create('�������� ������: '+inp);
      end;

      vals.Sort;

      //write sorted array to result
      for i := Result - 1 downto 0 do
        times[i] := vals[i];
    end;
  finally
    //clear temporaries
    SetLength(strings, 0);
    vals.Free;
  end;
end;

//Reads Timers from ini file. List of sections to read must be provided
function GetTimers(const ininame, secnames: string): TTimers;
var
  ss: TStringArray;
  ini: saTIniFile;
  i, k: Integer;
begin
  try
    try
      //section names to array
      k := saStringToArray(secnames, ss, [';', ',', ' ', #9]);
      for i := 1 to k - 1 do
        if ss[i] = ss[i-1] then
          raise Exception.Create('Duplicate timer entry ['+ss[i]+']');

      //Count of sections
      SetLength(Result, k);

      if k > 0 then try
        ini := nil;
        ini := saTIniFile.Create;
        ini.LoadSections(ininame, ss);

        for i := k - 1 downto 0 do begin
          ini.SetSection(ss[i]);

          Result[i].naim  := ss[i];
          Result[i].nproc := ini.AsStr('nproc');
          Result[i].exact := ini.AsBool('exact', False);
          Result[i].start := SexToMin(ini.AsFloat('start', 0));
          Result[i].untyl := SexToMin(ini.AsFloat('until', 0));
          Result[i].every := SexToMin(ini.AsFloat('every', 0));

          Result[i].id    := i + TM_ID_OFFSET;

          //���-�� �������� � ����������
          Result[i].sched := StrToTimes(
            ini.AsStr('sched', ''),
            Result[i].times);
        end;
      finally
        ini.Free;
      end;
    finally
      SetLength(ss, 0);
    end;
  except on e: Exception do begin
    raise Exception.Create('GetTimers: '+e.Message);
  end; end;
end;

procedure CheckTimers;
var
  i: Integer;
  s: string;
begin
  for i := Length(Timers) - 1 downto 0 do begin
    s := '';
    if timers[i].sched = 0 then begin
      if (timers[i].start <= 0) then s := s + #13#10 + '�� ������� ����� ������ [start]';
      if (timers[i].untyl <= 0) then s := s + #13#10 + '�� ������� ����� ��������� [until]';
      if (timers[i].every <= 0) then s := s + #13#10 + '�� ������ �������� [every]';
      if (timers[i].every > 12*60) then s := s + #13#10 + '�������� [every] ������ 12�';
    end else begin
      if (timers[i].start <> 0) or (timers[i].untyl <> 0) or (timers[i].every <> 0) then
        s := s + '������� ���������� [sched]. �������� � ����� ������/��������� ����� ������';
    end;
    if s <> '' then
      raise Exception.Create('����������� ������������� ������ ['+timers[i].naim+']:'+s);
  end;
end;

function RepeatedInterval(const t: RTimer; n: TMinutes; s: Word): Integer;
var ex: Boolean;
  tnext: TMinutes;
begin
  ex := True;
  if t.start > t.untyl then begin //16.10 - 7.00
    if n < t.untyl then begin //����� �� �������
      if t.exact //���� ��������� ������
      then tnext := ((24*60 + n - t.start) div t.every + 1) * t.every + t.start - 24*60
      else tnext := n + t.every;

      if tnext < t.untyl then ex := False //�������� � ������ �������
      else tnext := t.start; //����� �� ������, ������� �� �����
    end else if n < t.start then tnext := t.start //��� ������ � ��� ���� ������������. ������� �� �����
    else begin //������� ����� ������
      if t.exact //���� ��������� ������
      then tnext := ((n - t.start) div t.every + 1) * t.every + t.start
      else tnext := n + t.every;

      if tnext < t.untyl + 24*60 then ex := False //�������� � ������ �������
      else tnext := t.start + 24*60; //������� �� ����� ������
    end;
  end else begin //7.30 - 16.10
    if n < t.start then tnext := t.start //�� ����, ������� �� ������
    else if n >= t.untyl then tnext := t.start + 24*60 //�� ������, ������� �� ������
    else begin //�� � ������. �������
      if t.exact //���� ��������� ������
      then tnext := ((n - t.start) div t.every + 1) * t.every + t.start
      else tnext := n + t.every;

      if tnext < t.untyl then ex := False //�������� � ������ �������
      else tnext := t.start + 24*60; //������� �� ������
    end;
  end;

  Result := (tnext - n) * 60;
  if ex or t.exact then Result := Result - s;
  Result := Result * 1000;
end;

function CalcInterval(Timer: RTimer): Integer;
var
  i: Integer;
  n, tnext: TMinutes;
  rs, ru: TMinutes;
  st: TSystemTime;
begin
  GetLocalTime(st);
  n := st.wHour * 60 + st.wMinute;
  //n - � �������, ��� � times[], ��� � �� ���������

  {��� ����� ���������� ��������� ������������ ������� � ��������� �� ���������� � ���������� ��������
  ������ ��������� �� ������ ������ ������� ��� ������, ��� �� ������ ���������. ��� ������������, ������� ��� ������������
  ���� ����� �� ��������� ������� ������� � ������� �������. � ����� ������ ����, �� �������� �� ������. ��� � �� �� ������
  � ���� ������ ������� �� ������� �� ��� ����� ������. ������ �� ��������� � ������. ��� ��� ������� ������� � ������������� ����������}

  if Timer.sched > 0 then begin           //�� ����������
    if Timer.times[Timer.sched - 1] <= n then
      tnext := Timer.times[0] + 24*60     //����� ���������� - �� ��������� �����
    else for i := 0 to Timer.sched - 1 do
      if Timer.times[i] > n then begin    //�����, �� ���������� �������
        tnext := Timer.times[i];
        Break;
      end;
    Result := ((tnext - n)* 60 - st.wSecond) * 1000;
  end else //�� ���������
    Result := RepeatedInterval(Timer, n, st.wSecond);
end;

function FindTimer(const Timers: TTimers; ID: Cardinal): Integer;
var
  i, n: Integer;
begin
  n := Length(Timers);
  Result := ID - TM_ID_OFFSET;
  if not ((n > Result) and (Timers[Result].id = ID)) then begin
    Result := -1;
    for i := n - 1 downto 0 do
      if Timers[i].id = ID then begin
        Result := i;
        Break;
      end;
  end;
end;

end.
