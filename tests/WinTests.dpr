{
  WinIPC full test suite: portable framing plus the Windows WM_COPYDATA
  transport. Windows only.

    Free Pascal   fpc -Mdelphi -Fu../src -Fu. WinTests.dpr
    Delphi        add ../src and . to the search path, build in the IDE
}
program WinTests;

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
  WinIPC.Win in '../src/WinIPC.Win.pas',
  WinIPC.Testing in 'WinIPC.Testing.pas',
  WinIPC.Tests.Message in 'WinIPC.Tests.Message.pas',
  WinIPC.Tests.Integration in 'WinIPC.Tests.Integration.pas';

var
  Runner: TTestRunner;
begin
  WriteLn('WinIPC full test suite (framing + WM_COPYDATA transport)');
  {$IFDEF FPC}WriteLn('compiler: Free Pascal');{$ELSE}WriteLn('compiler: Delphi');{$ENDIF}

  Runner := TTestRunner.Create;
  try
    RunMessageTests(Runner);
    RunIntegrationTests(Runner);
    ExitCode := Runner.Finish;
  finally
    Runner.Free;
  end;
end.
