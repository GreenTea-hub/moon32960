// session_test.mbt
///|
test "session opens on login and closes on logout" {
  let session = @moon32960.TerminalSession::new("LGWEF4A56MF123456")
  let time = @moon32960.Time::new(
    year=2026,
    month=11,
    day=16,
    hour=15,
    minute=0,
    second=0,
  )
  assert_false(session.is_online())
  session.login(time~, sequence=1)
  assert_true(session.is_online())
  session.report(at=time)
  assert_eq(session.report_count, 1)
  session.heartbeat()
  session.logout()
  assert_false(session.is_online())
}

///|
test "session rejects a report before login" {
  let session = @moon32960.TerminalSession::new("LGWEF4A56MF123456")
  let time = @moon32960.Time::new(
    year=2026,
    month=11,
    day=16,
    hour=15,
    minute=0,
    second=0,
  )
  try session.report(at=time) catch {
    err => {
      match err {
        @moon32960.FrameError::Payload(_) => ()
        _ => fail("unexpected error variant")
      }
    }
  } noraise {
    _ => fail("expected a Payload error")
  }
}

///|
test "resend samples count separately from live reports" {
  let session = @moon32960.TerminalSession::new("LGWEF4A56MF123456")
  let time = @moon32960.Time::new(
    year=2026,
    month=11,
    day=16,
    hour=15,
    minute=0,
    second=0,
  )
  session.login(time~, sequence=1)
  session.report(at=time)
  session.report(at=time, resend=true)
  assert_eq(session.report_count, 1)
  assert_eq(session.resend_count, 1)
}
