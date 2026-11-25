// gateway_test.mbt
///|
fn login_frame(vin : String, sequence~ : Int32 = 1) -> @moon32960.Frame {
  try! {
    let login = @moon32960.VehicleLogin::new(
      time=sample_time(hour=9, minute=30),
      sequence~,
      iccid="89860620180001234567",
      storage_codes=["BAT-A01"],
      code_len=7,
    )
    @moon32960.Frame::new(
      command=@moon32960.Command::VehicleLogin,
      response=@moon32960.Command,
      vin~,
      encryption=@moon32960.Encryption::Plain,
      payload=login.to_bytes(),
    )
  }
}

///|
fn telemetry_payload(minute~ : Int32) -> Bytes {
  let vehicle : @moon32960.WholeVehicle = {
    vehicle_status: 0x01,
    charge_status: 0x02,
    operation_mode: 0x01,
    speed_raw: 623,
    odometer_raw: 123456,
    total_voltage_raw: 3600,
    total_current_raw: 30100,
    soc: 78,
    dc_dc_status: 0x01,
    gear: 0x04,
    insulation_raw: 1200,
    accelerator_raw: 30,
    brake_status: 0x01,
  }
  try! {
    let telemetry = @moon32960.Telemetry::new(
      time=sample_time(minute~),
      items=[@moon32960.ReportItem::Vehicle(vehicle)],
    )
    telemetry.to_bytes()
  }
}

///|
fn report_frame(
  vin : String,
  command~ : @moon32960.Command,
  minute~ : Int32,
) -> @moon32960.Frame {
  @moon32960.Frame::new(
    command~,
    response=@moon32960.Command,
    vin~,
    encryption=@moon32960.Encryption::Plain,
    payload=telemetry_payload(minute~),
  )
}

///|
fn flag_of(handled : @moon32960.Handled) -> @moon32960.ResponseFlag? {
  match handled.response {
    Some(response) =>
      match response.response {
        @moon32960.ResponseFlag::Success => Some(@moon32960.ResponseFlag::Success)
        @moon32960.ResponseFlag::Failure => Some(@moon32960.ResponseFlag::Failure)
        @moon32960.ResponseFlag::VinDuplicate =>
          Some(@moon32960.ResponseFlag::VinDuplicate)
        _ => None
      }
    None => None
  }
}

///|
test "登入成功必须应答 0x01" {
  let gateway = @moon32960.Gateway::new()
  let handled = gateway.handle(login_frame("LGWEF4A56MF123456"))
  assert_eq(handled.outcome.name(), "login-accepted")
  assert_true(handled.response is Some(_))
  assert_true(flag_of(handled) is Some(@moon32960.ResponseFlag::Success))
  assert_eq(gateway.online_count(), 1)
}

///|
test "重复登入在 2016 口径应答 0x02" {
  let gateway = @moon32960.Gateway::new()
  let vin = "LGWEF4A56MF123456"
  let _ = gateway.handle(login_frame(vin))
  let handled = gateway.handle(login_frame(vin, sequence=2))
  assert_eq(handled.outcome.name(), "login-duplicate")
  // 2016 版表 4 只有 0x01/0x02/0xFE，VIN 重复只能落在 0x02
  assert_true(flag_of(handled) is Some(@moon32960.ResponseFlag::Failure))
}

///|
test "重复登入在扩展口径应答 0x03" {
  let gateway = @moon32960.Gateway::new()
  let vin = "LGWEF4A56MF123456"
  let profile = @moon32960.ResponseProfile::Extended
  let _ = gateway.handle(login_frame(vin), profile~)
  let handled = gateway.handle(login_frame(vin, sequence=2), profile~)
  assert_true(flag_of(handled) is Some(@moon32960.ResponseFlag::VinDuplicate))
}

///|
test "应答保留请求数据单元（附录B）" {
  let gateway = @moon32960.Gateway::new()
  let frame = login_frame("LGWEF4A56MF123456")
  let handled = gateway.handle(frame)
  match handled.response {
    Some(response) => {
      assert_eq(response.payload.length(), frame.payload.length())
      assert_eq(@moon32960.to_hex(response.payload), @moon32960.to_hex(frame.payload))
    }
    None => fail("登入必须应答")
  }
}

///|
test "平台间实时上报校验正确也必须应答" {
  let gateway = @moon32960.Gateway::new()
  let frame = @moon32960.Frame::new(
    command=@moon32960.Command::RealtimeReport,
    response=@moon32960.Command,
    vin="PLATFORM-A",
    encryption=@moon32960.Encryption::Plain,
    payload=telemetry_payload(minute=31),
  )
  let handled = gateway.handle(frame, scope=@moon32960.Scope::PlatformToPlatform)
  assert_eq(handled.outcome.name(), "report-accepted")
  // 与车端相反：平台间 5.2.2 要求正确时也要应答
  assert_true(flag_of(handled) is Some(@moon32960.ResponseFlag::Success))
}

///|
test "终端校时是上行命令，平台应答 0x01" {
  let gateway = @moon32960.Gateway::new()
  let frame = @moon32960.Frame::new(
    command=@moon32960.Command::TerminalTimeSync,
    response=@moon32960.Command,
    vin="LGWEF4A56MF123456",
    encryption=@moon32960.Encryption::Plain,
    payload=Bytes::new(0),
  )
  let handled = gateway.handle(frame)
  assert_eq(handled.outcome.name(), "time-sync-acknowledged")
  assert_true(flag_of(handled) is Some(@moon32960.ResponseFlag::Success))
}

///|
test "平台下行 0x80 在平台侧方向不符" {
  let gateway = @moon32960.Gateway::new()
  let frame = @moon32960.Frame::new(
    command=@moon32960.Command::PlatformDownlink,
    response=@moon32960.Command,
    vin="LGWEF4A56MF123456",
    encryption=@moon32960.Encryption::Plain,
    payload=Bytes::new(0),
  )
  let handled = gateway.handle(frame)
  assert_eq(handled.outcome.name(), "conflicting-direction")
  assert_true(flag_of(handled) is Some(@moon32960.ResponseFlag::Failure))
}

///|
test "车端命令在平台间场景被拒绝" {
  let gateway = @moon32960.Gateway::new()
  let handled = gateway.handle(
    login_frame("LGWEF4A56MF123456"),
    scope=@moon32960.Scope::PlatformToPlatform,
  )
  assert_eq(handled.outcome.name(), "conflicting-direction")
}

///|
test "实时上报校验正确时不做应答" {
  let gateway = @moon32960.Gateway::new()
  let vin = "LGWEF4A56MF123456"
  let _ = gateway.handle(login_frame(vin))
  let handled = gateway.handle(
    report_frame(vin, command=@moon32960.Command::RealtimeReport, minute=31),
  )
  assert_eq(handled.outcome.name(), "report-accepted")
  assert_true(handled.response is None)
  match gateway.session(vin) {
    Some(session) => assert_eq(session.report_count, 1)
    None => fail("会话应存在")
  }
}

///|
test "上报数据单元校验失败应答 0x02" {
  let gateway = @moon32960.Gateway::new()
  let vin = "LGWEF4A56MF123456"
  let _ = gateway.handle(login_frame(vin))
  let broken = @moon32960.Frame::new(
    command=@moon32960.Command::RealtimeReport,
    response=@moon32960.Command,
    vin~,
    encryption=@moon32960.Encryption::Plain,
    payload=Bytes::new(0),
  )
  let handled = gateway.handle(broken)
  assert_eq(handled.outcome.name(), "rejected")
  assert_true(flag_of(handled) is Some(@moon32960.ResponseFlag::Failure))
}

///|
test "心跳应答 0x01" {
  let gateway = @moon32960.Gateway::new()
  let vin = "LGWEF4A56MF123456"
  let _ = gateway.handle(login_frame(vin))
  let heartbeat = @moon32960.Frame::new(
    command=@moon32960.Command::Heartbeat,
    response=@moon32960.Command,
    vin~,
    encryption=@moon32960.Encryption::Plain,
    payload=Bytes::new(0),
  )
  let handled = gateway.handle(heartbeat)
  assert_eq(handled.outcome.name(), "heartbeat-accepted")
  assert_true(flag_of(handled) is Some(@moon32960.ResponseFlag::Success))
}

///|
test "未登入的 VIN 上报被丢弃且不应答" {
  let gateway = @moon32960.Gateway::new()
  let handled = gateway.handle(
    report_frame(
      "LGWEF4A56MF999999",
      command=@moon32960.Command::RealtimeReport,
      minute=31,
    ),
  )
  assert_eq(handled.outcome.name(), "rejected")
  assert_true(handled.response is None)
}

///|
test "补发与实时分开计数" {
  let gateway = @moon32960.Gateway::new()
  let vin = "LGWEF4A56MF123456"
  let _ = gateway.handle(login_frame(vin))
  let _ = gateway.handle(
    report_frame(vin, command=@moon32960.Command::RealtimeReport, minute=31),
  )
  let first = gateway.handle(
    report_frame(vin, command=@moon32960.Command::ResendReport, minute=32),
  )
  let second = gateway.handle(
    report_frame(vin, command=@moon32960.Command::ResendReport, minute=33),
  )
  assert_eq(first.outcome.name(), "resend-accepted")
  assert_true(first.response is None)
  assert_true(second.response is None)
  match gateway.session(vin) {
    Some(session) => {
      assert_eq(session.report_count, 1)
      assert_eq(session.resend_count, 2)
    }
    None => fail("会话应存在")
  }
}

///|
test "登出应答 0x01 并关闭会话" {
  let gateway = @moon32960.Gateway::new()
  let vin = "LGWEF4A56MF123456"
  let _ = gateway.handle(login_frame(vin))
  let logout : @moon32960.VehicleLogout = {
    time: sample_time(hour=9, minute=35),
    sequence: 1,
  }
  let frame = @moon32960.Frame::new(
    command=@moon32960.Command::VehicleLogout,
    response=@moon32960.Command,
    vin~,
    encryption=@moon32960.Encryption::Plain,
    payload=logout.to_bytes(),
  )
  let handled = gateway.handle(frame)
  assert_eq(handled.outcome.name(), "logout-accepted")
  assert_true(flag_of(handled) is Some(@moon32960.ResponseFlag::Success))
  assert_eq(gateway.online_count(), 0)
}

///|
test "加密上报带密钥可解，无密钥应答 0x02" {
  let gateway = @moon32960.Gateway::new()
  let vin = "LGWEF4A56MF123456"
  let key = @moon32960.KeyMaterial::Aes128Ecb(
    key=@moon32960.from_hex("000102030405060708090a0b0c0d0e0f"),
  )
  let frame = try! @moon32960.Frame::new(
    command=@moon32960.Command::RealtimeReport,
    response=@moon32960.Command,
    vin~,
    encryption=@moon32960.Encryption::Aes128,
    payload=telemetry_payload(minute=31),
  )
  let wire = try! frame.hex(key~)
  let _ = gateway.handle(login_frame(vin))
  let decoded = gateway.handle_bytes(@moon32960.from_hex(wire), key~)
  assert_eq(decoded.outcome.name(), "report-accepted")
  assert_true(decoded.response is None)
  let blind = gateway.handle_bytes(@moon32960.from_hex(wire))
  assert_eq(blind.outcome.name(), "rejected")
  // 缺密钥时既解不开也无法按同加密方式应答，只能记录、不应答
  assert_true(blind.response is None)
}

///|
test "每次接收都留审计条目" {
  let gateway = @moon32960.Gateway::new()
  let vin = "LGWEF4A56MF123456"
  let _ = gateway.handle(login_frame(vin))
  let _ = gateway.handle(
    report_frame(vin, command=@moon32960.Command::RealtimeReport, minute=31),
  )
  assert_eq(gateway.audit.length(), 2)
  assert_eq(gateway.audit[0].command, "vehicle-login")
  assert_eq(gateway.audit[1].outcome, "report-accepted")
}
