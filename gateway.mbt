// gateway.mbt
///|
/// 平台对一跳上行帧的处理结论。
pub(all) enum RouteOutcome {
  LoginAccepted // 登入正确，应答 0x01
  LoginResumed // 会话已关闭后重登，应答 0x01
  LoginDuplicate // VIN 已在线，应答 0x03
  LoginIgnored // 登入校验未通过，按标准忽略且不应答
  ReportAccepted // 实时上报校验正确，按标准不应答
  ResendAccepted // 补发校验正确，按标准不应答
  HeartbeatAccepted // 心跳，应答 0x01
  LogoutAccepted // 登出，应答 0x01
  TimeSyncAcknowledged // 校时应答 0x01
  Rejected // 拒绝，应答 0x02
  Undecodable // 连报头都无法解析，无从应答
}

///|
pub fn RouteOutcome::name(self : RouteOutcome) -> String {
  match self {
    LoginAccepted => "login-accepted"
    LoginResumed => "login-resumed"
    LoginDuplicate => "login-duplicate"
    LoginIgnored => "login-ignored"
    ReportAccepted => "report-accepted"
    ResendAccepted => "resend-accepted"
    HeartbeatAccepted => "heartbeat-accepted"
    LogoutAccepted => "logout-accepted"
    TimeSyncAcknowledged => "time-sync-acknowledged"
    Rejected => "rejected"
    Undecodable => "undecodable"
  }
}

///|
/// 处理结果。`response` 为 `None` 表示按标准不应答——实时与补发在上报正确时属于这种情形。
pub(all) struct Handled {
  outcome : RouteOutcome
  response : Frame?
  note : String
}

///|
/// 审计条目：平台每次接收都留一条。
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
fn audit_and_pack(
  g : Gateway,
  vin : String,
  command : Command,
  outcome : RouteOutcome,
  response : Frame?,
  note~ : String,
) -> Handled {
  g.audit.push({
    vin,
    command: command.name(),
    outcome: outcome.name(),
    note,
  })
  match outcome {
    Rejected | Undecodable => g.rejected = g.rejected + 1
    _ => g.accepted = g.accepted + 1
  }
  { outcome, response, note }
}

///|
/// 处理一跳已解帧的上行帧。
///
/// 应答语义按 GB/T 32960.3 附录 B：登入必须应答；实时与补发上报校验正确时不应答，
/// 校验错误时回错误应答；心跳与登出应答。
pub fn Gateway::handle(self : Gateway, frame : Frame) -> Handled {
  match frame.command {
    VehicleLogin => {
      let login = VehicleLogin::decode(frame.payload[:]) catch {
        _ => {
          return audit_and_pack(
            self,
            frame.vin,
            frame.command,
            LoginIgnored,
            None,
            note="登入数据单元校验未通过，按标准忽略所接收数据且不应答",
          )
        }
      }
      match self.sessions.get(frame.vin) {
        Some(session) => {
          if session.is_online() {
            let response = response_frame(frame, VinDuplicate)
            audit_and_pack(
              self,
              frame.vin,
              frame.command,
              LoginDuplicate,
              Some(response),
              note="VIN 已处于在线会话，应答 0x03 VIN 重复",
            )
          } else {
            session.login(login)
            let response = response_frame(frame, Success)
            audit_and_pack(
              self,
              frame.vin,
              frame.command,
              LoginResumed,
              Some(response),
              note="会话曾关闭，重新登入成功，应答 0x01",
            )
          }
        }
        None => {
          let session = TerminalSession::new(frame.vin) catch {
            _ => {
              return audit_and_pack(
                self,
                frame.vin,
                frame.command,
                LoginIgnored,
                None,
                note="VIN 不合法，按标准忽略且不应答",
              )
            }
          }
          session.login(login)
          self.sessions.set(frame.vin, session)
          let response = response_frame(frame, Success)
          audit_and_pack(
            self,
            frame.vin,
            frame.command,
            LoginAccepted,
            Some(response),
            note="新建会话，应答 0x01；终端收到应答后才完成本次登入",
          )
        }
      }
    }
    RealtimeReport | ResendReport => {
      let resend = match frame.command {
        ResendReport => true
        _ => false
      }
      let telemetry = Telemetry::decode(frame.payload[:]) catch {
        _ => {
          let response = response_frame(frame, Failure)
          return audit_and_pack(
            self,
            frame.vin,
            frame.command,
            Rejected,
            Some(response),
            note="上报数据单元校验失败，应答 0x02；终端应间隔 1min 重发，失败 3 次后停止",
          )
        }
      }
      match self.sessions.get(frame.vin) {
        Some(session) => {
          session.report(at=telemetry.time, resend~) catch {
            _ => {
              let response = response_frame(frame, Failure)
              return audit_and_pack(
                self,
                frame.vin,
                frame.command,
                Rejected,
                Some(response),
                note="上报时间超出补发窗口，应答 0x02",
              )
            }
          }
          let outcome = if resend {
            ResendAccepted
          } else {
            ReportAccepted
          }
          audit_and_pack(
            self,
            frame.vin,
            frame.command,
            outcome,
            None,
            note="校验正确，按标准不做应答",
          )
        }
        None => {
          audit_and_pack(
            self,
            frame.vin,
            frame.command,
            Rejected,
            None,
            note="未见该 VIN 的有效登入，丢弃且不应答",
          )
        }
      }
    }
    Heartbeat => {
      match self.sessions.get(frame.vin) {
        Some(session) => {
          session.heartbeat() catch {
            _ => {
              return audit_and_pack(
                self,
                frame.vin,
                frame.command,
                Rejected,
                None,
                note="心跳时会话不在线，丢弃且不应答",
              )
            }
          }
          let response = response_frame(frame, Success)
          audit_and_pack(
            self,
            frame.vin,
            frame.command,
            HeartbeatAccepted,
            Some(response),
            note="心跳应答 0x01",
          )
        }
        None => {
          audit_and_pack(
            self,
            frame.vin,
            frame.command,
            Rejected,
            None,
            note="未知 VIN 心跳，丢弃且不应答",
          )
        }
      }
    }
    VehicleLogout => {
      let logout = VehicleLogout::decode(frame.payload[:]) catch {
        _ => {
          let response = response_frame(frame, Failure)
          return audit_and_pack(
            self,
            frame.vin,
            frame.command,
            Rejected,
            Some(response),
            note="登出数据单元解析失败，应答 0x02",
          )
        }
      }
      match self.sessions.get(frame.vin) {
        Some(session) => {
          session.logout() catch {
            _ => {
              let response = response_frame(frame, Failure)
              return audit_and_pack(
                self,
                frame.vin,
                frame.command,
                Rejected,
                Some(response),
                note="登出时会话不在线，应答 0x02",
              )
            }
          }
          let response = response_frame(frame, Success)
          let note = "登出流水号 \{logout.sequence}，会话关闭，应答 0x01"
          audit_and_pack(
            self,
            frame.vin,
            frame.command,
            LogoutAccepted,
            Some(response),
            note~,
          )
        }
        None => {
          let response = response_frame(frame, Failure)
          audit_and_pack(
            self,
            frame.vin,
            frame.command,
            Rejected,
            Some(response),
            note="未知 VIN 登出，应答 0x02",
          )
        }
      }
    }
    TerminalTimeSync => {
      let response = response_frame(frame, Success)
      audit_and_pack(
        self,
        frame.vin,
        frame.command,
        TimeSyncAcknowledged,
        Some(response),
        note="校时应答 0x01",
      )
    }
    _ => {
      let response = response_frame(frame, Failure)
      audit_and_pack(
        self,
        frame.vin,
        frame.command,
        Rejected,
        Some(response),
        note="平台不处理该命令，应答 0x02",
      )
    }
  }
}

///|
/// 处理一段原始字节：先取报头，再按密钥解密与校验，最后交给业务规则。
///
/// 解密或校验失败时，只要报头可读就回 0x02，让终端知道需要重发；报头都读不出则无从应答。
pub fn Gateway::handle_bytes(
  self : Gateway,
  data : Bytes,
  key~ : KeyMaterial = NoKey,
) -> Handled {
  let header = peek_header(data) catch {
    _ => {
      return audit_and_pack(
        self,
        "",
        Unknown(0),
        Undecodable,
        None,
        note="报头不可解析，无法确定 VIN 与命令，不应答",
      )
    }
  }
  let frame = decode_frame(data, key~) catch {
    _ => {
      let placeholder = Frame::new(
        command=header.command,
        response=header.response,
        vin=header.vin,
        encryption=header.encryption,
        payload=Bytes::new(0),
      )
      let response = response_frame(placeholder, Failure)
      return audit_and_pack(
        self,
        header.vin,
        header.command,
        Rejected,
        Some(response),
        note="校验码或解密失败，应答 0x02",
      )
    }
  }
  self.handle(frame)
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
