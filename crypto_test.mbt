// crypto_test.mbt
///|
/// FIPS-197 附录 C.1 的 AES-128 测试向量。
const FIPS_KEY : String = "000102030405060708090a0b0c0d0e0f"

///|
const FIPS_PLAIN : String = "00112233445566778899aabbccddeeff"

///|
const FIPS_CIPHER : String = "69c4e0d86a7b0430d8cdb78070b4c55a"

///|
test "AES-128 单分组加密匹配 FIPS-197" {
  let keys = @moon32960.aes128_expand_key(@moon32960.from_hex(FIPS_KEY))
  let encrypted = @moon32960.aes128_encrypt_block(@moon32960.from_hex(FIPS_PLAIN)[:], keys)
  assert_eq(@moon32960.to_hex(encrypted), FIPS_CIPHER)
}

///|
test "AES-128 ECB 往返" {
  let key = @moon32960.from_hex(FIPS_KEY)
  let plain = @moon32960.from_hex(FIPS_PLAIN)
  let cipher = @moon32960.aes128_ecb_encrypt(key, plain)
  assert_eq(@moon32960.to_hex(cipher), FIPS_CIPHER)
  assert_eq(
    @moon32960.to_hex(@moon32960.aes128_ecb_decrypt(key, cipher)),
    FIPS_PLAIN,
  )
}

///|
test "PKCS#7 填充与去填充" {
  let data = @moon32960.from_hex("0011223344")
  let padded = @moon32960.pkcs7_pad(data)
  assert_eq(padded.length(), 16)
  assert_eq(@moon32960.to_hex(@moon32960.pkcs7_unpad(padded)), "0011223344")
}

///|
test "AES 密钥必须是 16 字节" {
  try @moon32960.aes128_expand_key(@moon32960.from_hex("00112233")) catch {
    _ => ()
  } noraise {
    _ => fail("短密钥仍被接受")
  }
}
