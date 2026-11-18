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
    accelerator_raw: 30,
    brake_status: 0x01,
  }
}

///|
test "整车数据 20 字节往返与物理换算" {
  let vehicle = sample_vehicle()
  let bytes = vehicle.to_bytes()
  assert_eq(bytes.length(), 20)
  let decoded = @moon32960.WholeVehicle::decode(bytes[:])
  assert_eq(decoded.soc, 78)
  assert_eq(decoded.speed_kmh().unwrap(), 62.300000000000004)
  assert_eq(decoded.total_current_a().unwrap(), 10.0)
  assert_eq(decoded.odometer_km().unwrap(), 12345.6)
  assert_eq(decoded.total_voltage_v().unwrap(), 360.0)
}

///|
test "整车数据异常码不参与换算" {
  let vehicle : @moon32960.WholeVehicle = {
    vehicle_status: 0x01,
    charge_status: 0x01,
    operation_mode: 0x01,
    speed_raw: 0xfffe,
    odometer_raw: 0xfffffffe,
    total_voltage_raw: 0xffff,
    total_current_raw: 0xffff,
    soc: 0xff,
    dc_dc_status: 0x01,
    gear: 0x01,
    insulation_raw: 0xffff,
    accelerator_raw: 0xff,
    brake_status: 0x01,
  }
  assert_true(vehicle.speed_kmh() is None)
  assert_true(vehicle.odometer_km() is None)
  assert_true(vehicle.total_voltage_v() is None)
}

///|
test "驱动电机数据按个数展开" {
  let motor1 : @moon32960.DriveMotor = {
    sequence: 1,
    status: 0x01,
    controller_temp_raw: 60,
    speed_raw: 36000,
    torque_raw: 21000,
    motor_temp_raw: 55,
    input_voltage_raw: 3500,
    bus_current_raw: 3050,
  }
  let data : @moon32960.DriveMotorData = {
    count_raw: 1,
    motors: [motor1],
  }
  let bytes = data.to_bytes()
  assert_eq(bytes.length(), 13)
  let decoded = @moon32960.DriveMotorData::decode_at(bytes[:], 0, bytes.length())
  let (value, used) = decoded
  assert_eq(used, 13)
  assert_eq(value.motors.length(), 1)
  assert_eq(value.motors[0].speed_rpm().unwrap(), 4000)
  assert_eq(value.motors[0].torque_nm().unwrap(), 100.0)
}

///|
test "车辆位置按位解析定位状态" {
  let location : @moon32960.VehicleLocation = {
    position_status: 0x00,
    longitude_raw: 116397000,
    latitude_raw: 39909000,
  }
  let bytes = location.to_bytes()
  assert_eq(bytes.length(), 9)
  let decoded = @moon32960.VehicleLocation::decode(bytes[:])
  assert_true(decoded.is_fix_valid())
  assert_false(decoded.is_south())
  assert_false(decoded.is_west())
}

///|
test "位置无效为南纬西经时符号取负" {
  let location : @moon32960.VehicleLocation = {
    position_status: 0x07,
    longitude_raw: 116397000,
    latitude_raw: 39909000,
  }
  assert_false(location.is_fix_valid())
  assert_true(location.longitude() is None)
  let south_west : @moon32960.VehicleLocation = {
    position_status: 0x04,
    longitude_raw: 116397000,
    latitude_raw: 39909000,
  }
  assert_true(south_west.is_west())
}

///|
test "极值数据 14 字节往返" {
  let extreme : @moon32960.Extreme = {
    max_voltage_subsystem: 1,
    max_voltage_cell: 12,
    max_cell_voltage_raw: 3300,
    min_voltage_subsystem: 1,
    min_voltage_cell: 30,
    min_cell_voltage_raw: 3200,
    max_temp_subsystem: 1,
    max_temp_probe: 5,
    max_temp_raw: 65,
    min_temp_subsystem: 1,
    min_temp_probe: 9,
    min_temp_raw: 40,
  }
  let bytes = extreme.to_bytes()
  assert_eq(bytes.length(), 14)
  let decoded = @moon32960.Extreme::decode(bytes[:])
  assert_eq(decoded.max_cell_voltage_raw, 3300)
  assert_eq(@moon32960.probe_temperature(decoded.max_temp_raw).unwrap(), 25)
}

///|
test "报警数据五组故障列表往返" {
  let alarm : @moon32960.Alarm = {
    level_raw: 2,
    general_flags_raw: 0x00000005,
    storage_faults: [0x1001, 0x1002],
    motor_faults: [],
    engine_faults: [],
    other_faults: [],
    general_faults: [],
  }
  let bytes = alarm.to_bytes()
  let (decoded, used) = @moon32960.Alarm::decode_at(bytes[:], 0, bytes.length())
  assert_eq(used, bytes.length())
  assert_eq(decoded.level().unwrap(), 2)
  assert_eq(decoded.storage_faults.length(), 2)
  assert_eq(decoded.active_flags().length(), 2)
  assert_true(decoded.has_flag(0))
  assert_true(decoded.has_flag(2))
  assert_false(decoded.has_flag(1))
}

///|
test "储能电压按子系统与单体展开" {
  let group : @moon32960.StorageVoltageGroup = {
    subsystem: 1,
    cell_count: 2,
    cell_voltages_raw: [3300, 3250],
  }
  let voltage : @moon32960.StorageVoltage = { groups: [group] }
  let bytes = voltage.to_bytes()
  assert_eq(bytes.length(), 8)
  let (decoded, used) = @moon32960.StorageVoltage::decode_at(bytes[:], 0, bytes.length())
  assert_eq(used, 8)
  assert_eq(decoded.groups[0].cell_voltages_raw.length(), 2)
  assert_eq(decoded.groups[0].cell_voltages_raw[0], 3300)
}

///|
test "储能温度按子系统与探针展开" {
  let group : @moon32960.StorageTempGroup = {
    subsystem: 1,
    probe_count: 3,
    probe_temps_raw: [80, 85, 90],
  }
  let temperature : @moon32960.StorageTemperature = {
    groups: [group],
    max_temp_subsystem: 1,
    max_temp_probe: 3,
    max_temp_raw: 90,
    min_temp_subsystem: 1,
    min_temp_probe: 1,
    min_temp_raw: 80,
  }
  let bytes = temperature.to_bytes()
  let (decoded, used) = @moon32960.StorageTemperature::decode_at(
    bytes[:], 0, bytes.length(),
  )
  assert_eq(used, bytes.length())
  assert_eq(decoded.groups[0].probe_temps_raw.length(), 3)
  assert_eq(decoded.max_temp_raw, 90)
}

///|
test "发动机数据 5 字节往返" {
  let engine : @moon32960.Engine = {
    status: 0x01,
    crankshaft_speed_raw: 2000,
    fuel_consumption_raw: 800,
  }
  let bytes = engine.to_bytes()
  assert_eq(bytes.length(), 5)
  let decoded = @moon32960.Engine::decode(bytes[:])
  assert_eq(decoded.status_name(), "运行")
}

///|
test "燃料电池按探针总数展开" {
  let fuel : @moon32960.FuelCell = {
    voltage_raw: 2000,
    current_raw: 3000,
    hydrogen_consumption_raw: 200,
    probe_total: 2,
    probe_temps: [70, 75],
    max_hydrogen_temp_raw: 80,
    max_hydrogen_temp_probe: 1,
    max_hydrogen_concentration_raw: 500,
    max_hydrogen_concentration_probe: 2,
    max_hydrogen_pressure_raw: 1000,
    max_hydrogen_pressure_probe: 1,
    dc_dc_status: 0x01,
  }
  let bytes = fuel.to_bytes()
  assert_eq(bytes.length(), 20)
  let (decoded, used) = @moon32960.FuelCell::decode_at(bytes[:], 0, bytes.length())
  assert_eq(used, 20)
  assert_eq(decoded.probe_temps.length(), 2)
}

///|
test "实时上报容器按类型标志拼接九类信息体" {
  let time = @moon32960.Time::new(
    year=2026,
    month=11,
    day=18,
    hour=9,
    minute=31,
    second=0,
  )
  let motors : @moon32960.DriveMotorData = { count_raw: 0, motors: [] }
  let extreme : @moon32960.Extreme = {
    max_voltage_subsystem: 1,
    max_voltage_cell: 1,
    max_cell_voltage_raw: 3300,
    min_voltage_subsystem: 1,
    min_voltage_cell: 2,
    min_cell_voltage_raw: 3200,
    max_temp_subsystem: 1,
    max_temp_probe: 1,
    max_temp_raw: 60,
    min_temp_subsystem: 1,
    min_temp_probe: 2,
    min_temp_raw: 50,
  }
  let telemetry = @moon32960.Telemetry::new(
    time~,
    items=[
      @moon32960.ReportItem::Vehicle(sample_vehicle()),
      @moon32960.ReportItem::Motors(motors),
      @moon32960.ReportItem::Extreme(extreme),
      @moon32960.ReportItem::Location({
        position_status: 0x00,
        longitude_raw: 116397000,
        latitude_raw: 39909000,
      }),
    ],
  )
  let bytes = telemetry.to_bytes()
  // 6 字节时间 + 四段「1 字节类型 + 信息体」
  assert_eq(bytes.length(), 6 + 1 + 20 + 1 + 1 + 1 + 14 + 1 + 9)
  let decoded = @moon32960.Telemetry::decode(bytes[:])
  assert_eq(decoded.items.length(), 4)
  assert_true(decoded.has(@moon32960.InfoType::WholeVehicle))
  assert_true(decoded.has(@moon32960.InfoType::Extreme))
  assert_false(decoded.has(@moon32960.InfoType::Alarm))
}

///|
test "带信息流水号的布局同样可解析" {
  let time = @moon32960.Time::new(
    year=2026,
    month=11,
    day=18,
    hour=9,
    minute=31,
    second=0,
  )
  let telemetry = @moon32960.Telemetry::new(
    time~,
    items=[@moon32960.ReportItem::Vehicle(sample_vehicle())],
  )
  let with_serial = telemetry.with_serial(serial=7)
  let bytes = with_serial.to_bytes(header=@moon32960.TimestampWithSerial)
  assert_eq(bytes.length(), 8 + 1 + 20)
  let decoded = @moon32960.Telemetry::decode(bytes[:], header=@moon32960.TimestampWithSerial)
  assert_eq(decoded.serial.unwrap(), 7)
}

///|
test "未知信息类型明确报错" {
  let raw = @moon32960.from_hex("1a0b12091f00ff")
  try @moon32960.Telemetry::decode(raw[:]) catch {
    err => match err {
      @moon32960.FrameError::UnsupportedInfoType(code~) => assert_eq(code, 255)
      _ => fail("期望 UnsupportedInfoType")
    }
  } noraise {
    _ => fail("未知类型仍被忽略")
  }
}
