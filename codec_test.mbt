// codec_test.mbt
///|
test "hex helpers round-trip" {
  let bytes = @moon32960.from_hex("23 23 01 01")
  assert_eq(@moon32960.to_hex(bytes), "23230101")
}

///|
test "hex parser rejects odd length input" {
  try @moon32960.from_hex("abc") catch {
    err => {
      match err {
        @moon32960.FrameError::Payload(_) => ()
        _ => fail("unexpected error variant")
      }
    }
  } noraise {
    _ => fail("expected a Payload error")
  }
}

///|
test "vin accepts a valid identifier" {
  @moon32960.validate_vin("LGWEF4A56MF123456")
}

///|
test "vin rejects the wrong length" {
  try @moon32960.validate_vin("SHORTVIN") catch {
    err => {
      match err {
        @moon32960.FrameError::BadVin(_) => ()
        _ => fail("unexpected error variant")
      }
    }
  } noraise {
    _ => fail("expected a BadVin error")
  }
}

///|
test "vin rejects the excluded letters I O Q" {
  try @moon32960.validate_vin("LGWEF4A56MF12345I") catch {
    err => {
      match err {
        @moon32960.FrameError::BadVin(_) => ()
        _ => fail("unexpected error variant")
      }
    }
  } noraise {
    _ => fail("expected a BadVin error")
  }
}

///|
test "time encodes and decodes six bytes" {
  let time = @moon32960.Time::new(
    year=2026,
    month=11,
    day=16,
    hour=15,
    minute=0,
    second=0,
  )
  let bytes = time.to_bytes()
  assert_eq(@moon32960.to_hex(bytes), "1a0b100f0000")
  let decoded = @moon32960.Time::from_bytes(bytes[:])
  assert_eq(decoded.year, 2026)
  assert_eq(decoded.month, 11)
  assert_eq(decoded.day, 16)
  assert_eq(decoded.hour, 15)
}

///|
test "time rejects an out-of-range month" {
  try
    @moon32960.Time::new(
      year=2026,
      month=13,
      day=16,
      hour=15,
      minute=0,
      second=0,
    )
  catch {
    err => {
      match err {
        @moon32960.FrameError::BadTime(_) => ()
        _ => fail("unexpected error variant")
      }
    }
  } noraise {
    _ => fail("expected a BadTime error")
  }
}
