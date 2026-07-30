{
  WinIPC — small portable assertion runner. Same shape used across these
  libraries: no framework state, runs under Delphi and Free Pascal, exit code
  reports success to CI.
}
unit WinIPC.Testing;

{$IFDEF FPC}
  {$MODE DELPHI}
  {$H+}
{$ENDIF}

interface

type
  TTestRunner = class
  strict private
    FPassed: Integer;
    FFailed: Integer;
    FSuiteName: string;
    FHeaderWritten: Boolean;
    procedure EnsureHeader;
    procedure Pass(const ATestName: string);
    procedure Fail(const ATestName, AExpected, AActual: string);
  public
    constructor Create;
    procedure Suite(const AName: string);
    procedure IsTrue(const ATestName: string; ACondition: Boolean);
    procedure AreEqual(const ATestName: string; AExpected, AActual: Integer); overload;
    procedure AreEqual(const ATestName, AExpected, AActual: string); overload;
    function Finish: Integer;
    property Passed: Integer read FPassed;
    property Failed: Integer read FFailed;
  end;

implementation

uses
  {$IFDEF FPC}SysUtils{$ELSE}System.SysUtils{$ENDIF};

constructor TTestRunner.Create;
begin
  inherited Create;
  FPassed := 0;
  FFailed := 0;
  FHeaderWritten := True;
end;

procedure TTestRunner.Suite(const AName: string);
begin
  FSuiteName := AName;
  FHeaderWritten := False;
end;

procedure TTestRunner.EnsureHeader;
begin
  if FHeaderWritten then Exit;
  WriteLn;
  WriteLn(FSuiteName);
  FHeaderWritten := True;
end;

procedure TTestRunner.Pass(const ATestName: string);
begin
  EnsureHeader;
  Inc(FPassed);
  WriteLn('  ok      ', ATestName);
end;

procedure TTestRunner.Fail(const ATestName, AExpected, AActual: string);
begin
  EnsureHeader;
  Inc(FFailed);
  WriteLn('  FAILED  ', ATestName);
  WriteLn('            expected: ', AExpected);
  WriteLn('            actual:   ', AActual);
end;

procedure TTestRunner.IsTrue(const ATestName: string; ACondition: Boolean);
begin
  if ACondition then Pass(ATestName) else Fail(ATestName, 'True', 'False');
end;

procedure TTestRunner.AreEqual(const ATestName: string; AExpected, AActual: Integer);
begin
  if AExpected = AActual then Pass(ATestName)
  else Fail(ATestName, IntToStr(AExpected), IntToStr(AActual));
end;

procedure TTestRunner.AreEqual(const ATestName, AExpected, AActual: string);
begin
  if AExpected = AActual then Pass(ATestName)
  else Fail(ATestName, '"' + AExpected + '"', '"' + AActual + '"');
end;

function TTestRunner.Finish: Integer;
begin
  WriteLn;
  WriteLn('----------------------------------------');
  WriteLn(Format('%d passed, %d failed, %d total',
    [FPassed, FFailed, FPassed + FFailed]));
  if FFailed = 0 then Result := 0 else Result := 1;
end;

end.
