// errors.mbt
///|
/// Errors raised while decoding or encoding GB/T 32960.3-2016 frames.
///
/// Each variant names the failing field so a platform operator can tell a
/// malformed frame from an unsupported one without reading the log twice.
pub(all) suberror FrameError {
  InvalidStart(bytes~ : String)
  TooShort(needed~ : Int32, actual~ : Int32)
  BadResponseFlag(byte~ : Int32)
  BadEncryption(byte~ : Int32)
  BadChecksum(expected~ : Int32, actual~ : Int32)
  BadVin(vin~ : String)
  BadLength(expected~ : Int32, actual~ : Int32)
  BadTime(bytes~ : String)
  BadIccid(iccid~ : String)
  FieldOutOfRange(field~ : String, value~ : Int32, low~ : Int32, high~ : Int32)
  UnsupportedInfoType(code~ : Int32)
  Payload(message~ : String)
}
