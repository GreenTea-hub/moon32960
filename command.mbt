// command.mbt
// 依据：GB/T 32960.3-2025 表 3（平台间命令）、表 B.2（车端命令）、表 4（应答标志）、表 9（信息类型标志）

///|
/// 命令单元。车端与平台间使用不同的命令集合，方向判断见 `Scope`。
pub(all) enum Command {
  VehicleLogin // 0x01
  RealtimeReport // 0x02
  ResendReport // 0x03
  VehicleLogout // 0x04
  PlatformLogin // 0x05（正文）/ 平台传输数据占用（附录 B）
  PlatformLogout // 0x06
  Heartbeat // 0x07（附录 B）
  TerminalTimeSync // 0x08（附录 B）
  Activate // 0x09（附录 B）
  ActivateAck // 0x0A（附录 B，下行）
  KeyExchange // 0x0B
  Query // 0x80（附录 B）
  Setting // 0x81（附录 B）
  TerminalControl // 0x82（附录 B）
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
    Activate => b'\x09'
    ActivateAck => b'\x0a'
    KeyExchange => b'\x0b'
    Query => b'\x80'
    Setting => b'\x81'
    TerminalControl => b'\x82'
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
    0x09 => Activate
    0x0a => ActivateAck
    0x0b => KeyExchange
    0x80 => Query
    0x81 => Setting
    0x82 => TerminalControl
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
    Activate => "activate"
    ActivateAck => "activate-ack"
    KeyExchange => "key-exchange"
    Query => "query"
    Setting => "setting"
    TerminalControl => "terminal-control"
    Unknown(_) => "unknown"
  }
}

///|
/// 应答标志，GB/T 32960.3-2025 表 4。相比 2016 版新增 0x04~0x07。
pub(all) enum ResponseFlag {
  Success // 0x01 成功
  OtherError // 0x02 其他错误
  VinDuplicate // 0x03 VIN 重复
  VinMissing // 0x04 VIN 不存在
  SignatureError // 0x05 验签错误
  StructureError // 0x06 数据结构错误
  DecryptError // 0x07 解密错误
  Command // 0xFE 命令包
  Unknown(Int32)
}

///|
pub fn ResponseFlag::to_byte(self : ResponseFlag) -> Byte {
  match self {
    Success => b'\x01'
    OtherError => b'\x02'
    VinDuplicate => b'\x03'
    VinMissing => b'\x04'
    SignatureError => b'\x05'
    StructureError => b'\x06'
    DecryptError => b'\x07'
    Command => b'\xfe'
    Unknown(n) => n.to_byte()
  }
}

///|
pub fn ResponseFlag::from_byte(byte : Byte) -> ResponseFlag {
  match byte.to_int() {
    0x01 => Success
    0x02 => OtherError
    0x03 => VinDuplicate
    0x04 => VinMissing
    0x05 => SignatureError
    0x06 => StructureError
    0x07 => DecryptError
    0xfe => Command
    n => Unknown(n)
  }
}

///|
pub fn ResponseFlag::name(self : ResponseFlag) -> String {
  match self {
    Success => "success"
    OtherError => "other-error"
    VinDuplicate => "vin-duplicate"
    VinMissing => "vin-missing"
    SignatureError => "signature-error"
    StructureError => "structure-error"
    DecryptError => "decrypt-error"
    Command => "command"
    Unknown(_) => "unknown"
  }
}

///|
/// 数据单元加密方式，表 2。2025 版扩展了 SM2/SM4。
pub(all) enum Encryption {
  Plain // 0x01
  Rsa // 0x02
  Aes // 0x03
  Sm2 // 0x04
  Sm4 // 0x05
  Abnormal // 0xFE
  InvalidMode // 0xFF
  Unknown(Int32)
}

///|
pub fn Encryption::to_byte(self : Encryption) -> Byte {
  match self {
    Plain => b'\x01'
    Rsa => b'\x02'
    Aes => b'\x03'
    Sm2 => b'\x04'
    Sm4 => b'\x05'
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
    0x03 => Aes
    0x04 => Sm2
    0x05 => Sm4
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
    Aes => "aes"
    Sm2 => "sm2"
    Sm4 => "sm4"
    Abnormal => "abnormal"
    InvalidMode => "invalid"
    Unknown(_) => "unknown"
  }
}

///|
/// 信息类型标志，GB/T 32960.3-2025 表 9。编号相对 2016 版整体重排。
pub(all) enum InfoType {
  WholeVehicle // 0x01
  DriveMotor // 0x02
  FuelCellHydrogen // 0x03 燃料电池发动机及车载氢系统
  Engine // 0x04
  Location // 0x05
  Alarm // 0x06
  BatteryCellVoltage // 0x07 动力蓄电池最小并联单元电压
  BatteryTemperature // 0x08 动力蓄电池温度
  FuelCellStack // 0x30 燃料电池电堆
  SuperCapacitor // 0x31 超级电容器
  SuperCapacitorExtreme // 0x32 超级电容器极值
  Custom // 0x80~0xFE 自定义数据
  Signature // 0xFF 签名数据开始标识
  Unknown(Int32)
}

///|
pub fn InfoType::to_byte(self : InfoType) -> Byte {
  match self {
    WholeVehicle => b'\x01'
    DriveMotor => b'\x02'
    FuelCellHydrogen => b'\x03'
    Engine => b'\x04'
    Location => b'\x05'
    Alarm => b'\x06'
    BatteryCellVoltage => b'\x07'
    BatteryTemperature => b'\x08'
    FuelCellStack => b'\x30'
    SuperCapacitor => b'\x31'
    SuperCapacitorExtreme => b'\x32'
    Custom => b'\x80'
    Signature => b'\xff'
    Unknown(n) => n.to_byte()
  }
}

///|
pub fn InfoType::from_byte(byte : Byte) -> InfoType {
  match byte.to_int() {
    0x01 => WholeVehicle
    0x02 => DriveMotor
    0x03 => FuelCellHydrogen
    0x04 => Engine
    0x05 => Location
    0x06 => Alarm
    0x07 => BatteryCellVoltage
    0x08 => BatteryTemperature
    0x30 => FuelCellStack
    0x31 => SuperCapacitor
    0x32 => SuperCapacitorExtreme
    0x80 => Custom
    0xff => Signature
    n => {
      if n >= 0x80 && n <= 0xfe {
        Custom
      } else {
        Unknown(n)
      }
    }
  }
}

///|
pub fn InfoType::name(self : InfoType) -> String {
  match self {
    WholeVehicle => "whole-vehicle"
    DriveMotor => "drive-motor"
    FuelCellHydrogen => "fuel-cell-hydrogen"
    Engine => "engine"
    Location => "location"
    Alarm => "alarm"
    BatteryCellVoltage => "battery-cell-voltage"
    BatteryTemperature => "battery-temperature"
    FuelCellStack => "fuel-cell-stack"
    SuperCapacitor => "supercapacitor"
    SuperCapacitorExtreme => "supercapacitor-extreme"
    Custom => "custom"
    Signature => "signature"
    Unknown(_) => "unknown"
  }
}
