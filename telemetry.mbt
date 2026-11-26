// telemetry.mbt
// 依据：GB/T 32960.3-2025 表 7（实时信息上报）、表 8（车端签名）、表 9（信息类型标志）

///|
/// 车端数字签名（表 8）：签名类型(1) R长度(2) R值(N) S长度(2) S值(M)。
///
/// 本项目只做结构解析与保留，不做验签；验签需要 SM2/RSA/ECC 公钥，属部署方。
pub(all) struct Signature {
  kind_raw : Int32
  r : Bytes
  s : Bytes
}

///|
pub fn Signature::decode_at(
  bytes : BytesView,
  offset : Int32,
  end : Int32,
) -> (Signature, Int32) raise FrameError {
  ensure_at(bytes, offset, 3, what="签名类型与 R 长度")
  let r_len = u16_be(bytes, offset + 1)
  if offset + 3 + r_len + 2 > end {
    raise Payload(message="签名 R 值长度 \{r_len} 超出剩余字节")
  }
  let r = bytes[offset + 3:offset + 3 + r_len].to_owned()
  let s_len_at = offset + 3 + r_len
  let s_len = u16_be(bytes, s_len_at)
  if s_len_at + 2 + s_len > end {
    raise Payload(message="签名 S 值长度 \{s_len} 超出剩余字节")
  }
  let s = bytes[s_len_at + 2:s_len_at + 2 + s_len].to_owned()
  ({ kind_raw: bytes[offset].to_int(), r, s, }, 3 + r_len + 2 + s_len)
}

///|
/// 一帧实时上报携带的某一类信息体。
pub(all) enum ReportItem {
  Vehicle(WholeVehicle)
  Motors(DriveMotorData)
  FuelCell(FuelCellHydrogen)
  Engine(Engine)
  Location(VehicleLocation)
  Alarm(Alarm)
  BatteryCellVoltage(BatteryCellVoltage)
  BatteryTemperature(BatteryTemperature)
  FuelCellStack(FuelCellStackData)
  SuperCapacitor(SuperCapacitor)
  SuperCapacitorExtreme(SuperCapacitorExtreme)
  Custom(Bytes)
}

///|
pub fn ReportItem::info_type(self : ReportItem) -> InfoType {
  match self {
    Vehicle(_) => InfoType::WholeVehicle
    Motors(_) => InfoType::DriveMotor
    FuelCell(_) => InfoType::FuelCellHydrogen
    Engine(_) => InfoType::Engine
    Location(_) => InfoType::Location
    Alarm(_) => InfoType::Alarm
    BatteryCellVoltage(_) => InfoType::BatteryCellVoltage
    BatteryTemperature(_) => InfoType::BatteryTemperature
    FuelCellStack(_) => InfoType::FuelCellStack
    SuperCapacitor(_) => InfoType::SuperCapacitor
    SuperCapacitorExtreme(_) => InfoType::SuperCapacitorExtreme
    Custom(_) => InfoType::Custom
  }
}

///|
pub fn decode_item(
  bytes : BytesView,
  offset : Int32,
  end : Int32,
) -> (ReportItem, Int32) raise FrameError {
  ensure_at(bytes, offset, 1, what="信息类型标志")
  let kind = InfoType::from_byte(bytes[offset])
  let start = offset + 1
  let (item, used) = match kind {
    InfoType::WholeVehicle => {
      ensure_at(bytes, start, WHOLE_VEHICLE_LEN, what="整车数据")
      (
        Vehicle(WholeVehicle::decode(bytes[start:start + WHOLE_VEHICLE_LEN])),
        WHOLE_VEHICLE_LEN,
      )
    }
    InfoType::DriveMotor => {
      let (data, n) = DriveMotorData::decode_at(bytes, start, end)
      (Motors(data), n)
    }
    InfoType::FuelCellHydrogen => {
      ensure_at(
        bytes,
        start,
        FUEL_CELL_HYDROGEN_LEN,
        what="燃料电池发动机及车载氢系统",
      )
      (
        FuelCell(
          FuelCellHydrogen::decode(bytes[start:start + FUEL_CELL_HYDROGEN_LEN]),
        ),
        FUEL_CELL_HYDROGEN_LEN,
      )
    }
    InfoType::Engine => {
      ensure_at(bytes, start, ENGINE_LEN, what="发动机数据")
      (Engine(Engine::decode(bytes[start:start + ENGINE_LEN])), ENGINE_LEN)
    }
    InfoType::Location => {
      ensure_at(bytes, start, LOCATION_LEN, what="车辆位置数据")
      (
        Location(VehicleLocation::decode(bytes[start:start + LOCATION_LEN])),
        LOCATION_LEN,
      )
    }
    InfoType::Alarm => {
      let (data, n) = Alarm::decode_at(bytes, start, end)
      (Alarm(data), n)
    }
    InfoType::BatteryCellVoltage => {
      let (data, n) = BatteryCellVoltage::decode_at(bytes, start, end)
      (BatteryCellVoltage(data), n)
    }
    InfoType::BatteryTemperature => {
      let (data, n) = BatteryTemperature::decode_at(bytes, start, end)
      (BatteryTemperature(data), n)
    }
    InfoType::FuelCellStack => {
      let (data, n) = FuelCellStackData::decode_at(bytes, start, end)
      (FuelCellStack(data), n)
    }
    InfoType::SuperCapacitor => {
      let (data, n) = SuperCapacitor::decode_at(bytes, start, end)
      (SuperCapacitor(data), n)
    }
    InfoType::SuperCapacitorExtreme => {
      ensure_at(
        bytes,
        start,
        SUPERCAP_EXTREME_LEN,
        what="超级电容器极值数据",
      )
      (
        SuperCapacitorExtreme(
          SuperCapacitorExtreme::decode(
            bytes[start:start + SUPERCAP_EXTREME_LEN],
          ),
        ),
        SUPERCAP_EXTREME_LEN,
      )
    }
    InfoType::Custom => {
      ensure_at(bytes, start, 2, what="自定义数据长度")
      let len = u16_be(bytes, start)
      if len < 1 || start + 2 + len > end {
        raise Payload(
          message="自定义数据长度 \{len} 不合法或超出剩余字节",
        )
      }
      (Custom(bytes[start + 2:start + 2 + len].to_owned()), 2 + len)
    }
    InfoType::Signature =>
      raise Payload(
        message="签名数据开始标识不应作为信息类型出现在此位置",
      )
    InfoType::Unknown(code) => raise UnsupportedInfoType(code~)
  }
  (item, 1 + used)
}

///|
pub fn encode_item(item : ReportItem) -> Bytes {
  let body = match item {
    Vehicle(data) => data.to_bytes()
    Motors(data) => data.to_bytes()
    FuelCell(data) => data.to_bytes()
    Engine(data) => data.to_bytes()
    Location(data) => data.to_bytes()
    Alarm(data) => data.to_bytes()
    BatteryCellVoltage(data) => data.to_bytes()
    BatteryTemperature(data) => data.to_bytes()
    FuelCellStack(data) => data.to_bytes()
    SuperCapacitor(data) => data.to_bytes()
    SuperCapacitorExtreme(data) => data.to_bytes()
    Custom(data) => {
      let out : Array[Byte] = []
      push_u16_be(out, data.length())
      for byte in data {
        out.push(byte)
      }
      Bytes::from_array(out)
    }
  }
  let out : Array[Byte] = []
  out.push(item.info_type().to_byte())
  for byte in body {
    out.push(byte)
  }
  Bytes::from_array(out)
}

///|
/// 实时/补发上报数据单元（表 7）：数据采集时间(6) + (信息类型标志 + 信息体)* + 可选签名。
pub(all) struct Telemetry {
  time : Time
  items : Array[ReportItem]
  signature : Signature?
}

///|
pub fn Telemetry::new(time~ : Time, items~ : Array[ReportItem]) -> Telemetry {
  { time, items, signature: None, }
}

///|
pub fn Telemetry::with_signature(
  self : Telemetry,
  signature~ : Signature,
) -> Telemetry {
  { time: self.time, items: self.items, signature: Some(signature), }
}

///|
pub fn Telemetry::to_bytes(self : Telemetry) -> Bytes {
  let out : Array[Byte] = []
  for byte in self.time.to_bytes() {
    out.push(byte)
  }
  for item in self.items {
    for byte in encode_item(item) {
      out.push(byte)
    }
  }
  match self.signature {
    Some(sig) => {
      out.push(b'\xff')
      out.push(sig.kind_raw.to_byte())
      push_u16_be(out, sig.r.length())
      for byte in sig.r {
        out.push(byte)
      }
      push_u16_be(out, sig.s.length())
      for byte in sig.s {
        out.push(byte)
      }
    }
    None => ()
  }
  Bytes::from_array(out)
}

///|
pub fn Telemetry::decode(bytes : BytesView) -> Telemetry raise FrameError {
  ensure_at(bytes, 0, 6, what="数据采集时间")
  let time = Time::from_bytes(bytes[0:6])
  let items : Array[ReportItem] = []
  let end = bytes.length()
  let mut offset = 6
  let mut signature : Signature? = None
  while offset < end {
    // 0xFF 是签名数据开始标识，其后是签名信息
    if bytes[offset].to_int() == 0xff {
      let (sig, used) = Signature::decode_at(bytes, offset + 1, end)
      signature = Some(sig)
      offset = offset + 1 + used
      if offset != end {
        raise Payload(
          message="签名信息后仍有 \{end - offset} 字节未解析",
        )
      }
    } else {
      let (item, used) = decode_item(bytes, offset, end)
      items.push(item)
      offset = offset + used
    }
  }
  { time, items, signature, }
}

///|
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
