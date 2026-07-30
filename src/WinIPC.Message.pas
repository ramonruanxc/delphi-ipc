{
  WinIPC — portable core.

  Framing for a message sent between processes: turning a (kind, payload) pair
  into a self-describing byte buffer and back, with validation.

  This unit has no Windows dependency on purpose. The WM_COPYDATA transport in
  WinIPC.Win carries whatever bytes this produces, but the framing itself is
  plain Object Pascal, so it compiles and is tested under both Delphi and Free
  Pascal — the transport is Windows-only and cannot be tested in Linux CI, but
  the part most likely to have an off-by-one, the framing, can.

  Frame layout, little-endian:

    magic    4 bytes   'WIPC'
    version  1 byte    currently 1
    kind     4 bytes   caller-defined message kind
    length   4 bytes   payload length in bytes
    payload  length bytes, UTF-8
}
unit WinIPC.Message;

{$IFDEF FPC}
  {$MODE DELPHI}
  {$H+}
{$ENDIF}

interface

uses
  {$IFDEF FPC}SysUtils{$ELSE}System.SysUtils{$ENDIF};

type
  TIpcParseFailure = (
    pfNone,
    pfTooShort,
    pfBadMagic,
    pfUnsupportedVersion,
    pfLengthMismatch
  );

  TIpcMessage = record
    Kind: UInt32;
    Payload: string;
  end;

  TIpcParseResult = record
  strict private
    FOk: Boolean;
    FReason: TIpcParseFailure;
    FMessage: TIpcMessage;
  public
    class function Ok(const AMessage: TIpcMessage): TIpcParseResult; static;
    class function Fail(AReason: TIpcParseFailure): TIpcParseResult; static;
    property IsOk: Boolean read FOk;
    property Reason: TIpcParseFailure read FReason;
    property Message: TIpcMessage read FMessage;
  end;

const
  IPC_VERSION = 1;
  IPC_HEADER_SIZE = 13; { 4 magic + 1 version + 4 kind + 4 length }

{ Serialises a message to a frame. }
function EncodeMessage(const AMessage: TIpcMessage): TBytes;

{ Parses a frame. Never raises: a malformed buffer comes back as a failure with
  a reason, because the bytes arrive from another process and cannot be
  trusted. }
function DecodeMessage(const ABytes: TBytes): TIpcParseResult;

function ParseFailureToString(AReason: TIpcParseFailure): string;

implementation

{ Under FPC's Delphi mode, `string` is AnsiString while Delphi's is
  UnicodeString, so the UTF8Encode / UTF8ToString round trip that is lossless
  on Delphi trips FPC's implicit-cast warnings. The wire is always UTF-8 and
  the round trip is pinned by the non-ASCII test, so the warning is noise here
  and is silenced only for this unit. }
{$IFDEF FPC}
  {$WARN IMPLICIT_STRING_CAST OFF}
  {$WARN IMPLICIT_STRING_CAST_LOSS OFF}
{$ENDIF}

const
  Magic: array[0..3] of Byte = (Ord('W'), Ord('I'), Ord('P'), Ord('C'));

{ TIpcParseResult }

class function TIpcParseResult.Ok(const AMessage: TIpcMessage): TIpcParseResult;
begin
  Result.FOk := True;
  Result.FReason := pfNone;
  Result.FMessage := AMessage;
end;

class function TIpcParseResult.Fail(AReason: TIpcParseFailure): TIpcParseResult;
begin
  Result.FOk := False;
  Result.FReason := AReason;
  Result.FMessage.Kind := 0;
  Result.FMessage.Payload := '';
end;

procedure PutU32(var ABytes: TBytes; AOffset: Integer; AValue: UInt32);
begin
  ABytes[AOffset]     := Byte(AValue         and $FF);
  ABytes[AOffset + 1] := Byte((AValue shr 8)  and $FF);
  ABytes[AOffset + 2] := Byte((AValue shr 16) and $FF);
  ABytes[AOffset + 3] := Byte((AValue shr 24) and $FF);
end;

function GetU32(const ABytes: TBytes; AOffset: Integer): UInt32;
begin
  Result := UInt32(ABytes[AOffset]) or
            (UInt32(ABytes[AOffset + 1]) shl 8) or
            (UInt32(ABytes[AOffset + 2]) shl 16) or
            (UInt32(ABytes[AOffset + 3]) shl 24);
end;

function EncodeMessage(const AMessage: TIpcMessage): TBytes;
var
  Utf8: UTF8String;
  PayloadLen, I: Integer;
begin
  Result := nil;
  { UTF8Encode / UTF8ToString are the portable, lossless pair for moving text
    over a byte transport. TEncoding would work on Delphi but drags in implicit
    AnsiString/UnicodeString conversions under FPC that can lose non-ASCII. }
  Utf8 := UTF8Encode(AMessage.Payload);
  PayloadLen := Length(Utf8);

  SetLength(Result, IPC_HEADER_SIZE + PayloadLen);
  Result[0] := Magic[0];
  Result[1] := Magic[1];
  Result[2] := Magic[2];
  Result[3] := Magic[3];
  Result[4] := IPC_VERSION;
  PutU32(Result, 5, AMessage.Kind);
  PutU32(Result, 9, UInt32(PayloadLen));

  for I := 1 to PayloadLen do
    Result[IPC_HEADER_SIZE + I - 1] := Byte(Utf8[I]);
end;

function DecodeMessage(const ABytes: TBytes): TIpcParseResult;
var
  Len: Integer;
  Msg: TIpcMessage;
  Utf8: UTF8String;
  DeclaredLen: UInt32;
  I: Integer;
begin
  Len := Length(ABytes);

  if Len < IPC_HEADER_SIZE then
    Exit(TIpcParseResult.Fail(pfTooShort));

  if (ABytes[0] <> Magic[0]) or (ABytes[1] <> Magic[1]) or
     (ABytes[2] <> Magic[2]) or (ABytes[3] <> Magic[3]) then
    Exit(TIpcParseResult.Fail(pfBadMagic));

  if ABytes[4] <> IPC_VERSION then
    Exit(TIpcParseResult.Fail(pfUnsupportedVersion));

  DeclaredLen := GetU32(ABytes, 9);

  { The declared length must match the bytes actually present. A frame that
    claims more payload than it carries is the classic way a naive reader walks
    off the end of the buffer; here it is a clean rejection. }
  if UInt32(Len - IPC_HEADER_SIZE) <> DeclaredLen then
    Exit(TIpcParseResult.Fail(pfLengthMismatch));

  Msg.Kind := GetU32(ABytes, 5);

  SetLength(Utf8, DeclaredLen);
  for I := 1 to Integer(DeclaredLen) do
    Utf8[I] := AnsiChar(ABytes[IPC_HEADER_SIZE + I - 1]);

  Msg.Payload := UTF8ToString(Utf8);
  Result := TIpcParseResult.Ok(Msg);
end;

function ParseFailureToString(AReason: TIpcParseFailure): string;
begin
  case AReason of
    pfNone:                Result := 'none';
    pfTooShort:            Result := 'buffer shorter than the header';
    pfBadMagic:            Result := 'wrong magic bytes';
    pfUnsupportedVersion:  Result := 'unsupported version';
    pfLengthMismatch:      Result := 'declared length does not match the buffer';
  else
    Result := 'unspecified';
  end;
end;

end.
