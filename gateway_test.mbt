// gateway_test.mbt

///|
fn sample_time(
  hour~ : Int32 = 9,
  minute~ : Int32 = 30,
  second~ : Int32 = 0,
) -> @moon32960.Time {
  try! @moon32960.Time::new(
    year=2026,
    month=11,
    day=25,
    hour~,
    minute~,
    second~,
  )
}

///|
fn login_frame(vin : String) -> @moon32960.Frame {
  try! ({
    let login = @moon32960.VehicleLogin::new(
      time=sample_time(),
      sequence=1,
      iccid="89860620180001234567",
      systems=[
        @moon32960.BatteryManagementSystem::{
          pack_count: 1,
          pack_codes: ["LFPBAT202511250000000001"],
        },
      ],
    )
    @moon32960.Frame::new(
      command=@moon32960.Command::VehicleLogin,
      response=@moon32960.Command,
      vin~,
      encryption=@moon32960.Encryption::Plain,
      payload=login.to_bytes(),
    )
  })
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
  }
  @moon32960.Telemetry::new(time=sample_time(minute~), items=[
    @moon32960.ReportItem::Vehicle(vehicle),
  ]).to_bytes()
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
        @moon32960.ResponseFlag::Success =>
          Some(@moon32960.ResponseFlag::Success)
        @moon32960.ResponseFlag::OtherError =>
          Some(@moon32960.ResponseFlag::OtherError)
        @moon32960.ResponseFlag::VinDuplicate =>
          Some(@moon32960.ResponseFlag::VinDuplicate)
        _ => None
      }
    None => None
  }
}

///|
test "登入应答 0x01 且数据单元只保留报文时间" {
  let gateway = @moon32960.Gateway::new()
  let frame = login_frame("LGWEF4A56MF123456")
  let handled = gateway.handle(frame)
  assert_eq(handled.outcome.name(), "login-accepted")
  match handled.response {
    Some(response) => {
      assert_eq(response.payload.length(), 6)
      assert_eq(
        response.payload[0:6].to_owned() == frame.payload[0:6].to_owned(),
        true,
      )
    }
    None => fail("登入必须应答")
  }
  assert_eq(gateway.online_count(), 1)
}

///|
test "重复登入应答 0x03" {
  let gateway = @moon32960.Gateway::new()
  let vin = "LGWEF4A56MF123456"
  let _ = gateway.handle(login_frame(vin))
  let handled = gateway.handle(login_frame(vin))
  assert_true(flag_of(handled) is Some(@moon32960.ResponseFlag::VinDuplicate))
}

///|
test "车端实时上报校验正确不应答" {
  let gateway = @moon32960.Gateway::new()
  let vin = "LGWEF4A56MF123456"
  let _ = gateway.handle(login_frame(vin))
  let handled = gateway.handle(
    report_frame(vin, command=@moon32960.Command::RealtimeReport, minute=31),
  )
  assert_eq(handled.outcome.name(), "report-accepted")
  assert_true(handled.response is None)
}

///|
test "平台间实时上报必须应答 0x01" {
  let gateway = @moon32960.Gateway::new()
  let handled = gateway.handle(
    report_frame(
      "PLATFRM0000000001",
      command=@moon32960.Command::RealtimeReport,
      minute=31,
    ),
    scope=@moon32960.Scope::PlatformToPlatform,
  )
  assert_eq(handled.outcome.name(), "report-accepted")
  assert_true(flag_of(handled) is Some(@moon32960.ResponseFlag::Success))
}

///|
test "终端校时是上行，应答 0x01" {
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
test "平台下行命令在平台侧方向不符" {
  let gateway = @moon32960.Gateway::new()
  let frame = @moon32960.Frame::new(
    command=@moon32960.Command::Query,
    response=@moon32960.Command,
    vin="LGWEF4A56MF123456",
    encryption=@moon32960.Encryption::Plain,
    payload=Bytes::new(0),
  )
  let handled = gateway.handle(frame)
  assert_eq(handled.outcome.name(), "conflicting-direction")
}

///|
test "AES 加密上报带密钥可解，无密钥只记录" {
  let gateway = @moon32960.Gateway::new()
  let vin = "LGWEF4A56MF123456"
  let key = @moon32960.KeyMaterial::Aes128Ecb(
    key=@moon32960.from_hex("000102030405060708090a0b0c0d0e0f"),
  )
  let frame = @moon32960.Frame::new(
    command=@moon32960.Command::RealtimeReport,
    response=@moon32960.Command,
    vin~,
    encryption=@moon32960.Encryption::Aes,
    payload=telemetry_payload(minute=31),
  )
  let wire = try! frame.hex(key~)
  let _ = gateway.handle(login_frame(vin))
  let ok = gateway.handle_bytes(@moon32960.from_hex(wire), key~)
  assert_eq(ok.outcome.name(), "report-accepted")
  assert_true(ok.response is None)
  let blind = gateway.handle_bytes(@moon32960.from_hex(wire))
  assert_eq(blind.outcome.name(), "rejected")
  assert_true(blind.response is None)
}

///|
test "会话：未登入上报被丢弃" {
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
test "补发计入补发计数" {
  let gateway = @moon32960.Gateway::new()
  let vin = "LGWEF4A56MF123456"
  let _ = gateway.handle(login_frame(vin))
  let _ = gateway.handle(
    report_frame(vin, command=@moon32960.Command::RealtimeReport, minute=31),
  )
  let handled = gateway.handle(
    report_frame(vin, command=@moon32960.Command::ResendReport, minute=32),
  )
  assert_eq(handled.outcome.name(), "resend-accepted")
  assert_true(handled.response is None)
  match gateway.session(vin) {
    Some(session) => {
      assert_eq(session.report_count, 1)
      assert_eq(session.resend_count, 1)
    }
    None => fail("会话应存在")
  }
}
