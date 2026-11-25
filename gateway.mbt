// gateway.mbt
///|
/// 应答标志取值口径。GB/T 32960.3-2016 表 4 只给出 0x01 成功、0x02 失败、0xFE 命令；
/// 0x03 VIN 重复、0xFF 无效来自地方标准与 2025 版，默认不启用。
pub(all) enum ResponseProfile {
  Gb2016
  Extended
}

///|
/// 平台对一跳上行帧的处理结论。
pub(all) enum RouteOutcome {
  LoginAccepted
  LoginResumed
  LoginDuplicate
  LoginIgnored
  ReportAccepted
  ResendAccepted
  HeartbeatAccepted
  LogoutAccepted
  TimeSyncAcknowledged
  PlatformLoginAccepted
  PlatformLogoutAccepted
  Rejected
  ConflictingDirection
  Undecodable
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
    PlatformLoginAccepted => "platform-login-accepted"
    PlatformLogoutAccepted => "platform-logout-accepted"
    Rejected => "rejected"
    ConflictingDirection => "conflicting-direction"
    Undecodable => "undecodable"
  }
}

///|
/// 处理结果。`response` 为 `None` 表示按标准不应答。
pub(all) struct Handled {
  outcome : RouteOutcome
  response : Frame?
  note : String
}

///|
pub(all) struct AuditEntry {
  vin : String
  command : String
  outcome : String
  note : String
}

///|
/// 平台侧会话表与处理规则。纯逻辑，不含套接字。
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
    Rejected | ConflictingDirection | Undecodable =>
      g.rejected = g.rejected + 1
    _ => g.accepted = g.accepted + 1
  }
  { outcome, response, note }
}

///|
/// 应答构造失败时退化为不加密的原始应答，保证平台总有话可说。
fn answer(
  frame : Frame,
  flag : ResponseFlag,
  shape~ : ResponseShape,
  answer_time~ : Time?,
) -> Frame {
  build_response(frame, flag, shape~, answer_time~) catch {
    _ => response_frame(frame, flag)
  }
}

///|
/// 处理一跳上行帧。
///
/// 车端与平台间是两套规则：车端实时上报校验正确时不应答（附录 B.2.1），
/// 平台间实时上报校验正确时必须应答（正文 5.2.2）。两者由 `scope` 区分，不混用。
pub fn Gateway::handle(
  self : Gateway,
  frame : Frame,
  scope~ : Scope = TerminalToPlatform,
  shape? : ResponseShape,
  answer_time~ : Time? = None,
  profile~ : ResponseProfile = Gb2016,
) -> Handled {
  // 应答形态按场景取默认：附录 B（车端）要求其余报文内容与请求一致；
  // 平台间的地方口径是保留报文时间、删除其余内容。正文未规定平台间应答包格式。
  // 2025 版正文 6.3.2 与附录 B.3.3.2 一致：保留报文时间、删除其余报文内容，两个场景相同。
  let shape = match shape {
    Some(value) => value
    None => TimeOnly
  }
  // 方向检查：车端只收终端上行，平台间只收平台上行，下行命令平台侧一律不接受。
  let direction_ok = match scope {
    TerminalToPlatform => frame.command.is_terminal_uplink()
    PlatformToPlatform => frame.command.is_platform_uplink()
  }
  if !direction_ok {
    let response = answer(frame, OtherError, shape~, answer_time~)
    let expected = match scope {
      TerminalToPlatform => "车载终端上行命令"
      PlatformToPlatform => "平台上行命令"
    }
    return audit_and_pack(
      self,
      frame.vin,
      frame.command,
      ConflictingDirection,
      Some(response),
      note="命令 \{frame.command.name()} 不属于\{expected}，应答 0x02",
    )
  }
  match scope {
    TerminalToPlatform => self.handle_terminal(frame, shape~, answer_time~, profile~)
    PlatformToPlatform => self.handle_platform(frame, shape~, answer_time~)
  }
}

///|
/// 车端规则（附录 B，资料性）。
fn Gateway::handle_terminal(
  self : Gateway,
  frame : Frame,
  shape~ : ResponseShape,
  answer_time~ : Time?,
  profile~ : ResponseProfile,
) -> Handled {
  match frame.command {
    VehicleLogin => {
      let login = VehicleLogin::decode(frame.payload[:]) catch {
        _ => {
          // 附录 B.1：校验错误时忽略所接收数据，不应答。
          return audit_and_pack(
            self,
            frame.vin,
            frame.command,
            LoginIgnored,
            None,
            note="登入校验未通过，按附录 B.1 忽略且不应答",
          )
        }
      }
      match self.sessions.get(frame.vin) {
        Some(session) => {
          if session.is_online() {
            let flag = VinDuplicate
            let response = answer(frame, flag, shape~, answer_time~)
            let note = "VIN 已在线，按表 4 应答 0x03 VIN 重复"
            audit_and_pack(
              self,
              frame.vin,
              frame.command,
              LoginDuplicate,
              Some(response),
              note~,
            )
          } else {
            session.login(login)
            let response = answer(frame, Success, shape~, answer_time~)
            audit_and_pack(
              self,
              frame.vin,
              frame.command,
              LoginResumed,
              Some(response),
              note="会话曾关闭，重登成功，应答 0x01",
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
                note="VIN 不合法，按附录 B.1 忽略且不应答",
              )
            }
          }
          session.login(login)
          self.sessions.set(frame.vin, session)
          let response = answer(frame, Success, shape~, answer_time~)
          audit_and_pack(
            self,
            frame.vin,
            frame.command,
            LoginAccepted,
            Some(response),
            note="新建会话，应答 0x01；终端收到应答后才完成登入",
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
          let response = answer(frame, OtherError, shape~, answer_time~)
          return audit_and_pack(
            self,
            frame.vin,
            frame.command,
            Rejected,
            Some(response),
            note="上报校验失败，应答 0x02；终端间隔 1min 重发至多 3 次",
          )
        }
      }
      match self.sessions.get(frame.vin) {
        Some(session) => {
          // 7 日窗口是发送方的存储义务，平台不因此拒收；需要严格审计时由调用方开启。
          session.report(at=telemetry.time, resend~) catch {
            _ => {
              return audit_and_pack(
                self,
                frame.vin,
                frame.command,
                Rejected,
                None,
                note="会话状态异常（未在线），丢弃",
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
            note="校验正确，按附录 B.2.1 车端不做应答",
          )
        }
        None => {
          audit_and_pack(
            self,
            frame.vin,
            frame.command,
            Rejected,
            None,
            note="未见该 VIN 有效登入，丢弃且不应答",
          )
        }
      }
    }
    TerminalTimeSync => {
      // 0x08 是终端上行请求，数据单元为空；平台应答 0x01 表示可以校时。
      let response = answer(frame, Success, shape~, answer_time~)
      audit_and_pack(
        self,
        frame.vin,
        frame.command,
        TimeSyncAcknowledged,
        Some(response),
        note="终端校时请求，数据单元为空，应答 0x01",
      )
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
                note="心跳时会话不在线，丢弃",
              )
            }
          }
          let response = answer(frame, Success, shape~, answer_time~)
          audit_and_pack(
            self,
            frame.vin,
            frame.command,
            HeartbeatAccepted,
            Some(response),
            note="心跳应答 0x01（附录 B 未强制，按平台惯例应答）",
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
          let response = answer(frame, OtherError, shape~, answer_time~)
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
              let response = answer(frame, OtherError, shape~, answer_time~)
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
          let response = answer(frame, Success, shape~, answer_time~)
          let note = "登出流水号 \{logout.sequence}，会话关闭，应答 0x01（附录 B 未强制）"
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
          let response = answer(frame, OtherError, shape~, answer_time~)
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
    _ => {
      let response = answer(frame, OtherError, shape~, answer_time~)
      audit_and_pack(
        self,
        frame.vin,
        frame.command,
        Rejected,
        Some(response),
        note="车端场景不处理该命令，应答 0x02",
      )
    }
  }
}

///|
/// 平台间规则（正文第 5 章，规范性）：校验正确时也要正确应答，这与车端相反。
fn Gateway::handle_platform(
  self : Gateway,
  frame : Frame,
  shape~ : ResponseShape,
  answer_time~ : Time?,
) -> Handled {
  match frame.command {
    PlatformLogin => {
      let login = PlatformLogin::decode(frame.payload[:]) catch {
        _ => {
          let response = answer(frame, OtherError, shape~, answer_time~)
          return audit_and_pack(
            self,
            frame.vin,
            frame.command,
            Rejected,
            Some(response),
            note="平台登入校验失败，按 5.2.2 做错误应答 0x02",
          )
        }
      }
      let response = answer(frame, Success, shape~, answer_time~)
      audit_and_pack(
        self,
        frame.vin,
        frame.command,
        PlatformLoginAccepted,
        Some(response),
        note="平台登入校验正确，应答 0x01（用户名 \{login.username.length()} 字符）",
      )
    }
    PlatformLogout => {
      let response = answer(frame, Success, shape~, answer_time~)
      audit_and_pack(
        self,
        frame.vin,
        frame.command,
        PlatformLogoutAccepted,
        Some(response),
        note="平台登出，应答 0x01",
      )
    }
    RealtimeReport | ResendReport => {
      let telemetry = Telemetry::decode(frame.payload[:]) catch {
        _ => {
          let response = answer(frame, OtherError, shape~, answer_time~)
          return audit_and_pack(
            self,
            frame.vin,
            frame.command,
            Rejected,
            Some(response),
            note="平台间上报校验失败，应答 0x02，客户端 1min 后重发至多 3 次",
          )
        }
      }
      let _ = telemetry
      let response = answer(frame, Success, shape~, answer_time~)
      let outcome = match frame.command {
        ResendReport => ResendAccepted
        _ => ReportAccepted
      }
      audit_and_pack(
        self,
        frame.vin,
        frame.command,
        outcome,
        Some(response),
        note="校验正确，按 5.2.2 平台间仍须正确应答 0x01",
      )
    }
    _ => {
      let response = answer(frame, OtherError, shape~, answer_time~)
      audit_and_pack(
        self,
        frame.vin,
        frame.command,
        Rejected,
        Some(response),
        note="平台间场景不处理该命令，应答 0x02",
      )
    }
  }
}

///|
/// 处理一段原始字节：先取报头，再按密钥解密与校验，最后按场景处理。
pub fn Gateway::handle_bytes(
  self : Gateway,
  data : Bytes,
  scope~ : Scope = TerminalToPlatform,
  shape~ : ResponseShape = KeepRequestPayload,
  answer_time~ : Time? = None,
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
      // 应答要按「其余报文内容一致」保持原加密方式；拿不到密钥就无法加密应答，
      // 此时只能记录、不应答，而不是给出一个不加密的应答冒充合规。
      let can_answer = match header.encryption {
        Plain => true
        _ => false
      }
      let response = if can_answer {
        let placeholder = Frame::new(
          command=header.command,
          response=header.response,
          vin=header.vin,
          encryption=header.encryption,
          payload=Bytes::new(0),
        )
        Some(answer(placeholder, OtherError, shape~, answer_time~))
      } else {
        None
      }
      let note = if can_answer {
        "校验码失败，应答 0x02"
      } else {
        "加密帧无法解密（缺 \{header.encryption.name()} 密钥），也无法按同加密方式应答，只记录"
      }
      return audit_and_pack(
        self,
        header.vin,
        header.command,
        Rejected,
        response,
        note~,
      )
    }
  }
  self.handle(frame, scope~, shape~, answer_time~)
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
