// telemetry.mbt
///|
/// 一帧实时上报中携带的某一类信息体。
pub(all) enum ReportItem {
  Vehicle(WholeVehicle)
  Motors(DriveMotorData)
  FuelCell(FuelCell)
  Engine(Engine)
  Location(VehicleLocation)
  Extreme(Extreme)
  Alarm(Alarm)
  StorageVoltage(StorageVoltage)
  StorageTemperature(StorageTemperature)
}

///|
pub fn ReportItem::info_type(self : ReportItem) -> InfoType {
  match self {
    Vehicle(_) => InfoType::WholeVehicle
    Motors(_) => InfoType::DriveMotor
    FuelCell(_) => InfoType::FuelCell
    Engine(_) => InfoType::Engine
    Location(_) => InfoType::Location
    Extreme(_) => InfoType::Extreme
    Alarm(_) => InfoType::Alarm
    StorageVoltage(_) => InfoType::StorageVoltage
    StorageTemperature(_) => InfoType::StorageTemperature
  }
}

///|
/// 按信息类型标志解析一个信息体，返回解析结果与消费字节数。
///
/// `end` 是本帧数据单元的结束位置，用于防止变长字段越界读到下一帧。
pub fn decode_item(
  bytes : BytesView,
  offset : Int32,
  end : Int32,
) -> (ReportItem, Int32) raise FrameError {
  ensure_at(bytes, offset, 1, what="信息类型标志")
  let kind = InfoType::from_byte(bytes[offset])
  let body_start = offset + 1
  let (item, used) = match kind {
    InfoType::WholeVehicle => {
      ensure_at(bytes, body_start, WHOLE_VEHICLE_LEN, what="整车数据")
      (Vehicle(WholeVehicle::decode(bytes[body_start:body_start + WHOLE_VEHICLE_LEN])), WHOLE_VEHICLE_LEN)
    }
    InfoType::DriveMotor => {
      let (data, n) = DriveMotorData::decode_at(bytes, body_start, end)
      (Motors(data), n)
    }
    InfoType::FuelCell => {
      let (data, n) = FuelCell::decode_at(bytes, body_start, end)
      (FuelCell(data), n)
    }
    InfoType::Engine => {
      ensure_at(bytes, body_start, ENGINE_LEN, what="发动机数据")
      (Engine(Engine::decode(bytes[body_start:body_start + ENGINE_LEN])), ENGINE_LEN)
    }
    InfoType::Location => {
      ensure_at(bytes, body_start, LOCATION_LEN, what="车辆位置数据")
      (Location(VehicleLocation::decode(bytes[body_start:body_start + LOCATION_LEN])), LOCATION_LEN)
    }
    InfoType::Extreme => {
      ensure_at(bytes, body_start, EXTREME_LEN, what="极值数据")
      (Extreme(Extreme::decode(bytes[body_start:body_start + EXTREME_LEN])), EXTREME_LEN)
    }
    InfoType::Alarm => {
      let (data, n) = Alarm::decode_at(bytes, body_start, end)
      (Alarm(data), n)
    }
    InfoType::StorageVoltage => {
      let (data, n) = StorageVoltage::decode_at(bytes, body_start, end)
      (StorageVoltage(data), n)
    }
    InfoType::StorageTemperature => {
      let (data, n) = StorageTemperature::decode_at(bytes, body_start, end)
      (StorageTemperature(data), n)
    }
    InfoType::Unknown(code) => {
      raise UnsupportedInfoType(code=code)
    }
  }
  (item, 1 + used)
}

///|
/// 信息体编码：类型标志 + 内容。
pub fn encode_item(item : ReportItem) -> Bytes {
  let body = match item {
    Vehicle(data) => data.to_bytes()
    Motors(data) => data.to_bytes()
    FuelCell(data) => data.to_bytes()
    Engine(data) => data.to_bytes()
    Location(data) => data.to_bytes()
    Extreme(data) => data.to_bytes()
    Alarm(data) => data.to_bytes()
    StorageVoltage(data) => data.to_bytes()
    StorageTemperature(data) => data.to_bytes()
  }
  let out : Array[Byte] = []
  out.push(item.info_type().to_byte())
  for byte in body {
    out.push(byte)
  }
  Bytes::from_array(out)
}

///|
/// 实时/补发上报的数据单元头。
///
/// GB/T 32960.3-2016 表 7 的格式是「数据采集时间(6) + 信息类型标志 + 信息体」重复，**不含信息流水号**：
/// 团体标准与地方标准在引用该表时给出的都是这一结构。带 2 字节流水号的布局来自另一套标准
/// （其类型标志 0x01 为 OBD、0x05 为校时），不属于国标，仅作为兼容个别扩展实现的开关保留。
pub(all) enum ReportHeader {
  TimestampOnly
  TimestampWithSerial
}

///|
/// 实时信息上报（0x02）与补发信息上报（0x03）共用同一数据单元格式。
///
/// 布局：数据采集时间(6) [| 信息流水号(2)] | (信息类型标志(1) + 信息体)*
pub(all) struct Telemetry {
  time : Time
  serial : Int32?
  items : Array[ReportItem]
}

///|
pub fn Telemetry::new(time~ : Time, items~ : Array[ReportItem]) -> Telemetry {
  { time, serial: None, items }
}

///|
pub fn Telemetry::with_serial(self : Telemetry, serial~ : Int32) -> Telemetry {
  { time: self.time, serial: Some(serial), items: self.items }
}

///|
pub fn Telemetry::to_bytes(
  self : Telemetry,
  header~ : ReportHeader = TimestampOnly,
) -> Bytes raise FrameError {
  let out : Array[Byte] = []
  for byte in self.time.to_bytes() {
    out.push(byte)
  }
  match header {
    TimestampOnly => ()
    TimestampWithSerial => match self.serial {
      Some(value) => push_u16_be(out, value)
      None => raise Payload(message="选择了带流水号的布局，但未提供流水号")
    }
  }
  for item in self.items {
    for byte in encode_item(item) {
      out.push(byte)
    }
  }
  Bytes::from_array(out)
}

///|
pub fn Telemetry::decode(
  bytes : BytesView,
  header~ : ReportHeader = TimestampOnly,
) -> Telemetry raise FrameError {
  let header_len = match header {
    TimestampOnly => 6
    TimestampWithSerial => 8
  }
  ensure_at(bytes, 0, header_len, what="实时信息上报头部")
  let time = Time::from_bytes(bytes[0:6])
  let serial = match header {
    TimestampOnly => None
    TimestampWithSerial => Some(u16_be(bytes, 6))
  }
  let items : Array[ReportItem] = []
  let end = bytes.length()
  let mut offset = header_len
  while offset < end {
    let (item, used) = decode_item(bytes, offset, end)
    items.push(item)
    offset = offset + used
  }
  if offset != end {
    raise Payload(message="信息体解析未对齐：停在 \{offset}/\{end}")
  }
  { time, serial, items }
}

///|
/// 按信息类型取出第一个匹配的信息体，便于调用方直接访问常用项。
pub fn Telemetry::find(self : Telemetry, kind : InfoType) -> ReportItem? {
  let mut found : ReportItem? = None
  for item in self.items {
    if item.info_type().to_byte() == kind.to_byte() && found is None {
      found = Some(item)
    }
  }
  found
}

///|
pub fn Telemetry::has(self : Telemetry, kind : InfoType) -> Bool {
  self.find(kind) is Some(_)
}
