// gateway_test.mbt
///|
fn fixed_time() -> @moon32960.Time {
  try! @moon32960.Time::new(
    year=2026,
    month=11,
    day=16,
    hour=15,
    minute=0,
    second=0,
  )
}

///|
fn login_frame(vin : String, sequence : Int32) -> @moon32960.Frame raise {
  let time = fixed_time()
  let data = @moon32960.LoginData::new(time~, sequence~)
  @moon32960.Frame::new(
    command=@moon32960.Command::VehicleLogin,
    response=@moon32960.ResponseFlag::Success,
    vin~,
    encryption=@moon32960.Encryption::Plain,
    payload=data.to_bytes(),
  )
}

///|
fn report_frame(vin : String) -> @moon32960.Frame {
  let time = fixed_time()
  let report = @moon32960.RealtimeReport::new(time~, items=[])
  @moon32960.Frame::new(
    command=@moon32960.Command::RealtimeReport,
    response=@moon32960.ResponseFlag::Success,
    vin~,
    encryption=@moon32960.Encryption::Plain,
    payload=report.to_bytes(),
  )
}

///|
fn logout_frame(vin : String) -> @moon32960.Frame {
  let time = fixed_time()
  let data : @moon32960.LogoutData = { time, sequence: 1 }
  @moon32960.Frame::new(
    command=@moon32960.Command::VehicleLogout,
    response=@moon32960.ResponseFlag::Success,
    vin~,
    encryption=@moon32960.Encryption::Plain,
    payload=data.to_bytes(),
  )
}

///|
test "gateway accepts a login and marks the terminal online" {
  let gateway = @moon32960.Gateway::new()
  let outcome = gateway.route(login_frame("LGWEF4A56MF123456", 1))
  match outcome {
    @moon32960.RouteOutcome::LoginAccepted => ()
    _ => fail("expected LoginAccepted")
  }
  assert_eq(gateway.online_count(), 1)
  assert_eq(gateway.accepted, 1)
}

///|
test "gateway resumes an already known vin" {
  let gateway = @moon32960.Gateway::new()
  let vin = "LGWEF4A56MF123456"
  let _ = gateway.route(login_frame(vin, 1))
  let outcome = gateway.route(login_frame(vin, 2))
  match outcome {
    @moon32960.RouteOutcome::LoginResumed => ()
    _ => fail("expected LoginResumed")
  }
  assert_eq(gateway.online_count(), 1)
}

///|
test "gateway rejects a report from an unknown vin" {
  let gateway = @moon32960.Gateway::new()
  let outcome = gateway.route(report_frame("LGWEF4A56MF999999"))
  match outcome {
    @moon32960.RouteOutcome::Rejected(_) => ()
    _ => fail("expected Rejected")
  }
  assert_eq(gateway.rejected, 1)
  assert_eq(gateway.online_count(), 0)
}

///|
test "gateway accepts a known realtime report" {
  let gateway = @moon32960.Gateway::new()
  let vin = "LGWEF4A56MF123456"
  let _ = gateway.route(login_frame(vin, 1))
  let outcome = gateway.route(report_frame(vin))
  match outcome {
    @moon32960.RouteOutcome::ReportAccepted => ()
    _ => fail("expected ReportAccepted")
  }
  match gateway.session(vin) {
    Some(session) => assert_eq(session.report_count, 1)
    None => fail("expected a stored session")
  }
}

///|
test "gateway closes the session on logout" {
  let gateway = @moon32960.Gateway::new()
  let vin = "LGWEF4A56MF123456"
  let _ = gateway.route(login_frame(vin, 1))
  let outcome = gateway.route(logout_frame(vin))
  match outcome {
    @moon32960.RouteOutcome::LogoutAccepted => ()
    _ => fail("expected LogoutAccepted")
  }
  assert_eq(gateway.online_count(), 0)
}
