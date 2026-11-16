// errors.mbt
///|
/// Errors raised while decoding or encoding GB/T 32960 frames and payloads.
///
/// Every variant names the failing field so that CLI output and test
/// assertions stay actionable instead of collapsing into a single string.
pub(all) suberror FrameError {
  InvalidStart(bytes~ : String)
  TooShort(needed~ : Int32, actual~ : Int32)
  BadCommand(byte~ : Int32)
  BadResponseFlag(byte~ : Int32)
  BadEncryption(byte~ : Int32)
  BadVin(vin~ : String)
  BadLength(expected~ : Int32, actual~ : Int32)
  BadTime(bytes~ : String)
  Payload(message~ : String)
}