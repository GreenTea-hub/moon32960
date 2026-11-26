// fix_test.mbt
///|
fn t26() -> @moon32960.Time {
  try! @moon32960.Time::new(year=2026, month=11, day=26, hour=9, minute=30, second=0)
}

///|
test "挡位按附录A.1位定义解析" {
  // Bit0=0 有效、Bit1=1 有驱动力、Bit2=0 无制动力、Bit4~7=0100(4 挡)
  let four : @moon32960.WholeVehicle = {
    vehicle_status: 0x01,
    charge_status: 0x03,
    operation_mode: 0x01,
    speed_raw: 0,
    odometer_raw: 0,
    total_voltage_raw: 0,
    total_current_raw: 0,
    soc: 50,
    dc_dc_status: 0x01,
    gear: 0x42, // 0100 0010 → 挡位 4、有驱动力、有效
    insulation_raw: 0,
  }
  assert_true(four.gear_valid())
  assert_true(four.gear_has_drive_force())
  assert_false(four.gear_has_brake_force())
  assert_eq(four.gear_code(), 4)
  assert_eq(four.gear_name(), "4 挡")
  // 倒挡：1101 0000
  let reverse : @moon32960.WholeVehicle = {
    vehicle_status: 0x01,
    charge_status: 0x03,
    operation_mode: 0x01,
    speed_raw: 0,
    odometer_raw: 0,
    total_voltage_raw: 0,
    total_current_raw: 0,
    soc: 50,
    dc_dc_status: 0x01,
    gear: 0xd0,
    insulation_raw: 0,
  }
  assert_eq(reverse.gear_name(), "倒挡")
  // 无效位
  let invalid : @moon32960.WholeVehicle = {
    vehicle_status: 0x01,
    charge_status: 0x03,
    operation_mode: 0x01,
    speed_raw: 0,
    odometer_raw: 0,
    total_voltage_raw: 0,
    total_current_raw: 0,
    soc: 50,
    dc_dc_status: 0x01,
    gear: 0x01,
    insulation_raw: 0,
  }
  assert_false(invalid.gear_valid())
  assert_eq(invalid.gear_name(), "挡位无效")
}

///|
test "唯一识别码允许非 VIN 的自定义编码" {
  // 帧层只要求 17 字节可打印 ASCII
  @moon32960.validate_identifier("PLATFRM0000000001")
  @moon32960.validate_identifier("CUSTOM-CODE-0001!")
  // 严格 VIN 校验会拒绝含 O 的编码
  try @moon32960.validate_vin("PLATFORM000000001") catch {
    _ => ()
  } noraise {
    _ => fail("含 O 的字符串不应通过严格 VIN 校验")
  }
}

///|
test "非 VIN 识别码的帧可正常编解码" {
  let frame : @moon32960.Frame = {
    version: @moon32960.FrameVersion::V2025,
    command: @moon32960.Command::RealtimeReport,
    response: @moon32960.Command,
    vin: "CUSTOM-CODE-0001!",
    encryption: @moon32960.Encryption::Plain,
    payload: Bytes::new(0),
  }
  let wire = try! frame.hex()
  let decoded = try! @moon32960.decode_frame(@moon32960.from_hex(wire))
  assert_eq(decoded.vin, "CUSTOM-CODE-0001!")
}

///|
test "登入时识别码必须是 VIN" {
  let gateway = @moon32960.Gateway::new()
  let frame : @moon32960.Frame = {
    version: @moon32960.FrameVersion::V2025,
    command: @moon32960.Command::VehicleLogin,
    response: @moon32960.Command,
    vin: "CUSTOM-CODE-0001!",
    encryption: @moon32960.Encryption::Plain,
    payload: try!
      @moon32960.VehicleLogin::new(
        time=t26(),
        sequence=1,
        iccid="89860620180001234567",
        systems=[],
      ).to_bytes(),
  }
  // 表 B.1 车端识别码必须是 VIN，非法则拒绝并应答 0x02
  let handled = gateway.handle(frame)
  assert_eq(handled.outcome.name(), "rejected")
  assert_true(handled.response is Some(_))
}

///|
test "登出流水号须与登入一致" {
  let session = try! @moon32960.TerminalSession::new("LGWEF4A56MF123456")
  let login = try!
    @moon32960.VehicleLogin::new(
      time=t26(),
      sequence=7,
      iccid="89860620180001234567",
      systems=[],
    )
  session.login(login)
  try session.logout(sequence=8) catch {
    _ => ()
  } noraise {
    _ => fail("流水号不一致应被拒绝")
  }
  session.logout(sequence=7)
  assert_false(session.is_online())
}

///|
test "参数长度只对表B.8已定义项给出宽度" {
  assert_eq(@moon32960.param_len(0x01).unwrap(), 2)
  assert_eq(@moon32960.param_len(0x08).unwrap(), 5)
  // 0x09 起为预留、0x80~0xFE 用户自定义，标准未给宽度
  assert_true(@moon32960.param_len(0x09) is None)
  assert_true(@moon32960.param_len(0x40) is None)
}
