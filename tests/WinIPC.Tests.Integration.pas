{
  WinIPC — Windows transport tests.

  A real WM_COPYDATA round trip, in one process: the server owns a message-only
  window on the main thread, a worker thread sends to it, and the main thread
  pumps the queue to receive. WM_COPYDATA is delivered synchronously on the
  window-owning thread, so this exercises the true cross-thread marshalling
  path — the same path the kernel uses across a process boundary — without
  needing a second executable.

  Windows-only; built and run on the Windows CI job.
}
unit WinIPC.Tests.Integration;

{$IFDEF FPC}
  {$MODE DELPHI}
  {$H+}
{$ENDIF}

interface

{$IFDEF MSWINDOWS}

uses
  WinIPC.Testing;

procedure RunIntegrationTests(ARunner: TTestRunner);

{$ENDIF}

implementation

{$IFDEF MSWINDOWS}

uses
  {$IFDEF FPC}Windows, Classes, SysUtils{$ELSE}
  Winapi.Windows, System.Classes, System.SysUtils{$ENDIF},
  WinIPC.Message,
  WinIPC.Win;

type
  { Captures what the server hands back. }
  TReceiver = class
  strict private
    FGot: Boolean;
    FKind: UInt32;
    FPayload: string;
  public
    procedure OnMessage(const AMessage: TIpcMessage);
    property Got: Boolean read FGot;
    property Kind: UInt32 read FKind;
    property Payload: string read FPayload;
  end;

  TSenderThread = class(TThread)
  strict private
    FChannel: string;
    FMessage: TIpcMessage;
    FResult: TIpcSendResult;
  protected
    procedure Execute; override;
  public
    constructor Create(const AChannel: string; const AMessage: TIpcMessage);
    property Result: TIpcSendResult read FResult;
  end;

procedure TReceiver.OnMessage(const AMessage: TIpcMessage);
begin
  FGot := True;
  FKind := AMessage.Kind;
  FPayload := AMessage.Payload;
end;

constructor TSenderThread.Create(const AChannel: string;
  const AMessage: TIpcMessage);
begin
  inherited Create(True);
  FChannel := AChannel;
  FMessage := AMessage;
  FreeOnTerminate := False;
end;

procedure TSenderThread.Execute;
begin
  { A brief pause so the server window certainly exists before the send. The
    receiver still has to pump for the message to arrive, so this only orders
    creation, not delivery. }
  Sleep(50);
  FResult := TIpcClient.Send(FChannel, FMessage);
end;

procedure TestRoundTrip(ARunner: TTestRunner);
const
  Channel = 'winipc-test';
var
  Receiver: TReceiver;
  Server: TIpcServer;
  Sender: TSenderThread;
  Sent: TIpcMessage;
  Delivered: Boolean;
begin
  ARunner.Suite('WM_COPYDATA round trip');

  Sent.Kind := 42;
  Sent.Payload := 'ping from another thread — acentuação ok';

  Receiver := TReceiver.Create;
  Server := TIpcServer.Create(Channel, Receiver.OnMessage);
  Sender := TSenderThread.Create(Channel, Sent);
  try
    Sender.Start;
    Delivered := Server.PumpFor(3000);
    Sender.WaitFor;

    ARunner.IsTrue('the message pump reports activity', Delivered);
    ARunner.IsTrue('the sender reports delivery',
      Sender.Result = srDelivered);
    ARunner.IsTrue('the server received a message', Receiver.Got);
    ARunner.AreEqual('the kind arrived intact', 42, Integer(Receiver.Kind));
    ARunner.AreEqual('the payload arrived intact', Sent.Payload,
      Receiver.Payload);
  finally
    Sender.Free;
    Server.Free;
    Receiver.Free;
  end;
end;

procedure TestNoServer(ARunner: TTestRunner);
var
  Msg: TIpcMessage;
begin
  ARunner.Suite('Sending with no server');

  Msg.Kind := 1;
  Msg.Payload := 'into the void';
  { No server was ever created on this channel, so the client must report that
    rather than blocking or raising. }
  ARunner.IsTrue('reports that no server is listening',
    TIpcClient.Send('channel-that-does-not-exist', Msg) = srNoServer);
end;

procedure RunIntegrationTests(ARunner: TTestRunner);
begin
  TestRoundTrip(ARunner);
  TestNoServer(ARunner);
end;

{$ENDIF}

end.
