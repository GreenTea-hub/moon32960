// response.mbt
///|
/// 通信场景。GB/T 32960.3 对两者给出的应答规则不同，不能混用。
pub(all) enum Scope {
  /// 车载终端到平台，规则见附录 B（资料性）。
  TerminalToPlatform
  /// 客户端平台到服务端平台，规则见正文第 5 章（规范性）。
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
/// 应答包的数据单元形态。标准与地方口径存在差异，这里显式给出三种，默认取国标原文口径。
pub(all) enum ResponseShape {
  /// 附录 B.3.3.2：只变更应答标志与应答报文时间，其余报文内容与主动发送报文一致。
  KeepRequestPayload
  /// 部分地方标准：保留报文时间，删除其余报文内容。
  TimeOnly
  /// 简化口径：数据单元为空。不与任何标准条文对应，仅供联调时使用。
  EmptyPayload
}

///|
pub fn ResponseShape::name(self : ResponseShape) -> String {
  match self {
    KeepRequestPayload => "keep-request-payload (附录 B)"
    TimeOnly => "time-only (地方口径)"
    EmptyPayload => "empty-payload (联调用)"
  }
}

///|
/// 把数据单元的前 6 字节替换为应答报文时间；不足 6 字节时直接给出时间字段。
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
/// 构造应答包。
///
/// 附录 B 口径下数据单元与请求保持一致，仅把报文时间换成应答时刻；加密方式沿用请求，
/// 因此若请求是加密帧，应答编码时同样需要注入密钥。
pub fn build_response(
  request : Frame,
  flag : ResponseFlag,
  shape~ : ResponseShape = KeepRequestPayload,
  answer_time~ : Time? = None,
  key~ : KeyMaterial = NoKey,
) -> Frame raise FrameError {
  let _ = key
  let payload = match shape {
    KeepRequestPayload => match answer_time {
      Some(time) => replace_time(request.payload, time)
      None => request.payload
    }
    TimeOnly => match answer_time {
      Some(time) => time.to_bytes()
      None =>
        if request.payload.length() >= 6 {
          request.payload[0:6].to_owned()
        } else {
          raise Payload(message="应答需要报文时间，但请求数据单元不足 6 字节")
        }
    }
    EmptyPayload => Bytes::new(0)
  }
  Frame::new(
    command=request.command,
    response=flag,
    vin=request.vin,
    encryption=request.encryption,
    payload~,
  )
}

///|
/// 兼容旧调用的简写：附录 B 口径、沿用请求报文时间。
pub fn response_frame(request : Frame, flag : ResponseFlag) -> Frame {
  {
    command: request.command,
    response: flag,
    vin: request.vin,
    encryption: request.encryption,
    payload: request.payload,
  }
}

///|
/// 标记为命令包。主动发起方必须置 0xFE。
pub fn command_frame(frame : Frame) -> Frame {
  {
    command: frame.command,
    response: Command,
    vin: frame.vin,
    encryption: frame.encryption,
    payload: frame.payload,
  }
}

///|
/// 是否为应答包（应答标志非 0xFE）。
pub fn is_response_packet(frame : Frame) -> Bool {
  match frame.response {
    Command => false
    _ => true
  }
}

///|
/// 命令方向。0x08 终端校时是**上行**命令（终端向平台请求校时），只有 0x80 是下行。
pub fn Command::is_uplink(self : Command) -> Bool {
  match self {
    VehicleLogin | RealtimeReport | ResendReport | VehicleLogout | PlatformLogin |
    PlatformLogout | Heartbeat | TerminalTimeSync => true
    _ => false
  }
}

///|
pub fn Command::is_downlink(self : Command) -> Bool {
  match self {
    PlatformDownlink => true
    _ => false
  }
}

///|
/// 车端上行命令集（附录 B）：含登入、实时、补发、登出、心跳、终端校时。
pub fn Command::is_terminal_uplink(self : Command) -> Bool {
  match self {
    VehicleLogin | RealtimeReport | ResendReport | VehicleLogout | Heartbeat |
    TerminalTimeSync => true
    _ => false
  }
}

///|
/// 该命令是否属于平台间场景（正文第 5 章列出的平台命令）。
pub fn Command::is_platform_uplink(self : Command) -> Bool {
  match self {
    PlatformLogin | PlatformLogout | RealtimeReport | ResendReport => true
    _ => false
  }
}
