// frame_test.mbt
///|
/// Golden frame from the protocol notes: a plaintext vehicle-login frame with
/// an empty payload.
const GOLDEN_LOGIN_HEX : String = "23230101475245454e313233343536373839303132010000"

///|
/// Same header with a corrupted start marker.
const BAD_START_HEX : String = "00230101475245454e313233343536373839303132010000"

///|
/// Header that declares a one-byte payload but carries none.
const BAD_LENGTH_HEX : String = "23230101475245454e313233343536373839303132010001"

///|
test "decode a golden vehicle-login frame" {
  let wire = @moon32960.from_hex(GOLDEN_LOGIN_HEX)
  let frame = @moon32960.decode_frame(wire)
  assert_eq(frame.command.name(), "vehicle-login")
  assert_eq(frame.vin, "GREEN123456789012")
  assert_eq(frame.encryption.name(), "plain")
  assert_eq(frame.payload.length(), 0)
}

///|
test "encode is the inverse of decode" {
  let wire = @moon32960.from_hex(GOLDEN_LOGIN_HEX)
  let frame = @moon32960.decode_frame(wire)
  let again = @moon32960.encode_frame(frame)
  assert_eq(@moon32960.to_hex(again), GOLDEN_LOGIN_HEX)
}

///|
test "payload survives a full round trip" {
  let vin = "LGWEF4A56MF123456"
  let payload = @moon32960.from_hex("01020304")
  let frame = @moon32960.Frame::new(
    command=@moon32960.Command::RealtimeReport,
    response=@moon32960.ResponseFlag::Success,
    vin~,
    encryption=@moon32960.Encryption::Plain,
    payload~,
  )
  let wire = @moon32960.encode_frame(frame)
  let decoded = @moon32960.decode_frame(wire)
  assert_eq(decoded.vin, vin)
  assert_eq(decoded.command.name(), "realtime-report")
  assert_eq(@moon32960.to_hex(decoded.payload), "01020304")
}

///|
test "decode rejects a frame that is too short" {
  try @moon32960.decode_frame(@moon32960.from_hex("")) catch {
    err => {
      match err {
        @moon32960.FrameError::TooShort(needed~, actual~) => {
          assert_eq(needed, 24)
          assert_eq(actual, 0)
        }
        _ => fail("unexpected error variant")
      }
    }
  } noraise {
    _ => fail("expected a TooShort error")
  }
}

///|
test "decode rejects a bad start marker" {
  try @moon32960.decode_frame(@moon32960.from_hex(BAD_START_HEX)) catch {
    err => {
      match err {
        @moon32960.FrameError::InvalidStart(_) => ()
        _ => fail("unexpected error variant")
      }
    }
  } noraise {
    _ => fail("expected an InvalidStart error")
  }
}

///|
test "decode rejects a payload length mismatch" {
  try @moon32960.decode_frame(@moon32960.from_hex(BAD_LENGTH_HEX)) catch {
    err => {
      match err {
        @moon32960.FrameError::BadLength(expected~, actual~) => {
          assert_eq(expected, 1)
          assert_eq(actual, 0)
        }
        _ => fail("unexpected error variant")
      }
    }
  } noraise {
    _ => fail("expected a BadLength error")
  }
}
