// protocol_test.mbt

///|
fn t025(hour~ : Int32 = 9, minute~ : Int32 = 30) -> @moon32960.Time {
  try! @moon32960.Time::new(
    year=2026,
    month=11,
    day=25,
    hour~,
    minute~,
    second=0,
  )
}

///|
test "登入数据单元按表6：BMS 数 + 包个数 + 24 位编码" {
  let login = try! @moon32960.VehicleLogin::new(
    time=t025(),
    sequence=1,
    iccid="89860620180001234567",
    systems=[
      @moon32960.BatteryManagementSystem::{
        pack_count: 2,
        pack_codes: ["LFPBAT202511250000000001", "LFPBAT202511250000000002"],
      },
      @moon32960.BatteryManagementSystem::{ pack_count: 0, pack_codes: [], },
    ],
  )
  let bytes = login.to_bytes()
  // 29 固定 + BMS 数 2 + 包编码 2×24
  assert_eq(bytes.length(), 29 + 2 + 48)
  let decoded = @moon32960.VehicleLogin::decode(bytes[:])
  assert_eq(decoded.systems.length(), 2)
  assert_eq(decoded.systems[0].pack_codes.length(), 2)
  assert_eq(decoded.systems[1].pack_count, 0)
}

///|
test "登入拒绝非 24 位包编码" {
  try
    @moon32960.VehicleLogin::new(
      time=t025(),
      sequence=1,
      iccid="89860620180001234567",
      systems=[
        @moon32960.BatteryManagementSystem::{
          pack_count: 1,
          pack_codes: ["SHORT"],
        },
      ],
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("短编码仍被接受")
  }
}

///|
test "登入拒绝包个数与编码条数不一致" {
  try
    @moon32960.VehicleLogin::new(
      time=t025(),
      sequence=1,
      iccid="89860620180001234567",
      systems=[
        @moon32960.BatteryManagementSystem::{
          pack_count: 2,
          pack_codes: ["LFPBAT202511250000000001"],
        },
      ],
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("个数不一致仍被接受")
  }
}

///|
test "密钥交换按表31解析" {
  let exchange : @moon32960.KeyExchange = {
    key_type: 0x03,
    key: @moon32960.from_hex("000102030405060708090a0b0c0d0e0f"),
    enable_from: t025(),
    expire_at: t025(hour=10),
  }
  let bytes = exchange.to_bytes()
  // 类型 1 + 长度 2 + 密钥 16 + 启用 6 + 失效 6
  assert_eq(bytes.length(), 31)
  let decoded = @moon32960.KeyExchange::decode(bytes[:])
  assert_eq(decoded.key_type_name(), "AES")
  assert_eq(decoded.key.length(), 16)
}

///|
test "激活信息按表B.3解析" {
  let activation : @moon32960.Activate = {
    time: t025(),
    chip_id: "CHIP012345678901",
    public_key: @moon32960.from_hex("aabbccdd"),
    vin: "LGWEF4A56MF123456",
    signature: @moon32960.Signature::{
      kind_raw: 0x01,
      r: @moon32960.from_hex("1122"),
      s: @moon32960.from_hex("3344"),
    },
  }
  let bytes = activation.to_bytes()
  let decoded = @moon32960.Activate::decode(bytes[:])
  assert_eq(decoded.chip_id, "CHIP012345678901")
  assert_eq(decoded.vin, "LGWEF4A56MF123456")
  assert_eq(decoded.public_key.length(), 4)
}

///|
test "激活应答按表B.4" {
  let ack : @moon32960.ActivateAck = {
    state: @moon32960.ActivateState::ActivateOk,
    info: @moon32960.ActivateInfo::ActivateSucceeded,
  }
  let bytes = ack.to_bytes()
  assert_eq(@moon32960.to_hex(bytes), "0100")
  let decoded = @moon32960.ActivateAck::decode(bytes[:])
  match decoded.info {
    @moon32960.ActivateInfo::ActivateSucceeded => ()
    _ => fail("激活信息应为成功")
  }
}

///|
test "参数查询按表B.5" {
  let query : @moon32960.ParamQuery = { time: t025(), ids: [0x02, 0x06], }
  let bytes = query.to_bytes()
  assert_eq(bytes.length(), 9)
  let decoded = @moon32960.ParamQuery::decode(bytes[:])
  assert_eq(decoded.ids.length(), 2)
}

///|
test "参数设置按表B.9" {
  let setting : @moon32960.ParamSetting = {
    time: t025(),
    items: [
      @moon32960.ParamItem::{ id: 0x02, value: @moon32960.from_hex("10"), },
      @moon32960.ParamItem::{ id: 0x01, value: @moon32960.from_hex("1f40"), },
    ],
  }
  let bytes = setting.to_bytes()
  let decoded = @moon32960.ParamSetting::decode(bytes[:])
  assert_eq(decoded.items.length(), 2)
  assert_eq(decoded.items[0].id, 0x02)
}

///|
test "车载终端控制按表B.10" {
  let control : @moon32960.TerminalControl = {
    time: t025(),
    command_id: 0x02,
    params: Bytes::new(0),
  }
  let bytes = control.to_bytes()
  assert_eq(bytes.length(), 7)
  let decoded = @moon32960.TerminalControl::decode(bytes[:])
  assert_eq(decoded.command_name(), "车载终端关机")
}
