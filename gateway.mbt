// gateway.mbt
///|
/// 平台对一跳上行帧的处理结论。
pub(all) enum RouteOutcome {
  LoginAccepted
  LoginResumed
  LoginDuplicate
  ReportAccepted
  ResendAccepted
  HeartbeatAccepted
  LogoutAccepted
  TimeSyncAcknowledged
  Rejected
  Unsupported
}

///|
pub fn RouteOutcome::name(self : RouteOutcome) -> String {
  match self {
    LoginAccepted => "login-accepted"
    LoginResumed => "login-resumed"
    LoginDuplicate => "login-duplicate"
    ReportAccepted => "report-accepted"
    ResendAccepted => "resend-accepted"
    HeartbeatAccepted => "heartbeat-accepted"
    LogoutAccepted => "logout-accepted"
    TimeSyncAcknowledged => "time-sync-acknowledged"
    Rejected => "rejected"
    Unsupported => "unsupported"
  }
}

///|
/// 一次处理的结果：结论、要回给终端的应答帧、以及给运维看的一句话说明。
pub(all) struct Handled {
  outcome : RouteOutcome
  response : Frame
  note : String
}

///|
/// 审计条目：平台的每次接收都留一条，便于事后核对。
pub(all) struct AuditEntry {
  vin : String
  command : String
  outcome : String
  note : String
}

///|
/// 平台侧会话表与处理规则。纯逻辑，不含套接字，便于以回放数据驱动测试。
pub(all) struct Gateway {
  sessions : Map[String, TerminalSession]
  mut accepted : Int32
  mut rejected : Int32
  audit : Array[AuditEntry]
}

///|
pub fn Gateway::new() -> Gateway {
  { sessions: Map([]), accepted: 0, rejected: 0, audit: [] }
}

///|
fn audit_and_answer(
  g : Gateway,
  frame : Frame,
  outcome : RouteOutcome,
  note~ : String,
  response~ : Frame,
) -> Handled {
  g.audit.push({
    vin: frame.vin,
    command: frame.command.name(),
    outcome: outcome.name(),
    note,
  })
  match outcome {
    Rejected | Unsupported => g.rejected = g.rejected + 1
    _ => g.accepted = g.accepted + 1
  }
  { outcome, response, note }
}

///|
/// 处理一跳上行帧：解析数据单元、更新会话、生成应答。
///
/// 解析失败同样返回应答帧（应答标志取「失败」），保证终端能收到反馈而不是静默超时。
pub fn Gateway::handle(
  self : Gateway,
  frame : Frame,
  header~ : ReportHeader = TimestampOnly,
) -> Handled raise FrameError {
  match frame.command {
    VehicleLogin => {
      let login = VehicleLogin::decode(frame.payload[:])
      match self.sessions.get(frame.vin) {
        Some(session) => {
          if session.is_online() {
            let response = response_frame(frame, ResponseFlag::VinDuplicate)
            audit_and_answer(
              self,
              frame,
              LoginDuplicate,
              note="VIN 已处于在线状态，按重复登入拒绝",
              response~,
            )
          } else {
            session.login(login)
            let response = response_frame(frame, ResponseFlag::Success)
            audit_and_answer(
              self,
              frame,
              LoginResumed,
              note="会话已关闭后重新登入，复用原会话",
              response~,
            )
          }
        }
        None => {
          let session = TerminalSession::new(frame.vin)
          session.login(login)
          self.sessions.set(frame.vin, session)
          let response = response_frame(frame, ResponseFlag::Success)
          audit_and_answer(
            self,
            frame,
            LoginAccepted,
            note="新建会话，ICCID 共 \{login.iccid.length()} 位",
            response~,
          )
        }
      }
    }
    RealtimeReport => {
      let telemetry = Telemetry::decode(frame.payload[:], header~)
      match self.sessions.get(frame.vin) {
        Some(session) => {
          session.report(at=telemetry.time)
          let response = response_frame(frame, ResponseFlag::Success)
          audit_and_answer(
            self,
            frame,
            ReportAccepted,
            note="接收 \{telemetry.items.length()} 类信息体",
            response~,
          )
        }
        None => {
          let response = response_frame(frame, ResponseFlag::Failure)
          audit_and_answer(
            self,
            frame,
            Rejected,
            note="未登入的 VIN 上报，按失败应答",
            response~,
          )
        }
      }
    }
    ResendReport => {
      let telemetry = Telemetry::decode(frame.payload[:], header~)
      match self.sessions.get(frame.vin) {
        Some(session) => {
          session.report(at=telemetry.time, resend=true) catch {
            _ => {
              let response = response_frame(frame, ResponseFlag::Failure)
              let note = "补发被拒：\{telemetry.time.to_display()}"
              return audit_and_answer(self, frame, Rejected, note~, response~)
            }
          }
          let response = response_frame(frame, ResponseFlag::Success)
          audit_and_answer(
            self,
            frame,
            ResendAccepted,
            note="补发 \{telemetry.items.length()} 类信息体",
            response~,
          )
        }
        None => {
          let response = response_frame(frame, ResponseFlag::Failure)
          audit_and_answer(
            self,
            frame,
            Rejected,
            note="未登入的 VIN 补发，按失败应答",
            response~,
          )
        }
      }
    }
    Heartbeat => {
      match self.sessions.get(frame.vin) {
        Some(session) => {
          session.heartbeat() catch {
            _ => {
              let response = response_frame(frame, ResponseFlag::Failure)
              return audit_and_answer(self, frame, Rejected, note="心跳时会话不在线", response~)
            }
          }
          let response = response_frame(frame, ResponseFlag::Success)
          audit_and_answer(self, frame, HeartbeatAccepted, note="心跳正常", response~)
        }
        None => {
          let response = response_frame(frame, ResponseFlag::Failure)
          audit_and_answer(self, frame, Rejected, note="未知 VIN 心跳", response~)
        }
      }
    }
    VehicleLogout => {
      let logout = VehicleLogout::decode(frame.payload[:])
      match self.sessions.get(frame.vin) {
        Some(session) => {
          session.logout() catch {
            _ => {
              let response = response_frame(frame, ResponseFlag::Failure)
              return audit_and_answer(self, frame, Rejected, note="登出时会话不在线", response~)
            }
          }
          let response = response_frame(frame, ResponseFlag::Success)
          let note = "登出流水号 \{logout.sequence}，会话已关闭"
          audit_and_answer(self, frame, LogoutAccepted, note~, response~)
        }
        None => {
          let response = response_frame(frame, ResponseFlag::Failure)
          audit_and_answer(self, frame, Rejected, note="未知 VIN 登出", response~)
        }
      }
    }
    TerminalTimeSync => {
      let response = response_frame(frame, ResponseFlag::Success)
      audit_and_answer(self, frame, TimeSyncAcknowledged, note="校时应答", response~)
    }
    _ => {
      let response = response_frame(frame, ResponseFlag::CommandNotRecognized)
      audit_and_answer(
        self,
        frame,
        Unsupported,
        note="平台不处理的命令：\{frame.command.name()}",
        response~,
      )
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
