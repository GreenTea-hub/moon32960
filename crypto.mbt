// crypto.mbt
///|
/// AES-128 的 S 盒（FIPS-197 表 4）。
fn aes_sbox() -> Array[Int32] {
  [
    0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76, 0xca, 0x82, 0xc9,
    0x7d, 0xfa, 0x59, 0x47, 0xf0, 0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0, 0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f,
    0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15, 0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a, 0x07,
    0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75, 0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0, 0x52, 0x3b, 0xd6, 0xb3,
    0x29, 0xe3, 0x2f, 0x84, 0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58,
    0xcf, 0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c, 0x9f, 0xa8, 0x51, 0xa3,
    0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5, 0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2, 0xcd, 0x0c, 0x13, 0xec, 0x5f,
    0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73, 0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88,
    0x46, 0xee, 0xb8, 0x14, 0xde, 0x5e, 0x0b, 0xdb, 0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c, 0xc2, 0xd3, 0xac,
    0x62, 0x91, 0x95, 0xe4, 0x79, 0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a,
    0xae, 0x08, 0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a, 0x70,
    0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e, 0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e, 0xe1, 0xf8, 0x98, 0x11,
    0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf, 0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42,
    0x68, 0x41, 0x99, 0x2d, 0x0f, 0xb0, 0x54, 0xbb, 0x16,
  ]
}

///|
/// 逆 S 盒按正向表反查，避免再维护一张 256 项的表。
fn aes_inv_sbox(table : Array[Int32], value : Int32) -> Int32 {
  let mut result = 0
  let mut i = 0
  while i < 256 {
    if table[i] == value {
      result = i
      break
    }
    i = i + 1
  }
  result
}

///|
/// GF(2^8) 上的 x 乘 2。
fn xtime(value : Int32) -> Int32 {
  let doubled = value * 2
  if doubled >= 256 {
    (doubled % 256) ^ 0x1b
  } else {
    doubled
  }
}

///|
/// GF(2^8) 乘法（AES 多项式 0x11b）。
fn gf_mul(a : Int32, b : Int32) -> Int32 {
  let mut result = 0
  let mut x = a
  let mut y = b
  while y > 0 {
    if y % 2 == 1 {
      result = result ^ x
    }
    x = xtime(x)
    y = y / 2
  }
  result
}

///|
/// AES-128 密钥扩展，输出 176 字节（11 组 16 字节轮密钥）。
pub fn aes128_expand_key(key : Bytes) -> Array[Int32] raise FrameError {
  if key.length() != 16 {
    raise Payload(message="AES-128 密钥必须是 16 字节，收到 \{key.length()}")
  }
  let sbox = aes_sbox()
  let words : Array[Int32] = []
  for i in 0..<16 {
    words.push(key[i].to_int())
  }
  let rcon : Array[Int32] = [
    0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36,
  ]
  let mut round = 1
  let mut offset = 16
  while offset < 176 {
    let a = words[offset - 4]
    let b = words[offset - 3]
    let c = words[offset - 2]
    let d = words[offset - 1]
    // RotWord + SubWord + Rcon
    let r0 = sbox[b] ^ rcon[round - 1]
    let r1 = sbox[c]
    let r2 = sbox[d]
    let r3 = sbox[a]
    let base = offset - 16
    let mut i = 0
    while i < 4 {
      let t = match i {
        0 => r0
        1 => r1
        2 => r2
        _ => r3
      }
      words.push(words[base + i] ^ t)
      i = i + 1
    }
    // 后续 12 字节直接异或前一 16 字节
    let mut j = 4
    while j < 16 {
      words.push(words[offset + j - 4] ^ words[base + j])
      j = j + 1
    }
    offset = offset + 16
    round = round + 1
  }
  words
}

///|
fn add_round_key(state : Array[Int32], keys : Array[Int32], round : Int32) -> Unit {
  let base = round * 16
  for i in 0..<16 {
    state[i] = state[i] ^ keys[base + i]
  }
}

///|
/// SubBytes + ShiftRows。
fn sub_shift(state : Array[Int32], sbox : Array[Int32]) -> Unit {
  let old = state.copy()
  // 第 r 行左移 r 字节；AES 状态按列优先布局，索引 = 行 + 4 * 列
  for col in 0..<4 {
    for row in 0..<4 {
      let source_col = (col + row) % 4
      state[row + 4 * col] = sbox[old[row + 4 * source_col]]
    }
  }
}

///|
fn inv_sub_shift(state : Array[Int32], sbox : Array[Int32]) -> Unit {
  let old = state.copy()
  for col in 0..<4 {
    for row in 0..<4 {
      let source_col = (col + 4 - row) % 4
      state[row + 4 * col] = aes_inv_sbox(sbox, old[row + 4 * source_col])
    }
  }
}

///|
fn mix_columns(state : Array[Int32]) -> Unit {
  for col in 0..<4 {
    let a0 = state[4 * col]
    let a1 = state[4 * col + 1]
    let a2 = state[4 * col + 2]
    let a3 = state[4 * col + 3]
    state[4 * col] = gf_mul(a0, 2) ^ gf_mul(a1, 3) ^ a2 ^ a3
    state[4 * col + 1] = a0 ^ gf_mul(a1, 2) ^ gf_mul(a2, 3) ^ a3
    state[4 * col + 2] = a0 ^ a1 ^ gf_mul(a2, 2) ^ gf_mul(a3, 3)
    state[4 * col + 3] = gf_mul(a0, 3) ^ a1 ^ a2 ^ gf_mul(a3, 2)
  }
}

///|
fn inv_mix_columns(state : Array[Int32]) -> Unit {
  for col in 0..<4 {
    let a0 = state[4 * col]
    let a1 = state[4 * col + 1]
    let a2 = state[4 * col + 2]
    let a3 = state[4 * col + 3]
    state[4 * col] = gf_mul(a0, 14) ^ gf_mul(a1, 11) ^ gf_mul(a2, 13) ^ gf_mul(a3, 9)
    state[4 * col + 1] = gf_mul(a0, 9) ^ gf_mul(a1, 14) ^ gf_mul(a2, 11) ^ gf_mul(a3, 13)
    state[4 * col + 2] = gf_mul(a0, 13) ^ gf_mul(a1, 9) ^ gf_mul(a2, 14) ^ gf_mul(a3, 11)
    state[4 * col + 3] = gf_mul(a0, 11) ^ gf_mul(a1, 13) ^ gf_mul(a2, 9) ^ gf_mul(a3, 14)
  }
}

///|
/// 加密单个 16 字节分组。
pub fn aes128_encrypt_block(block : BytesView, keys : Array[Int32]) -> Bytes raise FrameError {
  if block.length() != 16 {
    raise Payload(message="AES 分组必须是 16 字节")
  }
  let sbox = aes_sbox()
  let state : Array[Int32] = []
  for i in 0..<16 {
    state.push(block[i].to_int())
  }
  add_round_key(state, keys, 0)
  let mut round = 1
  while round < 10 {
    sub_shift(state, sbox)
    mix_columns(state)
    add_round_key(state, keys, round)
    round = round + 1
  }
  sub_shift(state, sbox)
  add_round_key(state, keys, 10)
  let out : Array[Byte] = []
  for value in state {
    out.push(value.to_byte())
  }
  Bytes::from_array(out)
}

///|
/// 解密单个 16 字节分组。
pub fn aes128_decrypt_block(block : BytesView, keys : Array[Int32]) -> Bytes raise FrameError {
  if block.length() != 16 {
    raise Payload(message="AES 分组必须是 16 字节")
  }
  let sbox = aes_sbox()
  let state : Array[Int32] = []
  for i in 0..<16 {
    state.push(block[i].to_int())
  }
  add_round_key(state, keys, 10)
  let mut round = 9
  while round > 0 {
    inv_sub_shift(state, sbox)
    add_round_key(state, keys, round)
    inv_mix_columns(state)
    round = round - 1
  }
  inv_sub_shift(state, sbox)
  add_round_key(state, keys, 0)
  let out : Array[Byte] = []
  for value in state {
    out.push(value.to_byte())
  }
  Bytes::from_array(out)
}

///|
/// AES-128-ECB 加密：标准未规定分组模式，ECB 作为最基础的一种由部署方约定。
pub fn aes128_ecb_encrypt(key : Bytes, plain : Bytes) -> Bytes raise FrameError {
  let keys = aes128_expand_key(key)
  if plain.length() % 16 != 0 {
    raise Payload(message="ECB 输入长度必须是 16 的倍数")
  }
  let out : Array[Byte] = []
  let mut offset = 0
  while offset < plain.length() {
    for byte in aes128_encrypt_block(plain[offset:offset + 16], keys) {
      out.push(byte)
    }
    offset = offset + 16
  }
  Bytes::from_array(out)
}

///|
pub fn aes128_ecb_decrypt(key : Bytes, cipher : Bytes) -> Bytes raise FrameError {
  let keys = aes128_expand_key(key)
  if cipher.length() % 16 != 0 {
    raise Payload(message="ECB 输入长度必须是 16 的倍数")
  }
  let out : Array[Byte] = []
  let mut offset = 0
  while offset < cipher.length() {
    for byte in aes128_decrypt_block(cipher[offset:offset + 16], keys) {
      out.push(byte)
    }
    offset = offset + 16
  }
  Bytes::from_array(out)
}

///|
/// AES-128-CBC 加密，初始向量 16 字节。
pub fn aes128_cbc_encrypt(
  key : Bytes,
  iv : Bytes,
  plain : Bytes,
) -> Bytes raise FrameError {
  let keys = aes128_expand_key(key)
  if plain.length() % 16 != 0 {
    raise Payload(message="CBC 输入长度必须是 16 的倍数")
  }
  if iv.length() != 16 {
    raise Payload(message="CBC 初始向量必须是 16 字节")
  }
  let out : Array[Byte] = []
  let previous : Array[Int32] = []
  for i in 0..<16 {
    previous.push(iv[i].to_int())
  }
  let mut offset = 0
  while offset < plain.length() {
    let input : Array[Byte] = []
    for i in 0..<16 {
      input.push((plain[offset + i].to_int() ^ previous[i]).to_byte())
    }
    let encrypted = aes128_encrypt_block(Bytes::from_array(input)[:], keys)
    for i in 0..<16 {
      previous[i] = encrypted[i].to_int()
      out.push(encrypted[i])
    }
    offset = offset + 16
  }
  Bytes::from_array(out)
}

///|
pub fn aes128_cbc_decrypt(
  key : Bytes,
  iv : Bytes,
  cipher : Bytes,
) -> Bytes raise FrameError {
  let keys = aes128_expand_key(key)
  if cipher.length() % 16 != 0 {
    raise Payload(message="CBC 输入长度必须是 16 的倍数")
  }
  if iv.length() != 16 {
    raise Payload(message="CBC 初始向量必须是 16 字节")
  }
  let out : Array[Byte] = []
  let previous : Array[Int32] = []
  for i in 0..<16 {
    previous.push(iv[i].to_int())
  }
  let mut offset = 0
  while offset < cipher.length() {
    let block = cipher[offset:offset + 16]
    let decrypted = aes128_decrypt_block(block, keys)
    for i in 0..<16 {
      out.push((decrypted[i].to_int() ^ previous[i]).to_byte())
      previous[i] = block[i].to_int()
    }
    offset = offset + 16
  }
  Bytes::from_array(out)
}

///|
/// PKCS#7 填充。标准未规定分组填充方式，本项目默认 PKCS#7，可由部署方替换为约定方案。
pub fn pkcs7_pad(data : Bytes) -> Bytes {
  let remainder = data.length() % 16
  let pad_len = 16 - remainder
  let out : Array[Byte] = []
  for byte in data {
    out.push(byte)
  }
  for _ in 0..<pad_len {
    out.push(pad_len.to_byte())
  }
  Bytes::from_array(out)
}

///|
pub fn pkcs7_unpad(data : Bytes) -> Bytes raise FrameError {
  if data.length() % 16 != 0 || data.length() == 0 {
    raise Payload(message="PKCS#7 去填充要求长度为 16 的倍数")
  }
  let pad_len = data[data.length() - 1].to_int()
  if pad_len < 1 || pad_len > 16 || pad_len > data.length() {
    raise Payload(message="PKCS#7 填充字节非法：\{pad_len}")
  }
  let mut i = 0
  while i < pad_len {
    let at = data.length() - 1 - i
    if data[at].to_int() != pad_len {
      raise Payload(message="PKCS#7 填充内容不一致")
    }
    i = i + 1
  }
  Bytes::from_array(data[0:data.length() - pad_len].to_array())
}