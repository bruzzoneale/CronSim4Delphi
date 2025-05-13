program test_cron;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  CronSim,
  SCL.Types;

begin
  try
    WriteLn('CRONSIM TEST');
    if ParamCount = 0 then
      WriteLn('usage: test_cron "expression" [iterations] [reverse]')
    else
    begin
      var iterNum := ParamStr(2).toint(5);
      var reverse := lowercase(ParamStr(3).IfEmpty('advance'));

      var cron := TCronSim.New(ParamStr(1)).StartAt(Now);
      if (reverse.Chars[1] = 'r') then
        cron.Reversed;
      for var idx := 1 to iterNum do
        writeln(cron.Next.ToStringFormat('dd/mm/yyyy  hh:nn:ss'));
    end;

    WriteLn('');
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
