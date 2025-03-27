unit saUtils;

interface

uses Windows;

const
  INVALID_SET_FILE_POINTER = DWORD(-1);

  FILE_READ_ATTRIBUTES = $0080;
  FILE_SHARE_READ_WRITE = FILE_SHARE_READ or FILE_SHARE_WRITE;
  FILE_SHARE_NONE = 0;

type
  saTLockFunction = function(const fullname: string): THandle;
  saTFileAttr = record
    cr, wr: TFileTime;
    hS, lS: Cardinal;
  end;
  saTKey = (sakkEnter, sakkEscape, sakkSelectall, sakkMinus, sakkDecsep, sakkDrop, sakkKeep);
  saTCharSet = set of Char;

function saFileSize(const fullname: string): Int64;
function saFileExists(const fullname: string): Boolean;
procedure saDirectoryMustExist(const path: string);
function saFilesBinaryEqual(const fn1, fn2: string): Boolean;   
function saSameFileDateSize(const fn1, fn2: string): Boolean;
function saTheSameFile(const fn1, fn2: string): Boolean;
procedure saCopyFileSure(const src, dst: string; FailIfExists: Boolean = False);
procedure saMoveFileSure(const src, dst: string; FailIfExists: Boolean = False);
procedure saCopyFileAny(const srcs: array of string; const dst: string; FailIfNoSources: Boolean = True; FailIfExistsDest: Boolean = False);
procedure saCopyFileSureAskRetry(const src, dst: string; FailIfExists: Boolean = False); //windows.messagebox


procedure saCopyFromMyFile(hsrc: THandle; const dst: string; FailIfExists: Boolean = False);
procedure saCopyIntoMyFile(const src: string; hdst: THandle; SetEoF: Boolean);

function saGetAvailableFileName(const fpath, fname: string; minwidth: Byte = 0; separator: Char = #0): string;
function saCopyFileSurePickName(const srcpath, srcnaim, dstpath, dstnaim: string; minwidth: Byte = 0; separator: Char = #0): string;

function saCheckResult(procResult: LongBool; const caption: string): LongBool; overload;
function saCheckResult(procResult, failValue: Cardinal; const caption: string): Cardinal; overload;

procedure saRaiseLastError(const msg: string);
procedure saRaiseError(err: Cardinal; const msg: string);

function saMsgError(err: Cardinal): string;
function saMsgLastError: string;

function saExtractFileName(const fnameext: string): string;
procedure saSplitFileNameExt(const fnameext: string; out fname, fext: string);
procedure saFixDBF(const fullname: string);
procedure saKillIdx(const fullname: string);
procedure saWriteLog(const fullname, msg: string);


function  saLockRead(const fullname: string): THandle;
function  saLockWrite(const fullname: string): THandle;
function  saLockExcl(const fullname: string): THandle;
procedure saLockInfo(const fullname, info: string);
function  saLockInfoPickName(const fpath, fname, info: string; width: Byte = 2): string;
function  saLockedInfo(const fullname: string): string;
procedure saUnlock(var lock: THandle);


function saSysTime(yy, mm: Word): TSystemTime;
function saIncMonth(const st: TSystemTime; cnt: Byte = 1): TSystemTime;
function saDecMonth(const st: TSystemTime; cnt: Byte = 1): TSystemTime;

function saKeyHeldDown(vkey: Integer): Boolean;
function saOpenFileExcl(const fullname: string): Cardinal;

function saEndSlash(const s: string): string;

function saFileAttrRead(const fullname: string): saTFileAttr;
procedure saFileAttrSetTime(const fullname: string; const attr: saTFileAttr);
procedure saFileSetDate(const fullname: string; writetime: TDateTime; failIfNotExists: Boolean);

function saFileAge(const FullName: string; var FileTime: TFileTime): Boolean; //Returns False if file not found
function saFileAgeDat(const fullname: string): TDateTime; //Returns -1 if file not found
function saFileAgeInt(const fullname: string): Integer; //Returns -1 if file not found

function saKeyPressNum(var Key: Char; Negative: Boolean = False; Decimals: Boolean = False): saTKey; //Allows only numeric keys; returns Action keys

//neg - allowed minus sign                                           
//dec - allowed decimal separator
//sep - spaces, tabs or other allowed spacers and thousand separators
function saIsNumeric(const str: string; sep: saTCharSet = []; dec: saTCharSet = []; neg: Boolean = False): Boolean;

var saLogErrorCallback: procedure(const msg: string);
//в случае фейла, saWriteLog покажет на экран стандартное сообщение, мол, алярм, все погибло
//если хотите, то присвойте этой переменной свою функцию, например, для сервисов, где диалогове окно не вариант

implementation

uses SysUtils, StrUtils, Controls, Classes;

const
  SA_BLOCKSIZE = 65536; //в байтах, размер буффера для операций чтения/заипси

{$WARNINGS OFF}

function saEndSlash(const s: string): string;
begin
  if s[Length(s)] = '\'
  then Result := s
  else Result := s + '\';
end;

function saMsgError(err: Cardinal): string;
begin
  Result := Format('code %d: %s', [err, SysErrorMessage(err)]);
end;

function saMsgLastError: string;
begin
  Result := saMsgError(GetLastError);
end;

procedure saRaiseError(err: Cardinal; const msg: string);
begin
  raise Exception.Create(msg + #13#10 + saMsgError(err));
end;

procedure saRaiseLastError(const msg: string);
begin
  raise Exception.Create(msg + #13#10 + saMsgLastError);
end;

//проверяет выхлоп всяких таких
//"BOOL WINAPI Blah-Blah(foo, bar); If the function fails, the return value is zero"
//функций, и чуть что, кидается исключениями, с красиво отформатированным текстом, с заданным заголовком
//возвращает результат проверяемой проедуры
function saCheckResult(procResult: LongBool; const caption: string): LongBool; overload;
begin
  Result := procResult;
  if not procResult then saRaiseLastError(caption);
end;

//проверяет выхлоп всяких таких
//"DWORD WINAPI Blah-Blah(foo, bar); If the function fails, the return value is INVALID_ANYTHING
//функций, и чуть что, кидается исключениями, с красиво отформатированным текстом, с заданным зголовком
//возвращает результат проверяемой проедуры
function saCheckResult(procResult, failValue: Cardinal; const caption: string): Cardinal; overload;
begin
  Result := procResult;
  if procResult = failValue then saRaiseLastError(caption);
end;

//проверяет наличие указанног офайла
//вобщем-то, та же фигня, что и "SysUtils.FileExists",
//но без обертки из FileFirst и тягомотины с таймштампами
function saFileExists(const fullname: string): Boolean;
var
  fh: Cardinal;
  err: Cardinal;
begin
  fh := Windows.CreateFile(PChar(fullname), 0, FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil, OPEN_EXISTING, 0, 0);
  Result := fh <> INVALID_HANDLE_VALUE;
  if Result then
    Windows.CloseHandle(fh)
  else begin
    err := Windows.GetLastError;
    if not (err in [ERROR_FILE_NOT_FOUND, ERROR_PATH_NOT_FOUND]) then
      saRaiseError(err, 'saFileExists failed on ['+fullname+']');
  end;
end;

//Выдаёт exception, если каталог не существует
procedure saDirectoryMustExist(const path: string);
begin
  if not SysUtils.DirectoryExists(path) then
    raise Exception.Create('Нет доступа к ['+path+']: '+saMsgLastError);
end;

//разбирает имя файла на имя и расширение
procedure saSplitFileNameExt(const fnameext: string; out fname, fext: string);
var
  k: integer;
begin
  for k := length(fnameext) downto 1 do
    if fnameext[k] = '.' then begin
      //расширение в наличии
      fname := PChar(Copy(fnameext, 1, k-1));
      fext  := PChar(Copy(fnameext, k, MaxInt));
      Exit;
    end;

  //расширения нема, только имя
  fname := PChar(fnameext);
  fext  := '';
end;

function saExtractFileName(const fnameext: string): string;
var ext: string;
begin
  saSplitFileNameExt(fnameext, Result, ext);
end;

type
  TsaInternalIFC = function(const fpath, fname: string; param: Pointer): Boolean;

function saInternalGetAvailableFilename(const fpath, fname: string; param: Pointer): Boolean;
begin
  Result := not saFileExists(fpath + fname);
end;

function saInternalCopyFileSurePickName(const fpath, fname: string; param: Pointer): Boolean;
var
  err: Cardinal;
begin
  Result := Windows.CopyFile(PChar(string(param^)), PChar(fpath + fname), True);
  if not Result then begin
    err := Windows.GetLastError;
    if err <> ERROR_FILE_EXISTS then
      saRaiseError(err, 'saInternalCopyFileSurePickName failed to copy ['+string(param^)+'] to ['+fpath + fname+']');
  end;
end;

function saInternalIterateFileName(const fpath, fname: string; width: Byte; separ: Char; MustUseSuff: Boolean;
  const callback: TsaInternalIFC; cbparam: Pointer): string;
var
  i, x: Integer;
  nam, ext, fmt: string;
begin
  //да, я ссусь отключенной оптимизации булевских условий
  if MustUseSuff = False then begin
    Result := fname;
    MustUseSuff := not callback(fpath, fname, cbparam);
  end;

  if MustUseSuff then begin
    saSplitFileNameExt(fname, nam, ext);

    //добавляем разделитель между именем и суффиксом
    if separ <> #0 then begin
      i := Length(nam);
      if (i > 0) and (nam[i] <> separ) then
        nam := nam + separ;
    end;


    if width > 6
    then width := 6;       //хватит тебе. потому что.

    if width = 0
    then fmt := '%s%d%s'
    else fmt := '%s%.'+Chr(width+48)+'d%s';  //а это - инттостр для бедных, то есть для цифры, одной

    if width = 0 then x := 999999
    else begin
      x := 1;
      for i := width downto 1 do x := x * 10;
      Dec(x);
    end;

    for i := 1 to x do begin
      Result := Format(fmt, [nam, i, ext]);
      if callback(fpath, Result, cbparam) then Exit;
    end;

    raise Exception.Create('saInternalIterateFileName failed: All names for ['+fname+'] in ['+fpath+'] are taken');
  end;
end;

//fpath ОБЯЗАТЕЛЬНО заканчивается на слеш
//добирает имя файла числовым нарастающим суффиксом, пока не найдется незанятое имя файла
//Не подходит для разных пользователей/потоков !!!!!!!!!!!!
function saGetAvailableFileName(const fpath, fname: string; minwidth: Byte = 0; separator: Char = #0): string;
begin
  Result := saInternalIterateFileName(fpath, fname, minwidth, separator, False, saInternalGetAvailableFilename, nil);
end;

function saCopyFileSurePickName(const srcpath, srcnaim, dstpath, dstnaim: string; minwidth: Byte = 0; separator: Char = #0): string;
var
  srcfile, dstfile: string;
begin
  srcfile := srcpath + srcnaim;
  Result := saInternalIterateFileName(dstpath, dstnaim, minwidth, separator, False, saInternalCopyFileSurePickName, @srcfile);
  dstfile := dstpath + Result;
  if not saFilesBinaryEqual(srcfile, dstfile) then raise Exception.Create('saCopyFileSurePickName failed: dest file ['+dstfile+'] seems to be corrupt');
end;

//Копирует файл. Бросается исключениями в случае неудачи
procedure saCopyFileSure(const src, dst: string; FailIfExists: Boolean = False);
begin
  saCheckResult(Windows.CopyFile(PChar(src), PChar(dst), FailIfExists), 'saCopyFileSure failed to copy [' + src + '] to [' + dst + ']');
end;

procedure saCopyFileSureAskRetry(const src, dst: string; FailIfExists: Boolean = False);
var lasterr: string;
begin
  while not Windows.CopyFile(PChar(src), PChar(dst), FailIfExists) do begin
    lasterr := 'error ' + saMsgLastError;
    if Windows.MessageBox(0, PChar('Не удалось копировать файл [' + src + '] to [' + dst + ']: ' + lasterr), 'Ошибка копирования', MB_ICONWARNING or MB_RETRYCANCEL) <> mrRetry
    then raise Exception.Create('Прервано пользователем: ' + lasterr);
  end;
end;

procedure saCopyFileAny(const srcs: array of string; const dst: string; FailIfNoSources: Boolean = True; FailIfExistsDest: Boolean = False);
var i: Integer;
begin
  for i := Low(srcs) to High(srcs) do
    if saFileExists(srcs[i]) then begin
      saCopyFileSure(srcs[i], dst, FailIfExistsDest);
      Exit;
    end;
  if FailIfNoSources then raise Exception.Create('saCopyFileAny failed to copy to [' + dst + ']: couldn''t find any single source file');
end;

procedure saMoveFileSure(const src, dst: string; FailIfExists: Boolean = False);
begin
  if (not FailIfExists) and saFileExists(dst)
  then saCheckResult(Windows.DeleteFile(PChar(dst)), 'saMoveFileSure failed to delete ['+dst+']');
  saCheckResult(Windows.MoveFile(PChar(src), PChar(dst)), 'saMoveFileSure failed to move ['+src+'] to ['+dst+']');
end;

function saOpenFileExcl(const fullname: string): Cardinal;
begin
  Result := saCheckResult(Windows.CreateFile(PChar(fullname), GENERIC_ALL, FILE_SHARE_NONE, nil, OPEN_EXISTING, 0, 0), INVALID_HANDLE_VALUE, 'saOpenFileExcl ['+fullname+']');
end;

//открываем файл для чтения, шарим только чтение (схерали, запись тоже шарим!), возвращаем чапельник
//если файла не существует, то тихо мирно возвращаем invalid handle
function saOpenFileReadIfExists(const fullname: string): Cardinal;
var
  err: Cardinal;
begin
  Result := Windows.CreateFile(PChar(fullname), GENERIC_READ, FILE_SHARE_READ_WRITE, nil, OPEN_EXISTING, 0, 0);
  if Result = INVALID_HANDLE_VALUE then begin
    err := Windows.GetLastError;
    if err <> ERROR_FILE_NOT_FOUND then
      saRaiseError(err, 'saOpenFile ['+fullname+']');
  end;
end;

//сравнивает побитово два файла
//если один или оба указаннх файла не существует - вернет FALSE
function saFilesBinaryEqual(const fn1, fn2: string): Boolean;
var
  fs1, fs2: Int64Rec;
  fh1, fh2, bs1, bs2: Cardinal;
  bf1, bf2: string;
begin
  fh1 := INVALID_HANDLE_VALUE; fh2 := INVALID_HANDLE_VALUE;
  try
    fh1 := saOpenFileReadIfExists(fn1);
    fh2 := saOpenFileReadIfExists(fn2);

    Result := not ((fh1 = INVALID_HANDLE_VALUE) or (fh2 = INVALID_HANDLE_VALUE));

    if Result then begin
      fs1.Hi := 0;
      fs2.Hi := 0;
      fs1.Lo := windows.SetFilePointer(fh1, 0, @fs1.Hi, FILE_END);
      fs2.Lo := windows.SetFilePointer(fh2, 0, @fs2.Hi, FILE_END);
      saCheckResult(fs1.Lo, INVALID_SET_FILE_POINTER, 'saBinaryEqual seek end f1');
      saCheckResult(fs2.Lo, INVALID_SET_FILE_POINTER, 'saBinaryEqual seek end f2');

      Result := (fs1.Lo = fs2.Lo) and (fs1.Hi = fs2.Hi);
    end;

    if Result then begin
      SetLength(bf1, SA_BLOCKSIZE);
      SetLength(bf2, SA_BLOCKSIZE);

      saCheckResult(windows.SetFilePointer(fh1, 0, nil, FILE_BEGIN), INVALID_SET_FILE_POINTER, 'saBinaryEqual seek begin f1');
      saCheckResult(windows.SetFilePointer(fh2, 0, nil, FILE_BEGIN), INVALID_SET_FILE_POINTER, 'saBinaryEqual seek begin f2');

      while True do begin
        saCheckResult(Windows.ReadFile(fh1, bf1[1], SA_BLOCKSIZE, bs1, nil), 'saBinaryEqual read "'+fn1+'"');
        saCheckResult(Windows.ReadFile(fh2, bf2[1], SA_BLOCKSIZE, bs2, nil), 'saBinaryEqual read "'+fn2+'"');
        if (bs1 <> bs2) then begin
          Result := False; Break;        //разная длина файлов. Сразу нет
        end else if (bs1 = 0) then begin
          Result := True;  Break;        //длина одинаковая, нулевая. Мы уже были в конце файла, и до сих пор не нашли отличий?
        end else if not CompareMem(@bf1[1], @bf2[1], bs1) then begin
          Result := False; Break;        //чота из файлов прочиталось, но не совпадает по содержимому
        end else if (bs1 < SA_BLOCKSIZE) then begin
          Result := True;  Break;        //содержимое совпадает, в файлах больше ничего не осталось
        end;
      end;
    end;
  finally
    if fh1 <> INVALID_HANDLE_VALUE then Windows.CloseHandle(fh1);
    if fh2 <> INVALID_HANDLE_VALUE then Windows.CloseHandle(fh2);
  end;
end;

//заменяет нули на пробелы в ДБФке, кроме шапки
//и да, я свято верю, что ДБФ больше 4гб весом не должны существовать
procedure saFixDBF(const fullname: string);
var
  fh, cursor, blocksz, res, filesize, i: Cardinal;
  block: string;
  changed: Boolean;
begin
  //открыть файло
  fh := saCheckResult(
    Windows.CreateFile(PChar(fullname), GENERIC_READ or GENERIC_WRITE, FILE_SHARE_READ, nil, OPEN_EXISTING, 0, 0),
    INVALID_HANDLE_VALUE, 'saFixDBF Open file "'+fullname+'"');
  try
    //читаем длину заголовка
    filesize := saCheckResult(
                  Windows.SetFilePointer(fh, 0, nil, FILE_END), INVALID_SET_FILE_POINTER, 'saFixDBF Seek FSz');
    saCheckResult(Windows.SetFilePointer(fh, 8, nil, FILE_BEGIN), INVALID_SET_FILE_POINTER, 'saFixDBF Seek HSz');
    cursor := 0; //во избежание конфуза, ибо в нем 4 байта, а читаем только младшие 2
    saCheckResult(Windows.ReadFile(fh, cursor, 2, res, nil), 'saFixDBF Read HSz');
    if res <> 2 then raise Exception.Create('saFixDBF Got '+inttostr(res)+' bytes reading HSz');

    //погнали по блокам
    SetLength(block, SA_BLOCKSIZE);

    while cursor < filesize do begin
      //читаем блок
      saCheckResult(Windows.SetFilePointer(fh, cursor, nil, FILE_BEGIN), INVALID_SET_FILE_POINTER, 'saFixDBF Seek block read');
      saCheckResult(Windows.ReadFile(fh, block[1], SA_BLOCKSIZE, blocksz, nil), 'saFixDBF Read block');

      //обрабатываем блок
      changed := False;
      for i := 1 to blocksz do begin
        if block[i] = #0 then begin
          block[i] := #$20;
          changed := True;
        end else if (block[i] = #$1A) and (cursor + i < filesize) then begin
          block[i] := #$2A;
          changed := true;
        end;
      end;

      //пишем взад
      if changed then begin
        saCheckResult(Windows.SetFilePointer(fh, cursor, nil, FILE_BEGIN), INVALID_SET_FILE_POINTER, 'saFixDBF Seek block read');
        saCheckResult(Windows.WriteFile(fh, block[1], blocksz, res, nil), 'saFixDBF Write block');
        if blocksz <> res then raise Exception.Create(Format('saFixDBF written [%d] bytes, expected [%d]', [res, blocksz]));
      end;

      //двигаем курсор
      cursor := cursor + blocksz;
    end;
  finally
    Windows.CloseHandle(fh);
  end;
end;

//рубит признак индекса в ДБФке
procedure saKillIdx(const fullname: string);
var
  fh, res: Cardinal;
  b: Byte;
begin
  fh := saCheckResult(
    Windows.CreateFile(PChar(fullname), GENERIC_READ or GENERIC_WRITE, FILE_SHARE_READ, nil, OPEN_EXISTING, 0, 0),
    INVALID_HANDLE_VALUE, 'saKillIdx Open file "'+fullname+'"');

  try
    saCheckResult(Windows.SetFilePointer(fh, $1C, nil, FILE_BEGIN), INVALID_SET_FILE_POINTER, 'saKillIdx seek to read');
    saCheckResult(Windows.ReadFile(fh, b, 1, res, nil), 'saKillIdx read');
    if res <> 1 then raise Exception.Create('saKillIdx read result = '+IntToStr(res));
    if b = 0 then Exit;
    b := 0;
    saCheckResult(Windows.SetFilePointer(fh, $1C, nil, FILE_BEGIN), INVALID_SET_FILE_POINTER, 'saKillIdx seek to write');
    saCheckResult(Windows.WriteFile(fh, b, 1, res, nil), 'saKillIdx write');
    if res <> 1 then raise Exception.Create('saKillIdx write result = '+IntToStr(res));
  finally
    Windows.CloseHandle(fh);
  end;
end;

function saTimeStampNow: string;
var st: TSystemTime;
begin
  GetLocalTime(st);
  with st do Result := Format(
    '%.2d.%.2d.%.4d %.2d:%.2d:%.2d',
    [wDay, wMonth, wYear, wHour, wMinute, wSecond]);
end;

//записывает сообщение (разбирает его на строки) в текстовый файл, с меткой времени
procedure saWriteLog(const fullname, msg: string);
const
  linechr = [#10, #13];
  skipchr = [#10, #13, ' ', #9];
var
  fh: THandle;
  res, len, n, k, q: Cardinal;
  datestamp, buff: string;
  errmsg: string;
begin
  try
    fh := saCheckResult(
      Windows.CreateFile(PChar(fullname), GENERIC_READ or GENERIC_WRITE, FILE_SHARE_READ, nil, OPEN_ALWAYS, 0, 0),
      INVALID_HANDLE_VALUE, 'saWriteLog Open file "'+fullname+'"');
    saCheckResult(Windows.SetFilePointer(fh, 0, nil, FILE_END), INVALID_SET_FILE_POINTER, 'saWriteLog seek');

    try
      datestamp := saTimeStampNow + #9;
      n := Length(msg);
      k := 1;

      while k <= n do begin
        //тримаем начало строки
        while (k <= n) and (msg[k] in skipchr) do Inc(k);

        //ищем конец строки
        q := k + 1;
        while (q <= n) and not (msg[q] in linechr) do Inc(q);
        len := q - k;

        //тримаем конец строки
        while msg[k + len - 1] in skipchr do Dec(len);

        //пишем строку
        if k <= n then begin
          buff := datestamp + Copy(msg, k, len) + #13#10;
          len := Length(buff);
          saCheckResult(Windows.WriteFile(fh, buff[1], len, res, nil), 'saWriteLog write');
          if len <> res then raise Exception.Create(Format('saWriteLog written %d bytes, expected %d bytes', [res, len]));
          datestamp := #9#9#9;
          k := q + 1;
        end;
      end;
    finally
      Windows.CloseHandle(fh);
    end;
  except on e: Exception do begin
    errmsg := 'Ошибка при записи в журнал событий!'#13#10 + e.Message + #13#10#13#10'Исходное сообщение:'#13#10 + msg;
    if @saLogErrorCallback = nil then begin
      if Windows.MessageBox(0,
        PChar('ВНИМАНИЕ! Сохраните текст этого сообщения!'#13#10+errmsg),
        PChar('Внимание! Важная информация'),
        MB_ICONSTOP or MB_ABORTRETRYIGNORE) = mrAbort
      then raise exception.Create('Abort');
    end else
      saLogErrorCallback(errmsg);
  end; end;
end;

//Создает лок-файл при надобности, возвращает нормальный или инвалидный хендл
function saLock(const fullname: string; access, share: Cardinal): THandle;
var
  err: Cardinal;
begin
  Result := Windows.CreateFile(PChar(fullname), access, share, nil, OPEN_ALWAYS, 0, 0);
  if Result = INVALID_HANDLE_VALUE then begin
    err := Windows.GetlastError;
    if err <> ERROR_SHARING_VIOLATION
    then saRaiseError(err, 'saLock ['+fullname+']')
    else Exit;
  end;
end;

function saLockRead(const fullname: string): THandle;
begin
  Result := saLock(fullname, GENERIC_READ, FILE_SHARE_READ_WRITE);
end;

function saLockWrite(const fullname: string): THandle;
begin
  Result := saLock(fullname, GENERIC_READ or GENERIC_WRITE, FILE_SHARE_READ);
end;

function saLockExcl(const fullname: string): THandle;
begin
  Result := saLock(fullname, GENERIC_READ or GENERIC_WRITE, FILE_SHARE_NONE);
end;

procedure saInternalLockInfo(handle: THandle; const info: string);
var len, res: Cardinal;
begin
  len := Length(info);
  if len > 0 then begin
    saCheckResult(WriteFile(handle, info[1], len, res, nil), 'WriteFile');
    if res <> len then raise Exception.Create(Format('Written [%d] bytes, expected [%d]', [res, len]));
  end;
end;

procedure saLockInfo(const fullname, info: string);
var hndl: THandle;
begin
  try
    hndl := Windows.CreateFile(PChar(fullname), GENERIC_WRITE, FILE_SHARE_READ, nil, CREATE_ALWAYS, 0, 0);
    if hndl = INVALID_HANDLE_VALUE then
      saRaiseLastError('CreateFile')
    else try
      saInternalLockInfo(hndl, info);
    finally
      CloseHandle(hndl);
    end;
  except on e: Exception do
    raise Exception.Create('saLockInfo ['+fullname+']: '+e.Message);
  end;
end;

function saInternalLockInfoPickName(const fpath, fname: string; param: Pointer): Boolean;
var err: Cardinal;
begin
  err := Windows.CreateFile(PChar(fpath + fname), GENERIC_WRITE, FILE_SHARE_READ, nil, CREATE_NEW, 0, 0);
  Result := err <> INVALID_HANDLE_VALUE;

  if Result then THandle(param^) := err
  else begin
    err := Windows.GetLastError;
    if err <> ERROR_FILE_EXISTS then
      saRaiseError(err, 'CreateFile');
  end;
end;

function  saLockInfoPickName(const fpath, fname, info: string; width: Byte = 2): string;
var hndl: THandle;
begin
  try
    Result := saInternalIterateFileName(saEndSlash(fpath), fname, width, '.', True, saInternalLockInfoPickName, @hndl);
    try
      saInternalLockInfo(hndl, info);
    finally
      CloseHandle(hndl);
    end;
  except on e: Exception do
    raise Exception.Create('saLockInfoPickName ['+fpath+']['+fname+']: '+e.Message);
  end;
end;

function  saLockedInfo(const fullname: string): string;
var
  hndl: THandle;
  res: Cardinal;
  buf: string;
begin
  try
    Result := '';
    hndl := saOpenFileReadIfExists(fullname);
    if hndl <> INVALID_HANDLE_VALUE then try
      SetLength(buf, SA_BLOCKSIZE);
      while True do begin
        saCheckResult(ReadFile(hndl, buf[1], SA_BLOCKSIZE, res, nil), 'ReadFile');
        if res < SA_BLOCKSIZE then begin
          Result := Result + Copy(buf, 1, res);
          Break;
        end else
          Result := Result + buf;
      end;
    finally
      CloseHandle(hndl);
    end;
  except on e: Exception do
    raise Exception.Create('saLockedInfo ['+fullname+']: '+e.Message);
  end;
end;

procedure saUnlock(var lock: THandle);
begin
  if lock <> INVALID_HANDLE_VALUE then begin
    Windows.CloseHandle(lock);
    lock := INVALID_HANDLE_VALUE;
  end;
end;

//проверяет размер и дату файлов на одинаковость. Содержимое НЕ проверяет
//если кто-то из файлов не существует, вернет false
function saSameFileDateSize(const fn1, fn2: string): Boolean;
var
  fa1, fa2: WIN32_FILE_ATTRIBUTE_DATA;
begin
  Result := saFileExists(fn1) and saFileExists(fn2);
  if not Result then Exit;

  saCheckResult(GetFileAttributesEx(PChar(fn1), GetFileExInfoStandard, @fa1), 'GetFileAttributesEx fn1');
  saCheckResult(GetFileAttributesEx(PChar(fn2), GetFileExInfoStandard, @fa2), 'GetFileAttributesEx fn2');

  Result := (fa1.ftLastWriteTime.dwLowDateTime  = fa2.ftLastWriteTime.dwLowDateTime)
    and (fa1.ftLastWriteTime.dwHighDateTime = fa2.ftLastWriteTime.dwHighDateTime)
    and (fa1.nFileSizeLow  = fa2.nFileSizeLow)
    and (fa1.nFileSizeHigh = fa2.nFileSizeHigh);
end;

//Проверяет, ссылаются ли два пути на один и тот же файл
function saTheSameFile(const fn1, fn2: string): Boolean;
var
  s1, s2: string;
  h1, h2: THandle;
  i1, i2: BY_HANDLE_FILE_INFORMATION;
begin
  s1 := LowerCase(fn1);
  s2 := LowerCase(fn2);
  //Очевидно одинаковые пути
  if s1 = s2 then begin
    Result := True;
    Exit;
  end;

  s1 := ExtractFileName(s1);
  s2 := ExtractFileName(s2);
  //Очевидно разные файлы
  if s1 <> s2 then begin
    Result := False;
    Exit;
  end;

  s1 := ExtractFilePath(fn1);
  s2 := ExtractFilePath(fn2);

  if not (DirectoryExists(s1) and DirectoryExists(s2)) then begin
    Result := False;
    Exit;
  end;

  h1 := INVALID_HANDLE_VALUE;
  h2 := INVALID_HANDLE_VALUE;

  try
    try
      h1 := saOpenFileReadIfExists(fn1);
      h2 := saOpenFileReadIfExists(fn2);

      //Кто-то из них недоступен, значит считаем что они разные
      if (h1 = INVALID_HANDLE_VALUE) or (h2 = INVALID_HANDLE_VALUE) then begin
        Result := False;
        Exit;
      end;

      saCheckResult(GetFileInformationByHandle(h1, i1), 'GetFileInformation ['+fn1+']');
      saCheckResult(GetFileInformationByHandle(h2, i2), 'GetFileInformation ['+fn2+']');
    finally
      if h1 <> INVALID_HANDLE_VALUE then CloseHandle(h1);
      if h2 <> INVALID_HANDLE_VALUE then CloseHandle(h2);
    end;
  except on e: Exception do
    raise Exception.Create('Error in saSameTheFile: ' + e.Message);
  end;

  Result := (i1.dwVolumeSerialNumber = i2.dwVolumeSerialNumber)
        and (i1.nFileIndexHigh = i2.nFileIndexHigh)
        and (i1.nFileIndexLow = i2.nFileIndexLow);
end;

function saSysTime(yy, mm: Word): TSystemTime;
begin
  FillMemory(@Result, SizeOf(Result), 0);
  Result.wMonth := mm;
  Result.wYear := yy;
end;

function saIncMonth(const st: TSystemTime; cnt: Byte = 1): TSystemTime;
var i: Integer;
begin
  i := st.wMonth + cnt - 1;
  Result.wYear := st.wYear + i div 12;
  Result.wMonth := i mod 12 + 1;
end;

function saDecMonth(const st: TSystemTime; cnt: Byte = 1): TSystemTime;
begin
  Result.wMonth := (st.wMonth + 11 - cnt mod 12) mod 12 + 1;
  Result.wYear := st.wYear - (cnt + 12 - st.wMonth) div 12;
end;

function saKeyHeldDown(vkey: Integer): Boolean;
begin
  Result := (GetAsyncKeyState(vkey) and $8000) > 0;
end;

type PInt64rec = ^Int64rec;
function GetFileSizeEx(hFile: THandle; lpSize: PInt64rec): LongBool; stdcall; external kernel32;

function saFileSize(const fullname: string): Int64;
var fh: Cardinal;
begin
  try
    fh := saCheckResult(Windows.CreateFile(PChar(fullname), FILE_READ_ATTRIBUTES, FILE_SHARE_READ_WRITE, nil, OPEN_EXISTING, 0, 0), INVALID_HANDLE_VALUE, 'CreateFile');
    try
      saCheckResult(GetFileSizeEx(fh, @Result), 'GetFileSize');
    finally
      CloseHandle(fh);
    end;
  except on e: Exception do
    raise Exception.Create('Error in saFileSize: '+e.Message);
  end;
end;

procedure saInnerCopyFile(hsrc, hdst: THandle);
var
  block: string;
  filesize, cursor: Int64;
  rbytes, wbytes: Cardinal;
begin
  try
    saCheckResult(GetFileSizeEx(hsrc, @filesize), 'GetFileSize');
    cursor := 0;

    saCheckResult(Windows.SetFilePointer(hdst, 0, nil, FILE_BEGIN), INVALID_SET_FILE_POINTER, 'seek hdst start');
    saCheckResult(Windows.SetFilePointer(hsrc, 0, nil, FILE_BEGIN), INVALID_SET_FILE_POINTER, 'seek hsrc start');

    SetLength(block, SA_BLOCKSIZE);
    while cursor < filesize do begin
      saCheckResult(Windows.ReadFile(hsrc, block[1], SA_BLOCKSIZE, rbytes, nil), 'saCopyFromMyFile Read block');
      if rbytes = 0 then raise Exception.Create('saCopyFromMyFile unexpected EoF at ' + IntToStr(cursor));
      saCheckResult(Windows.WriteFile(hdst, block[1], rbytes, wbytes, nil), 'saCopyFromMyFile Write block');
      if rbytes <> wbytes then raise Exception.Create(Format('saCopyFromMyFile written [%d] bytes, expected [%d]', [wbytes, rbytes]));
      cursor := cursor + rbytes;
    end;
  except on e: Exception do
    raise Exception.Create('saInnerCopyFile: '+e.Message);
  end;
end;

procedure saCopyFromMyFile(hsrc: THandle; const dst: string; FailIfExists: Boolean = False);
var hdst: THandle;
  DISP: Cardinal;
begin
  if FailIfExists then DISP := CREATE_NEW
  else DISP := CREATE_ALWAYS;

  try
    hdst := saCheckResult(Windows.CreateFile(PChar(dst), GENERIC_READ or GENERIC_WRITE, FILE_SHARE_READ, nil, DISP, 0, 0),
      INVALID_HANDLE_VALUE, 'create destination file ['+dst+']');

    try
      saInnerCopyFile(hsrc, hdst);
    finally
      Windows.CloseHandle(hdst);
    end;
  except on e: Exception do
    raise Exception.Create('saCopyFromMyFile: ' + e.Message);
  end;
end;

procedure saCopyIntoMyFile(const src: string; hdst: THandle; SetEoF: Boolean);
var hsrc: THandle;
begin
  try
    hsrc := saCheckResult(Windows.CreateFile(PChar(src), GENERIC_READ, FILE_SHARE_READ_WRITE, nil, OPEN_EXISTING, 0, 0),
      INVALID_HANDLE_VALUE, 'open source file ['+src+']');

    try
      saInnerCopyFile(hsrc, hdst);   
      if SetEoF then
      saCheckResult(Windows.SetEndOfFile(hdst), 'set eof');
    finally
      Windows.CloseHandle(hsrc);
    end;
  except on e: Exception do
    raise Exception.Create('saCopyFromMyFile: ' + e.Message);
  end;
end;

function saFileAttrRead(const fullname: string): saTFileAttr;
var fa: WIN32_FILE_ATTRIBUTE_DATA;
begin
  saCheckResult(GetFileAttributesEx(PChar(fullname), GetFileExInfoStandard, @fa), 'GetFileAttributesEx');

  Result.cr := fa.ftCreationTime;
  Result.wr := fa.ftLastWriteTime;
  Result.hS := fa.nFileSizeHigh;
  Result.lS := fa.nFileSizeLow;
end;

procedure saFileAttrSetTime(const fullname: string; const attr: saTFileAttr);
var handle: THandle;
begin
  try
    handle := saCheckResult(
      CreateFile(PChar(fullname), GENERIC_WRITE, FILE_SHARE_READ_WRITE, nil, OPEN_EXISTING, 0, 0),
      INVALID_HANDLE_VALUE, 'CreateFile');
      
    try
      saCheckResult(SetFileTime(handle, nil, nil, @attr.wr), 'SetFileTime');
    finally
      CloseHandle(handle);
    end;
  except on e: Exception do
    raise Exception.Create('saFileAttrSetTime ['+fullname+'] failed: ' + e.Message);
  end;
end;

procedure saFileSetDate(const fullname: string; writetime: TDateTime; failIfNotExists: Boolean);
var handle, mode: Cardinal;     
  locftime, utcftime: TFileTime;
  systime: TSystemTime;
begin
  try
    DateTimeToSystemTime(writetime, sysTime);
    saCheckResult(SystemTimeToFileTime(sysTime, locftime), 'SystemTimeToFileTime');
    saCheckResult(LocalFileTimeToFileTime(locftime, utcftime), 'LocalFileTimeToFileTime');

    if failIfNotExists then mode := OPEN_EXISTING
    else mode := OPEN_ALWAYS;

    handle := saCheckResult(
      CreateFile(PChar(fullname), GENERIC_WRITE, FILE_SHARE_READ_WRITE, nil, mode, 0, 0),
      INVALID_HANDLE_VALUE, 'CreateFile');

    try
      saCheckResult(SetFileTime(handle, nil, nil, @utcftime), 'SetFileTime');
    finally
      CloseHandle(handle);
    end;
  except on e: Exception do
    raise Exception.Create('saFileSetDate ['+fullname+'] failed: ' + e.Message);
  end;
end;


function saFileAge(const FullName: string; var FileTime: TFileTime): Boolean; //Returns False if file not found
var fh: THandle;
  res: LongBool;
begin
  try
    fh := Windows.CreateFile(PChar(FullName), FILE_READ_ATTRIBUTES, FILE_SHARE_READ_WRITE, nil, OPEN_EXISTING, 0, 0);
    if fh = INVALID_HANDLE_VALUE then begin
      fh := Windows.GetLastError;
      if fh in [ERROR_FILE_NOT_FOUND, ERROR_PATH_NOT_FOUND] then Result := False
      else saRaiseError(fh, 'CreateFile');
    end else begin
      res := Windows.GetFileTime(fh, nil, nil, @FileTime);
      Windows.CloseHandle(fh);

      saCheckResult(res, 'GetFileTime');
      saCheckResult(FileTimeToLocalFileTime(FileTime, FileTime), 'FileTimeToLocalFileTime');   
      Result := True;
    end;
  except on e: Exception do
    raise Exception.Create('saFileAgeInternal failed at ['+fullname+']: ' + e.Message);
  end;
end;

function saFileAgeInt(const fullname: string): Integer; //Returns -1 if file not found
var ft: TFileTime;
begin
  if saFileAge(fullname, ft) then saCheckResult(FileTimeToDosDateTime(ft, LongRec(Result).Hi, LongRec(Result).Lo), 'FileTimeToDosDateTime')
  else Result := -1;
end;

function saFileAgeDat(const fullname: string): TDateTime; //Returns -1 if file not found
var ft: Integer;
begin
  ft := saFileAgeInt(fullname);
  if ft < 0 then Result := -1
  else Result := FileDateToDateTime(ft);
end;

function saKeyPressNum(var Key: Char; Negative: Boolean = False; Decimals: Boolean = False): saTKey;
begin
  Result := sakkDrop;
  
  case Key of
   {Bck ^C  ^V   ^X   ^Z}
    #8, #3, #22, #24, #26: Result := sakkKeep;
    #1: Result := sakkSelectall;
    #27: Result := sakkEscape;
    #13: Result := sakkEnter;
    '0'..'9': Result := sakkKeep;
    ',', '.': if Decimals then Result := sakkDecsep;
    '-': if Negative then Result := sakkMinus;
  else Beep;
  end;

  case Result of
    sakkDecsep: Key := '.';
    sakkMinus, sakkKeep:;
  else Key := #0;
  end;
end;

function saIsNumeric(const str: string; sep: saTCharSet = []; dec: saTCharSet = []; neg: Boolean = False): Boolean;
var i, n, m, d: Integer;
  c: Char;
begin
  Result := False;
  n := -1; //must have at least one number
  d := Length(str) + 1; //allowed only between numbers
  m := -1; //allowed only before numbers

  for i := Length(str) downto 1 do begin
    c := str[i];
    if c in ['0'..'9'] then n := i //number found
    else if not (c in sep) then //allowed everywhere
    if c in dec then begin
      if n > i then begin
        dec := []; //only one allowed
        d := i; //remember position
      end else Exit; //No numbers after decimal separator
    end else if c = '-' then begin
      if neg then begin
        neg := False; //only one allowed
        m := i; //remember where it is
      end else Exit; //Negatives are not allowed
    end else Exit;
  end;

  Result := (n > 0) and (d > n) and (m < n);
end;

{$WARNINGS ON}

initialization
  saLogErrorCallback := nil;

end.
