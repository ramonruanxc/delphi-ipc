{
  WinIPC portable framing tests. Runs on both compilers; this is the Linux CI
  coverage.

    Free Pascal   fpc -Mdelphi -Fu../src -Fu. CoreTests.dpr
}
program CoreTests;

{$IFDEF FPC}
  {$MODE DELPHI}
  {$H+}
{$ELSE}
  {$APPTYPE CONSOLE}
{$ENDIF}

uses
  WinIPC.Testing,
  WinIPC.Tests.Message;

var
  Runner: TTestRunner;
begin
  WriteLn('WinIPC framing test suite');
  {$IFDEF FPC}WriteLn('compiler: Free Pascal');{$ELSE}WriteLn('compiler: Delphi');{$ENDIF}

  Runner := TTestRunner.Create;
  try
    RunMessageTests(Runner);
    ExitCode := Runner.Finish;
  finally
    Runner.Free;
  end;
end.
