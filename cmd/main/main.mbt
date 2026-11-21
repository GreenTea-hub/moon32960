// main.mbt
///|
fn usage() -> Unit {
  println("moon32960 · GB/T 32960.3-2016 报文工具")
  println("")
  println("  decode <hex> [--with-serial] [--aes128 <16字节hex>]")
  println("                                解析一帧（加密帧需提供密钥）")
  println("  encode <vin> <command> <payload-hex> [--aes128 <16字节hex>]")
  println("                                组帧；加密帧先加密再算校验码")
  println("  case login                    登入应答端到端：命令包 → 应答 0x01 → 终端确认")
  println("  case encrypted                AES128 加密上报端到端：加密 → 解密 → 字段 → 应答语义")
  println("  case report                   实时上报：校验正确时平台不应答")
  println("  case resend                   断线补发：缓存 → 补发 → 计数")
  println("")
  println("command 取值：vehicle-login realtime-report resend-report vehicle-logout")
  println("             heartbeat terminal-time-sync platform-downlink")
}

///|
fn command_of(name : String) -> @moon32960.Command raise {
  match name {
    "vehicle-login" => @moon32960.Command::VehicleLogin
    "realtime-report" => @moon32960.Command::RealtimeReport
    "resend-report" => @moon32960.Command::ResendReport
    "vehicle-logout" => @moon32960.Command::VehicleLogout
    "heartbeat" => @moon32960.Command::Heartbeat
    "terminal-time-sync" => @moon32960.Command::TerminalTimeSync
    "platform-downlink" => @moon32960.Command::PlatformDownlink
    _ => fail("未知命令：\{name}")
  }
}

///|
fn sample_time(
  hour~ : Int32 = 15,
  minute~ : Int32 = 0,
  second~ : Int32 = 0,
) -> @moon32960.Time {
  try! @moon32960.Time::new(
    year=2026,
    month=11,
    day=18,
    hour~,
    minute~,
    second~,
  )
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
fn field_text(
  raw : Int32,
  width~ : Int32,
  divisor~ : Int32 = 10,
  offset~ : Int32 = 0,
) -> String {
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
  println("  命令单元    : \{frame.command.name()}")
  println(
    "  应答标志    : \{@moon32960.ResponseFlag::to_byte(frame.response).to_hex()}",
  )
  if @moon32960.is_response_packet(frame) {
    println("                （应答包）")
  } else {
    println("                （命令包，0xFE）")
  }
  println("  VIN         : \{frame.vin}")
  println("  加密方式    : \{frame.encryption.name()}")
  println("  数据单元    : \{frame.payload.length()} 字节（已解密）")
}

///|
fn print_handled(handled : @moon32960.Handled) -> Unit raise {
  println("  平台结论    : \{handled.outcome.name()}")
  println("  说明        : \{handled.note}")
  match handled.response {
    Some(response) => {
      println("  应答帧      : \{response.hex()}")
      println(
        "  应答标志    : \{@moon32960.ResponseFlag::to_byte(response.response).to_hex()}",
      )
    }
    None => println("  应答帧      : 无（按标准校验正确时不做应答）")
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
        println(
          "      总电流     \{field_text(data.total_current_raw, width=2, offset=30000)} A",
        )
      }
      @moon32960.ReportItem::Motors(data) => {
        println("  · 驱动电机数据 0x02，共 \{data.motors.length()} 个")
      }
      @moon32960.ReportItem::FuelCell(data) => {
        println("  · 燃料电池数据 0x03，温度探针 \{data.probe_temps.length()} 个")
      }
      @moon32960.ReportItem::Engine(data) => {
        println("  · 发动机数据 0x04，状态 \{data.status_name()}")
      }
      @moon32960.ReportItem::Location(data) => {
        println("  · 车辆位置 0x05")
        println("      定位有效   \{data.is_fix_valid()}")
        println("      经度       \{fmt_geo(data.longitude_raw)}")
        println("      纬度       \{fmt_geo(data.latitude_raw)}")
      }
      @moon32960.ReportItem::Extreme(data) => {
        println("  · 极值数据 0x06")
        println(
          "      最高单体电压 \{field_text(data.max_cell_voltage_raw, width=2, divisor=1000)} V",
        )
      }
      @moon32960.ReportItem::Alarm(data) => {
        println("  · 报警数据 0x07，置位标志 \{fmt_flags(data.active_flags())}")
      }
      @moon32960.ReportItem::StorageVoltage(data) => {
        println("  · 储能电压 0x08，\{data.groups.length()} 个子系统")
      }
      @moon32960.ReportItem::StorageTemperature(data) => {
        println("  · 储能温度 0x09，\{data.groups.length()} 个子系统")
      }
    }
  }
}

///|
fn decode_uplink(
  frame : @moon32960.Frame,
  header~ : @moon32960.ReportHeader,
) -> Unit raise {
  describe_frame(frame)
  match frame.command {
    @moon32960.Command::VehicleLogin => {
      let login = @moon32960.VehicleLogin::decode(frame.payload[:])
      section("车辆登入数据单元（表 6）")
      println("  登入时间    : \{login.time.to_display()}")
      println("  登入流水号  : \{login.sequence}")
      println("  ICCID       : \{login.iccid}")
      println("  储能子系统  : \{login.storage_codes.length()} 个")
      for code in login.storage_codes {
        println("  子系统编码  : \{code}")
      }
    }
    @moon32960.Command::RealtimeReport | @moon32960.Command::ResendReport => {
      let telemetry = @moon32960.Telemetry::decode(frame.payload[:], header~)
      section("上报数据单元（表 7）")
      println("  数据采集时间: \{telemetry.time.to_display()}")
      describe_items(telemetry)
    }
    @moon32960.Command::VehicleLogout => {
      let logout = @moon32960.VehicleLogout::decode(frame.payload[:])
      section("车辆登出数据单元（表 8）")
      println("  登出时间    : \{logout.time.to_display()}")
      println("  登出流水号  : \{logout.sequence}")
    }
    @moon32960.Command::Heartbeat => {
      section("心跳数据单元")
      println("  长度        : \{frame.payload.length()} 字节（标准为空）")
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
    time=sample_time(hour=9, minute=30),
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
    accelerator_raw: 30,
    brake_status: 0x01,
  }
  let location : @moon32960.VehicleLocation = {
    position_status: 0x00,
    longitude_raw: 116397000,
    latitude_raw: 39909000,
  }
  @moon32960.Telemetry::new(
    time~,
    items=[
      @moon32960.ReportItem::Vehicle(vehicle),
      @moon32960.ReportItem::Location(location),
    ],
  )
}

///|
fn demo_key() -> @moon32960.KeyMaterial raise {
  @moon32960.KeyMaterial::Aes128Ecb(
    key=@moon32960.from_hex("000102030405060708090a0b0c0d0e0f"),
  )
}

///|
fn case_login() -> Unit raise {
  section("案例一 · 登入应答端到端（命令单元 0x01）")
  let vin = "LGWEF4A56MF123456"
  let frame = login_frame(vin)
  println("  ① 终端发出命令包：\{frame.hex()}")
  println("     应答标志 0xFE 表示这是命令包，请求平台应答")
  decode_uplink(frame, header=@moon32960.TimestampOnly)
  let gateway = @moon32960.Gateway::new()
  let handled = gateway.handle(frame)
  section("② 平台应答")
  print_handled(handled)
  section("③ 终端收到应答后完成登入")
  println("  · 会话置为在线，登记流水号 1，保存 ICCID")
  println("  · 若 3 分钟内未收到应答，终端应重发；连续 3 次无应答应间隔 30 分钟再连")
  println("  · 平台在线终端数：\{gateway.online_count()}")
  section("④ 同一 VIN 再次登入")
  let again = login_frame(vin)
  let duplicate = gateway.handle(again)
  print_handled(duplicate)
  println("  · 应答标志 0x03 表示 VIN 重复，终端据此判断需换会话或排查串号")
}

///|
fn case_encrypted() -> Unit raise {
  section("案例二 · AES128 加密上报端到端（命令单元 0x02）")
  let vin = "LGWEF4A56MF123456"
  let key = demo_key()
  println("  密钥：AES128-ECB，000102...0e0f（由部署方约定并注入）")
  let gateway = @moon32960.Gateway::new()
  let _ = gateway.handle(login_frame(vin))
  let telemetry = sample_telemetry(time=sample_time(hour=9, minute=31))
  let plain_payload = telemetry.to_bytes()
  println("  ① 明文数据单元：\{plain_payload.length()} 字节")
  println("     \{@moon32960.to_hex(plain_payload)}")
  let frame = @moon32960.Frame::new(
    command=@moon32960.Command::RealtimeReport,
    response=@moon32960.Command,
    vin~,
    encryption=@moon32960.Encryption::Aes128,
    payload=plain_payload,
  )
  let wire = frame.hex(key~)
  println("  ② 加密后组帧：\{wire}")
  println(
    "     加密方式字段 0x03，数据单元 \{@moon32960.peek_header(@moon32960.from_hex(wire)).payload_len} 字节密文",
  )
  println("     BCC 在密文之上计算，与标准「先加密再校验」一致")
  section("③ 平台收到字节流")
  let handled = gateway.handle_bytes(@moon32960.from_hex(wire), key~)
  print_handled(handled)
  let decoded = @moon32960.decode_frame(@moon32960.from_hex(wire), key~)
  section("④ 解密后的字段")
  println("  数据单元    : \{decoded.payload.length()} 字节（PKCS#7 填充已去除）")
  let parsed = @moon32960.Telemetry::decode(decoded.payload[:])
  println("  数据采集时间: \{parsed.time.to_display()}")
  describe_items(parsed)
  section("⑤ 未注入密钥时的行为")
  let blind = gateway.handle_bytes(@moon32960.from_hex(wire))
  print_handled(blind)
  println("  · 声明 AES128 却拿不到密钥时，拒绝解析并应答 0x02，绝不当明文解析")
  section("⑥ 责任划分")
  println("  · 32960.3 只定义加密方式字节，不定义密钥协商与填充；")
  println("  · 本项目内置 AES128-ECB/CBC 与 PKCS#7，密钥由部署方注入；")
  println("  · RSA 私钥同样由部署方持有，未注入时按拒绝处理，见 docs/CONFORMANCE.md")
}

///|
fn case_report() -> Unit raise {
  section("案例三 · 实时上报：校验正确时平台不应答")
  let vin = "LGWEF4A56MF123456"
  let gateway = @moon32960.Gateway::new()
  let _ = gateway.handle(login_frame(vin))
  let telemetry = sample_telemetry(time=sample_time(hour=9, minute=31))
  let frame = @moon32960.Frame::new(
    command=@moon32960.Command::RealtimeReport,
    response=@moon32960.Command,
    vin~,
    encryption=@moon32960.Encryption::Plain,
    payload=telemetry.to_bytes(),
  )
  println("  终端发出    : \{frame.hex()}")
  decode_uplink(frame, header=@moon32960.TimestampOnly)
  let handled = gateway.handle(frame)
  section("平台处理")
  print_handled(handled)
  println("  · 标准规定校验正确时平台不做应答，因此这里没有应答帧")
  println("  · 校验失败时才回 0x02，终端间隔 1 分钟重发，失败 3 次后停止")
  section("校验失败时的对照")
  let tampered = @moon32960.from_hex(frame.hex())
  let _ = gateway.handle_bytes(tampered)
  let broken = @moon32960.Frame::new(
    command=@moon32960.Command::RealtimeReport,
    response=@moon32960.Command,
    vin~,
    encryption=@moon32960.Encryption::Plain,
    payload=Bytes::new(0),
  )
  let rejected = gateway.handle(broken)
  print_handled(rejected)
}

///|
fn case_resend() -> Unit raise {
  section("案例四 · 断线补发")
  let vin = "LGWEF4A56MF123456"
  let gateway = @moon32960.Gateway::new()
  let _ = gateway.handle(login_frame(vin))
  let first = @moon32960.Frame::new(
    command=@moon32960.Command::RealtimeReport,
    response=@moon32960.Command,
    vin~,
    encryption=@moon32960.Encryption::Plain,
    payload=sample_telemetry(time=sample_time(hour=9, minute=31)).to_bytes(),
  )
  let first_handled = gateway.handle(first)
  println("  09:31 实时  : \{first_handled.outcome.name()}（不应答）")
  section("模拟链路中断 09:32 至 09:35")
  println("  · 终端缓存三帧，超过 7 日的记录丢弃")
  section("链路恢复后补发")
  for minute in [32, 33] {
    let frame = @moon32960.Frame::new(
      command=@moon32960.Command::ResendReport,
      response=@moon32960.Command,
      vin~,
      encryption=@moon32960.Encryption::Plain,
      payload=sample_telemetry(time=sample_time(hour=9, minute~)).to_bytes(),
    )
    let handled = gateway.handle(frame)
    println(
      "  补发 09:\{minute} : \{handled.outcome.name()}（不应答）  帧 \{frame.hex()}",
    )
  }
  section("计数")
  match gateway.session(vin) {
    Some(session) => {
      println("  实时帧      : \{session.report_count}")
      println("  补发帧      : \{session.resend_count}")
    }
    None => println("  会话不存在")
  }
  println("  · 补发包与实时包数据单元相同，仅命令单元改为 0x03")
}

///|
fn parse_key(text : String) -> @moon32960.KeyMaterial raise {
  let raw = @moon32960.from_hex(text)
  if raw.length() != 16 {
    fail("AES128 密钥必须是 16 字节，当前 \{raw.length()} 字节")
  }
  @moon32960.KeyMaterial::Aes128Ecb(key=raw)
}

///|
fn main raise {
  let args = @env.args()
  match args[1:] {
    ["decode", hex] => {
      let frame = @moon32960.decode_frame(@moon32960.from_hex(hex))
      decode_uplink(frame, header=@moon32960.TimestampOnly)
    }
    ["decode", hex, "--aes128", key] => {
      let frame = @moon32960.decode_frame(
        @moon32960.from_hex(hex),
        key=parse_key(key),
      )
      decode_uplink(frame, header=@moon32960.TimestampOnly)
    }
    ["decode", hex, "--with-serial"] => {
      let frame = @moon32960.decode_frame(@moon32960.from_hex(hex))
      decode_uplink(frame, header=@moon32960.TimestampWithSerial)
    }
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
    ["encode", vin, command_name, payload_hex, "--aes128", key] => {
      let frame = @moon32960.Frame::new(
        command=command_of(command_name),
        response=@moon32960.Command,
        vin~,
        encryption=@moon32960.Encryption::Aes128,
        payload=@moon32960.from_hex(payload_hex),
      )
      println(frame.hex(key=parse_key(key)))
    }
    ["case", "login"] => case_login()
    ["case", "encrypted"] => case_encrypted()
    ["case", "report"] => case_report()
    ["case", "resend"] => case_resend()
    _ => usage()
  }
}
