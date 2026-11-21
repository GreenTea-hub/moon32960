// crypto_test.mbt
///|
/// FIPS-197 附录 C.1 的 AES-128 测试向量，用于证明实现与标准一致。
const FIPS_KEY : String = "000102030405060708090a0b0c0d0e0f"

///|
const FIPS_PLAIN : String = "00112233445566778899aabbccddeeff"

///|
const FIPS_CIPHER : String = "69c4e0d86a7b0430d8cdb78070b4c55a"

///|
test "AES-128 单分组加密匹配 FIPS-197 向量" {
  let keys = @moon32960.aes128_expand_key(@moon32960.from_hex(FIPS_KEY))
  let block = @moon32960.from_hex(FIPS_PLAIN)
  let encrypted = @moon32960.aes128_encrypt_block(block[:], keys)
  assert_eq(@moon32960.to_hex(encrypted), FIPS_CIPHER)
}

///|
test "AES-128 单分组解密还原明文" {
  let keys = @moon32960.aes128_expand_key(@moon32960.from_hex(FIPS_KEY))
  let cipher = @moon32960.from_hex(FIPS_CIPHER)
  let decrypted = @moon32960.aes128_decrypt_block(cipher[:], keys)
  assert_eq(@moon32960.to_hex(decrypted), FIPS_PLAIN)
}

///|
test "AES-128 ECB 往返" {
  let key = @moon32960.from_hex(FIPS_KEY)
  let plain = @moon32960.from_hex(FIPS_PLAIN)
  let cipher = @moon32960.aes128_ecb_encrypt(key, plain)
  assert_eq(@moon32960.to_hex(cipher), FIPS_CIPHER)
  let back = @moon32960.aes128_ecb_decrypt(key, cipher)
  assert_eq(@moon32960.to_hex(back), FIPS_PLAIN)
}

///|
test "AES-128 CBC 往返" {
  let key = @moon32960.from_hex(FIPS_KEY)
  let iv = @moon32960.from_hex("00000000000000000000000000000000")
  let plain = @moon32960.from_hex(FIPS_PLAIN)
  let cipher = @moon32960.aes128_cbc_encrypt(key, iv, plain)
  let back = @moon32960.aes128_cbc_decrypt(key, iv, cipher)
  assert_eq(@moon32960.to_hex(back), FIPS_PLAIN)
}

///|
test "AES 密钥长度必须是 16 字节" {
  try @moon32960.aes128_expand_key(@moon32960.from_hex("00112233")) catch {
    err => match err {
      @moon32960.FrameError::Payload(_) => ()
      _ => fail("期望 Payload")
    }
  } noraise {
    _ => fail("短密钥仍被接受")
  }
}
