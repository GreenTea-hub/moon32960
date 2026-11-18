// response.mbt
///|
/// 应答帧：命令单元与请求相同，应答标志取处理结果，数据单元为空。
///
/// 平台对登入、实时上报、补发上报、登出、心跳、校时均按本规则应答；终端对下行命令同样如此。
pub fn response_frame(request : Frame, flag : ResponseFlag) -> Frame {
  Frame::new(
    command=request.command,
    response=flag,
    vin=request.vin,
    encryption=request.encryption,
    payload=Bytes::new(0),
  )
}

///|
/// 快速判断一帧是否为应答帧（应答标志非「无效」，且命令属于终端上行集）。
pub fn is_ack(frame : Frame) -> Bool {
  match frame.response {
    Success | Failure | VinDuplicate | CommandNotRecognized => true
    _ => false
  }
}
