// command.mbt
///|
/// GB/T 32960 command identifier (the third byte of the frame header).
///
/// `Unknown` keeps forward compatibility: a future revision can add commands
/// without making the decoder reject the frame outright.
pub(all) enum Command {
  VehicleLogin
  RealtimeReport
  ResendReport
  VehicleLogout
  PlatformLogin
  PlatformLogout
  Heartbeat
  TerminalTimeSync
  PlatformDownlink
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
/// Response flag carried by every frame (fourth header byte).
pub(all) enum ResponseFlag {
  Success
  Failure
  VinDuplicate
  CommandNotRecognized
  Invalid
  Unknown(Int32)
}

///|
pub fn ResponseFlag::to_byte(self : ResponseFlag) -> Byte {
  match self {
    Success => b'\x01'
    Failure => b'\x02'
    VinDuplicate => b'\x03'
    CommandNotRecognized => b'\xfe'
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
    0xfe => CommandNotRecognized
    0xff => Invalid
    n => Unknown(n)
  }
}

///|
/// Data encryption mode byte.
///
/// The encoder and decoder only carry the value through; encryption itself is
/// a later milestone and is called out in `docs/PROTOCOL.md`.
pub(all) enum Encryption {
  Plain
  Rsa
  Aes128
  Abnormal
  Invalid
  Unknown(Int32)
}

///|
pub fn Encryption::to_byte(self : Encryption) -> Byte {
  match self {
    Plain => b'\x01'
    Rsa => b'\x02'
    Aes128 => b'\x03'
    Abnormal => b'\xfe'
    Invalid => b'\xff'
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
    0xff => Invalid
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
    Invalid => "invalid"
    Unknown(_) => "unknown"
  }
}