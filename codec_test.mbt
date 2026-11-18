// codec_test.mbt
///|
test "时间按 6 字节年月日时分秒编码" {
  let time = @moon32960.Time::new(
    year=2026,
    month=11,
    day=18,
    hour=9,
    minute=30,
    second=0,
  )
  assert_eq(@moon32960.to_hex(time.to_bytes()), "1a0b12091e00")
  let decoded = @moon32960.Time::from_bytes(time.to_bytes()[:])
  assert_eq(decoded.year, 2026)
  assert_eq(decoded.hour, 9)
  assert_eq(decoded.to_display(), "2026-11-18 09:30:00")
}

///|
test "时间字段越界被拒绝" {
  try
    @moon32960.Time::new(
      year=2026,
      month=13,
      day=1,
      hour=0,
      minute=0,
      second=0,
    )
  catch {
    err => match err {
      @moon32960.FrameError::BadTime(_) => ()
      _ => fail("期望 BadTime")
    }
  } noraise {
    _ => fail("月份 13 仍被接受")
  }
}

///|
test "VIN 排除 I O Q" {
  try @moon32960.validate_vin("LGWEF4A56MF12345I") catch {
    err => match err {
      @moon32960.FrameError::BadVin(_) => ()
      _ => fail("期望 BadVin")
    }
  } noraise {
    _ => fail("含 I 的 VIN 仍被接受")
  }
}

///|
test "VIN 长度必须为 17" {
  try @moon32960.validate_vin("SHORT") catch {
    err => match err {
      @moon32960.FrameError::BadVin(_) => ()
      _ => fail("期望 BadVin")
    }
  } noraise {
    _ => fail("长度不足的 VIN 仍被接受")
  }
}

///|
test "ICCID 必须为 20 位数字" {
  @moon32960.validate_iccid("89860620180001234567")
  try @moon32960.validate_iccid("8986062018000123456A") catch {
    err => match err {
      @moon32960.FrameError::BadIccid(_) => ()
      _ => fail("期望 BadIccid")
    }
  } noraise {
    _ => fail("含字母的 ICCID 仍被接受")
  }
}

///|
test "十六进制往返与奇数长度拒绝" {
  let bytes = @moon32960.from_hex("23 23 01 01")
  assert_eq(@moon32960.to_hex(bytes), "23230101")
  try @moon32960.from_hex("abc") catch {
    err => match err {
      @moon32960.FrameError::Payload(_) => ()
      _ => fail("期望 Payload")
    }
  } noraise {
    _ => fail("奇数长度十六进制仍被接受")
  }
}

///|
test "大端读取 WORD 与 DWORD" {
  let bytes = @moon32960.from_hex("0025 0001e240")
  assert_eq(@moon32960.u16_be(bytes[:], 0), 37)
  assert_eq(@moon32960.u32_be(bytes[:], 2), 123456)
}
