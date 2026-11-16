// realtime.mbt

///|
/// Signed 32-bit big-endian helpers (coordinates use two's complement).
pub fn push_i32_be(out : Array[Byte], value : Int32) -> Unit {
  out.push((value >> 24).to_byte())
  out.push((value >> 16).to_byte())
  out.push((value >> 8).to_byte())
  out.push(value.to_byte())
}

///|
pub fn i32_be(bytes : BytesView, offset : Int32) -> Int32 {
  (bytes[offset].to_int() << 24) |
  (bytes[offset + 1].to_int() << 16) |
  (bytes[offset + 2].to_int() << 8) |
  bytes[offset + 3].to_int()
}

///|
/// Realtime information types carried by a realtime report.
pub(all) enum InfoType {
  WholeVehicle
  DriveMotor
  FuelCell
  Engine
  Location
  Extreme
  Alarm
  StorageVoltage
  StorageTemperature
  StorageExtreme
  Unknown(Int32)
}

///|
pub fn InfoType::to_byte(self : InfoType) -> Byte {
  match self {
    WholeVehicle => b'\x01'
    DriveMotor => b'\x02'
    FuelCell => b'\x03'
    Engine => b'\x04'
    Location => b'\x05'
    Extreme => b'\x06'
    Alarm => b'\x07'
    StorageVoltage => b'\x08'
    StorageTemperature => b'\x09'
    StorageExtreme => b'\x0a'
    Unknown(n) => n.to_byte()
  }
}

///|
pub fn InfoType::from_byte(byte : Byte) -> InfoType {
  match byte.to_int() {
    0x01 => WholeVehicle
    0x02 => DriveMotor
    0x03 => FuelCell
    0x04 => Engine
    0x05 => Location
    0x06 => Extreme
    0x07 => Alarm
    0x08 => StorageVoltage
    0x09 => StorageTemperature
    0x0a => StorageExtreme
    n => Unknown(n)
  }
}

///|
/// Snapshot of whole-vehicle state items used for demonstration and tests.
pub(all) struct WholeVehicle {
  status : Int32
  charge_status : Int32
  speed : Int32
  soc : Int32
  voltage : Int32
  odometer : Int32
}

///|
pub fn WholeVehicle::to_bytes(self : WholeVehicle) -> Bytes {
  let out : Array[Byte] = []
  out.push(self.status.to_byte())
  out.push(self.charge_status.to_byte())
  out.push(self.speed.to_byte())
  out.push(self.soc.to_byte())
  push_u16_be(out, self.voltage)
  out.push((self.odometer >> 16).to_byte())
  out.push((self.odometer >> 8).to_byte())
  out.push(self.odometer.to_byte())
  Bytes::from_array(out)
}

///|
pub fn WholeVehicle::parse(bytes : BytesView) -> WholeVehicle raise FrameError {
  if bytes.length() != 9 {
    raise Payload(
      message="whole-vehicle payload must be 9 bytes, got \{bytes.length()}",
    )
  }
  {
    status: bytes[0].to_int(),
    charge_status: bytes[1].to_int(),
    speed: bytes[2].to_int(),
    soc: bytes[3].to_int(),
    voltage: u16_be(bytes, 4),
    odometer: bytes[6].to_int() * 65536 + bytes[7].to_int() * 256 + bytes[8].to_int(),
  }
}

///|
/// Vehicle position, with longitude/latitude scaled by 1e6 (degrees).
pub(all) struct Location {
  status : Int32
  longitude : Int32
  latitude : Int32
}

///|
pub fn Location::to_bytes(self : Location) -> Bytes {
  let out : Array[Byte] = []
  out.push(self.status.to_byte())
  push_i32_be(out, self.longitude)
  push_i32_be(out, self.latitude)
  Bytes::from_array(out)
}

///|
pub fn Location::parse(bytes : BytesView) -> Location raise FrameError {
  if bytes.length() != 9 {
    raise Payload(message="location payload must be 9 bytes, got \{bytes.length()}")
  }
  {
    status: bytes[0].to_int(),
    longitude: i32_be(bytes, 1),
    latitude: i32_be(bytes, 5),
  }
}

///|
pub(all) enum InfoItem {
  WholeVehicleItem(WholeVehicle)
  LocationItem(Location)
}

///|
pub fn InfoItem::info_type(self : InfoItem) -> InfoType {
  match self {
    WholeVehicleItem(_) => InfoType::WholeVehicle
    LocationItem(_) => InfoType::Location
  }
}

///|
fn encode_item(item : InfoItem) -> Bytes {
  let body = match item {
    WholeVehicleItem(data) => data.to_bytes()
    LocationItem(data) => data.to_bytes()
  }
  let out : Array[Byte] = []
  out.push(item.info_type().to_byte())
  out.push(body.length().to_byte())
  for byte in body {
    out.push(byte)
  }
  Bytes::from_array(out)
}

///|
pub(all) struct RealtimeReport {
  time : Time
  items : Array[InfoItem]
}

///|
pub fn RealtimeReport::new(time~ : Time, items~ : Array[InfoItem]) -> RealtimeReport {
  { time, items }
}

///|
pub fn RealtimeReport::to_bytes(self : RealtimeReport) -> Bytes {
  let out : Array[Byte] = []
  for byte in self.time.to_bytes() {
    out.push(byte)
  }
  for item in self.items {
    for byte in encode_item(item) {
      out.push(byte)
    }
  }
  Bytes::from_array(out)
}

///|
pub fn RealtimeReport::parse(bytes : BytesView) -> RealtimeReport raise FrameError {
  if bytes.length() < 6 {
    raise TooShort(needed=6, actual=bytes.length())
  }
  let items : Array[InfoItem] = []
  let mut offset = 6
  while offset < bytes.length() {
    if offset + 2 > bytes.length() {
      raise Payload(message="truncated info item header at offset \{offset}")
    }
    let kind = InfoType::from_byte(bytes[offset])
    let len = bytes[offset + 1].to_int()
    let start = offset + 2
    if start + len > bytes.length() {
      raise Payload(message="truncated info item body at offset \{offset}")
    }
    let body = bytes[start:start + len]
    let item = match kind {
      InfoType::WholeVehicle => WholeVehicleItem(WholeVehicle::parse(body))
      InfoType::Location => LocationItem(Location::parse(body))
      _ => raise Payload(message="unsupported info type \{kind.name()}")
    }
    items.push(item)
    offset = start + len
  }
  { time: Time::from_bytes(bytes[0:6]), items }
}

///|
pub fn InfoType::name(self : InfoType) -> String {
  match self {
    WholeVehicle => "whole-vehicle"
    DriveMotor => "drive-motor"
    FuelCell => "fuel-cell"
    Engine => "engine"
    Location => "location"
    Extreme => "extreme"
    Alarm => "alarm"
    StorageVoltage => "storage-voltage"
    StorageTemperature => "storage-temperature"
    StorageExtreme => "storage-extreme"
    Unknown(_) => "unknown"
  }
}