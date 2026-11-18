// session_test.mbt
///|
fn sample_time(hour~ : Int32 = 9, minute~ : Int32 = 31, second~ : Int32 = 0) -> @moon32960.Time {
  try! @moon32960.Time::new(
    year=2026,
    month=11,
    day=18,
    hour~,
    minute~,
    second~,
  )
}

///|
fn sample_login(sequence~ : Int32 = 1) -> @moon32960.VehicleLogin {
  try!
    @moon32960.VehicleLogin::new(
      time=sample_time(hour=9, minute=30),
      sequence~,
      iccid="89860620180001234567",
      storage_codes=["BAT-A01"],
      code_len=7,
    )
}

///|
test "登入后在线，登出后关闭" {
  let session = @moon32960.TerminalSession::new("LGWEF4A56MF123456")
  assert_false(session.is_online())
  session.login(sample_login())
  assert_true(session.is_online())
  assert_eq(session.iccid, "89860620180001234567")
  assert_eq(session.storage_codes.length(), 1)
  session.report(at=sample_time())
  assert_eq(session.report_count, 1)
  session.heartbeat()
  session.logout()
  assert_false(session.is_online())
}

///|
test "未登入上报被拒绝" {
  let session = @moon32960.TerminalSession::new("LGWEF4A56MF123456")
  try session.report(at=sample_time()) catch {
    _ => ()
  } noraise {
    _ => fail("未登入上报未被拒绝")
  }
}

///|
test "补发与实时分开计数" {
  let session = @moon32960.TerminalSession::new("LGWEF4A56MF123456")
  session.login(sample_login())
  session.report(at=sample_time())
  session.report(at=sample_time(hour=9, minute=32), resend=true)
  session.report(at=sample_time(hour=9, minute=33), resend=true)
  assert_eq(session.report_count, 1)
  assert_eq(session.resend_count, 2)
  assert_eq(session.last_report.unwrap().minute, 33)
}

///|
test "补发超出 7 日窗口被拒绝" {
  let session = @moon32960.TerminalSession::new("LGWEF4A56MF123456")
  session.login(sample_login())
  session.report(at=sample_time())
  let too_late = try! @moon32960.Time::new(
    year=2026,
    month=11,
    day=27,
    hour=9,
    minute=31,
    second=0,
  )
  try session.report(at=too_late, resend=true) catch {
    _ => ()
  } noraise {
    _ => fail("超过 7 日的补发未被拒绝")
  }
}
