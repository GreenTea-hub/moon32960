// payload_test.mbt

///|
fn sample_vehicle() -> @moon32960.WholeVehicle {
  {
    vehicle_status: 0x01,
    charge_status: 0x02,
    operation_mode: 0x01,
    speed_raw: 623,
    odometer_raw: 123456,
    total_voltage_raw: 3600,
    total_current_raw: 30100,
    soc: 78,
    dc_dc_status: 0x01,
    gear: 0x04,
    insulation_raw: 1200,
  }
}

///|
test "整车数据 18 字节 11 字段" {
  let vehicle = sample_vehicle()
  let bytes = vehicle.to_bytes()
  assert_eq(bytes.length(), 18)
  let decoded = @moon32960.WholeVehicle::decode(bytes[:])
  assert_eq(decoded.soc, 78)
  assert_eq(decoded.speed_kmh().unwrap(), 62.300000000000004)
  assert_eq(decoded.total_current_a().unwrap(), 10.0)
}

///|
test "驱动电机每项 10 字节，转矩为 DWORD" {
  let motor : @moon32960.DriveMotor = {
    sequence: 1,
    status: 0x01,
    controller_temp_raw: 60,
    speed_raw: 36000,
    torque_raw: 220000,
    motor_temp_raw: 55,
  }
  let data : @moon32960.DriveMotorData = { count_raw: 1, motors: [motor], }
  let bytes = data.to_bytes()
  assert_eq(bytes.length(), 11)
  let (decoded, used) = @moon32960.DriveMotorData::decode_at(
    bytes[:],
    0,
    bytes.length(),
  )
  assert_eq(used, 11)
  assert_eq(decoded.motors[0].speed_rpm().unwrap(), 4000)
  assert_eq(decoded.motors[0].torque_nm().unwrap(), 2000.0)
}

///|
test "位置数据 10 字节含坐标系" {
  let location : @moon32960.VehicleLocation = {
    position_status: 0x00,
    coordinate_system: 0x02,
    longitude_raw: 116397000,
    latitude_raw: 39909000,
  }
  let bytes = location.to_bytes()
  assert_eq(bytes.length(), 10)
  let decoded = @moon32960.VehicleLocation::decode(bytes[:])
  assert_eq(decoded.coordinate_system_name(), "GCJ02")
  assert_true(decoded.is_fix_valid())
}

///|
test "发动机数据只有曲轴转速 2 字节" {
  let engine : @moon32960.Engine = { crankshaft_speed_raw: 2000, }
  let bytes = engine.to_bytes()
  assert_eq(bytes.length(), 2)
  assert_eq(@moon32960.Engine::decode(bytes[:]).crankshaft_speed_raw, 2000)
}

///|
test "报警数据等级 0~4 与五组列表" {
  let alarm : @moon32960.Alarm = {
    level_raw: 4,
    general_flags_raw: 0x00000005,
    storage_faults: [0x1001],
    motor_faults: [],
    engine_faults: [],
    other_faults: [],
    general_faults: [],
  }
  let bytes = alarm.to_bytes()
  let (decoded, used) = @moon32960.Alarm::decode_at(bytes[:], 0, bytes.length())
  assert_eq(used, bytes.length())
  assert_eq(decoded.level().unwrap(), 4)
  assert_true(decoded.has_flag(0))
}

///|
test "蓄电池最小并联单元电压" {
  let pack : @moon32960.BatteryPackVoltage = {
    pack_no: 1,
    voltage_raw: 3600,
    current_raw: 31000,
    cell_count: 2,
    cell_voltages_raw: [3300, 3250],
  }
  let data : @moon32960.BatteryCellVoltage = { packs: [pack], }
  let bytes = data.to_bytes()
  let (decoded, used) = @moon32960.BatteryCellVoltage::decode_at(
    bytes[:],
    0,
    bytes.length(),
  )
  assert_eq(used, bytes.length())
  assert_eq(decoded.packs[0].cell_voltages_raw.length(), 2)
  assert_eq(decoded.packs[0].cell_voltages_raw[0], 3300)
}

///|
test "蓄电池温度探针" {
  let pack : @moon32960.BatteryPackTemperature = {
    pack_no: 1,
    probe_count: 3,
    probe_temps_raw: [80, 85, 90],
  }
  let data : @moon32960.BatteryTemperature = { packs: [pack], }
  let bytes = data.to_bytes()
  let (decoded, used) = @moon32960.BatteryTemperature::decode_at(
    bytes[:],
    0,
    bytes.length(),
  )
  assert_eq(used, bytes.length())
  assert_eq(decoded.packs[0].probe_temps_raw.length(), 3)
  assert_eq(@moon32960.probe_temperature(90).unwrap(), 50)
}

///|
test "超级电容器与极值数据" {
  let cap : @moon32960.SuperCapacitor = {
    system_no: 1,
    total_voltage_raw: 5000,
    total_current_raw: 31000,
    cell_voltages_raw: [2700, 2600],
    probe_temps_raw: [70, 75],
  }
  let bytes = cap.to_bytes()
  let (decoded, used) = @moon32960.SuperCapacitor::decode_at(
    bytes[:],
    0,
    bytes.length(),
  )
  assert_eq(used, bytes.length())
  assert_eq(decoded.cell_voltages_raw.length(), 2)
  let extreme : @moon32960.SuperCapacitorExtreme = {
    max_voltage_system: 1,
    max_voltage_cell: 2,
    max_voltage_raw: 2700,
    min_voltage_system: 1,
    min_voltage_cell: 5,
    min_voltage_raw: 2600,
    max_temp_system: 1,
    max_temp_probe: 3,
    max_temp_raw: 80,
    min_temp_system: 1,
    min_temp_probe: 1,
    min_temp_raw: 70,
  }
  let ext_bytes = extreme.to_bytes()
  assert_eq(ext_bytes.length(), 18)
  assert_eq(
    @moon32960.SuperCapacitorExtreme::decode(ext_bytes[:]).max_voltage_raw,
    2700,
  )
}

///|
test "电堆与自定义数据" {
  let unit : @moon32960.FuelCellStackUnit = {
    sequence: 1,
    voltage_raw: 1000,
    current_raw: 500,
    hydrogen_inlet_pressure_raw: 2000,
    air_inlet_pressure_raw: 2100,
    air_inlet_temp_raw: 60,
    cooling_temps_raw: [75, 76],
  }
  let data : @moon32960.FuelCellStackData = { count_raw: 1, stacks: [unit], }
  let bytes = data.to_bytes()
  let (decoded, used) = @moon32960.FuelCellStackData::decode_at(
    bytes[:],
    0,
    bytes.length(),
  )
  assert_eq(used, bytes.length())
  assert_eq(decoded.stacks[0].cooling_temps_raw.length(), 2)
}

///|
test "实时上报容器与签名信息" {
  let time = try! @moon32960.Time::new(
    year=2026,
    month=11,
    day=25,
    hour=9,
    minute=30,
    second=0,
  )
  let telemetry = @moon32960.Telemetry::new(time~, items=[
    @moon32960.ReportItem::Vehicle(sample_vehicle()),
    @moon32960.ReportItem::Location({
      position_status: 0x00,
      coordinate_system: 0x02,
      longitude_raw: 116397000,
      latitude_raw: 39909000,
    }),
  ])
  let sig : @moon32960.Signature = {
    kind_raw: 0x01,
    r: @moon32960.from_hex("aabb"),
    s: @moon32960.from_hex("ccdd"),
  }
  let signed = telemetry.with_signature(signature=sig)
  let bytes = signed.to_bytes()
  let decoded = @moon32960.Telemetry::decode(bytes[:])
  assert_eq(decoded.items.length(), 2)
  assert_true(decoded.signature is Some(_))
  match decoded.signature {
    Some(s) => {
      assert_eq(s.kind_raw, 1)
      assert_eq(@moon32960.to_hex(s.r), "aabb")
    }
    None => fail("签名应存在")
  }
}
