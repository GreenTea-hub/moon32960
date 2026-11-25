// alarm.mbt
// 依据：GB/T 32960.3-2025 表 23（报警数据）、表 24（通用报警标志位）

///|
/// 报警数据（信息类型标志 0x06）。等级 0~4，4 为热事件。
///
/// 布局：最高报警等级(1) 通用报警标志(4) + 五组列表
/// 每组为 总数(1) + N 条记录：储能/电机/发动机/其他各 4 字节，通用报警 2 字节。
pub(all) struct Alarm {
  level_raw : Int32
  general_flags_raw : Int32
  storage_faults : Array[Int32]
  motor_faults : Array[Int32]
  engine_faults : Array[Int32]
  other_faults : Array[Int32]
  general_faults : Array[Int32]
}

///|
pub const ALARM_MIN_LEN : Int32 = 10

///|
fn read_list(
  bytes : BytesView,
  offset : Int32,
  end : Int32,
  width : Int32,
  what~ : String,
) -> (Array[Int32], Int32) raise FrameError {
  ensure_at(bytes, offset, 1, what~)
  let count_raw = bytes[offset].to_int()
  let count = match FieldState::byte(count_raw) {
    Valid => {
      check_count(count_raw, 0, 253, field=what)
      count_raw
    }
    _ => 0
  }
  let need = 1 + count * width
  if offset + need > end {
    raise Payload(message="\{what}: 声明 \{count} 条需要 \{need} 字节，实际不足")
  }
  let items : Array[Int32] = []
  for i in 0..<count {
    let at = offset + 1 + i * width
    if width == 4 {
      items.push(u32_be(bytes, at))
    } else {
      items.push(u16_be(bytes, at))
    }
  }
  (items, need)
}

///|
fn write_list(out : Array[Byte], items : Array[Int32], width : Int32) -> Unit {
  out.push(items.length().to_byte())
  for item in items {
    if width == 4 {
      push_u32_be(out, item)
    } else {
      push_u16_be(out, item)
    }
  }
}

///|
pub fn Alarm::decode_at(
  bytes : BytesView,
  offset : Int32,
  end : Int32,
) -> (Alarm, Int32) raise FrameError {
  ensure_at(bytes, offset, 5, what="报警数据")
  let mut cursor = offset + 5
  let (storage_faults, used1) = read_list(bytes, cursor, end, 4, what="可充电储能装置故障列表")
  cursor = cursor + used1
  let (motor_faults, used2) = read_list(bytes, cursor, end, 4, what="驱动电机故障列表")
  cursor = cursor + used2
  let (engine_faults, used3) = read_list(bytes, cursor, end, 4, what="发动机故障列表")
  cursor = cursor + used3
  let (other_faults, used4) = read_list(bytes, cursor, end, 4, what="其他故障列表")
  cursor = cursor + used4
  let (general_faults, used5) = read_list(bytes, cursor, end, 2, what="通用报警故障列表")
  cursor = cursor + used5
  (
    {
      level_raw: bytes[offset].to_int(),
      general_flags_raw: u32_be(bytes, offset + 1),
      storage_faults,
      motor_faults,
      engine_faults,
      other_faults,
      general_faults,
    },
    cursor - offset,
  )
}

///|
pub fn Alarm::to_bytes(self : Alarm) -> Bytes {
  let out : Array[Byte] = []
  out.push(self.level_raw.to_byte())
  push_u32_be(out, self.general_flags_raw)
  write_list(out, self.storage_faults, 4)
  write_list(out, self.motor_faults, 4)
  write_list(out, self.engine_faults, 4)
  write_list(out, self.other_faults, 4)
  write_list(out, self.general_faults, 2)
  Bytes::from_array(out)
}

///|
/// 最高报警等级：0 无故障，1~3 分级，4 热事件，0xFE/0xFF 异常无效。
pub fn Alarm::level(self : Alarm) -> Int32? {
  match self.level_raw {
    0xfe | 0xff => None
    _ => Some(self.level_raw)
  }
}

///|
pub fn Alarm::has_flag(self : Alarm, bit : Int32) -> Bool {
  ((self.general_flags_raw / pow2(bit)) % 2) == 1
}

///|
fn pow2(exp : Int32) -> Int32 {
  let mut result = 1
  let mut i = 0
  while i < exp {
    result = result * 2
    i = i + 1
  }
  result
}

///|
pub fn Alarm::active_flags(self : Alarm) -> Array[Int32] {
  let bits : Array[Int32] = []
  for bit in 0..<32 {
    if self.has_flag(bit) {
      bits.push(bit)
    }
  }
  bits
}
