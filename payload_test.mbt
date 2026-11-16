// payload_test.mbt
///|
test "login payload encodes to time plus sequence" {
  let time = @moon32960.Time::new(
    year=2026,
    month=11,
    day=16,
    hour=15,
    minute=0,
    second=0,
  )
  let data = @moon32960.LoginData::new(time~, sequence=1)
  assert_eq(@moon32960.to_hex(data.to_bytes()), "1a0b100f00000001")
  let parsed = @moon32960.LoginData::parse(data.to_bytes()[:])
  assert_eq(parsed.sequence, 1)
  assert_eq(parsed.time.year, 2026)
  assert_eq(parsed.time.hour, 15)
}

///|
test "login payload rejects a wrong size" {
  try @moon32960.LoginData::parse(@moon32960.from_hex("0102")[:]) catch {
    err => {
      match err {
        @moon32960.FrameError::Payload(_) => ()
        _ => fail("unexpected error variant")
      }
    }
  } noraise {
    _ => fail("expected a Payload error")
  }
}

///|
test "realtime report round-trips the whole-vehicle and location items" {
  let time = @moon32960.Time::new(
    year=2026,
    month=11,
    day=16,
    hour=15,
    minute=30,
    second=0,
  )
  let vehicle = @moon32960.WholeVehicle::{
    status: 1,
    charge_status: 2,
    speed: 3,
    soc: 40,
    voltage: 500,
    odometer: 12345,
  }
  let location = @moon32960.Location::{
    status: 1,
    longitude: 116400000,
    latitude: 39900000,
  }
  let report = @moon32960.RealtimeReport::new(
    time~,
    items=[
      @moon32960.InfoItem::WholeVehicleItem(vehicle),
      @moon32960.InfoItem::LocationItem(location),
    ],
  )
  let bytes = report.to_bytes()
  let parsed = @moon32960.RealtimeReport::parse(bytes[:])
  assert_eq(parsed.time.minute, 30)
  assert_eq(parsed.items.length(), 2)
  match parsed.items[0] {
    @moon32960.InfoItem::WholeVehicleItem(data) => {
      assert_eq(data.speed, 3)
      assert_eq(data.soc, 40)
      assert_eq(data.odometer, 12345)
    }
    _ => fail("expected a whole-vehicle item")
  }
  match parsed.items[1] {
    @moon32960.InfoItem::LocationItem(data) => {
      assert_eq(data.longitude, 116400000)
      assert_eq(data.latitude, 39900000)
    }
    _ => fail("expected a location item")
  }
}

///|
test "realtime report rejects a truncated item body" {
  let time = @moon32960.Time::new(
    year=2026,
    month=11,
    day=16,
    hour=15,
    minute=30,
    second=0,
  )
  let raw : Array[Byte] = []
  for byte in time.to_bytes() {
    raw.push(byte)
  }
  raw.push(b'\x01')
  raw.push(b'\x09')
  raw.push(b'\x01')
  try @moon32960.RealtimeReport::parse(Bytes::from_array(raw)[:]) catch {
    err => {
      match err {
        @moon32960.FrameError::Payload(_) => ()
        _ => fail("unexpected error variant")
      }
    }
  } noraise {
    _ => fail("expected a Payload error")
  }
}
