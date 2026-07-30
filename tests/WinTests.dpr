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
  WinIPC.Testing,
  WinIPC.Tests.Message,
  WinIPC.Tests.Integration;

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
