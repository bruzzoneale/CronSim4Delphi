unit CronSim;

interface

uses
  System.SysUtils,
  System.DateUtils,
  System.Math,
  SCL.Types;

type
  ICronSim = interface
    ['{C46C92D7-2FDF-4C36-85BF-F85C91AB8150}']
    function Next: TDateTime;
    function StartAt(aDateRef: TDateTime): ICronSim;
    function Reversed: ICronSim;
  end;

  TCronSim = class(TInterfacedObject, ICronSim)
  private
    type
      TSpecItem = array of Integer;
      TSpecItemHelper = record helper for TSpecItem
        function Add(aValue: Integer): TSpecItem;
        function Sort: TSpecItem;
        function StepBy(aStep: Integer): TSpecItem;
        function Min: Integer;
        function Max: Integer;
        function Contains(aValue: Integer): Boolean;
      end;

      TRange = record
        Start: Integer;
        &End: Integer;
        constructor Create(aStart, aEnd: Integer);
        function Update(var aDestination: TSpecItem): TSpecItem;
        function IsInRange(aValue: Integer): Boolean;
      end;

      TElement = (MINUTE, HOUR, DAY, MONTH, DOW);

      TField = class
      private
        class var RANGES: array[TElement] of TRange;
        class function GetMsgError(aElement: TElement): string;
        class function getInt(aElement: TElement; aValue: string): Integer;
      public
        class constructor Create;
        class function Parse(aElement: TElement; const aValue: string): TSpecItem;
      end;


  private
    FDateRef: TDateTime;
    FTickDirection: Integer;
    FParts : TStringDynArray;
    FDayAND: Boolean;

    FMinutes : TSpecItem;
    FHours   : TSpecItem;
    FDays    : TSpecItem;
    FMonths  : TSpecItem;
    FWeekdays: TSpecItem;

    procedure Tick(aMinutes: Integer = 1);
    function TruncSeconds(aDate: TDateTime): TDateTime;

    function AdvanceMinute: Boolean;
    function ReverseMinute: Boolean;
    function AdvanceHour  : Boolean;
    function ReverseHour  : Boolean;
    function AdvanceDay   : Boolean;
    function ReverseDay   : Boolean;
    function Match_dom(aDate: TDateTime): Boolean;
    function Match_dow(aDate: TDateTime): Boolean;
    function Match_day(aDate: TDateTime): Boolean;
    procedure AdvanceMonth;
    procedure ReverseMonth;
    procedure Advance;
    procedure Reverse;
  public
    constructor Create(const aExpression: string);

    class function New(const aExpression: string): ICronSim;
    function StartAt(aDateRef: TDateTime): ICronSim;
    function Reversed: ICronSim;

    function Next: TDateTime;
  end;


  ECronSimError = class(Exception)
  end;

implementation

const
  SYMBOLIC_DAYS   : TStringDynArray = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
  SYMBOLIC_MONTHS : TStringDynArray = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
  DAYS_IN_MONTH   : TIntegerDynArray= [-1, 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  FIELD_NAMES     : TStringDynArray = ['minute', 'hour', 'day-of-month', 'month', 'day-of-week'];

  LAST         = -1000;
  LAST_WEEKDAY = -1001;
  INT_ERR      = -1;

  MAX_ADVANCE_YEARS = 50;


{ TCronSim.TSpecItemHelper }

function TCronSim.TSpecItemHelper.Add(aValue: Integer): TSpecItem;
begin
  SetLength(Self, Length(Self)+1);
  Self[High(Self)] := aValue;
  Result := Self;
end;

function TCronSim.TSpecItemHelper.Contains(aValue: Integer): Boolean;
begin
  for var item in Self do
    if item = aValue then
      Exit(True);

  Result := False;
end;

function TCronSim.TSpecItemHelper.Max: Integer;
begin
  Result := 0;
  for var item in Self do
    if item > Result then
      Result := item;
end;

function TCronSim.TSpecItemHelper.Min: Integer;
begin
  if Length(Self) = 0 then
    Exit(0);

  Result := MaxInt;
  for var item in Self do
    if item < Result then
      Result := item;
end;

function TCronSim.TSpecItemHelper.Sort: TSpecItem;
begin
  var tot := length(Self);
  for var i := 0 to tot - 2 do
    for var j := 0 to tot - i - 2 do
    begin
      if Self[j] > Self[j + 1] then
      begin
        var tmp := Self[j];
        Self[j] := Self[j + 1];
        Self[j + 1] := tmp;
      end;
    end;

  Result := Self;
end;

function TCronSim.TSpecItemHelper.StepBy(aStep: Integer): TSpecItem;
begin
  SetLength(Result, 0);
  var idx := 0;
  while idx < Length(Self) do
  begin
    Result.Add(Self[idx]);
    Inc(idx, aStep);
  end;
end;

{ TCronSim.TRange }

constructor TCronSim.TRange.Create(aStart, aEnd: Integer);
begin
  Start := aStart;
  &End  := aEnd;
end;

function TCronSim.TRange.IsInRange(aValue: Integer): Boolean;
begin
  Result := (aValue >= Start) and (aValue <= &End);
end;

function TCronSim.TRange.Update(var aDestination: TSpecItem): TSpecItem;
begin
  for var idx := Start to &End do
  begin
    SetLength(aDestination, Length(aDestination)+1);
    aDestination[High(aDestination)] := idx;
  end;
  Result := aDestination;
end;

{ TCronSim.TField }

class constructor TCronSim.TField.Create;
begin
  RANGES[MINUTE] := TRange.Create(0, 59);
  RANGES[HOUR]   := TRange.Create(0, 23);
  RANGES[DAY]    := TRange.Create(1, 31);
  RANGES[MONTH]  := TRange.Create(1, 12);
  RANGES[DOW]    := TRange.Create(0,  7);
end;

class function TCronSim.TField.GetMsgError(aElement: TElement): string;
begin
  Result := 'Bad '+FIELD_NAMES[Ord(aElement)];
end;

class function TCronSim.TField.getInt(aElement: TElement; aValue: string): Integer;
begin
  if (aElement = MONTH) and (SYMBOLIC_MONTHS.Contains(aValue)) then
    Result := SYMBOLIC_MONTHS.IndexOf(aValue)+1
  else
  if (aElement = DOW) and (SYMBOLIC_DAYS.Contains(aValue)) then
    Result := SYMBOLIC_DAYS.IndexOf(aValue)+1
  else
  begin
    Result := aValue.ToInt(INT_ERR);
    if not RANGES[aElement].IsInRange(Result) then
      raise ECronSimError.Create(GetMsgError(aElement));
  end;
end;

class function TCronSim.TField.Parse(aElement: TElement; const aValue: string): TSpecItem;
begin
  SetLength(Result, 0);

  if aValue = '*' then
    RANGES[aElement].Update(Result)
  else
  if aValue.Contains(',') then
  begin
    for var term in aValue.Split(',') do
      Result.Add(term.ToInt);
  end
  else
  if (aElement = DOW) and (aValue.LastChar = 'L') then
  begin
    var day := getInt(aElement, aValue.Left(aValue.Length-1));
    Result.Add(day);
    Result.Add(LAST);
  end
  else
  if (aElement = DOW) and aValue.Contains('#') then
  begin
    var term := getInt(aElement, aValue.Left(Pred(aValue.Pos('#'))));
    var nth  := aValue.CopyFrom(Succ(aValue.Pos('#'))).ToInt(INT_ERR);
    if (nth < 1) or (nth > 5) then
      raise ECronSimError.Create(GetMsgError(aElement));

    TRange.Create(term,nth).Update(Result);
  end
  else
  if aValue.Contains('/') then
  begin
    var term := aValue.Left(Pred(aValue.Pos('/')));
    var step := aValue.CopyFrom(Succ(aValue.Pos('/'))).ToInt(INT_ERR);
    if step <= 0 then
      raise ECronSimError.Create(GetMsgError(aElement));

    var items := Parse(aElement, term);
    if (items[0] = LAST) or (items[0] = LAST_WEEKDAY) then
      Result := items
    else
    if Length(items) = 1 then
      Result := TRange.Create(items[0], RANGES[aElement].&End).Update(Result).StepBy(step)
    else
      Result := items.Sort.StepBy(step);
  end
  else
  if aValue.Contains('-') then
  begin
    var start := getInt(aElement, aValue.Left(Pred(aValue.Pos('-'))));
    var endx  := getInt(aElement, aValue.CopyFrom(Succ(aValue.Pos('-'))));

    if (endx < start)  then
      raise ECronSimError.Create(GetMsgError(aElement));

    TRange.Create(start, endx).Update(Result);
  end
  else
  if (aElement = DAY) and aValue.Equals('LW') then
    Result.Add(LAST_WEEKDAY)
  else
  if (aElement = DAY) and aValue.Equals('L') then
    Result.Add(LAST)
  else
  begin
    Result.Add(getInt(aElement, aValue));
  end;
end;

function LastWeekDay(aYear, aMonth: Integer): Integer;
begin
  Result := DayOfTheWeek(EndOfTheMonth(EncodeDate(aYear, aMonth, 1)));
  if Result = 7 then // Sun
    Result := Result - 2
  else if Result = 6 then // Sat
    Result := Result - 1;
end;

{ TCronSim }

class function TCronSim.New(const aExpression: string): ICronSim;
begin
  Result := TCronSim.Create(aExpression)
end;

function TCronSim.StartAt(aDateRef: TDateTime): ICronSim;
begin
  FDateRef := TruncSeconds(aDateRef);
  Result := Self;
end;

function TCronSim.Reversed: ICronSim;
begin
  FTickDirection := -1;
  Result := Self;
end;

constructor TCronSim.Create(const aExpression: string);
begin
  FParts := aExpression.ToUpper.Split(' ');
  if FParts.Count <> 5 then
    raise ECronSimError.Create('Wrong number of fields in cron expression');

  FDateRef       := TruncSeconds(Now);
  FTickDirection := 1;
  FDayAND        := FParts[2].StartsWith('*') or FParts[4].StartsWith('*');

  FMinutes       := TField.Parse(MINUTE, FParts[0]);
  FHours         := TField.Parse(HOUR  , FParts[1]);
  FDays          := TField.Parse(DAY   , FParts[2]);
  FMonths        := TField.Parse(MONTH , FParts[3]);
  FWeekdays      := TField.Parse(DOW   , FParts[4]);

  var minDays    := FDays.Min;
  if (Length(FDays) > 0) and (minDays > 29) then
    for var month in FMonths do
      if minDays > DAYS_IN_MONTH[month] then
        raise ECronSimError.Create(TField.GetMsgError(DAY));
end;

function TCronSim.TruncSeconds(aDate: TDateTime): TDateTime;
var
  d, m, y, h, n, s, ms: Word;
begin
  DecodeDateTime(aDate, y, m, d, h, n, s, ms);
  Result := EncodeDateTime(y, m, d, h, n, 0, 0);
end;

procedure TCronSim.Tick(aMinutes: Integer);
begin
  FDateRef := IncMinute(FDateRef, aMinutes*FTickDirection);
end;

function TCronSim.AdvanceMinute: Boolean;
begin
  if FMinutes.Contains(FDateRef.Time.Minute) then
    Exit(False);

  if Length(FMinutes) = 1 then
  begin
    var target_minute := FMinutes[0];
    var delta := (target_minute - FDateRef.Time.Minute);
    if delta < 0 then
      delta := 60+delta
    else
      delta := delta mod 60;

    Tick(delta);
  end;

  while not FMinutes.Contains(FDateRef.Time.Minute) do
  begin
    Tick;
    if FDateRef.Time.Minute = 0 then
      Break;
  end;

  Result := True;
end;

function TCronSim.ReverseMinute: Boolean;
begin
  if FMinutes.Contains(FDateRef.Time.Minute) then
    Exit(False);

  if Length(FMinutes) = 1 then
  begin
    var target_minute := FMinutes[0];
    var delta := (FDateRef.Time.Minute - target_minute) ;
    if delta < 0 then
      delta := 60+delta
    else
      delta := delta mod 60;

    Tick(delta);
  end;

  while not FMinutes.Contains(FDateRef.Time.Minute) do
  begin
    Tick;
    if FDateRef.Time.Minute = 59 then
      Break;
  end;

  Result := True;
end;

function TCronSim.AdvanceHour: Boolean;
begin
  if FHours.Contains(FDateRef.Time.Hour) then
    Exit(False);

  FDateRef := RecodeMinute(FDateRef, 0);
  while not FHours.Contains(FDateRef.Time.Hour) do
  begin
    Tick(60);
    if FDateRef.Time.Hour = 0 then
      Break;
  end;

  Result := True;
end;

function TCronSim.ReverseHour: Boolean;
begin
  if FHours.Contains(FDateRef.Time.Hour) then
    Exit(False);

  FDateRef := RecodeMinute(FDateRef, 59);
  while not FHours.Contains(FDateRef.Time.Hour) do
  begin
    Tick(60);
    if FDateRef.Time.Hour = 23 then
      Break;
  end;

  Result := True;
end;

function TCronSim.Match_dom(aDate: TDateTime): Boolean;
var
 day, month, year: Word;
begin
  DecodeDate(aDate, year, month, day);

  if FDays.Contains(day) then
    Exit(True);

  if FDays.Contains(LAST_WEEKDAY) and (day >= 26) and
    (day = LastWeekDay(year, month)) then
    Exit(True);

  if FDays.Contains(LAST) and (day >= 28) and
    (day = DaysInAMonth(year, month)) then
    Exit(True);

  Result := False;
end;

function TCronSim.Match_dow(aDate: TDateTime): Boolean;
var
 day, month, year: Word;
begin
  DecodeDate(aDate, year, month, day);

  var dow := DayOfTheWeek(aDate);
  if FWeekdays.Contains(dow) or FWeekdays.Contains(dow mod 7) then
    Exit(True);

  if (FWeekdays.Contains(LAST) and FWeekdays.Contains(dow)) or
     (FWeekdays.Contains(LAST) and FWeekdays.Contains(dow mod 7)) then
  begin
    if (day + 7) > DaysInAMonth(year, month) then
      Exit(True);
  end;

  var idx := (day + 6) div 7;
  if (FWeekdays.Contains(idx) and FWeekdays.Contains(dow)) or
     (FWeekdays.Contains(idx) and FWeekdays.Contains(dow mod 7)) then
    Exit(True);

  Result := False;
end;

function TCronSim.Match_day(aDate: TDateTime): Boolean;
begin
  if FDayAND then
    Result := Match_dom(aDate) and Match_dow(aDate)
  else
    Result := Match_dom(aDate) or Match_dow(aDate);
end;

function TCronSim.AdvanceDay: Boolean;
begin
  var needle: TDate := FDateRef.Date;
  if match_day(needle) then
    Exit(False);

  while not Match_day(needle) do
  begin
    needle := IncDay(needle, 1);
    if needle.Day = 1 then
      Break;
  end;

  FDateRef := needle;
  Result := True;
end;

function TCronSim.ReverseDay: Boolean;
begin
  var needle: TDate := FDateRef.Date;
  if match_day(needle) then
    Exit(False);

  var month := needle.Month;
  while not Match_day(needle) do
  begin
    needle := IncDay(needle, -1);
    if needle.Month <> month then
      Break;
  end;

  FDateRef := needle;
  FDateRef.Time := TTime.Encode(23, 59);
  Result := True;
end;

procedure TCronSim.AdvanceMonth;
begin
  var needle: TDate := FDateRef.Date;
  if FMonths.Contains(needle.Month) then
    Exit;

  while not FMonths.Contains(needle.Month) do
    needle := IncMonth(needle, 1).Date.FirstDayOfMonth;

  FDateRef := needle;
end;

procedure TCronSim.ReverseMonth;
begin
  var needle: TDate := FDateRef.Date;
  if FMonths.Contains(needle.Month) then
    Exit;

  while not FMonths.Contains(needle.Month) do
    needle := IncMonth(needle, -1).Date.LastDayOfMonth;

  FDateRef := needle;
  FDateRef.Time := TTime.Encode(23, 59);
end;

procedure TCronSim.Advance;
begin
  var start_year := FDateRef.Date.Year;
  while True do
  begin
    AdvanceMonth;
    if FDateRef.Date.Year > start_year + MAX_ADVANCE_YEARS then
      Exit;

    if AdvanceDay then
      Continue;

    if AdvanceHour then
      Continue;

    if AdvanceMinute then
      Continue;

    Break;
  end;
end;

procedure TCronSim.Reverse;
begin
  var start_year := FDateRef.Date.Year;
  while True do
  begin
    ReverseMonth;
    if FDateRef.Date.Year < start_year - MAX_ADVANCE_YEARS then
      Exit;

    if ReverseDay then
      Continue;

    if ReverseHour then
      Continue;

    if ReverseMinute then
      Continue;

    Break;
  end;
end;

function TCronSim.Next: TDateTime;
begin
  Tick;
  if FTickDirection = 1 then
    Advance
  else
    Reverse;

  Result := FDateRef;
end;

end.
