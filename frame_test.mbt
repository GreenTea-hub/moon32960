// frame_test.mbt
///|
/// 由 `moon run cmd/main -- case login` 生成的车辆登入帧，数据单元 37 字节，
/// 末尾一字节为 BCC 校验码（0x2a）。
const GOLDEN_LOGIN_HEX : String = "232301014c47574546344135364d463132333435360100251a0b12091e000001383938363036323031383030303132333435363701074241542d4130312a"

///|
test "解码黄金登入帧" {
  let frame = @moon32960.decode_frame(@moon32960.from_hex(GOLDEN_LOGIN_HEX))
  assert_eq(frame.command.name(), "vehicle-login")
  assert_eq(frame.vin, "LGWEF4A56MF123456")
  assert_eq(frame.payload.length(), 37)
  let login = @moon32960.VehicleLogin::decode(frame.payload[:])
  assert_eq(login.sequence, 1)
  assert_eq(login.iccid, "89860620180001234567")
  assert_eq(login.storage_codes.length(), 1)
  assert_eq(login.storage_codes[0], "BAT-A01")
  assert_eq(login.code_len, 7)
}

///|
test "编码是解码的逆运算" {
  let frame = @moon32960.decode_frame(@moon32960.from_hex(GOLDEN_LOGIN_HEX))
  assert_eq(frame.hex(), GOLDEN_LOGIN_HEX)
}

///|
test "校验码错误被拒绝" {
  // 把最后一字节 0x2a 改成 0x2b
  let tampered = GOLDEN_LOGIN_HEX[0:GOLDEN_LOGIN_HEX.length() - 2].to_owned() + "2b"
  try @moon32960.decode_frame(@moon32960.from_hex(tampered)) catch {
    err => match err {
      @moon32960.FrameError::BadChecksum(expected~, actual~) => {
        assert_eq(expected, 43)
        assert_eq(actual, 42)
      }
      _ => fail("期望 BadChecksum")
    }
  } noraise {
    _ => fail("篡改校验码后仍解码成功")
  }
}

///|
test "声明长度与实际不符被拒绝" {
  // 数据单元长度字段位于偏移 22，原值为 0x0025
  let tampered = GOLDEN_LOGIN_HEX[0:44].to_owned() + "0026" + GOLDEN_LOGIN_HEX[48:].to_owned()
  try @moon32960.decode_frame(@moon32960.from_hex(tampered)) catch {
    err => match err {
      @moon32960.FrameError::BadLength(expected~, ..) => assert_eq(expected, 38)
      _ => fail("期望 BadLength")
    }
  } noraise {
    _ => fail("长度不符的帧仍解码成功")
  }
}

///|
test "起始符错误被拒绝" {
  let tampered = "00" + GOLDEN_LOGIN_HEX[2:GOLDEN_LOGIN_HEX.length()].to_owned()
  try @moon32960.decode_frame(@moon32960.from_hex(tampered)) catch {
    err => match err {
      @moon32960.FrameError::InvalidStart(_) => ()
      _ => fail("期望 InvalidStart")
    }
  } noraise {
    _ => fail("起始符错误的帧仍解码成功")
  }
}

///|
test "空帧长度不足被拒绝" {
  try @moon32960.decode_frame(Bytes::new(0)) catch {
    err => match err {
      @moon32960.FrameError::TooShort(needed~, actual~) => {
        assert_eq(needed, 25)
        assert_eq(actual, 0)
      }
      _ => fail("期望 TooShort")
    }
  } noraise {
    _ => fail("空帧仍解码成功")
  }
}

///|
test "应答帧数据单元为空且校验码正确" {
  let request = @moon32960.decode_frame(@moon32960.from_hex(GOLDEN_LOGIN_HEX))
  let response = @moon32960.response_frame(request, @moon32960.ResponseFlag::Success)
  let wire = response.hex()
  assert_eq(
    wire,
    "232301014c47574546344135364d4631323334353601000024",
  )
  let decoded = @moon32960.decode_frame(@moon32960.from_hex(wire))
  assert_eq(decoded.payload.length(), 0)
}

///|
test "BCC 覆盖命令单元到数据单元末字节" {
  // 起始符不参与校验：对同一帧从偏移 2 开始的异或值应与末尾校验码一致
  let frame = @moon32960.decode_frame(@moon32960.from_hex(GOLDEN_LOGIN_HEX))
  let body = @moon32960.encode_frame(frame)
  let checksum = body[body.length() - 1].to_int()
  assert_eq(checksum, @moon32960.bcc(body[2:body.length() - 1]).to_int())
}
