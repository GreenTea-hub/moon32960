// session.mbt
///|
/// 会话状态：终端登入后在线，登出或断开后关闭。
pub(all) enum SessionState {
  Idle
  Online
  Closed
}

///|
/// 补发允许窗口，单位秒：GB/T 32960.3 要求补发 7 日内链路异常期间的数据。
pub const RESEND_WINDOW_SECONDS : Int32 = 7 * 24 * 3600

///|
/// 一个终端的平台侧会话。
///
/// 登入时记录 ICCID 与可充电储能子系统编码，用于后续身份核对；上报按实时/补发分别计数，
/// 并保留首次与最近一次上报时间，供补发窗口判断。
pub(all) struct TerminalSession {
  vin : String
  mut iccid : String
  mut storage_codes : Array[String]
  mut state : SessionState
  mut sequence : Int32
  mut report_count : Int32
  mut resend_count : Int32
  mut first_report : Time?
  mut last_report : Time?
  mut alarm_level : Int32
}

///|
pub fn TerminalSession::new(vin : String) -> TerminalSession raise FrameError {
  validate_vin(vin)
  {
    vin,
    iccid: "",
    storage_codes: [],
    state: SessionState::Idle,
    sequence: 0,
    report_count: 0,
    resend_count: 0,
    first_report: None,
    last_report: None,
    alarm_level: 0,
  }
}

///|
pub fn TerminalSession::login(
  self : TerminalSession,
  login : VehicleLogin,
) -> Unit raise FrameError {
  self.state = SessionState::Online
  self.sequence = login.sequence
  self.iccid = login.iccid
  self.storage_codes = login.storage_codes
}

///|
/// 记录一次上报。`resend` 为 true 表示补发，会计入补发计数并检查 7 日窗口。
pub fn TerminalSession::report(
  self : TerminalSession,
  at~ : Time,
  resend~ : Bool = false,
) -> Unit raise FrameError {
  match self.state {
    Online => {
      if resend {
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
  let day = ((time.year - 2000) * 365 + (time.month - 1) * 30 + time.day) * 86400
  let clock = time.hour * 3600 + time.minute * 60 + time.second
  day + clock
}

///|
pub fn TerminalSession::heartbeat(self : TerminalSession) -> Unit raise FrameError {
  match self.state {
    Online => ()
    _ => raise Payload(message="未登入即心跳：vin=\{self.vin}")
  }
}

///|
pub fn TerminalSession::logout(self : TerminalSession) -> Unit raise FrameError {
  match self.state {
    Online => self.state = SessionState::Closed
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
