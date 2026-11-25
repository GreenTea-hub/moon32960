// main.mbt
// 依据：GB/T 32960.3-2025

///|
fn usage() -> Unit {
  println("moon32960 · GB/T 32960.3-2025 报文工具")
  println("")
  println("  decode <hex> [--aes <16字节hex>]   解析一帧")
  println("  encode <vin> <command> <payload-hex> [--aes <key>]")
  println("  case login        车辆登入与应答（$$ 起始符）")
  println("  case encrypted    AES 加密上报")
  println("  case report       实时上报：车端校验正确不应答")
  println("  case resend       断线补发")
  println("  case platform     车端 vs 平台间应答规则")
}

///|
fn command_of(name : String) -> @moon32960.Command raise {
  match name {
    "vehicle-login" => @moon32960.Command::VehicleLogin
    "realtime-report" => @moon32960.Command::RealtimeReport
    "resend-report" => @moon32960.Command::ResendReport
    "vehicle-logout" => @moon32960.Command::VehicleLogout
    "platform-login" => @moon32960.Command::PlatformLogin
    "platform-logout" => @moon32960.Command::PlatformLogout
    "heartbeat" => @moon32960.Command::Heartbeat
    "terminal-time-sync" => @moon32960.Command::TerminalTimeSync
    _ => fail("未知命令：\{name}")
  }
}

///|
fn sample_time(hour~ : Int32 = 9, minute~ : Int32 = 30, second~ : Int32 = 0) -> @moon32960.Time {
  try! @moon32960.Time::new(year=2026, month=11, day=25, hour~, minute~, second~)
}

///|
fn section(title : String) -> Unit {
  println("")
  println("── \{title}")
}

///|
fn fmt_scaled(raw : Int32, divisor~ : Int32 = 10, offset~ : Int32 = 0) -> String {
  let tenths = (raw - offset) * 10 / divisor
  let negative = tenths < 0
  let magnitude = if negative {
    -tenths
  } else {
    tenths
  }
  let sign = if negative {
    "-"
  } else {
    ""
  }
  "\{sign}\{magnitude / 10}.\{magnitude % 10}"
}

///|
fn field_text(raw : Int32, width~ : Int32, divisor~ : Int32 = 10, offset~ : Int32 = 0) -> String {
  let abnormal = match width {
    1 => 0xfe
    2 => 0xfffe
    _ => 0xfffffffe
  }
  let invalid = match width {
    1 => 0xff
    2 => 0xffff
    _ => 0xffffffff
  }
  if raw == invalid {
    "无效"
  } else if raw == abnormal {
    "异常"
  } else {
    fmt_scaled(raw, divisor~, offset~)
  }
}

///|
fn fmt_geo(raw : Int32) -> String {
  let whole = raw / 1000000
  let frac = raw % 1000000
  let text = frac.to_string()
  let sb = StringBuilder()
  for _ in 0..<(6 - text.length()) {
    sb.write_string("0")
  }
  sb.write_string(text)
  "\{whole}.\{sb.to_string()}"
}

///|
fn fmt_flags(flags : Array[Int32]) -> String {
  let sb = StringBuilder()
  for i, flag in flags {
    if i > 0 {
      sb.write_string(",")
    }
    sb.write_string(flag.to_string())
  }
  "[\{sb.to_string()}]"
}

///|
fn describe_frame(frame : @moon32960.Frame) -> Unit {
  println("  协议版本    : \{frame.version.name()}")
  println("  命令单元    : \{frame.command.name()}")
  println("  应答标志    : \{@moon32960.ResponseFlag::to_byte(frame.response).to_hex()} (\{frame.response.name()})")
  println("  VIN         : \{frame.vin}")
  println("  加密方式    : \{frame.encryption.name()}")
  println("  数据单元    : \{frame.payload.length()} 字节（已解密）")
}

///|
fn print_handled(handled : @moon32960.Handled, key~ : @moon32960.KeyMaterial = @moon32960.KeyMaterial::NoKey) -> Unit raise {
  println("  平台结论    : \{handled.outcome.name()}")
  println("  说明        : \{handled.note}")
  match handled.response {
    Some(response) => {
      println("  应答帧      : \{response.hex(key~)}")
      println("  应答标志    : \{@moon32960.ResponseFlag::to_byte(response.response).to_hex()} (\{response.response.name()})")
      println("  应答数据单元: \{response.payload.length()} 字节")
    }
    None => println("  应答帧      : 无（本次处理不产生应答）")
  }
}

///|
fn describe_items(telemetry : @moon32960.Telemetry) -> Unit {
  for item in telemetry.items {
    match item {
      @moon32960.ReportItem::Vehicle(data) => {
        println("  · 整车数据 0x01")
        println("      车辆状态   \{data.vehicle_status_name()}")
        println("      充电状态   \{data.charge_status_name()}")
        println("      SOC        \{data.soc}%")
        println("      车速       \{field_text(data.speed_raw, width=2)} km/h")
        println("      累计里程   \{field_text(data.odometer_raw, width=4)} km")
        println("      总电压     \{field_text(data.total_voltage_raw, width=2)} V")
        println("      总电流     \{field_text(data.total_current_raw, width=2, offset=30000)} A")
      }
      @moon32960.ReportItem::Motors(data) => {
        println("  · 驱动电机 0x02，共 \{data.motors.length()} 个")
        for motor in data.motors {
          println("      电机\{motor.sequence} \{motor.status_name()} 转速 \{motor.speed_rpm()} r/min 转矩 \{motor.torque_nm()} N·m")
        }
      }
      @moon32960.ReportItem::FuelCell(_) => println("  · 燃料电池发动机及车载氢系统 0x03")
      @moon32960.ReportItem::Engine(data) => println("  · 发动机 0x04，曲轴转速 \{data.crankshaft_speed_raw} r/min")
      @moon32960.ReportItem::Location(data) => {
        println("  · 车辆位置 0x05")
        println("      定位有效   \{data.is_fix_valid()}，坐标系 \{data.coordinate_system_name()}")
        println("      经度       \{fmt_geo(data.longitude_raw)}，纬度 \{fmt_geo(data.latitude_raw)}")
      }
      @moon32960.ReportItem::Alarm(data) => {
        println("  · 报警数据 0x06，等级 \{(match data.level() { Some(l) => l.to_string(); None => "无效" })}, 置位 \{fmt_flags(data.active_flags())}")
      }
      @moon32960.ReportItem::BatteryCellVoltage(data) => println("  · 蓄电池最小并联单元电压 0x07，\{data.packs.length()} 个包")
      @moon32960.ReportItem::BatteryTemperature(data) => println("  · 蓄电池温度 0x08，\{data.packs.length()} 个包")
      @moon32960.ReportItem::FuelCellStack(data) => println("  · 燃料电池电堆 0x30，\{data.stacks.length()} 个")
      @moon32960.ReportItem::SuperCapacitor(data) => println("  · 超级电容器 0x31，单体 \{data.cell_voltages_raw.length()} 个")
      @moon32960.ReportItem::SuperCapacitorExtreme(_) => println("  · 超级电容器极值 0x32")
      @moon32960.ReportItem::Custom(data) => println("  · 自定义数据，\{data.length()} 字节")
    }
  }
  match telemetry.signature {
    Some(sig) => println("  · 签名：类型 \{sig.kind_raw}，R \{sig.r.length()} 字节，S \{sig.s.length()} 字节（只解析不验签）")
    None => ()
  }
}

///|
fn decode_uplink(frame : @moon32960.Frame) -> Unit raise {
  describe_frame(frame)
  match frame.command {
    @moon32960.Command::VehicleLogin => {
      let login = @moon32960.VehicleLogin::decode(frame.payload[:])
      section("车辆登入（表 6）")
      println("  登入时间    : \{login.time.to_display()}")
      println("  登入流水号  : \{login.sequence}")
      println("  ICCID       : \{login.iccid}")
      println("  储能子系统  : \{login.storage_codes.length()} 个")
    }
    @moon32960.Command::RealtimeReport | @moon32960.Command::ResendReport => {
      let telemetry = @moon32960.Telemetry::decode(frame.payload[:])
      section("实时上报（表 7）")
      println("  数据采集时间: \{telemetry.time.to_display()}")
      describe_items(telemetry)
    }
    @moon32960.Command::VehicleLogout => {
      let logout = @moon32960.VehicleLogout::decode(frame.payload[:])
      section("车辆登出（表 28）")
      println("  登出时间    : \{logout.time.to_display()}，流水号 \{logout.sequence}")
    }
    @moon32960.Command::Heartbeat => {
      section("心跳（附录 B）")
      println("  数据单元    : \{frame.payload.length()} 字节（标准为空）")
    }
    _ => {
      section("数据单元")
      println("  原始        : \{@moon32960.to_hex(frame.payload)}")
    }
  }
}

///|
fn login_frame(vin : String) -> @moon32960.Frame raise {
  let login = @moon32960.VehicleLogin::new(
    time=sample_time(),
    sequence=1,
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

///|
fn sample_telemetry(time~ : @moon32960.Time) -> @moon32960.Telemetry {
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
  let location : @moon32960.VehicleLocation = {
    position_status: 0x00,
    coordinate_system: 0x02,
    longitude_raw: 116397000,
    latitude_raw: 39909000,
  }
  @moon32960.Telemetry::new(
    time~,
    items=[@moon32960.ReportItem::Vehicle(vehicle), @moon32960.ReportItem::Location(location)],
  )
}

///|
fn demo_key() -> @moon32960.KeyMaterial raise {
  @moon32960.KeyMaterial::Aes128Ecb(key=@moon32960.from_hex("000102030405060708090a0b0c0d0e0f"))
}

///|
fn case_login() -> Unit raise {
  section("案例一 · 车辆登入（$$ 起始符，命令 0x01）")
  let vin = "LGWEF4A56MF123456"
  let frame = login_frame(vin)
  println("  ① 终端命令包：\{frame.hex()}")
  decode_uplink(frame)
  let gateway = @moon32960.Gateway::new()
  section("② 平台应答")
  print_handled(gateway.handle(frame))
  section("③ 同一 VIN 再次登入")
  print_handled(gateway.handle(login_frame(vin)))
  println("  · 2025 表 4 定义 0x03 为 VIN 重复，可直接使用")
}

///|
fn case_encrypted() -> Unit raise {
  section("案例二 · AES 加密上报（加密方式 0x03）")
  let vin = "LGWEF4A56MF123456"
  let key = demo_key()
  let gateway = @moon32960.Gateway::new()
  let _ = gateway.handle(login_frame(vin))
  let plain = sample_telemetry(time=sample_time(minute=31)).to_bytes()
  println("  ① 明文数据单元：\{plain.length()} 字节")
  let frame = @moon32960.Frame::new(
    command=@moon32960.Command::RealtimeReport,
    response=@moon32960.Command,
    vin~,
    encryption=@moon32960.Encryption::Aes,
    payload=plain,
  )
  let wire = frame.hex(key~)
  println("  ② 加密组帧：\{wire}")
  section("③ 平台处理")
  print_handled(gateway.handle_bytes(@moon32960.from_hex(wire), key~), key~)
  let decoded = @moon32960.decode_frame(@moon32960.from_hex(wire), key~)
  section("④ 解密后的字段")
  describe_items(@moon32960.Telemetry::decode(decoded.payload[:]))
  section("⑤ 未注入密钥")
  print_handled(gateway.handle_bytes(@moon32960.from_hex(wire)))
}

///|
fn case_report() -> Unit raise {
  section("案例三 · 实时上报（车端校验正确不应答）")
  let vin = "LGWEF4A56MF123456"
  let gateway = @moon32960.Gateway::new()
  let _ = gateway.handle(login_frame(vin))
  let frame = @moon32960.Frame::new(
    command=@moon32960.Command::RealtimeReport,
    response=@moon32960.Command,
    vin~,
    encryption=@moon32960.Encryption::Plain,
    payload=sample_telemetry(time=sample_time(minute=31)).to_bytes(),
  )
  println("  终端发出    : \{frame.hex()}")
  decode_uplink(frame)
  section("平台处理")
  print_handled(gateway.handle(frame))
}

///|
fn case_resend() -> Unit raise {
  section("案例四 · 断线补发（命令 0x03）")
  let vin = "LGWEF4A56MF123456"
  let gateway = @moon32960.Gateway::new()
  let _ = gateway.handle(login_frame(vin))
  for minute in [32, 33] {
    let frame = @moon32960.Frame::new(
      command=@moon32960.Command::ResendReport,
      response=@moon32960.Command,
      vin~,
      encryption=@moon32960.Encryption::Plain,
      payload=sample_telemetry(time=sample_time(minute~)).to_bytes(),
    )
    println("  补发 09:\{minute} : \{gateway.handle(frame).outcome.name()}")
  }
  match gateway.session(vin) {
    Some(session) => println("  补发帧计 \{session.resend_count}，实时帧计 \{session.report_count}")
    None => println("  会话不存在")
  }
}

///|
fn case_platform() -> Unit raise {
  section("案例五 · 车端与平台间应答规则")
  let payload = sample_telemetry(time=sample_time(minute=31)).to_bytes()
  let terminal = @moon32960.Frame::new(
    command=@moon32960.Command::RealtimeReport,
    response=@moon32960.Command,
    vin="LGWEF4A56MF123456",
    encryption=@moon32960.Encryption::Plain,
    payload~,
  )
  let platform_side = @moon32960.Frame::new(
    command=@moon32960.Command::RealtimeReport,
    response=@moon32960.Command,
    vin="PLATFRM0000000001",
    encryption=@moon32960.Encryption::Plain,
    payload~,
  )
  section("① 车端")
  let gateway = @moon32960.Gateway::new()
  let _ = gateway.handle(login_frame("LGWEF4A56MF123456"))
  print_handled(gateway.handle(terminal))
  section("② 平台间（正文 5.2.2：正确也必须应答）")
  print_handled(@moon32960.Gateway::new().handle(platform_side, scope=@moon32960.Scope::PlatformToPlatform))
  section("③ 终端校时 0x08（上行）")
  let time_sync = @moon32960.Frame::new(
    command=@moon32960.Command::TerminalTimeSync,
    response=@moon32960.Command,
    vin="LGWEF4A56MF123456",
    encryption=@moon32960.Encryption::Plain,
    payload=Bytes::new(0),
  )
  print_handled(@moon32960.Gateway::new().handle(time_sync))
}

///|
fn parse_key(text : String) -> @moon32960.KeyMaterial raise {
  let raw = @moon32960.from_hex(text)
  if raw.length() != 16 {
    fail("AES 密钥必须是 16 字节")
  }
  @moon32960.KeyMaterial::Aes128Ecb(key=raw)
}

///|
fn main raise {
  let args = @env.args()
  match args[1:] {
    ["decode", hex] => decode_uplink(@moon32960.decode_frame(@moon32960.from_hex(hex)))
    ["decode", hex, "--aes", key] =>
      decode_uplink(@moon32960.decode_frame(@moon32960.from_hex(hex), key=parse_key(key)))
    ["encode", vin, command_name, payload_hex] => {
      let frame = @moon32960.Frame::new(
        command=command_of(command_name),
        response=@moon32960.Command,
        vin~,
        encryption=@moon32960.Encryption::Plain,
        payload=@moon32960.from_hex(payload_hex),
      )
      println(frame.hex())
    }
    ["encode", vin, command_name, payload_hex, "--aes", key] => {
      let frame = @moon32960.Frame::new(
        command=command_of(command_name),
        response=@moon32960.Command,
        vin~,
        encryption=@moon32960.Encryption::Aes,
        payload=@moon32960.from_hex(payload_hex),
      )
      println(frame.hex(key=parse_key(key)))
    }
    ["case", "login"] => case_login()
    ["case", "encrypted"] => case_encrypted()
    ["case", "report"] => case_report()
    ["case", "resend"] => case_resend()
    ["case", "platform"] => case_platform()
    _ => usage()
  }
}
