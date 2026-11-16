// session.mbt
///|
/// State of one terminal session on the platform side.
pub(all) enum SessionState {
  Idle
  Online
  Closed
}

///|
/// Terminal session bookkeeping.
///
/// The state machine is intentionally small: login opens a session, reports
/// are only counted while online, logout closes it, and a fresh login after a
/// close reopens it. This mirrors the acceptance behaviour a platform needs
/// before it starts writing reports to storage.
pub(all) struct TerminalSession {
  vin : String
  mut state : SessionState
  mut sequence : Int32
  mut report_count : Int32
  mut resend_count : Int32
  mut last_report : Time?
}

///|
pub fn TerminalSession::new(vin : String) -> TerminalSession raise FrameError {
  validate_vin(vin)
  {
    vin,
    state: SessionState::Idle,
    sequence: 0,
    report_count: 0,
    resend_count: 0,
    last_report: None,
  }
}

///|
pub fn TerminalSession::login(
  self : TerminalSession,
  time~ : Time,
  sequence~ : Int32,
) -> Unit raise FrameError {
  if sequence < 0 || sequence > 0xFFFF {
    raise Payload(message="login sequence out of range: \{sequence}")
  }
  self.state = SessionState::Online
  self.sequence = sequence
  self.last_report = Some(time)
}

///|
/// Record a realtime report. `resend` distinguishes a re-sent sample.
pub fn TerminalSession::report(
  self : TerminalSession,
  at~ : Time,
  resend~ : Bool = false,
) -> Unit raise FrameError {
  match self.state {
    Online => {
      if resend {
        self.resend_count = self.resend_count + 1
      } else {
        self.report_count = self.report_count + 1
      }
      self.last_report = Some(at)
    }
    _ => raise Payload(message="report before login: vin=\{self.vin}")
  }
}

///|
pub fn TerminalSession::heartbeat(self : TerminalSession) -> Unit raise FrameError {
  match self.state {
    Online => ()
    _ => raise Payload(message="heartbeat before login: vin=\{self.vin}")
  }
}

///|
pub fn TerminalSession::logout(self : TerminalSession) -> Unit raise FrameError {
  match self.state {
    Online => self.state = SessionState::Closed
    _ => raise Payload(message="logout before login: vin=\{self.vin}")
  }
}

///|
pub fn TerminalSession::is_online(self : TerminalSession) -> Bool {
  match self.state {
    Online => true
    _ => false
  }
}