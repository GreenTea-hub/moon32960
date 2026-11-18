// internal.mbt
///|
/// 字段取值状态。GB/T 32960.3 用固定码表示异常与无效，解读时不应报错，而应标记。
pub(all) enum FieldState {
  Valid
  Abnormal // 0xFE / 0xFFFE / 0xFFFFFFFE
  Invalid // 0xFF / 0xFFFF / 0xFFFFFFFF
}

///|
pub fn FieldState::byte(code : Int32) -> FieldState {
  match code {
    0xfe => Abnormal
    0xff => Invalid
    _ => Valid
  }
}

///|
pub fn FieldState::word(code : Int32) -> FieldState {
  match code {
    0xfffe => Abnormal
    0xffff => Invalid
    _ => Valid
  }
}

///|
pub fn FieldState::dword(code : Int32) -> FieldState {
  match code {
    0xfffffffe => Abnormal
    0xffffffff => Invalid
    _ => Valid
  }
}

///|
/// 读取前先做边界检查，避免越界 panic 把畸形帧伪装成崩溃。
pub fn ensure_at(
  bytes : BytesView,
  offset : Int32,
  need : Int32,
  what~ : String,
) -> Unit raise FrameError {
  if offset < 0 || offset + need > bytes.length() {
    raise Payload(
      message="\{what}: need \{need} bytes at offset \{offset}, have \{bytes.length()}",
    )
  }
}

///|
/// 读取一个 BYTE 并按范围校验。
pub fn read_byte(
  bytes : BytesView,
  offset : Int32,
  what~ : String,
) -> Int32 raise FrameError {
  ensure_at(bytes, offset, 1, what~)
  bytes[offset].to_int()
}

///|
pub fn read_word(
  bytes : BytesView,
  offset : Int32,
  what~ : String,
) -> Int32 raise FrameError {
  ensure_at(bytes, offset, 2, what~)
  u16_be(bytes, offset)
}

///|
pub fn read_dword(
  bytes : BytesView,
  offset : Int32,
  what~ : String,
) -> Int32 raise FrameError {
  ensure_at(bytes, offset, 4, what~)
  u32_be(bytes, offset)
}

///|
/// 校验计数类字段（子系统数、探针数等）落在协议允许的闭区间内。
pub fn check_count(
  value : Int32,
  low : Int32,
  high : Int32,
  field~ : String,
) -> Unit raise FrameError {
  if value < low || value > high {
    raise FieldOutOfRange(field~, value~, low~, high~)
  }
}

///|
/// 判断两个字节目段是否恰好等于某信息类型的固定长度。
pub fn expect_len(
  actual : Int32,
  expected : Int32,
  what~ : String,
) -> Unit raise FrameError {
  if actual != expected {
    raise Payload(
      message="\{what}: expected \{expected} bytes, got \{actual}",
    )
  }
}
