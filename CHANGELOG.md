# Changelog

This project follows [Semantic Versioning](https://semver.org/).

## [1.0.0] — unreleased

First release. A typed WM_COPYDATA IPC layer extracted from a personal systems
project and rebuilt as a standalone, tested component.

### Added

- `TIpcServer`: receives messages on a named channel through a message-only
  (`HWND_MESSAGE`) window, and allows cross-integrity delivery via
  `ChangeWindowMessageFilterEx`.
- `TIpcClient`: locates a channel with `FindWindowEx` and sends with
  `SendMessage`, reporting `srDelivered` / `srNoServer` / `srEncodeEmpty`.
- `WinIPC.Message`: a portable, UI-free frame — `magic | version | kind |
  length | payload` — whose decoder validates every field and rejects a frame
  whose declared length does not match the buffer.
- A portable framing test suite run on Linux, plus a Windows test that performs
  a real cross-thread WM_COPYDATA round trip; both run in CI (Linux + Windows
  jobs). 19 assertions in total.
- A two-process demo (`Demo.exe server` / `Demo.exe client "..."`).
- `boss.json` for installation through Boss.
