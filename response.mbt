// response.mbt
///|
/// 应答帧：命令单元与请求相同，应答标志取处理结果，按标准「删除其余报文内容」，数据单元为空；
/// 校验码随内容重新计算。
pub fn response_frame(request : Frame, flag : ResponseFlag) -> Frame {
  Frame::new(
    command=request.command,
    response=flag,
    vin=request.vin,
    // 应答帧数据单元为空，按标准删除其余报文内容，加密方式回到不加密
    encryption=Encryption::Plain,
    payload=Bytes::new(0),
  )
}

///|
/// 应答帧的可选形式：数据单元携带 6 字节应答时间。
///
/// 部分地方标准表述为「变更应答标志、应答报文时间，删除其余报文内容」，此时保留时间字段；
/// 国标正文未强制，默认构造为空数据单元。
pub fn response_frame_with_time(
  request : Frame,
  flag : ResponseFlag,
  time~ : Time,
) -> Frame {
  Frame::new(
    command=request.command,
    response=flag,
    vin=request.vin,
    encryption=Encryption::Plain,
    payload=time.to_bytes(),
  )
}

///|
/// 命令包标记：主动发起方把应答标志置 0xFE。
pub fn command_frame(frame : Frame) -> Frame {
  { command: frame.command, response: Command, vin: frame.vin, encryption: frame.encryption, payload: frame.payload }
}

///|
/// 是否为应答包（应答标志非 0xFE）。
pub fn is_response_packet(frame : Frame) -> Bool {
  match frame.response {
    Command => false
    _ => true
  }
}
