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
  { Every project unit is listed with its path, including the ones only reached
    indirectly, so the project builds from a clone with nothing to configure. }
  WinIPC.Message in '../src/WinIPC.Message.pas',
  WinIPC.Testing in 'WinIPC.Testing.pas',
  WinIPC.Tests.Message in 'WinIPC.Tests.Message.pas';

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
