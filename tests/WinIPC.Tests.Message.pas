{
  WinIPC — portable framing tests.

  These run on both Delphi and Free Pascal and are the CI coverage on Linux,
  where the WM_COPYDATA transport cannot be built. Framing is where an
  off-by-one or a trust-the-length bug would live, so it is what is pinned
  here.
}
unit WinIPC.Tests.Message;

{$IFDEF FPC}
  {$MODE DELPHI}
  {$H+}
{$ENDIF}

interface

uses
  WinIPC.Testing;

procedure RunMessageTests(ARunner: TTestRunner);

implementation

uses
  {$IFDEF FPC}SysUtils{$ELSE}System.SysUtils{$ENDIF},
  WinIPC.Message;

function Msg(AKind: UInt32; const APayload: string): TIpcMessage;
begin
  Result.Kind := AKind;
  Result.Payload := APayload;
end;

procedure TestRoundTrip(ARunner: TTestRunner);
var
  Original: TIpcMessage;
  Parsed: TIpcParseResult;
begin
  ARunner.Suite('Round trip');

  Original := Msg(7, 'hello, other process');
  Parsed := DecodeMessage(EncodeMessage(Original));
  ARunner.IsTrue('a normal message decodes', Parsed.IsOk);
  ARunner.AreEqual('kind survives', 7, Integer(Parsed.Message.Kind));
  ARunner.AreEqual('payload survives', 'hello, other process',
    Parsed.Message.Payload);

  Original := Msg(0, '');
  Parsed := DecodeMessage(EncodeMessage(Original));
  ARunner.IsTrue('an empty payload is valid', Parsed.IsOk);
  ARunner.AreEqual('empty payload survives', '', Parsed.Message.Payload);

  { UTF-8 must survive the byte round trip, since the transport is byte-based
    and the payload is text. }
  Original := Msg(1, 'acentuação e emoji ok');
  Parsed := DecodeMessage(EncodeMessage(Original));
  ARunner.AreEqual('non-ASCII payload survives', Original.Payload,
    Parsed.Message.Payload);

  Original := Msg(High(UInt32), 'max kind');
  Parsed := DecodeMessage(EncodeMessage(Original));
  ARunner.IsTrue('the maximum kind value survives',
    Parsed.Message.Kind = High(UInt32));
end;

procedure TestRejection(ARunner: TTestRunner);
var
  Good, Bad: TBytes;
  Parsed: TIpcParseResult;
begin
  ARunner.Suite('Rejecting bad frames');

  SetLength(Bad, 4);
  Parsed := DecodeMessage(Bad);
  ARunner.IsTrue('a buffer shorter than the header is rejected', not Parsed.IsOk);
  ARunner.AreEqual('reported as too short',
    ParseFailureToString(pfTooShort), ParseFailureToString(Parsed.Reason));

  Good := EncodeMessage(Msg(1, 'payload'));

  Bad := Copy(Good, 0, Length(Good));
  Bad[0] := Ord('X');
  Parsed := DecodeMessage(Bad);
  ARunner.AreEqual('wrong magic is rejected',
    ParseFailureToString(pfBadMagic), ParseFailureToString(Parsed.Reason));

  Bad := Copy(Good, 0, Length(Good));
  Bad[4] := 99;
  Parsed := DecodeMessage(Bad);
  ARunner.AreEqual('an unsupported version is rejected',
    ParseFailureToString(pfUnsupportedVersion),
    ParseFailureToString(Parsed.Reason));

  { A frame claiming more payload than it carries is the buffer-overrun trap.
    Truncate the payload but leave the declared length untouched. }
  Bad := Copy(Good, 0, Length(Good) - 3);
  Parsed := DecodeMessage(Bad);
  ARunner.AreEqual('a length longer than the buffer is rejected',
    ParseFailureToString(pfLengthMismatch),
    ParseFailureToString(Parsed.Reason));

  { And a frame carrying more than it declares is equally wrong. }
  Bad := Copy(Good, 0, Length(Good));
  SetLength(Bad, Length(Bad) + 3);
  Parsed := DecodeMessage(Bad);
  ARunner.AreEqual('a length shorter than the buffer is rejected',
    ParseFailureToString(pfLengthMismatch),
    ParseFailureToString(Parsed.Reason));
end;

procedure RunMessageTests(ARunner: TTestRunner);
begin
  TestRoundTrip(ARunner);
  TestRejection(ARunner);
end;

end.
