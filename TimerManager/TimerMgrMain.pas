unit TimerMgrMain;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, DBGridEhGrouping, MemTableDataEh, Db, MemTableEh, GridsEh,
  DBGridEh, StdCtrls, ComCtrls, sCheckBox, Mask, sMaskEdit,
  sCustomComboEdit, sTooledit, sComboBox, sEdit, ExtCtrls, sMemo, Buttons,
  sBitBtn, sButton;

type
  TForm1 = class(TForm)
    DBGridEh1: TDBGridEh;
    DataSource1: TDataSource;
    MemTableEh1: TMemTableEh;
    PageControl1: TPageControl;
    TabSheet1: TTabSheet;
    TabSheet2: TTabSheet;
    edFrom: TsEdit;
    edUntil: TsEdit;
    edEvery: TsEdit;
    check: TsCheckBox;
    edSched: TsMemo;
    eddll: TsFilenameEdit;
    combo: TsComboBox;
    edTest: TsMemo;
    edini: TsFilenameEdit;
    Button1: TButton;
    Button2: TButton;
    Button3: TButton;
    sButton1: TsButton;
    sBitBtn1: TsBitBtn;
    procedure FormCreate(Sender: TObject);
    procedure EditChange(Sender: TObject);
    procedure MemTableEh1AfterScroll(DataSet: TDataSet);
    procedure EditKeyPress(Sender: TObject; var Key: Char);
    procedure edSchedChange(Sender: TObject);
    procedure Button2Click(Sender: TObject);
    procedure sButton1Click(Sender: TObject);
  private
    vsched: string;
    vexact: Boolean;
    vfrom, vuntil, vevery: Double;
    vals: array of double;

    function ValidateRepeat: Boolean;
    function ValidateSched: Boolean;
  public
    { Public declarations }
  end;
  RTimer = record
    nproc, sched: string;
    start, untyl, every: Double;
    exact: Boolean;
  end;         
  TTimers = array of RTimer;

var
  Form1: TForm1;
  ID: Integer;

function GetTimers(const ininame: string): TTimers;

implementation

uses Math, saRound, QuickSort, saUtils, saIniLoader, StrUtils;

{$R *.dfm}

procedure TForm1.FormCreate(Sender: TObject);
begin
  DecimalSeparator := '.';

  MemTableEh1.AfterScroll := nil;
  MemTableEh1.FieldDefs.Clear;
  MemTableEh1.FieldDefs.Add('id', ftInteger);
  MemTableEh1.FieldDefs.Add('foo', ftString, 100);
  MemTableEh1.FieldDefs.Add('bar', ftString, 255);
  MemTableEh1.FieldDefs.Add('sched', ftString, 255);
  MemTableEh1.FieldDefs.Add('from', ftFloat);
  MemTableEh1.FieldDefs.Add('until', ftFloat);
  MemTableEh1.FieldDefs.Add('every', ftFloat);
  MemTableEh1.FieldDefs.Add('wait', ftBoolean);
  MemTableEh1.CreateDataSet;
  MemTableEh1.Open;
  MemTableEh1.AfterScroll := MemTableEh1AfterScroll;
  MemTableEh1AfterScroll(MemTableEh1);

  combo.Clear;
  eddll.Clear;
  edini.Clear;
  edTest.Clear;

  edSched.Clear;
  edFrom.Clear;
  edUntil.Clear;
  edEvery.Clear;
  check.Checked := False;
  PageControl1.ActivePageIndex := 0;
end;

procedure Blink(const edit: TsEdit; count: Byte); overload;
begin
  if (count = 0) or (count > 5) then Exit;

  edit.SkinData.CustomColor := True;
  while count > 0 do begin
    Dec(count);

    edit.Color := $00AAAAFF;
    edit.Repaint;
    Sleep(70);

    edit.Color := clWhite;
    edit.Repaint;
    if count > 0 then Sleep(70);
  end;
  edit.SkinData.CustomColor := False;
end;

procedure Blink(const memo: TsMemo; count: Byte); overload;
begin
  if (count = 0) or (count > 5) then Exit;

  memo.SkinData.CustomColor := True;
  while count > 0 do begin
    Dec(count);

    memo.Color := $00AAAAFF;
    memo.Repaint;
    Sleep(70);

    memo.Color := clWhite;
    memo.Repaint;
    if count > 0 then Sleep(70);
  end;
  memo.SkinData.CustomColor := False;
end;

function DecToSex(v: Double):Double;
begin
  Result := saR2(Int(v) + Frac(v)*3/5);
end;

function SexToDec(v: Double):Double;
begin         
  Result := saR4(Int(v) + Frac(v)*5/3);
end;

function TimeAdd(v1, v2: Double): Double;
begin
  Result := DecToSex(SexToDec(v1) + SexToDec(v2));
end;

function TimeSub(v1, v2: Double): Double;
begin
  Result := DecToSex(SexToDec(v1) - SexToDec(v2));
end;    

function MyTryStrToTime(const edit: TsEdit; out val: Double; allowZero: Boolean = True): Boolean;
var str: string;
begin
  str := Trim(edit.Text);
  if str = '' then begin
    val := 0;
    Result := False;
  end else begin
    str := StringReplace(str, ':', '.', [rfReplaceAll]);
    str := StringReplace(str, ',', '.', [rfReplaceAll]);
    Result := TryStrToFloat(str, val);
    if Result then begin
      val := DecToSex(SexToDec(saR2(val)));
      Result := ((val > 0) or allowZero) and (val <= 24);
    end;
    if Result
    then edit.Text := FormatFloat('00.00', val)
    else Blink(edit, 3);
  end;
end;

function TForm1.ValidateRepeat: Boolean;
begin
  Result := True;
  Result := Result and MyTryStrToTime(edFrom, vfrom);
  Result := Result and MyTryStrToTime(edUntil, vuntil);
  Result := Result and MyTryStrToTime(edEvery, vevery, False);
end;

procedure TForm1.EditChange(Sender: TObject);
var
  vnow, vadd: Double;
  str: string;
begin
  if ValidateRepeat then begin
    str := '';
    vnow := vfrom;
    if check.Checked
    then vadd := TimeAdd(vevery, 0.05)
    else vadd := vevery;

    if (vfrom > vuntil) or (vuntil = 0) then begin
      repeat
        str := str + FormatFloat('00.00', vnow) + #13#10;
        vnow := TimeAdd(vnow, vevery);
      until vnow >= 24;
      vnow := vnow - 24;
    end;
    repeat
      str := str + FormatFloat('00.00', vnow) + #13#10;
      vnow := TimeAdd(vnow, vevery);
    until vnow > vuntil;

    edTest.Text := Copy(str, 1, Length(str)-2);
  end else begin
    edTest.Clear;
    Exit;
  end;
end;

procedure TForm1.MemTableEh1AfterScroll(DataSet: TDataSet);
begin
  if (MemTableEh1.Active) and (MemTableEh1.RecordCount > 0) then begin
    if MemTableEh1['sched'] = '' then begin
      PageControl1.ActivePageIndex := 0;
      edFrom.Text := MemTableEh1.FieldByName('from').AsString;
      edUntil.Text := MemTableEh1.FieldByName('until').AsString;
      edEvery.Text := MemTableEh1.FieldByName('every').AsString;
      check.Checked := MemTableEh1.FieldByName('wait').AsBoolean;
      EditChange(nil);
    end else begin
      PageControl1.ActivePageIndex := 1;
      edSched.Text := MemTableEh1.FieldByName('sched').AsString;
      edSchedChange(nil);
    end;
  end;
end;

procedure TForm1.EditKeyPress(Sender: TObject; var Key: Char);
begin
  if not (key in ['0'..'9', ',', '.', ':', #8, #3, #22, #24, #26]) then
    key := #0;
end;

function TForm1.ValidateSched: Boolean;
var
  s: tstringlist;
  str: string;
  val: Double;
  i, j, n, k: integer;
  vals: saTDoubleSorter;
begin
  Result := False;

  str := Trim(edSched.Text);
  str := StringReplace(str, ':', '.', [rfReplaceAll]);
  str := StringReplace(str, ',', '.', [rfReplaceAll]);

  str := StringReplace(str, ' ', ';', [rfReplaceAll]);
  str := StringReplace(str, #9,  ';', [rfReplaceAll]);
  str := StringReplace(str, #13, ';', [rfReplaceAll]);
  str := StringReplace(str, #10, ';', [rfReplaceAll]);

  str := StringReplace(str, ';;', ';', [rfReplaceAll]);
  str := StringReplace(str, ';;', ';', [rfReplaceAll]);

  i := 1;
  k := 0;
  n := Length(str);
  vals := saTDoubleSorter.Create;
  try
    vals.Count := (n div 2)+1;

    while i <= n do begin
      j := PosEx(';', str, i + 1);
      if j < 1 then j := n + 1;
      if j - i > 0 then
        if TryStrToFloat(Copy(str, i, j-i), val) then begin
          vals[k] := DecToSex(SexToDec(saR2(val)));
          inc(k);
        end else begin
          Blink(edSched, 3);
          Exit;
        end;
      i := j + 1;
    end;

    if k > 0 then begin
      vals.Count := k;
      vals.Sort;
      str := '';
      for i := 0 to k-1 do
        if (i < 1) or (vals[i] <> vals[i-1]) then
          str := str + FormatFloat('00.00', vals[i]) + '; ';
      vsched := Copy(str, 1, Length(str)-2);
      Result := True;
    end else
      vsched := '';
  finally
    vals.Free;
  end;
end;

procedure TForm1.edSchedChange(Sender: TObject);
begin
  if ValidateSched then
    edSched.Text := StringReplace(vsched, '; ', #13#10, [rfReplaceAll])
  else
    edSched.Clear;
end;

procedure TForm1.Button2Click(Sender: TObject);
begin
  if PageControl1.ActivePageIndex = 0 then begin
    if ValidateRepeat then begin
      Inc(ID);
      MemTableEh1.Append;
      MemTableEh1['ID'] := ID;
      MemTableEh1['foo'] := combo.Text;
      MemTableEh1['bar']  := edTest.Text;
      MemTableEh1['from']  := vfrom;
      MemTableEh1['until'] := vuntil;
      MemTableEh1['every'] := vevery;
      MemTableEh1['wait']  := check.Checked;
      MemTableEh1['sched'] := Null;
      MemTableEh1.Post;
    end;
  end else begin
    if ValidateSched then begin
      Inc(ID);
      MemTableEh1.Append;               
      MemTableEh1['foo'] := combo.Text;
      MemTableEh1['bar']  := vsched;
      MemTableEh1['sched'] := vsched;
      MemTableEh1.Post;
    end;
  end;
end;

function GetTimers(const ininame: string): TTimers;
var
  ss: TStringArray;
  ini: saTIniFile;
  i, k: Integer;
begin
  if Length(Trim(ininame)) > 0 then try
    if saFileExists(ininame) then try
      ini := nil;
      ini := saTIniFile.Create;

      ini.LoadSections(ininame, ['main']);
      ss := saStringToArray(
        ini.AsStr('timers', ''),
        [';', ',', ' ', #13, #10, #9, #0]);
      k := Length(ss);
      if k > 0 then begin             
        SetLength(Result, k);
        ini.LoadSections(ininame, ss);
        for i := Length(ss) - 1 downto 0 do begin
          ini.SetSection(ss[i]);

          Result[i].nproc := ini.AsStr('nproc', '');
          Result[i].sched := ini.AsStr('sched', '');
          Result[i].exact := ini.AsBool('exact', True);
          Result[i].start := ini.AsFloat('start', -1);
          Result[i].untyl := ini.AsFloat('until', -1);
          Result[i].every := ini.AsFloat('every', -1);
        end;
      end else
        Result := nil;
    finally
      ini.Free;
    end;
  except on e: Exception do begin
    Result := nil;
    raise Exception.Create('Error reading timers from ['+ininame+']: '+e.Message);
  end; end;
end;

procedure TForm1.sButton1Click(Sender: TObject);
begin
  if GetTimers(edini.FileName) = nil
  then ShowMessage('No timers specified');
end;

end.
