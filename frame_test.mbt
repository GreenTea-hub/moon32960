// frame_test.mbt
///|
/// 由 `moon run cmd/main -- case login` 生成的车辆登入命令包：
/// 应答标志 0xFE 表示命令包，数据单元 37 字节，末尾一字节为 BCC。
const GOLDEN_LOGIN_HEX : String = "232301fe4c47574546344135364d463132333435360100251a0b12091e000001383938363036323031383030303132333435363701074241542d413031d5"

///|
/// 平台对该命令包的应答：应答标志 0x01，数据单元为空，加密方式回到 0x01。
const GOLDEN_LOGIN_ACK_HEX : String = "232301014c47574546344135364d4631323334353601000024"

///|
/// 由 `moon run cmd/main -- case encrypted` 生成的 AES128 加密上报帧：
/// 加密方式 0x03，数据单元 48 字节密文（37 字节明文经 PKCS#7 填充到 48）。
const GOLDEN_ENCRYPTED_HEX : String = "232302fe4c47574546344135364d463132333435360300304c2229bb4dc2e406c63d054d69f47cbc725f02e50d74f0e58f4b78c3309bcaf466c0da206dbc7e84c0580854cd83ea3af4"

///|
const AES_KEY_HEX : String = "000102030405060708090a0b0c0d0e0f"

///|
test "解码黄金登入命令包" {
  let frame = @moon32960.decode_frame(@moon32960.from_hex(GOLDEN_LOGIN_HEX))
  assert_eq(frame.command.name(), "vehicle-login")
  assert_false(@moon32960.is_response_packet(frame))
  assert_eq(frame.vin, "LGWEF4A56MF123456")
  assert_eq(frame.payload.length(), 37)
  let login = @moon32960.VehicleLogin::decode(frame.payload[:])
  assert_eq(login.sequence, 1)
  assert_eq(login.iccid, "89860620180001234567")
  assert_eq(login.storage_codes[0], "BAT-A01")
}

///|
test "编码是解码的逆运算" {
  let frame = @moon32960.decode_frame(@moon32960.from_hex(GOLDEN_LOGIN_HEX))
  assert_eq(frame.hex(), GOLDEN_LOGIN_HEX)
}

///|
test "附录B应答保留请求数据单元，只改应答标志" {
  let request = @moon32960.decode_frame(@moon32960.from_hex(GOLDEN_LOGIN_HEX))
  let response = @moon32960.build_response(
    request,
    @moon32960.ResponseFlag::Success,
  )
  // B.3.3.2：其余报文内容与主动发送报文一致
  assert_eq(response.payload.length(), request.payload.length())
  assert_eq(@moon32960.to_hex(response.payload), @moon32960.to_hex(request.payload))
  let decoded = @moon32960.decode_frame(@moon32960.from_hex(response.hex()))
  assert_true(@moon32960.is_response_packet(decoded))
  match decoded.response {
    @moon32960.ResponseFlag::Success => ()
    _ => fail("应答标志应为 0x01")
  }
}

///|
test "应答报文时间替换数据单元前 6 字节" {
  let request = @moon32960.decode_frame(@moon32960.from_hex(GOLDEN_LOGIN_HEX))
  let answer_time = try! @moon32960.Time::new(
    year=2026, month=11, day=18, hour=9, minute=32, second=0,
  )
  let response = @moon32960.build_response(
    request,
    @moon32960.ResponseFlag::Success,
    answer_time=Some(answer_time),
  )
  assert_eq(response.payload.length(), 37)
  assert_eq(@moon32960.to_hex(response.payload[0:6]), "1a0b12092000")
  // 其余字节保持不变
  assert_eq(
    @moon32960.to_hex(response.payload[6:37]),
    @moon32960.to_hex(request.payload[6:37]),
  )
}

///|
test "TimeOnly 形态只保留 6 字节报文时间" {
  let request = @moon32960.decode_frame(@moon32960.from_hex(GOLDEN_LOGIN_HEX))
  let response = @moon32960.build_response(
    request,
    @moon32960.ResponseFlag::VinDuplicate,
    shape=@moon32960.TimeOnly,
  )
  assert_eq(response.payload.length(), 6)
  assert_eq(@moon32960.to_hex(response.payload), "1a0b12091e00")
}

///|
test "EmptyPayload 形态数据单元为空" {
  let request = @moon32960.decode_frame(@moon32960.from_hex(GOLDEN_LOGIN_HEX))
  let response = @moon32960.build_response(
    request,
    @moon32960.ResponseFlag::Success,
    shape=@moon32960.EmptyPayload,
  )
  assert_eq(response.payload.length(), 0)
  assert_eq(response.hex(), GOLDEN_LOGIN_ACK_HEX)
}

///|
test "加密帧无密钥时拒绝，不当明文解析" {
  try @moon32960.decode_frame(@moon32960.from_hex(GOLDEN_ENCRYPTED_HEX)) catch {
    err => match err {
      @moon32960.FrameError::CryptoUnavailable(mode~, ..) => assert_eq(mode, "AES128")
      _ => fail("期望 CryptoUnavailable")
    }
  } noraise {
    _ => fail("无密钥时加密帧仍被解析")
  }
}

///|
test "加密帧带密钥可解密回明文" {
  let key = @moon32960.KeyMaterial::Aes128Ecb(key=@moon32960.from_hex(AES_KEY_HEX))
  let frame = @moon32960.decode_frame(@moon32960.from_hex(GOLDEN_ENCRYPTED_HEX), key~)
  assert_eq(frame.payload.length(), 37)
  let telemetry = @moon32960.Telemetry::decode(frame.payload[:])
  assert_eq(telemetry.items.length(), 2)
  assert_eq(telemetry.time.minute, 31)
}

///|
test "加密后组帧与黄金密文一致" {
  let key = @moon32960.KeyMaterial::Aes128Ecb(key=@moon32960.from_hex(AES_KEY_HEX))
  let frame = @moon32960.decode_frame(@moon32960.from_hex(GOLDEN_ENCRYPTED_HEX), key~)
  assert_eq(frame.hex(key~), GOLDEN_ENCRYPTED_HEX)
}

///|
test "校验码错误被拒绝" {
  let tampered = GOLDEN_LOGIN_HEX[0:GOLDEN_LOGIN_HEX.length() - 2].to_owned() + "d4"
  try @moon32960.decode_frame(@moon32960.from_hex(tampered)) catch {
    err => match err {
      @moon32960.FrameError::BadChecksum(..) => ()
      _ => fail("期望 BadChecksum")
    }
  } noraise {
    _ => fail("篡改校验码后仍解码成功")
  }
}

///|
test "声明长度与实际不符被拒绝" {
  let tampered = GOLDEN_LOGIN_HEX[0:44].to_owned() + "0026" +
    GOLDEN_LOGIN_HEX[48:].to_owned()
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
test "BCC 覆盖命令单元到数据单元末字节" {
  let frame = @moon32960.decode_frame(@moon32960.from_hex(GOLDEN_LOGIN_HEX))
  let body = @moon32960.encode_frame(frame)
  let checksum = body[body.length() - 1].to_int()
  assert_eq(checksum, @moon32960.bcc(body[2:body.length() - 1]).to_int())
}
