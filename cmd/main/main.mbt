// main.mbt
///|
fn usage() -> Unit {
  println("moon32960 CLI")
  println("  decode <hex>                 decode a frame and print its fields")
  println("  encode <vin> <command> <hex> build a frame from a payload")
  println("  demo                         round-trip a golden login frame")
  println("")
  println("commands: vehicle-login realtime-report resend-report vehicle-logout")
  println("          heartbeat terminal-time-sync platform-downlink")
}

///|
fn command_of(name : String) -> @moon32960.Command raise {
  match name {
    "vehicle-login" => @moon32960.Command::VehicleLogin
    "realtime-report" => @moon32960.Command::RealtimeReport
    "resend-report" => @moon32960.Command::ResendReport
    "vehicle-logout" => @moon32960.Command::VehicleLogout
    "heartbeat" => @moon32960.Command::Heartbeat
    "terminal-time-sync" => @moon32960.Command::TerminalTimeSync
    "platform-downlink" => @moon32960.Command::PlatformDownlink
    _ => fail("unknown command: \{name}")
  }
}

///|
fn describe(frame : @moon32960.Frame) -> Unit {
  println("command   : \{frame.command.name()}")
  println("response  : \{frame.response.to_byte().to_hex()}")
  println("vin       : \{frame.vin}")
  println("encryption: \{frame.encryption.name()}")
  println("payload   : \{@moon32960.to_hex(frame.payload)}")
}

///|
fn demo() -> Unit raise {
  let vin = "GREEN123456789012"
  let time = @moon32960.Time::new(
    year=2026,
    month=11,
    day=16,
    hour=15,
    minute=0,
    second=0,
  )
  let login = @moon32960.LoginData::new(time~, sequence=1)
  let frame = @moon32960.Frame::new(
    command=@moon32960.Command::VehicleLogin,
    response=@moon32960.ResponseFlag::Success,
    vin~,
    encryption=@moon32960.Encryption::Plain,
    payload=login.to_bytes(),
  )
  let wire = @moon32960.encode_frame(frame)
  println("golden frame: \{@moon32960.to_hex(wire)}")
  let decoded = @moon32960.decode_frame(wire)
  describe(decoded)
  let parsed = @moon32960.LoginData::parse(decoded.payload[:])
  println("login seq : \{parsed.sequence}")
}

///|
fn main raise {
  let args = @env.args()
  match args[1:] {
    ["decode", hex] => {
      let frame = @moon32960.decode_frame(@moon32960.from_hex(hex))
      describe(frame)
    }
    ["encode", vin, command_name, payload_hex] => {
      let frame = @moon32960.Frame::new(
        command=command_of(command_name),
        response=@moon32960.ResponseFlag::Success,
        vin~,
        encryption=@moon32960.Encryption::Plain,
        payload=@moon32960.from_hex(payload_hex),
      )
      println(@moon32960.to_hex(@moon32960.encode_frame(frame)))
    }
    ["demo"] => demo()
    _ => usage()
  }
}
