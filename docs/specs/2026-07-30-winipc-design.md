# WinIPC — design

Date: 2026-07-30
Status: implemented, framing + transport verified on FPC (Windows); CI covers
both Linux (framing) and Windows (transport).

## Goal

A small, typed way to send structured messages between Windows processes,
extracted from a personal systems project and rebuilt as a standalone,
public, tested component. Same portfolio intent as the other extractions: the
technique is the asset, presented cleanly and generically.

## The constraint that shapes it

`WM_COPYDATA` is Win32. Unlike the other libraries, this one cannot be fully
tested on a free Linux toolchain — the transport is Windows-only. Rather than
give up CI, the library is split so the part that *can* be tested portably is,
and the Windows part gets its own Windows CI job.

## Architecture

```
src/WinIPC.Message.pas   portable framing. Delphi + FPC, Linux + Windows.
src/WinIPC.Win.pas       WM_COPYDATA transport. {$IFDEF MSWINDOWS} only.
```

- **Framing** turns `(kind, payload)` into `magic | version | kind | length |
  bytes` and back, validating every field. No Windows dependency. This is the
  bulk of the logic and the bulk of the risk (parsing untrusted bytes), so it
  is the bulk of the tests, run on Linux.
- **Transport** is the message-only window, the class-name channel lookup, the
  `SendMessage` send, and the UIPI filter. Windows-only, tested on Windows.

## Key decisions

**Message-only window (`HWND_MESSAGE`).** A background IPC endpoint should not
be a visible or top-level window. A message-only window receives messages and
nothing else, and is found via `FindWindowEx(HWND_MESSAGE, ...)` by class name.

**`SendMessage`, not `PostMessage`.** The kernel marshals the `COPYDATASTRUCT`
buffer across the process boundary only for the span of a synchronous
`SendMessage`. Posting would deliver a pointer valid only in the sender.

**`ChangeWindowMessageFilterEx` on the receiver.** Cross-integrity delivery
(one side elevated) is silently dropped by UIPI otherwise. This is the
real-world failure that makes people abandon `WM_COPYDATA` believing it
"doesn't work across elevation."

**Delivery judged by a counter, not by the pump.** A cross-thread/cross-process
`WM_COPYDATA` is dispatched as a side effect of `PeekMessage`, which returns
`False`. `PumpFor` therefore reports delivery from `Handled`, incremented in the
window procedure, not from whether the pump saw a queued message. This is
subtle and is pinned by a test — an earlier version got it wrong and reported
no delivery for messages it had in fact delivered.

**Validate the declared length against the buffer.** A frame claiming more
payload than it carries is the standard buffer-overrun path. The decoder treats
frame bytes as untrusted and rejects the mismatch instead of reading past the
end.

## Testing

- Framing: round trip (including empty and non-ASCII payloads and the maximum
  kind), and rejection of every malformed frame class — short buffer, bad
  magic, unsupported version, and length longer *or* shorter than the buffer.
  Runs on both compilers; Linux CI.
- Transport: a real cross-thread `WM_COPYDATA` round trip in one process — a
  server window on the main thread, a worker thread sending — plus the
  no-server-listening case. Windows CI.
- 19 assertions total, all passing under FPC 3.2.2 on Windows locally.

## Verification status

- Framing and transport both compile and pass under FPC 3.2.2 on Windows.
- The two-process demo was smoke-tested by hand (server + two clients).
- Not verified under Delphi's compiler (Community Edition blocks command-line
  builds); the code targets Delphi 10.1+ and uses only long-standing RTL and
  Win32 APIs.

## Out of scope

- A reply channel. `WM_COPYDATA` is one-way; a request/response layer would sit
  on top by having each side run its own server. Not built here.
- Non-Windows transports (D-Bus, domain sockets). The framing is reusable if
  someone wants to; the transport is deliberately Win32.
- Large payloads. `WM_COPYDATA` copies the whole buffer per send; for streaming
  or megabytes, shared memory is the right tool.
