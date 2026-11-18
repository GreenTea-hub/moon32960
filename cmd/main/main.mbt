// main.mbt
///|
fn usage() -> Unit {
  println("moon32960 · GB/T 32960.3-2016 报文工具")
  println("")
  println("  decode <hex> [--with-serial]  解析一帧并打印字段")
  println("  encode <vin> <command> <payload-hex>")
  println("                                由 VIN、命令单元与数据单元组帧")
  println("  case login                    标准车辆登入：报文→字段→应答→后续动作")
  println("  case report                   标准实时上报：报文→字段→应答→后续动作")
  println("  case resend                   断线补发：缓存→补发→应答→计数")
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
/// 整数拼小数，避免浮点显示出现 62.300000000000004 这类尾巴。
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
  let whole = magnitude / 10
  let frac = magnitude % 10
  "\{sign}\{whole}.\{frac}"
}

///|
/// 按字段宽度给出「有效值 / 异常 / 无效」文本。
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
/// 经纬度保留 6 位小数。
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
/// 报警标志位清单转文本。
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
  println("  VIN         : \{frame.vin}")
  println("  加密方式    : \{frame.encryption.name()}")
  println("  数据单元    : \{frame.payload.length()} 字节")
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
        println("  · 驱动电机数据 0x02，共 \{data.motors.length()} 个")
        for motor in data.motors {
          println(
            "      电机\{motor.sequence} \{motor.status_name()} 转速 \{motor.speed_rpm()} r/min 转矩 \{motor.torque_nm()} N·m",
          )
        }
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
        println("      经度       \{fmt_geo(data.longitude_raw)} 东经为正")
        println("      纬度       \{fmt_geo(data.latitude_raw)} 北纬为正")
      }
      @moon32960.ReportItem::Extreme(data) => {
        println("  · 极值数据 0x06")
        println("      最高单体电压 \{field_text(data.max_cell_voltage_raw, width=2, divisor=1000)} V")
        println("      最低单体电压 \{field_text(data.min_cell_voltage_raw, width=2, divisor=1000)} V")
      }
      @moon32960.ReportItem::Alarm(data) => {
        println("  · 报警数据 0x07")
        println("      最高报警等级 \{(match data.level() { Some(l) => l.to_string(); None => "无效" })}")
        println("      置位标志     \{fmt_flags(data.active_flags())}")
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
fn print_handled(handled : @moon32960.Handled) -> Unit raise {
  println("  平台结论    : \{handled.outcome.name()}")
  println("  说明        : \{handled.note}")
  println("  应答帧      : \{handled.response.hex()}")
  println(
    "  应答标志    : \{@moon32960.ResponseFlag::to_byte(handled.response.response).to_hex()}",
  )
}

///|
/// 按命令单元分派到对应数据单元结构。
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
      println("  编码长度    : \{login.code_len} 字节")
      for code in login.storage_codes {
        println("  子系统编码  : \{code}")
      }
    }
    @moon32960.Command::RealtimeReport | @moon32960.Command::ResendReport => {
      let telemetry = @moon32960.Telemetry::decode(frame.payload[:], header~)
      section("上报数据单元（表 7）")
      println("  数据采集时间: \{telemetry.time.to_display()}")
      match telemetry.serial {
        Some(value) => println("  信息流水号  : \{value}")
        None => ()
      }
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
    @moon32960.Command::PlatformLogin => {
      let login = @moon32960.PlatformLogin::decode(frame.payload[:])
      section("平台登入数据单元")
      println("  登入时间    : \{login.time.to_display()}")
      println("  平台用户名  : \{login.username}")
      println("  加密规则    : \{login.encryption_rule}")
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
    response=@moon32960.ResponseFlag::Success,
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
fn case_login() -> Unit raise {
  section("案例一 · 车辆登入（命令单元 0x01）")
  let vin = "LGWEF4A56MF123456"
  let frame = login_frame(vin)
  println("  终端发出    : \{frame.hex()}")
  decode_uplink(frame, header=@moon32960.TimestampOnly)
  let gateway = @moon32960.Gateway::new()
  let handled = gateway.handle(frame)
  section("平台应答")
  print_handled(handled)
  section("后续动作")
  println("  · 会话置为在线，记录登入流水号 1")
  println("  · ICCID 入库，作为身份核对依据")
  println("  · 该 VIN 的上报与补发开始被接收")
  println("  · 平台在线终端数：\{gateway.online_count()}")
}

///|
fn case_report() -> Unit raise {
  section("案例二 · 实时信息上报（命令单元 0x02）")
  let vin = "LGWEF4A56MF123456"
  let gateway = @moon32960.Gateway::new()
  let handled_login = gateway.handle(login_frame(vin))
  println("  先行登入    : \{handled_login.outcome.name()}")
  let telemetry = sample_telemetry(time=sample_time(hour=9, minute=31))
  let frame = @moon32960.Frame::new(
    command=@moon32960.Command::RealtimeReport,
    response=@moon32960.ResponseFlag::Success,
    vin~,
    encryption=@moon32960.Encryption::Plain,
    payload=telemetry.to_bytes(),
  )
  println("  终端发出    : \{frame.hex()}")
  decode_uplink(frame, header=@moon32960.TimestampOnly)
  let handled = gateway.handle(frame)
  section("平台应答")
  print_handled(handled)
  section("后续动作")
  println("  · 实时计数加一，最近上报时间更新为 09:31:00")
  println("  · 整车与位置两类信息体分别入库")
  println("  · 报警位未置位，不触发补发请求")
}

///|
fn case_resend() -> Unit raise {
  section("案例三 · 断线补发（命令单元 0x03）")
  let vin = "LGWEF4A56MF123456"
  let gateway = @moon32960.Gateway::new()
  let handled_login = gateway.handle(login_frame(vin))
  println("  先行登入    : \{handled_login.outcome.name()}")
  let first = sample_telemetry(time=sample_time(hour=9, minute=31))
  let first_frame = @moon32960.Frame::new(
    command=@moon32960.Command::RealtimeReport,
    response=@moon32960.ResponseFlag::Success,
    vin~,
    encryption=@moon32960.Encryption::Plain,
    payload=first.to_bytes(),
  )
  println("  链路正常    : \{gateway.handle(first_frame).outcome.name()}")
  section("模拟链路中断 09:32 至 09:35")
  println("  · 终端将 09:32、09:33、09:34 三帧写入本地存储")
  println("  · 本地存储按时间戳排序，超过 7 日的记录丢弃")
  section("链路恢复后补发")
  let buffered : Array[(@moon32960.Time, Int32)] = [
    (sample_time(hour=9, minute=32), 32),
    (sample_time(hour=9, minute=33), 33),
  ]
  for (time, minute) in buffered {
    let frame = @moon32960.Frame::new(
      command=@moon32960.Command::ResendReport,
      response=@moon32960.ResponseFlag::Success,
      vin~,
      encryption=@moon32960.Encryption::Plain,
      payload=sample_telemetry(time~).to_bytes(),
    )
    println("  补发 09:\{minute}   : \{frame.hex()}")
    let handled = gateway.handle(frame)
    println("  平台结论    : \{handled.outcome.name()}")
    println(
      "  应答标志    : \{@moon32960.ResponseFlag::to_byte(handled.response.response).to_hex()}",
    )
  }
  section("补发结果")
  match gateway.session(vin) {
    Some(session) => {
      println("  实时帧      : \{session.report_count}")
      println("  补发帧      : \{session.resend_count}")
      match session.last_report {
        Some(t) => println("  最近上报    : \{t.to_display()}")
        None => println("  最近上报    : 无")
      }
    }
    None => println("  会话不存在")
  }
  println("  · 补发包与实时包数据单元相同，仅命令单元改为 0x03")
  println("  · 平台逐包应答，补发计数与实时计数分开统计")
}

///|
fn main raise {
  let args = @env.args()
  match args[1:] {
    ["decode", hex] => {
      let frame = @moon32960.decode_frame(@moon32960.from_hex(hex))
      decode_uplink(frame, header=@moon32960.TimestampOnly)
    }
    ["decode", hex, "--with-serial"] => {
      let frame = @moon32960.decode_frame(@moon32960.from_hex(hex))
      decode_uplink(frame, header=@moon32960.TimestampWithSerial)
    }
    ["encode", vin, command_name, payload_hex] => {
      let frame = @moon32960.Frame::new(
        command=command_of(command_name),
        response=@moon32960.ResponseFlag::Success,
        vin~,
        encryption=@moon32960.Encryption::Plain,
        payload=@moon32960.from_hex(payload_hex),
      )
      println(frame.hex())
    }
    ["case", "login"] => case_login()
    ["case", "report"] => case_report()
    ["case", "resend"] => case_resend()
    _ => usage()
  }
}
