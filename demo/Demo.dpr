{
  WinIPC demo — two real processes talking over WM_COPYDATA.

  Run it with no arguments (or press F9 in the IDE) and it demonstrates itself
  in one launch: it opens a channel, starts a second copy of this executable as
  the sender, receives that process's message and prints a single OK or FAILED
  line. The message genuinely crosses a process boundary; the two processes
  share nothing but the channel name.

    Demo.exe                          one-launch round trip, two processes
    Demo.exe server                   listen on "winipc-demo" until Ctrl+C
    Demo.exe client "message text"    send one message to a running server

  Building needs nothing configured:

    Delphi        open demo/Demo.dpr (XE7 or later) and press F9
    Free Pascal   fpc demo/Demo.dpr    (from the repository root)

  Exit code 0 means the message was delivered. Windows only, like the transport
  it demonstrates.
}
program Demo;

{$IFDEF FPC}
  {$MODE DELPHI}
  { FPC resolves in-paths from the working directory; UNITPATH is relative
    to this file, so the command above works from the repository root. }
  {$UNITPATH ../src}
  {$H+}
{$ELSE}
  {$APPTYPE CONSOLE}
{$ENDIF}

uses
  {$IFDEF FPC}Windows, SysUtils{$ELSE}Winapi.Windows, System.SysUtils{$ENDIF},
  { Every unit from this repository is listed with its path, so opening this
    file in the IDE is enough to build it. Forward slashes on purpose: Delphi
    accepts them on Windows. Free Pascal resolves these paths against the
    current directory, which is why its command line adds -Fusrc. }
  WinIPC.Message in '../src/WinIPC.Message.pas',
  WinIPC.Win in '../src/WinIPC.Win.pas';

const
  DefaultChannel = 'winipc-demo';
  DemoText = 'hello from another process';
  { How long the one-launch demo waits for the sender process to deliver. }
  DeliveryTimeoutMs = 10000;

type
  TPrinter = class
  strict private
    FLastPayload: string;
  public
    procedure OnMessage(const AMessage: TIpcMessage);
    property LastPayload: string read FLastPayload;
  end;

procedure TPrinter.OnMessage(const AMessage: TIpcMessage);
begin
  FLastPayload := AMessage.Payload;
  WriteLn(Format('  received  kind=%u  "%s"', [AMessage.Kind, AMessage.Payload]));
end;

procedure RunServer;
var
  Printer: TPrinter;
  Server: TIpcServer;
begin
  Printer := TPrinter.Create;
  Server := TIpcServer.Create(DefaultChannel, Printer.OnMessage);
  try
    WriteLn('server listening on channel "', DefaultChannel, '"');
    WriteLn('run  Demo.exe client "your message"  in another console.');
    WriteLn('press Ctrl+C here to stop.');
    WriteLn;
    while True do
    begin
      Server.ProcessPending;
      Sleep(10);
    end;
  finally
    Server.Free;
    Printer.Free;
  end;
end;

procedure RunClient(const AText, AChannel: string);
var
  Msg: TIpcMessage;
begin
  Msg.Kind := 1;
  Msg.Payload := AText;
  case TIpcClient.Send(AChannel, Msg) of
    srDelivered:
      WriteLn('  sender    delivered.');
    srNoServer:
      begin
        WriteLn('no server is listening on "', AChannel,
          '". Start Demo.exe server first.');
        ExitCode := 1;
      end;
    srEncodeEmpty:
      begin
        WriteLn('nothing to send.');
        ExitCode := 1;
      end;
  end;
end;

{ Starts this same executable as "client <text> <channel>" and returns the
  child's process handle, or 0 if it could not be started. Handles are
  inherited so the child writes to the same console or pipe as this process. }
function StartSender(const AChannel, AText: string;
  out AProcessId: DWORD): THandle;
var
  CommandLine: string;
  StartupInfo: TStartupInfo;
  ProcessInfo: TProcessInformation;
begin
  Result := 0;
  AProcessId := 0;
  CommandLine := Format('"%s" client "%s" "%s"', [ParamStr(0), AText, AChannel]);
  { CreateProcessW may write to the command-line buffer, so it must not be
    shared with any other string. }
  UniqueString(CommandLine);
  FillChar(StartupInfo, SizeOf(StartupInfo), 0);
  StartupInfo.cb := SizeOf(StartupInfo);
  FillChar(ProcessInfo, SizeOf(ProcessInfo), 0);
  if not CreateProcess(nil, PChar(CommandLine), nil, nil, True, 0, nil, nil,
    StartupInfo, ProcessInfo) then
    Exit;
  CloseHandle(ProcessInfo.hThread);
  AProcessId := ProcessInfo.dwProcessId;
  Result := ProcessInfo.hProcess;
end;

{ The one-launch demo: this process receives, a second process sends. }
procedure RunRoundTrip;
var
  Printer: TPrinter;
  Server: TIpcServer;
  Channel: string;
  Child: THandle;
  ChildId, ChildExit, StartError: DWORD;
  Delivered: Boolean;
begin
  { A channel per run, so a "Demo.exe server" left open elsewhere cannot be the
    one that answers. }
  Channel := Format('%s-%u', [DefaultChannel, GetCurrentProcessId]);
  Delivered := False;
  ChildId := 0;
  ChildExit := 1;

  WriteLn('WinIPC demo: one message between two processes over WM_COPYDATA');
  Printer := TPrinter.Create;
  try
    Server := TIpcServer.Create(Channel, Printer.OnMessage);
    try
      WriteLn(Format('  receiver  pid %u  listening on "%s"',
        [GetCurrentProcessId, Channel]));
      Child := StartSender(Channel, DemoText, ChildId);
      if Child = 0 then
      begin
        StartError := GetLastError;
        WriteLn(Format('FAILED: could not start the sender process (error %u).',
          [StartError]));
        ExitCode := 1;
        Exit;
      end;
      try
        WriteLn(Format('  sender    pid %u  started as a separate process',
          [ChildId]));
        Delivered := Server.PumpFor(DeliveryTimeoutMs);
        WaitForSingleObject(Child, DeliveryTimeoutMs);
        if not GetExitCodeProcess(Child, ChildExit) then
          ChildExit := 1;
      finally
        CloseHandle(Child);
      end;
    finally
      Server.Free;
    end;

    if Delivered and (ChildExit = 0) and (Printer.LastPayload = DemoText) then
      WriteLn(Format('OK: process %u sent "%s" to process %u over WM_COPYDATA.',
        [ChildId, DemoText, GetCurrentProcessId]))
    else
    begin
      WriteLn(Format('FAILED: no message arrived from process %u within %d ms.',
        [ChildId, DeliveryTimeoutMs]));
      ExitCode := 1;
    end;
  finally
    Printer.Free;
  end;
end;

procedure ShowUsage;
begin
  WriteLn('usage:');
  WriteLn('  Demo.exe                          one-launch round trip');
  WriteLn('  Demo.exe server                   listen until Ctrl+C');
  WriteLn('  Demo.exe client "message text"    send to a running server');
  ExitCode := 2;
end;

begin
  if ParamCount = 0 then
    RunRoundTrip
  else if SameText(ParamStr(1), 'server') then
    RunServer
  else if SameText(ParamStr(1), 'client') and (ParamCount = 2) then
    RunClient(ParamStr(2), DefaultChannel)
  else if SameText(ParamStr(1), 'client') and (ParamCount = 3) then
    RunClient(ParamStr(2), ParamStr(3))
  else
    ShowUsage;

  { Keeps the console open when the demo is started from the Delphi IDE, which
    otherwise closes the window before the result can be read. DebugHook is
    only non-zero under the debugger, so a command-line run, CI and Free Pascal
    never pause here. }
  {$IFNDEF FPC}
  if DebugHook <> 0 then
  begin
    Write('Press Enter to exit...');
    ReadLn;
  end;
  {$ENDIF}
end.
