// gateway.mbt
///|
/// What the platform did with an inbound frame.
pub(all) enum RouteOutcome {
  LoginAccepted
  LoginResumed
  ReportAccepted
  HeartbeatAccepted
  LogoutAccepted
  Rejected(reason~ : String)
}

///|
/// Platform-side session registry.
///
/// Pure logic, no sockets: the transport loop is deliberately kept outside so
/// the routing rules can be property-tested and reused by a wasm or native
/// listener without change.
pub(all) struct Gateway {
  sessions : Map[String, TerminalSession]
  mut accepted : Int32
  mut rejected : Int32
}

///|
pub fn Gateway::new() -> Gateway {
  { sessions: Map([]), accepted: 0, rejected: 0 }
}

///|
/// Route one decoded frame and update the matching session.
pub fn Gateway::route(self : Gateway, frame : Frame) -> RouteOutcome raise FrameError {
  match frame.command {
    VehicleLogin => {
      let login = LoginData::parse(frame.payload[:])
      match self.sessions.get(frame.vin) {
        Some(session) => {
          session.login(time=login.time, sequence=login.sequence)
          self.accepted = self.accepted + 1
          LoginResumed
        }
        None => {
          let session = TerminalSession::new(frame.vin)
          session.login(time=login.time, sequence=login.sequence)
          self.sessions.set(frame.vin, session)
          self.accepted = self.accepted + 1
          LoginAccepted
        }
      }
    }
    RealtimeReport => {
      let report = RealtimeReport::parse(frame.payload[:])
      match self.sessions.get(frame.vin) {
        Some(session) => {
          session.report(at=report.time)
          self.accepted = self.accepted + 1
          ReportAccepted
        }
        None => {
          self.rejected = self.rejected + 1
          Rejected(reason="unknown vin: \{frame.vin}")
        }
      }
    }
    ResendReport => {
      let report = RealtimeReport::parse(frame.payload[:])
      match self.sessions.get(frame.vin) {
        Some(session) => {
          session.report(at=report.time, resend=true)
          self.accepted = self.accepted + 1
          ReportAccepted
        }
        None => {
          self.rejected = self.rejected + 1
          Rejected(reason="unknown vin: \{frame.vin}")
        }
      }
    }
    Heartbeat => {
      match self.sessions.get(frame.vin) {
        Some(session) => {
          session.heartbeat()
          self.accepted = self.accepted + 1
          HeartbeatAccepted
        }
        None => {
          self.rejected = self.rejected + 1
          Rejected(reason="unknown vin: \{frame.vin}")
        }
      }
    }
    VehicleLogout => {
      match self.sessions.get(frame.vin) {
        Some(session) => {
          session.logout()
          self.accepted = self.accepted + 1
          LogoutAccepted
        }
        None => {
          self.rejected = self.rejected + 1
          Rejected(reason="unknown vin: \{frame.vin}")
        }
      }
    }
    _ => {
      self.rejected = self.rejected + 1
      Rejected(reason="unsupported command: \{frame.command.name()}")
    }
  }
}

///|
pub fn Gateway::online_count(self : Gateway) -> Int32 {
  let mut count = 0
  for _, session in self.sessions {
    if session.is_online() {
      count = count + 1
    }
  }
  count
}

///|
pub fn Gateway::session(self : Gateway, vin : String) -> TerminalSession? {
  self.sessions.get(vin)
}