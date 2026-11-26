// session.mbt

///|
/// 会话状态：终端登入后在线，登出或断开后关闭。
pub(all) enum SessionState {
  Idle
  Online
  Closed
}

///|
/// 补发时间窗，单位秒。标准把「7 日内链路异常期间的数据」写成发送方的存储义务，
/// 不是平台的拒收规则；因此默认不校验，仅作为终端侧建议与可选审计开关保留。
pub const RESEND_WINDOW_SECONDS : Int32 = 7 * 24 * 3600

///|
/// 一个终端的平台侧会话。
///
/// 登入时记录 ICCID 与可充电储能子系统编码，用于后续身份核对；上报按实时与补发分别计数，
/// 并保留首次与最近一次上报时间，供补发窗口判断。
pub(all) struct TerminalSession {
  vin : String
  mut iccid : String
  mut systems : Array[BatteryManagementSystem]
  mut state : SessionState
  mut sequence : Int32
  mut report_count : Int32
  mut resend_count : Int32
  mut first_report : Time?
  mut last_report : Time?
}

///|
pub fn TerminalSession::new(vin : String) -> TerminalSession raise FrameError {
  validate_vin(vin)
  {
    vin,
    iccid: "",
    systems: [],
    state: SessionState::Idle,
    sequence: 0,
    report_count: 0,
    resend_count: 0,
    first_report: None,
    last_report: None,
  }
}

///|
/// 记录登入信息。字段已在 `VehicleLogin` 解码阶段校验，这里只做状态切换。
pub fn TerminalSession::login(
  self : TerminalSession,
  login : VehicleLogin,
) -> Unit {
  self.state = SessionState::Online
  self.sequence = login.sequence
  self.iccid = login.iccid
  self.systems = login.systems
}

///|
/// 记录一次上报。`resend` 为 true 表示补发。
///
/// `enforce_window` 默认关闭：7 日窗口是对发送方存储的要求，平台不应因此拒收；
/// 需要严格审计的部署可以打开，超窗返回错误由调用方决定如何处理。
pub fn TerminalSession::report(
  self : TerminalSession,
  at~ : Time,
  resend~ : Bool = false,
  enforce_window~ : Bool = false,
) -> Unit raise FrameError {
  match self.state {
    Online => {
      if resend {
        if enforce_window {
          match self.last_report {
            Some(last) => {
              let gap = second_of_day(at) - second_of_day(last)
              if gap < -RESEND_WINDOW_SECONDS || gap > RESEND_WINDOW_SECONDS {
                raise Payload(
                  message="补发时间 \{at.to_display()} 超出最近上报 \{last.to_display()} 的 7 日窗口",
                )
              }
            }
            None => ()
          }
        }
        self.resend_count = self.resend_count + 1
      } else {
        self.report_count = self.report_count + 1
      }
      if self.first_report is None {
        self.first_report = Some(at)
      }
      self.last_report = Some(at)
    }
    _ => raise Payload(message="未登入即上报：vin=\{self.vin}")
  }
}

///|
/// 以天为单位的粗略秒数，仅用于补发窗口的量级判断（不含闰年与跨月修正）。
fn second_of_day(time : Time) -> Int32 {
  let day = ((time.year - 2000) * 365 + (time.month - 1) * 30 + time.day) *
    86400
  let clock = time.hour * 3600 + time.minute * 60 + time.second
  day + clock
}

///|
pub fn TerminalSession::heartbeat(
  self : TerminalSession,
) -> Unit raise FrameError {
  match self.state {
    Online => ()
    _ => raise Payload(message="未登入即心跳：vin=\{self.vin}")
  }
}

///|
/// 登出。表 28 要求登出流水号与当次登入一致，`sequence` 非空时校验。
pub fn TerminalSession::logout(
  self : TerminalSession,
  sequence? : Int32,
) -> Unit raise FrameError {
  match self.state {
    Online => {
      match sequence {
        Some(value) =>
          if value != self.sequence {
            raise Payload(
              message="登出流水号 \{value} 与登入流水号 \{self.sequence} 不一致",
            )
          }
        None => ()
      }
      self.state = SessionState::Closed
    }
    _ => raise Payload(message="未登入即登出：vin=\{self.vin}")
  }
}

///|
pub fn TerminalSession::is_online(self : TerminalSession) -> Bool {
  match self.state {
    Online => true
    _ => false
  }
}
