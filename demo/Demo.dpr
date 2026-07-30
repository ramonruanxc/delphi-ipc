{
  WinIPC demo — two real processes talking over WM_COPYDATA.

  Build it, then open two consoles:

    Demo.exe server
    Demo.exe client "hello from the other process"

  The server prints what it receives until you press a key. Each client run is
  a separate process sending one message across the boundary.

    Free Pascal   fpc -Mdelphi -Fu../src Demo.dpr
    Delphi        add ../src to the search path, build in the IDE

  Windows only, like the transport it demonstrates.
}
program Demo;

{$IFDEF FPC}
  {$MODE DELPHI}
  {$H+}
{$ELSE}
  {$APPTYPE CONSOLE}
{$ENDIF}

uses
  {$IFDEF FPC}Windows, SysUtils{$ELSE}Winapi.Windows, System.SysUtils{$ENDIF},
  WinIPC.Message,
  WinIPC.Win;

const
  Channel = 'winipc-demo';

type
  TPrinter = class
    procedure OnMessage(const AMessage: TIpcMessage);
  end;

procedure TPrinter.OnMessage(const AMessage: TIpcMessage);
begin
  WriteLn(Format('  received  kind=%u  "%s"', [AMessage.Kind, AMessage.Payload]));
end;

procedure RunServer;
var
  Printer: TPrinter;
  Server: TIpcServer;
begin
  Printer := TPrinter.Create;
  Server := TIpcServer.Create(Channel, Printer.OnMessage);
  try
    WriteLn('server listening on channel "', Channel, '"');
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

procedure RunClient(const AText: string);
var
  Msg: TIpcMessage;
begin
  Msg.Kind := 1;
  Msg.Payload := AText;
  case TIpcClient.Send(Channel, Msg) of
    srDelivered:   WriteLn('delivered.');
    srNoServer:    WriteLn('no server is listening on "', Channel,
                     '". Start Demo.exe server first.');
    srEncodeEmpty: WriteLn('nothing to send.');
  end;
end;

begin
  if (ParamCount >= 1) and SameText(ParamStr(1), 'server') then
    RunServer
  else if (ParamCount >= 2) and SameText(ParamStr(1), 'client') then
    RunClient(ParamStr(2))
  else
  begin
    WriteLn('usage:');
    WriteLn('  Demo.exe server');
    WriteLn('  Demo.exe client "message text"');
  end;
end.
