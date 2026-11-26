// frame_test.mbt
///|
/// 2025 版登入命令包：起始符 $$(0x24 0x24)、命令 0x01、应答标志 0xFE、37 字节数据单元。
const GOLDEN_LOGIN_HEX : String = "242401fe4c47574546344135364d463132333435360100361a0b19091e000001383938363036323031383030303132333435363701014c4650424154323032353131323530303030303030303031ff"

///|
/// 平台应答：应答标志 0x01，数据单元只保留 6 字节报文时间。
const GOLDEN_ACK_HEX : String = "242401014c47574546344135364d463132333435360100061a0b19091e003d"

///|
test "解码 2025 版登入命令包" {
  let frame = @moon32960.decode_frame(@moon32960.from_hex(GOLDEN_LOGIN_HEX))
  assert_eq(frame.version.name(), "GB/T 32960.3-2025")
  assert_eq(frame.command.name(), "vehicle-login")
  assert_eq(frame.vin, "LGWEF4A56MF123456")
  assert_eq(frame.payload.length(), 54)
  let login = @moon32960.VehicleLogin::decode(frame.payload[:])
  assert_eq(login.iccid, "89860620180001234567")
  // 2025 表 6：电池管理系统数 + 每系统包个数 + 24 位包编码
  assert_eq(login.systems.length(), 1)
  assert_eq(login.systems[0].pack_count, 1)
  assert_eq(login.systems[0].pack_codes[0], "LFPBAT202511250000000001")
}

///|
test "编码是解码的逆运算" {
  let frame = @moon32960.decode_frame(@moon32960.from_hex(GOLDEN_LOGIN_HEX))
  assert_eq(frame.hex(), GOLDEN_LOGIN_HEX)
}

///|
test "应答只保留报文时间" {
  let request = @moon32960.decode_frame(@moon32960.from_hex(GOLDEN_LOGIN_HEX))
  let response = @moon32960.build_response(request, @moon32960.ResponseFlag::Success)
  assert_eq(response.payload.length(), 6)
  assert_eq(response.hex(), GOLDEN_ACK_HEX)
}

///|
test "起始符区分协议版本" {
  let request = @moon32960.decode_frame(@moon32960.from_hex(GOLDEN_LOGIN_HEX))
  let v2016 = @moon32960.Frame::new(
    version=@moon32960.FrameVersion::V2016,
    command=request.command,
    response=request.response,
    vin=request.vin,
    encryption=request.encryption,
    payload=request.payload,
  )
  let wire = try! v2016.hex()
  assert_true(wire[:4] == "2323")
  let frame = @moon32960.decode_frame(@moon32960.from_hex(wire))
  assert_eq(frame.version.name(), "GB/T 32960.3-2016")
  try @moon32960.decode_frame(@moon32960.from_hex(wire), expect_version=@moon32960.FrameVersion::V2025) catch {
    _ => ()
  } noraise {
    _ => fail("应识别出 2016 版起始符")
  }
}

///|
test "校验码错误被拒绝" {
  let tampered = GOLDEN_LOGIN_HEX[0:GOLDEN_LOGIN_HEX.length() - 2].to_owned() + "dd"
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
test "长度不符被拒绝" {
  let tampered = GOLDEN_LOGIN_HEX[0:44].to_owned() + "0026" +
    GOLDEN_LOGIN_HEX[48:].to_owned()
  try @moon32960.decode_frame(@moon32960.from_hex(tampered)) catch {
    err => match err {
      @moon32960.FrameError::BadLength(..) => ()
      _ => fail("期望 BadLength")
    }
  } noraise {
    _ => fail("长度不符仍解码成功")
  }
}
