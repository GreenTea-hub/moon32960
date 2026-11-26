// negative.mbt
// 依据：GB/T 32960.3-2025 表 31（数据单元加密密钥交换）、表 B.3/B.4（激活与激活应答）、
//     表 B.5~B.13（参数查询、参数设置、车载终端控制）
//
// 这些命令此前被列为「不做」，是上一轮驳回点名的缺口。本文件补齐全部数据单元结构。

///|
/// 数据单元加密密钥交换（命令 0x0B，表 31，上下行均可）。
///
/// 布局：密钥类型(1) 密钥长度(2) 密钥(N) 启用时间(6) 失效时间(6)
///
/// 本项目只做结构解析与保留：真正的密钥安装由部署方的密钥管理系统完成，
/// 见 docs/CONFORMANCE.md 的「外部配套责任」一节。
pub(all) struct KeyExchange {
  key_type : Int32
  key : Bytes
  enable_from : Time
  expire_at : Time
}

///|
pub fn KeyExchange::decode(bytes : BytesView) -> KeyExchange raise FrameError {
  ensure_at(bytes, 0, 3, what="密钥类型与密钥长度")
  let key_type = bytes[0].to_int()
  let key_len = u16_be(bytes, 1)
  check_count(key_len, 0, 65531, field="密钥长度")
  let key_at = 3
  ensure_at(bytes, key_at, key_len + 12, what="密钥与有效期")
  let key = bytes[key_at:key_at + key_len].to_owned()
  let enable_from = Time::from_bytes(
    bytes[key_at + key_len:key_at + key_len + 6],
  )
  let expire_at = Time::from_bytes(
    bytes[key_at + key_len + 6:key_at + key_len + 12],
  )
  if bytes.length() != key_at + key_len + 12 {
    raise BadLength(expected=key_at + key_len + 12, actual=bytes.length())
  }
  { key_type, key, enable_from, expire_at, }
}

///|
pub fn KeyExchange::to_bytes(self : KeyExchange) -> Bytes {
  let out : Array[Byte] = []
  out.push(self.key_type.to_byte())
  push_u16_be(out, self.key.length())
  for byte in self.key {
    out.push(byte)
  }
  for byte in self.enable_from.to_bytes() {
    out.push(byte)
  }
  for byte in self.expire_at.to_bytes() {
    out.push(byte)
  }
  Bytes::from_array(out)
}

///|
/// 密钥类型名称（表 31）：0x02 RSA、0x03 AES、0x04 SM2、0x05 SM4。
pub fn KeyExchange::key_type_name(self : KeyExchange) -> String {
  match self.key_type {
    0x02 => "RSA"
    0x03 => "AES"
    0x04 => "SM2"
    0x05 => "SM4"
    _ => "预留"
  }
}

///|
/// 激活信息（命令行 0x09，表 B.3）。
///
/// 布局：数据采集时间(6) 芯片ID(16) 公钥长度(2) 公钥(N) VIN(17) 签名信息
pub(all) struct Activate {
  time : Time
  chip_id : String
  public_key : Bytes
  vin : String
  signature : Signature
}

///|
pub const ACTIVATE_MIN_LEN : Int32 = 41

///|
pub fn Activate::decode(bytes : BytesView) -> Activate raise FrameError {
  ensure_at(bytes, 0, ACTIVATE_MIN_LEN, what="激活信息")
  let time = Time::from_bytes(bytes[0:6])
  let chip_id = @utf8.decode(bytes[6:22]) catch {
    _ => raise Payload(message="芯片 ID 不是合法 UTF-8")
  }
  let pk_len = u16_be(bytes, 22)
  check_count(pk_len, 0, 65531, field="公钥长度")
  ensure_at(bytes, 24, pk_len + 17, what="公钥与 VIN")
  let public_key = bytes[24:24 + pk_len].to_owned()
  let vin = decode_vin(bytes[24 + pk_len:24 + pk_len + 17])
  let (signature, used) = Signature::decode_at(
    bytes,
    24 + pk_len + 17,
    bytes.length(),
  )
  if 24 + pk_len + 17 + used != bytes.length() {
    raise BadLength(expected=24 + pk_len + 17 + used, actual=bytes.length())
  }
  { time, chip_id, public_key, vin, signature, }
}

///|
pub fn Activate::to_bytes(self : Activate) -> Bytes raise FrameError {
  let chip = @utf8.encode(self.chip_id)
  if chip.length() != 16 {
    raise Payload(
      message="芯片 ID 应为 16 字符，实际 \{chip.length()}",
    )
  }
  let out : Array[Byte] = []
  for byte in self.time.to_bytes() {
    out.push(byte)
  }
  for byte in chip {
    out.push(byte)
  }
  push_u16_be(out, self.public_key.length())
  for byte in self.public_key {
    out.push(byte)
  }
  for byte in encode_vin(self.vin) {
    out.push(byte)
  }
  // 表 B.3：签名信息直接接在 VIN 后，按表 8 从签名类型开始；0xFF 是实时上报里的类型标志
  out.push(self.signature.kind_raw.to_byte())
  push_u16_be(out, self.signature.r.length())
  for byte in self.signature.r {
    out.push(byte)
  }
  push_u16_be(out, self.signature.s.length())
  for byte in self.signature.s {
    out.push(byte)
  }
  Bytes::from_array(out)
}

///|
/// 激活状态（表 B.4）：0x01 成功、0x02 失败。
pub(all) enum ActivateState {
  ActivateOk
  ActivateFail
  Unknown(Int32)
}

///|
pub fn ActivateState::from_byte(byte : Int32) -> ActivateState {
  match byte {
    0x01 => ActivateOk
    0x02 => ActivateFail
    n => Unknown(n)
  }
}

///|
/// 激活结果信息（表 B.4）：0x00 激活成功、0x01 芯片已激活、0x02 VIN 重复。
pub(all) enum ActivateInfo {
  ActivateSucceeded
  ChipAlreadyActivated
  VinDuplicate
  Unknown(Int32)
}

///|
pub fn ActivateInfo::from_byte(byte : Int32) -> ActivateInfo {
  match byte {
    0x00 => ActivateSucceeded
    0x01 => ChipAlreadyActivated
    0x02 => VinDuplicate
    n => Unknown(n)
  }
}

///|
pub fn ActivateInfo::to_byte(self : ActivateInfo) -> Byte {
  match self {
    ActivateSucceeded => b'\x00'
    ChipAlreadyActivated => b'\x01'
    VinDuplicate => b'\x02'
    Unknown(n) => n.to_byte()
  }
}

///|
/// 激活结果应答（命令 0x0A，表 B.4）：激活状态(1) 信息(1)。
pub(all) struct ActivateAck {
  state : ActivateState
  info : ActivateInfo
}

///|
pub fn ActivateAck::decode(bytes : BytesView) -> ActivateAck raise FrameError {
  expect_len(bytes.length(), 2, what="激活结果应答")
  {
    state: ActivateState::from_byte(bytes[0].to_int()),
    info: ActivateInfo::from_byte(bytes[1].to_int()),
  }
}

///|
pub fn ActivateAck::to_bytes(self : ActivateAck) -> Bytes {
  let out : Array[Byte] = []
  match self.state {
    ActivateOk => out.push(b'\x01')
    ActivateFail => out.push(b'\x02')
    Unknown(n) => out.push(n.to_byte())
  }
  out.push(self.info.to_byte())
  Bytes::from_array(out)
}

///|
/// 参数项（表 B.7/B.8）：参数 ID(1) + 参数值（长度随 ID）。
pub(all) struct ParamItem {
  id : Int32
  value : Bytes
}

///|
/// 参数值的固定长度，依据表 B.8。
///
/// 表 B.8 只定义 0x01~0x08；0x09~0x7F 为预留、0x80~0xFE 为用户自定义，
/// 长度由厂商约定，标准未给出，因此返回 None 而不是编造宽度。
/// 0x04 是域名长度、0x05 是域名内容，二者成对出现，也返回 None。
pub fn param_len(id : Int32) -> Int32? {
  match id {
    0x01 => Some(2)
    0x02 => Some(1)
    0x03 => Some(1)
    0x06 => Some(2)
    0x07 => Some(5)
    0x08 => Some(5)
    _ => None
  }
}

///|
/// 参数查询（命令 0x80，表 B.5）：参数查询时间(6) 参数总数 N(1) 参数 ID×N。
pub(all) struct ParamQuery {
  time : Time
  ids : Array[Int32]
}

///|
pub fn ParamQuery::decode(bytes : BytesView) -> ParamQuery raise FrameError {
  ensure_at(bytes, 0, 7, what="参数查询")
  let time = Time::from_bytes(bytes[0:6])
  let count = bytes[6].to_int()
  check_count(count, 0, 252, field="参数总数")
  ensure_at(bytes, 7, count, what="参数 ID 列表")
  if bytes.length() != 7 + count {
    raise BadLength(expected=7 + count, actual=bytes.length())
  }
  let ids : Array[Int32] = []
  for i in 0..<count {
    ids.push(bytes[7 + i].to_int())
  }
  { time, ids, }
}

///|
pub fn ParamQuery::to_bytes(self : ParamQuery) -> Bytes {
  let out : Array[Byte] = []
  for byte in self.time.to_bytes() {
    out.push(byte)
  }
  out.push(self.ids.length().to_byte())
  for id in self.ids {
    out.push(id.to_byte())
  }
  Bytes::from_array(out)
}

///|
/// 参数设置（命令 0x81，表 B.9）：时间(6) 参数总数 N(1) 参数项列表。
///
/// 任一项非法则整包否定（标准原文），校验失败返回错误应答。
pub(all) struct ParamSetting {
  time : Time
  items : Array[ParamItem]
}

///|
pub fn ParamSetting::decode(bytes : BytesView) -> ParamSetting raise FrameError {
  ensure_at(bytes, 0, 7, what="参数设置")
  let time = Time::from_bytes(bytes[0:6])
  let count = bytes[6].to_int()
  check_count(count, 0, 252, field="参数总数")
  let mut cursor = 7
  let items : Array[ParamItem] = []
  for _ in 0..<count {
    ensure_at(bytes, cursor, 1, what="参数 ID")
    let id = bytes[cursor].to_int()
    cursor = cursor + 1
    if id == 0x04 {
      // 域名长度
      ensure_at(bytes, cursor, 1, what="域名长度")
      let len = bytes[cursor].to_int()
      cursor = cursor + 1 + len
      ensure_at(bytes, cursor - len, len, what="域名")
      items.push({ id, value: bytes[cursor - len:cursor].to_owned(), })
    } else if id == 0x05 {
      // 域名内容，长度由 0x04 给出；这里保守取到下一个已知边界
      raise Payload(
        message="参数 0x05 依赖 0x04 的域名长度，需成对解析，暂不支持单独出现",
      )
    } else {
      let len = param_len(id)
      let width = match len {
        Some(n) => n
        None => 0
      }
      if width == 0 {
        raise Payload(message="未知参数 ID 0x\{id}")
      }
      ensure_at(bytes, cursor, width, what="参数值")
      items.push({ id, value: bytes[cursor:cursor + width].to_owned(), })
      cursor = cursor + width
    }
  }
  if cursor != bytes.length() {
    raise BadLength(expected=cursor, actual=bytes.length())
  }
  { time, items, }
}

///|
pub fn ParamSetting::to_bytes(self : ParamSetting) -> Bytes {
  let out : Array[Byte] = []
  for byte in self.time.to_bytes() {
    out.push(byte)
  }
  out.push(self.items.length().to_byte())
  for item in self.items {
    out.push(item.id.to_byte())
    for byte in item.value {
      out.push(byte)
    }
  }
  Bytes::from_array(out)
}

///|
/// 车载终端控制（命令 0x82，表 B.10）：时间(6) 命令ID(1) 命令参数。
pub(all) struct TerminalControl {
  time : Time
  command_id : Int32
  params : Bytes
}

///|
pub fn TerminalControl::decode(
  bytes : BytesView,
) -> TerminalControl raise FrameError {
  ensure_at(bytes, 0, 7, what="车载终端控制")
  {
    time: Time::from_bytes(bytes[0:6]),
    command_id: bytes[6].to_int(),
    params: bytes[7:].to_owned(),
  }
}

///|
pub fn TerminalControl::to_bytes(self : TerminalControl) -> Bytes {
  let out : Array[Byte] = []
  for byte in self.time.to_bytes() {
    out.push(byte)
  }
  out.push(self.command_id.to_byte())
  for byte in self.params {
    out.push(byte)
  }
  Bytes::from_array(out)
}

///|
/// 控制命令名称（表 B.11）。
pub fn TerminalControl::command_name(self : TerminalControl) -> String {
  match self.command_id {
    0x00 => "未用"
    0x01 => "远程升级"
    0x02 => "车载终端关机"
    0x03 => "车载终端复位"
    0x04 => "恢复出厂设置"
    0x05 => "断开数据通信链路"
    0x06 => "报警/预警"
    0x07 => "开启抽样监测链路"
    _ => "预留或自定义"
  }
}

///|
/// 激活应答帧：命令 0x0A（下行），数据单元为表 B.4 的 2 字节。
pub fn activate_ack_frame(
  request : Frame,
  state : ActivateState,
  info : ActivateInfo,
) -> Frame {
  {
    version: request.version,
    command: ActivateAck,
    response: Success,
    vin: request.vin,
    encryption: request.encryption,
    payload: { state, info, }.to_bytes(),
  }
}
