// response.mbt
// 依据：GB/T 32960.3-2025 6.3.2、附录 B.3.3.2（应答构造）

///|
/// 通信场景：车端（附录 B，资料性）与平台间（正文第 5 章，规范性）规则不同。
pub(all) enum Scope {
  TerminalToPlatform
  PlatformToPlatform
}

///|
pub fn Scope::name(self : Scope) -> String {
  match self {
    TerminalToPlatform => "terminal->platform (附录 B)"
    PlatformToPlatform => "platform->platform (正文第 5 章)"
  }
}

///|
/// 应答包的数据单元形态。
///
/// 2025 版正文 6.3.2 与附录 B.3.3.2 措辞一致：「变更应答标志，保留报文时间，删除其余报文内容」，
/// 因此 `TimeOnly` 是唯一与现行标准一致的形态，作为默认。
/// `KeepRequestPayload` 只对应 2016 版某些解读与地方标准，保留但不作默认。
pub(all) enum ResponseShape {
  TimeOnly // 保留 6 字节报文时间（现行标准）
  KeepRequestPayload // 保留请求数据单元（2016 解读/地方口径）
  EmptyPayload // 空数据单元（仅联调，无条文对应）
}

///|
pub fn ResponseShape::name(self : ResponseShape) -> String {
  match self {
    TimeOnly => "time-only (现行标准)"
    KeepRequestPayload => "keep-request-payload (2016/地方口径)"
    EmptyPayload => "empty-payload (联调用)"
  }
}

///|
fn replace_time(payload : Bytes, time : Time) -> Bytes {
  if payload.length() < 6 {
    time.to_bytes()
  } else {
    let out : Array[Byte] = []
    for byte in time.to_bytes() {
      out.push(byte)
    }
    for i in 6..<payload.length() {
      out.push(payload[i])
    }
    Bytes::from_array(out)
  }
}

///|
/// 构造应答包。默认按现行标准只保留报文时间；加密方式沿用请求。
pub fn build_response(
  request : Frame,
  flag : ResponseFlag,
  shape~ : ResponseShape = TimeOnly,
  answer_time~ : Time? = None,
) -> Frame raise FrameError {
  let payload = match shape {
    TimeOnly => match answer_time {
      Some(time) => time.to_bytes()
      None =>
        if request.payload.length() >= 6 {
          request.payload[0:6].to_owned()
        } else {
          raise Payload(message="应答需要报文时间，但请求数据单元不足 6 字节")
        }
    }
    KeepRequestPayload => match answer_time {
      Some(time) => replace_time(request.payload, time)
      None => request.payload
    }
    EmptyPayload => Bytes::new(0)
  }
  {
    version: request.version,
    command: request.command,
    response: flag,
    vin: request.vin,
    encryption: request.encryption,
    payload,
  }
}

///|
/// 兼容简写：现行标准形态。
pub fn response_frame(request : Frame, flag : ResponseFlag) -> Frame {
  let payload = if request.payload.length() >= 6 {
    request.payload[0:6].to_owned()
  } else {
    request.payload
  }
  {
    version: request.version,
    command: request.command,
    response: flag,
    vin: request.vin,
    encryption: request.encryption,
    payload,
  }
}

///|
/// 标记为命令包：主动发起方必须置 0xFE。
pub fn command_frame(frame : Frame) -> Frame {
  { version: frame.version, command: frame.command, response: Command, vin: frame.vin, encryption: frame.encryption, payload: frame.payload }
}

///|
pub fn is_response_packet(frame : Frame) -> Bool {
  match frame.response {
    Command => false
    _ => true
  }
}

///|
/// 车端上行命令（附录 B 表 B.2）：登入、实时、补发、登出、心跳、校时、激活、密钥交换。
pub fn Command::is_terminal_uplink(self : Command) -> Bool {
  match self {
    VehicleLogin | RealtimeReport | ResendReport | VehicleLogout | Heartbeat |
    TerminalTimeSync | Activate | KeyExchange => true
    _ => false
  }
}

///|
/// 平台间上行命令（正文表 3）：登入、实时、补发、登出、平台登入/登出、密钥交换。
pub fn Command::is_platform_uplink(self : Command) -> Bool {
  match self {
    VehicleLogin | RealtimeReport | ResendReport | VehicleLogout | PlatformLogin |
    PlatformLogout | KeyExchange => true
    _ => false
  }
}
