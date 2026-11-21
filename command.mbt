// command.mbt
///|
/// 命令标识（命令单元），GB/T 32960.3-2016 表 3。
pub(all) enum Command {
  VehicleLogin // 0x01 车辆登入（上行）
  RealtimeReport // 0x02 实时信息上报（上行）
  ResendReport // 0x03 补发信息上报（上行）
  VehicleLogout // 0x04 车辆登出（上行）
  PlatformLogin // 0x05 平台登入
  PlatformLogout // 0x06 平台登出
  Heartbeat // 0x07 心跳
  TerminalTimeSync // 0x08 终端校时
  PlatformDownlink // 0x80 平台下行
  Unknown(Int32)
}

///|
pub fn Command::to_byte(self : Command) -> Byte {
  match self {
    VehicleLogin => b'\x01'
    RealtimeReport => b'\x02'
    ResendReport => b'\x03'
    VehicleLogout => b'\x04'
    PlatformLogin => b'\x05'
    PlatformLogout => b'\x06'
    Heartbeat => b'\x07'
    TerminalTimeSync => b'\x08'
    PlatformDownlink => b'\x80'
    Unknown(n) => n.to_byte()
  }
}

///|
pub fn Command::from_byte(byte : Byte) -> Command {
  match byte.to_int() {
    0x01 => VehicleLogin
    0x02 => RealtimeReport
    0x03 => ResendReport
    0x04 => VehicleLogout
    0x05 => PlatformLogin
    0x06 => PlatformLogout
    0x07 => Heartbeat
    0x08 => TerminalTimeSync
    0x80 => PlatformDownlink
    n => Unknown(n)
  }
}

///|
pub fn Command::name(self : Command) -> String {
  match self {
    VehicleLogin => "vehicle-login"
    RealtimeReport => "realtime-report"
    ResendReport => "resend-report"
    VehicleLogout => "vehicle-logout"
    PlatformLogin => "platform-login"
    PlatformLogout => "platform-logout"
    Heartbeat => "heartbeat"
    TerminalTimeSync => "terminal-time-sync"
    PlatformDownlink => "platform-downlink"
    Unknown(_) => "unknown"
  }
}

///|
/// 应答标志，GB/T 32960.3-2016 表 3。
pub(all) enum ResponseFlag {
  Success // 0x01 成功
  Failure // 0x02 失败
  VinDuplicate // 0x03 VIN 重复
  Command // 0xFE 命令包（主动发起方标记）
  Invalid // 0xFF 无效
  Unknown(Int32)
}

///|
pub fn ResponseFlag::to_byte(self : ResponseFlag) -> Byte {
  match self {
    Success => b'\x01'
    Failure => b'\x02'
    VinDuplicate => b'\x03'
    Command => b'\xfe'
    Invalid => b'\xff'
    Unknown(n) => n.to_byte()
  }
}

///|
pub fn ResponseFlag::from_byte(byte : Byte) -> ResponseFlag {
  match byte.to_int() {
    0x01 => Success
    0x02 => Failure
    0x03 => VinDuplicate
    0xfe => Command
    0xff => Invalid
    n => Unknown(n)
  }
}

///|
/// 数据加密方式，GB/T 32960.3-2016。
pub(all) enum Encryption {
  Plain // 0x01 不加密
  Rsa // 0x02 RSA
  Aes128 // 0x03 AES128
  Abnormal // 0xFE 异常
  InvalidMode // 0xFF 无效
  Unknown(Int32)
}

///|
pub fn Encryption::to_byte(self : Encryption) -> Byte {
  match self {
    Plain => b'\x01'
    Rsa => b'\x02'
    Aes128 => b'\x03'
    Abnormal => b'\xfe'
    InvalidMode => b'\xff'
    Unknown(n) => n.to_byte()
  }
}

///|
pub fn Encryption::from_byte(byte : Byte) -> Encryption {
  match byte.to_int() {
    0x01 => Plain
    0x02 => Rsa
    0x03 => Aes128
    0xfe => Abnormal
    0xff => InvalidMode
    n => Unknown(n)
  }
}

///|
pub fn Encryption::name(self : Encryption) -> String {
  match self {
    Plain => "plain"
    Rsa => "rsa"
    Aes128 => "aes128"
    Abnormal => "abnormal"
    InvalidMode => "invalid"
    Unknown(_) => "unknown"
  }
}

///|
/// 信息类型标志，GB/T 32960.3-2016 表 7。九类全覆盖，未列取值保留前向兼容分支。
pub(all) enum InfoType {
  WholeVehicle // 0x01 整车数据
  DriveMotor // 0x02 驱动电机数据
  FuelCell // 0x03 燃料电池数据
  Engine // 0x04 发动机数据
  Location // 0x05 车辆位置数据
  Extreme // 0x06 极值数据
  Alarm // 0x07 报警数据
  StorageVoltage // 0x08 可充电储能装置电压数据
  StorageTemperature // 0x09 可充电储能装置温度数据
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
    n => Unknown(n)
  }
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
    Unknown(_) => "unknown"
  }
}
