unit saIniLoader;
{$WARN UNSAFE_CODE OFF}
{$WARN UNSAFE_TYPE OFF}
{$WARN UNSAFE_CAST OFF}

//sections and keys in ini file must be in ascii
//because i use LowerCase/UpperCase (too much overhead with ansi)

interface

type
  saTIniLoadMode = (saIlmLoad, saIlmAdd, saIlmOver);
  saTIniFile = class
  protected
    sects, keys, vals: array of string;
    sids: array of Integer;
    sct, sid, cap, cnt, ki: Integer;    
    mode: saTIniLoadMode;

    procedure CheckCapacity;
    procedure SelectSection(const sect: string);
    procedure AppendKey(const key, val: string);
    procedure SetKeyVal(const key, val: string);
    function  FindKey(const key: string; throw: Boolean): Boolean;

    function GetStr(endSlash: Boolean): string;
    function GetInt: Integer;
    function GetBool: Boolean;
    function GetFloat: Double;
  public
    constructor Create;
    destructor  Destroy; override;

    //If there is only one section it will be selected
    procedure LoadSections(const FileName: string; const SectionNames: array of string; LoadMode: saTIniLoadMode = saIlmLoad);

    procedure SetSection(const sect: string);

    function AsStr(const key: string;      endSlash: Boolean = False): string; overload;
    function AsStr(const key, def: string; endSlash: Boolean = False): string; overload;

    function AsInt(const key: string              ): Integer; overload;
    function AsInt(const key: string; def: Integer): Integer; overload;

    function AsBool(const key: string              ): Boolean; overload;
    function AsBool(const key: string; def: Boolean): Boolean; overload;

    function AsFloat(const key: string             ): Double; overload;
    function AsFloat(const key: string; def: Double): Double; overload;
                                                      
    procedure SetStr(const key, val: string);                                  
    procedure SetInt(const key: string; val: Integer);
    procedure SetFloat(const key: string; val: Double);
    procedure AddSection(const Name: string); //Adds section if not exist and selects it
    procedure SaveAsIniFile(const FileName: string); //Dont save to original file, it will destroy comments and unread sections
  end;
                               
  TCharSet = set of Char;
  TStringArray = array of string;
  function saStringToArray(const str: string; out arr: TStringArray; const delims: TCharSet): Integer; //returns array length
  //use this to parse delimeted string into "array of string" parameter for LoadSections

implementation

uses
  SysUtils, Windows;

const        
  FILE_SHARE_ALL = FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE;
  INVALID_SET_FILE_POINTER = DWORD(-1);
  BLOCK_SZ = 4096;

  CHAR_COMMENT = ['''', '#', '-', '/', '=', ';'];
  CHAR_SPACE = [#10, #13, #32, #9];
  CHAR_SECT_BEG = '[';
  CHAR_SECT_END = ']';

type
  TIniReader = class
  private
    hFile: Cardinal;
    block: string;
    res, idx: Cardinal;

    procedure ReadBlock;
  public
    constructor Create(const IniFileName: string);
    destructor Destroy; override;

    function EoF: Boolean;
    function HasData: Boolean;
    function Readln: string;
    procedure ProcessLine(const ini: saTIniFile; const line: string);
  end;       

procedure RaiseWinError(const msg: string);
var err: Cardinal;
begin
  err := GetLastError;
  raise Exception.Create(msg + #13#10 + 'code ['+IntToStr(err)+']: '+SysErrorMessage(err));
end;

//TIniReader

constructor TIniReader.Create(const IniFileName: string);
begin
  hFile := CreateFile(PChar(IniFileName), GENERIC_READ, FILE_SHARE_READ, nil, OPEN_EXISTING, 0, 0);
  if hFile = INVALID_HANDLE_VALUE then
    RaiseWinError('Не удалось открыть файл');
  if SetFilePointer(hFile, 0, nil, FILE_BEGIN) = INVALID_SET_FILE_POINTER then
    RaiseWinError('Ошибка при открытии файла (seek)');
  SetLength(block, BLOCK_SZ);
  res := 0; idx := 0;
end;

destructor TIniReader.Destroy;
begin
  SetLength(block, 0);
  if hFile <> INVALID_HANDLE_VALUE then
    CloseHandle(hFile);
end;

procedure TIniReader.ReadBlock;
begin
  if ReadFile(hFile, block[1], BLOCK_SZ, res, nil) = False then
    RaiseWinError('Ошибка при чтении файла (read)');
  idx := 1;
end;

function TIniReader.EoF;
begin
  Result := res = 0;
end;

function TIniReader.HasData;
begin
  if (idx = 0) or (idx > res)
  then ReadBlock;
  Result := res > 0;
end;

function TIniReader.Readln;
var
  i: Cardinal;
  a: Boolean;
begin          
  a := False;
  Result := '';
  while Self.HasData do begin
    if a then begin
      if block[idx] = #10 then Inc(idx);
      Exit;
    end else begin      
      i := idx;
      while (i <= res) and (block[i] <> #13) do Inc(i);
      if i > idx
      then Result := Result + Copy(block, idx, i - idx);
      a := i <= res;
      idx := i + 1;
    end;
  end;
end;

procedure TIniReader.ProcessLine(const ini: saTIniFile; const line: string);
var
  k, q, i, j: Integer;
  isSect: Boolean;
begin
  k := 1;
  q := Length(line);

  while (k <= q) and (line[k] in CHAR_SPACE) do Inc(k);                         //Trim left
  if k > q then Exit;
  if line[k] in CHAR_COMMENT then Exit;                                         //Detect and skip comment
  isSect := line[k] = CHAR_SECT_BEG;                                            //Detect opening SECTION identificator
  if (ini.sid < 0) and (not isSect) then Exit;                                  //Not a section, nor values needed (i count on this line)
  while (line[q] in CHAR_SPACE) do Dec(q);                                      //Trim right
  if isSect then isSect := (line[q] = CHAR_SECT_END) and (q - k > 1);           //Detect closing SECTION identificator

  if isSect then begin                                                          //Got a section string, need to find its index
    ini.SelectSection(copy(line, k+1, q-k-1));                                  //saTIniFile.sid - is index of section, is set there
  end else begin                                                                //Not a section, and we have sid > 0
    i := k;
    while (i <= q) and (line[i] <> '=') do Inc(i);                              //Not a KEY=VALUE pair
    if i > q then Exit;
    j := i+1;
    i := i-1;
    while line[i] in CHAR_SPACE do Dec(i);                                      //Trim key/value (i'm sure, k and q chars are not space)
    while line[j] in CHAR_SPACE do Inc(j);

    ini.SetKeyVal(Copy(line, k, i-k+1), Copy(line, j, q-j+1));                  //saTIniFile.sid is used here
  end;
end;

//saTIniFile

constructor saTIniFile.Create;
begin
  cnt := 0;
  cap := 4;
  SetLength(keys, cap);
  SetLength(vals, cap);
  SetLength(sids, cap);
  sct := 0;
  sid := -1;
end;

destructor saTIniFile.Destroy;
begin
  SetLength(keys, 0);
  SetLength(vals, 0);
  SetLength(sids, 0);
  SetLength(sects, 0);
end;

procedure saTIniFile.CheckCapacity;
begin
  if (cnt >= cap) then begin
    if cap > 16
    then cap := cap + 16
    else cap := cap * 2;

    SetLength(keys, cap);
    SetLength(vals, cap);
    SetLength(sids, cap);
  end;
end;

procedure saTIniFile.SelectSection(const sect: string);
var str: string;
begin
  str := UpperCase(sect);

  sid := sct-1;
  while sid >= 0 do begin
    if sects[sid] = str then Break;
    Dec(sid);
  end;
end;

procedure saTIniFile.AppendKey(const key, val: string);
begin             
  if sid < 0 then raise Exception.Create('Error in saTIniFile.Append - no section selected');
  
  CheckCapacity;

  keys[cnt] := LowerCase(key);
  vals[cnt] := val;
  sids[cnt] := sid;

  Inc(cnt);
end;


procedure saTIniFile.SetKeyVal(const key, val: string);
begin
  if sid < 0 then raise Exception.Create('Error in saTIniFile.Append - no section selected');

  if FindKey(key, False) then begin
    case mode of
      saIlmLoad: raise Exception.Create('Duplicate key ['+key+'] in section ['+sects[sid]+']');
      saIlmOver: vals[ki] := val;
    end;
  end else begin
    CheckCapacity;

    keys[cnt] := LowerCase(key);
    vals[cnt] := val;
    sids[cnt] := sid;

    Inc(cnt);
  end;
end;

procedure saTIniFile.LoadSections(const FileName: string; const SectionNames: array of string; LoadMode: saTIniLoadMode = saIlmLoad);
var
  i: Integer;
  ir: TIniReader;
begin
  try
    mode := LoadMode;
    if mode = saIlmLoad then begin
      sct := Length(SectionNames);
      if sct <= 0 then Exit;

      SetLength(sects, sct);
      for i := sct - 1 downto 0 do
        sects[i] := UpperCase(SectionNames[i]);

      cnt := 0;
    end else begin
      for i := Length(SectionNames) - 1 downto 0 do
        AddSection(SectionNames[i]);
    end;

    ir := nil;
    sid := -1;
    //it must be set to -1 here. It's set in TIniReader.ProcessLine
    //and it's used in saTIniFile.Append
    try     
      ir := nil;
      ir := TIniReader.Create(FileName);
      repeat ir.ProcessLine(Self, ir.Readln)
      until ir.EoF;
    finally
      ir.Free;
    end;

    if mode = saIlmLoad then begin
      if sct = 1
      then sid := 0;
    end;
  except on e: Exception do
    raise Exception.Create('saTIniFile.LoadSections ['+FileName+']: '+e.Message);
  end;
end;

procedure saTIniFile.SetSection(const sect: string);
begin
  SelectSection(sect);
  if sid < 0 then raise Exception.Create('Section not found ['+sect+']');
end;

function saTIniFile.FindKey(const key: string; throw: Boolean): Boolean;
var
  str: string;
begin
  if sid < 0 then raise Exception.Create('Error in saTIniFile.FindKey - no section selected');
  
  str := LowerCase(key);

  ki := cnt - 1;
  while ki >= 0 do begin
    if (sids[ki] = sid) and (keys[ki] = str)
    then Break
    else Dec(ki);
  end;
  Result := ki >= 0;

  if not Result and throw then raise Exception.Create('Key ['+key+'] not found in section ['+sects[sid]+']');
end;


function saTIniFile.GetStr;
var
  s: ^string;
begin
  s := @vals[ki];
 { if endSlash and (s^ = '')
  then raise Exception.Create('Key ['+keys[ki]+'] in section ['+sects[sid]+'] is empty string');  }

  if endSlash and (s^ <> '') and (s^[Length(s^)] <> '\')
  then Result := s^ + '\'
  else Result := s^;
end;

function saTIniFile.AsStr(const key: string; endslash: Boolean = False): string;
begin
  FindKey(key, True);
  Result := GetStr(endSlash);
end;

function saTIniFile.AsStr(const key, def: string; endslash: Boolean = False): string;
begin
  if FindKey(key, False)
  then Result := GetStr(endSlash)
  else Result := def;
end;   


function saTIniFile.GetInt;
begin
  if not TryStrToInt(vals[ki], Result)
  then raise Exception.Create('Key ['+keys[ki]+'] in section ['+sects[sid]+'] is not an integer');
end;

function saTIniFile.AsInt(const key: string): Integer;
begin
  FindKey(key, True);
  Result := GetInt;
end;

function saTIniFile.AsInt(const key: string; def: Integer): Integer;
begin
  if FindKey(key, False)
  then Result := GetInt
  else Result := def;
end;


function saTIniFile.GetBool;
var
  s: ^string;
begin
  s := @vals[ki];
  if s^ = '0'
  then Result := False
  else
  if s^ = '1'
  then Result := True
  else raise Exception.Create('Key ['+keys[ki]+'] in section ['+sects[sid]+'] is not a boolean');
end;

function saTIniFile.AsBool(const key: string): Boolean;
begin
  FindKey(key, True);
  Result := GetBool;
end;

function saTIniFile.AsBool(const key: string; def: Boolean): Boolean;
begin
  if FindKey(key, False)
  then Result := GetBool
  else Result := def;
end;


function saTIniFile.GetFloat;
begin
  if not TryStrToFloat(vals[ki], Result)
  then raise Exception.Create('Key ['+keys[ki]+'] in section ['+sects[sid]+'] is not a float');
end;

function saTIniFile.AsFloat(const key: string): Double;
begin
  FindKey(key, True);
  Result := GetFloat;
end;

function saTIniFile.AsFloat(const key: string; def: Double): Double;
begin
  if FindKey(key, False)
  then Result := GetFloat
  else Result := def;
end;

procedure saTIniFile.AddSection(const Name: string);
var n: Integer;
begin
  SelectSection(Name);
  if sid < 0 then begin
    Inc(sct);

    n := Length(sects);
    if sct > n then begin
      if n = 0 then n := 2
      else if n > 16 then n := n + 16
      else n := n * 2;
      SetLength(sects, n);
    end;
    
    sid := sct - 1;
    sects[sid] := UpperCase(Name);
  end;
end;

procedure saTIniFile.SetStr(const key, val: string);
begin
  if FindKey(key, False)
  then vals[ki] := val
  else AppendKey(key, val);
end;

procedure saTIniFile.SetInt(const key: string; val: Integer);
begin
  if FindKey(key, False)
  then vals[ki] := IntToStr(val)
  else AppendKey(key, IntToStr(val));
end;

procedure saTIniFile.SetFloat(const key: string; val: Double);
begin
  if FindKey(key, False)
  then vals[ki] := FloatToStr(val)
  else AppendKey(key, FloatToStr(val));
end;

procedure saTIniFile.SaveAsIniFile(const FileName: string);
var
  hFile: Cardinal;
  i, j: Integer;

procedure WriteLine(const buff: string);
var k, n: Cardinal;
begin
  n := Length(buff);
  if WriteFile(hFile, buff[1], n, k, nil) = False then
    RaiseWinError('Ошибка при записи в файл (write)');
  if k < n then
    RaiseWinError(Format('Ошибка при записи в файл (%d of %d written)', [k, n]));
end;

begin
  try
    hFile := CreateFile(PChar(FileName+'.t'), GENERIC_WRITE, FILE_SHARE_READ, nil, CREATE_ALWAYS, 0, 0);
    if hFile = INVALID_HANDLE_VALUE then
      RaiseWinError('Не удалось создать файл');
    try
      if SetFilePointer(hFile, 0, nil, FILE_BEGIN) = INVALID_SET_FILE_POINTER then
        RaiseWinError('Ошибка при создании файла (seek)');

      for i := 0 to sct - 1 do begin
        WriteLine('['+sects[i]+']'#13#10);

        for j := 0 to cnt - 1 do
          if sids[j] = i then
            WriteLine(keys[j]+'='+vals[j]+#13#10);
      end;
    finally
      CloseHandle(hFile);
    end;
    if CopyFile(PChar(FileName+'.t'), PChar(FileName), False) = False then
      RaiseWinError('Ошибка при создании файла (MoveFile)');
    DeleteFile(PChar(FileName+'.t'));
  except on e: Exception do
    raise Exception.Create('saTIniFile.SaveAsIniFile ['+FileName+']: '+e.Message);
  end;
end;

function saStringToArray(const str: string; out arr: TStringArray; const delims: TCharSet): Integer;
var
  i, j, n: Integer;
begin
  Result := 0;
  n := Length(str);
  try
    if n = 0 then Exit;

    SetLength(arr, (n div 2) + 1);

    i := 1;
    while True do begin
      while (i <= n) and (str[i] in delims) do Inc(i);
      if i > n then Break;
      j := i + 1;
      while (j <= n) and not (str[j] in delims) do Inc(j);
      arr[Result] := Copy(str, i, j - i);
      Inc(Result);
      i := j + 1;
    end;
  finally
    SetLength(arr, Result);
  end;
end;
{$WARNINGS ON}
end.
