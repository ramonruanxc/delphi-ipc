{
  WinIPC — Windows transport.

  Sends the frames from WinIPC.Message between processes with WM_COPYDATA, the
  Win32 mechanism built for exactly this: handing a block of bytes to another
  process's window, with the kernel marshalling it across the process boundary.
  No sockets, no pipes, no shared files.

  The receiver is a message-only window (HWND_MESSAGE). Such a window never
  appears on screen, is not enumerated as a top-level window, and exists only
  to receive messages — which is what a background IPC endpoint wants. A sender
  locates it by window class through FindWindowEx under HWND_MESSAGE.

  This unit is Windows-only. The framing it carries (WinIPC.Message) is
  portable and tested in CI on Linux; this transport is tested on a Windows CI
  runner.
}
unit WinIPC.Win;

{$IFDEF FPC}
  {$MODE DELPHI}
  {$H+}
{$ENDIF}

interface

{$IFDEF MSWINDOWS}

uses
  {$IFDEF FPC}Windows, Messages, SysUtils{$ELSE}
  Winapi.Windows, Winapi.Messages, System.SysUtils{$ENDIF},
  WinIPC.Message;

type
  TIpcMessageEvent = procedure(const AMessage: TIpcMessage) of object;

  { Receives messages on a named channel.

    Create one with a channel name and an OnMessage handler, then pump the
    window's message queue — ProcessPending in your own loop, or PumpFor in a
    simple blocking wait. The handler runs on the thread that pumps. }
  TIpcServer = class
  strict private
    FChannel: string;
    FClassName: string;
    FWindow: HWND;
    FOnMessage: TIpcMessageEvent;
    FClassAtom: ATOM;
    FHandled: Int64;
  public
    constructor Create(const AChannel: string; AOnMessage: TIpcMessageEvent);
    destructor Destroy; override;

    { Called by the shared window procedure — not part of the intended public
      surface, but must be reachable from a plain function in this unit, which
      strict private would forbid. }
    procedure HandleCopyData(const ACopyData: TCopyDataStruct);

    { Dispatches every message currently queued for this window, without
      blocking. Returns how many were dispatched. Call it from your app's idle
      loop. }
    function ProcessPending: Integer;

    { Pumps until at least one message has been delivered to OnMessage or the
      timeout elapses. Returns True if a message was delivered. Convenience for
      a program whose only job is to wait for IPC. }
    function PumpFor(ATimeoutMs: Cardinal): Boolean;

    property Channel: string read FChannel;
    property WindowHandle: HWND read FWindow;

    { How many valid messages this server has handled since creation. This,
      not PeekMessage's return value, is the ground truth of delivery: a
      WM_COPYDATA sent cross-thread is dispatched as a side effect of
      PeekMessage, which still returns False, so the count is the only reliable
      signal that something arrived. }
    property Handled: Int64 read FHandled;
  end;

  TIpcSendResult = (srDelivered, srNoServer, srEncodeEmpty);

  { Sends messages to a named channel. Stateless — construct once and reuse, or
    use the class function. }
  TIpcClient = class
  public
    class function Send(const AChannel: string;
      const AMessage: TIpcMessage): TIpcSendResult;
  end;

function ChannelClassName(const AChannel: string): string;

{$ENDIF}

implementation

{$IFDEF MSWINDOWS}

const
  { Lets the window accept WM_COPYDATA from a lower-integrity process — the
    case that silently fails when one side runs elevated and the other does
    not. Declared here because older RTL headers may not expose it. }
  MSGFLT_ALLOW = 1;

function ChangeWindowMessageFilterEx(hWnd: HWND; message: UINT; action: DWORD;
  pChangeFilterStruct: Pointer): BOOL; stdcall; external 'user32.dll';

{ FPC's Windows unit does not define HWND_MESSAGE (the special parent that
  makes a window message-only). Delphi's does. }
{$IFDEF FPC}
const
  HWND_MESSAGE = HWND(-3);
{$ENDIF}

function ChannelClassName(const AChannel: string): string;
begin
  Result := 'WinIPC.' + AChannel;
end;

{ One window procedure for every server window. The instance is stashed in the
  window's user data at creation, so the right server handles each message. }
function ServerWndProc(hWnd: HWND; uMsg: UINT; wParam: WPARAM;
  lParam: LPARAM): LRESULT; stdcall;
var
  Server: TIpcServer;
  CopyData: PCopyDataStruct;
begin
  if uMsg = WM_COPYDATA then
  begin
    Server := TIpcServer(Pointer(GetWindowLongPtr(hWnd, GWLP_USERDATA)));
    if Server <> nil then
    begin
      CopyData := PCopyDataStruct(lParam);
      Server.HandleCopyData(CopyData^);
      Exit(1); { non-zero: processed }
    end;
  end;
  Result := DefWindowProc(hWnd, uMsg, wParam, lParam);
end;

{ TIpcServer }

constructor TIpcServer.Create(const AChannel: string;
  AOnMessage: TIpcMessageEvent);
var
  WndClass: TWndClass;
begin
  inherited Create;
  FChannel := AChannel;
  FClassName := ChannelClassName(AChannel);
  FOnMessage := AOnMessage;

  FillChar(WndClass, SizeOf(WndClass), 0);
  WndClass.lpfnWndProc := @ServerWndProc;
  WndClass.hInstance := HInstance;
  WndClass.lpszClassName := PChar(FClassName);

  FClassAtom := RegisterClass(WndClass);
  if FClassAtom = 0 then
    raise Exception.CreateFmt(
      'Could not register IPC window class "%s" (error %d).',
      [FClassName, GetLastError]);

  { HWND_MESSAGE makes this a message-only window. }
  FWindow := CreateWindow(PChar(FClassName), PChar(FClassName), 0,
    0, 0, 0, 0, HWND_MESSAGE, 0, HInstance, nil);
  if FWindow = 0 then
    raise Exception.CreateFmt('Could not create IPC window (error %d).',
      [GetLastError]);

  SetWindowLongPtr(FWindow, GWLP_USERDATA, LONG_PTR(Pointer(Self)));
  ChangeWindowMessageFilterEx(FWindow, WM_COPYDATA, MSGFLT_ALLOW, nil);
end;

destructor TIpcServer.Destroy;
begin
  if FWindow <> 0 then
    DestroyWindow(FWindow);
  if FClassAtom <> 0 then
    {$IFDEF FPC}
    Windows.UnregisterClass(PChar(FClassName), HInstance);
    {$ELSE}
    Winapi.Windows.UnregisterClass(PChar(FClassName), HInstance);
    {$ENDIF}
  inherited Destroy;
end;

procedure TIpcServer.HandleCopyData(const ACopyData: TCopyDataStruct);
var
  Bytes: TBytes;
  Parsed: TIpcParseResult;
begin
  if (ACopyData.cbData = 0) or (ACopyData.lpData = nil) then
    Exit;

  SetLength(Bytes, ACopyData.cbData);
  Move(ACopyData.lpData^, Bytes[0], ACopyData.cbData);

  { A frame from another process is untrusted input; a bad one is dropped, not
    fatal. }
  Parsed := DecodeMessage(Bytes);
  if not Parsed.IsOk then
    Exit;

  Inc(FHandled);
  if Assigned(FOnMessage) then
    FOnMessage(Parsed.Message);
end;

function TIpcServer.ProcessPending: Integer;
var
  Msg: TMsg;
begin
  Result := 0;
  while PeekMessage(Msg, FWindow, 0, 0, PM_REMOVE) do
  begin
    TranslateMessage(Msg);
    DispatchMessage(Msg);
    Inc(Result);
  end;
end;

function TIpcServer.PumpFor(ATimeoutMs: Cardinal): Boolean;
var
  Start: UInt64;
  StartCount: Int64;
  Msg: TMsg;
begin
  StartCount := FHandled;
  Start := GetTickCount64;
  repeat
    { PeekMessage dispatches any queued messages and, as a side effect,
      processes cross-thread sent messages like WM_COPYDATA even when it
      returns False — which is why delivery is judged by FHandled, not by this
      loop running. }
    while PeekMessage(Msg, FWindow, 0, 0, PM_REMOVE) do
    begin
      TranslateMessage(Msg);
      DispatchMessage(Msg);
    end;
    if FHandled > StartCount then
      Exit(True);
    Sleep(1);
  until GetTickCount64 - Start >= ATimeoutMs;
  Result := FHandled > StartCount;
end;

{ TIpcClient }

class function TIpcClient.Send(const AChannel: string;
  const AMessage: TIpcMessage): TIpcSendResult;
var
  Target: HWND;
  Frame: TBytes;
  CopyData: TCopyDataStruct;
begin
  { Message-only windows are not top-level, so FindWindow cannot see them;
    FindWindowEx with HWND_MESSAGE as the parent can. }
  Target := FindWindowEx(HWND_MESSAGE, 0, PChar(ChannelClassName(AChannel)), nil);
  if Target = 0 then
    Exit(srNoServer);

  Frame := EncodeMessage(AMessage);
  if Length(Frame) = 0 then
    Exit(srEncodeEmpty);

  CopyData.dwData := AMessage.Kind;
  CopyData.cbData := Length(Frame);
  CopyData.lpData := @Frame[0];

  { WM_COPYDATA must be sent, not posted: the kernel only marshals the buffer
    across the process boundary for the duration of a synchronous SendMessage.
    A PostMessage would hand the receiver a pointer into this process. }
  SendMessage(Target, WM_COPYDATA, WPARAM(0), LPARAM(@CopyData));
  Result := srDelivered;
end;

{$ENDIF}

end.
