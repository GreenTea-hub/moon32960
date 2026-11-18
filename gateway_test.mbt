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
      response=@moon32960.ResponseFlag::Success,
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
    response=@moon32960.ResponseFlag::Success,
    vin~,
    encryption=@moon32960.Encryption::Plain,
    payload=telemetry_payload(minute~),
  )
}

///|
fn logout_frame(vin : String) -> @moon32960.Frame {
  let data : @moon32960.VehicleLogout = {
    time: sample_time(hour=9, minute=35),
    sequence: 1,
  }
  @moon32960.Frame::new(
    command=@moon32960.Command::VehicleLogout,
    response=@moon32960.ResponseFlag::Success,
    vin~,
    encryption=@moon32960.Encryption::Plain,
    payload=data.to_bytes(),
  )
}

///|
test "登入被接受并应答成功" {
  let gateway = @moon32960.Gateway::new()
  let handled = gateway.handle(login_frame("LGWEF4A56MF123456"))
  assert_eq(handled.outcome.name(), "login-accepted")
  match handled.response.response {
    @moon32960.ResponseFlag::Success => ()
    _ => fail("登入应答标志应为成功")
  }
  assert_eq(gateway.online_count(), 1)
  assert_eq(gateway.accepted, 1)
}

///|
test "重复登入应答 VIN 重复" {
  let gateway = @moon32960.Gateway::new()
  let vin = "LGWEF4A56MF123456"
  let _ = gateway.handle(login_frame(vin))
  let handled = gateway.handle(login_frame(vin, sequence=2))
  assert_eq(handled.outcome.name(), "login-duplicate")
  match handled.response.response {
    @moon32960.ResponseFlag::VinDuplicate => ()
    _ => fail("重复登入应答标志应为 0x03")
  }
  assert_eq(gateway.online_count(), 1)
}

///|
test "未登入上报应答失败" {
  let gateway = @moon32960.Gateway::new()
  let handled = gateway.handle(
    report_frame(
      "LGWEF4A56MF999999",
      command=@moon32960.Command::RealtimeReport,
      minute=31,
    ),
  )
  assert_eq(handled.outcome.name(), "rejected")
  match handled.response.response {
    @moon32960.ResponseFlag::Failure => ()
    _ => fail("未登入上报应答标志应为 0x02")
  }
  assert_eq(gateway.rejected, 1)
}

///|
test "登入后实时上报被接收" {
  let gateway = @moon32960.Gateway::new()
  let vin = "LGWEF4A56MF123456"
  let _ = gateway.handle(login_frame(vin))
  let handled = gateway.handle(
    report_frame(vin, command=@moon32960.Command::RealtimeReport, minute=31),
  )
  assert_eq(handled.outcome.name(), "report-accepted")
  assert_eq(handled.note, "接收 1 类信息体")
  match gateway.session(vin) {
    Some(session) => assert_eq(session.report_count, 1)
    None => fail("会话应存在")
  }
}

///|
test "补发与实时计数分离" {
  let gateway = @moon32960.Gateway::new()
  let vin = "LGWEF4A56MF123456"
  let _ = gateway.handle(login_frame(vin))
  let _ = gateway.handle(
    report_frame(vin, command=@moon32960.Command::RealtimeReport, minute=31),
  )
  let _ = gateway.handle(
    report_frame(vin, command=@moon32960.Command::ResendReport, minute=32),
  )
  let _ = gateway.handle(
    report_frame(vin, command=@moon32960.Command::ResendReport, minute=33),
  )
  match gateway.session(vin) {
    Some(session) => {
      assert_eq(session.report_count, 1)
      assert_eq(session.resend_count, 2)
    }
    None => fail("会话应存在")
  }
}

///|
test "登出关闭会话" {
  let gateway = @moon32960.Gateway::new()
  let vin = "LGWEF4A56MF123456"
  let _ = gateway.handle(login_frame(vin))
  let handled = gateway.handle(logout_frame(vin))
  assert_eq(handled.outcome.name(), "logout-accepted")
  assert_eq(gateway.online_count(), 0)
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
