// cipher.mbt
///|
/// 数据单元加解密的密钥材料。
///
/// GB/T 32960.3-2016 只定义「数据加密方式」字节（0x01 不加密、0x02 RSA、0x03 AES128），
/// 不定义密钥协商与密钥管理；后者的责任落在部署方与 GB/T 40855 通信安全要求。
/// 因此本项目把「用哪把钥匙」做成显式入参，而不是隐式约定。
pub(all) enum KeyMaterial {
  NoKey // 无密钥：只能处理 0x01 明文帧
  Aes128Ecb(key~ : Bytes) // 0x03 AES128，ECB 分组模式
  Aes128Cbc(key~ : Bytes, iv~ : Bytes) // 0x03 AES128，CBC 分组模式
}

///|
pub fn KeyMaterial::describe(self : KeyMaterial) -> String {
  match self {
    NoKey => "未配置密钥"
    Aes128Ecb(_) => "AES128-ECB"
    Aes128Cbc(..) => "AES128-CBC"
  }
}

///|
/// 按帧头声明的加密方式加密数据单元。
///
/// 加密发生在组帧之前，因此 BCC 校验码覆盖的是密文，与标准「先加密再校验」一致。
pub fn encrypt_payload(
  encryption : Encryption,
  payload : Bytes,
  key~ : KeyMaterial,
) -> Bytes raise FrameError {
  match encryption {
    Plain => payload
    Aes128 => {
      match key {
        Aes128Ecb(key~) => {
          aes128_ecb_encrypt(key, pkcs7_pad(payload))
        }
        Aes128Cbc(key~, iv~) => {
          aes128_cbc_encrypt(key, iv, pkcs7_pad(payload))
        }
        NoKey => {
          raise CryptoUnavailable(
            mode="AES128",
            message="帧声明 AES128，但未提供密钥；不允许按明文处理",
          )
        }
      }
    }
    Rsa => {
      raise CryptoUnavailable(
        mode="RSA",
        message="RSA 私钥由部署方持有并注入，本项目不内置密钥管理；未注入时拒绝该帧",
      )
    }
    Abnormal | InvalidMode | Unknown(_) => {
      raise CryptoUnavailable(
        mode=encryption.name(),
        message="加密方式字节非法，拒绝处理",
      )
    }
  }
}

///|
/// 按帧头声明的加密方式解密数据单元；无法解密时抛出明确错误，绝不当明文解析。
pub fn decrypt_payload(
  encryption : Encryption,
  payload : Bytes,
  key~ : KeyMaterial,
) -> Bytes raise FrameError {
  match encryption {
    Plain => payload
    Aes128 => {
      match key {
        Aes128Ecb(key~) => {
          if payload.length() % 16 != 0 {
            raise CryptoUnavailable(
              mode="AES128",
              message="密文长度 \{payload.length()} 不是 16 的倍数，无法解密",
            )
          }
          pkcs7_unpad(aes128_ecb_decrypt(key, payload))
        }
        Aes128Cbc(key~, iv~) => {
          if payload.length() % 16 != 0 {
            raise CryptoUnavailable(
              mode="AES128",
              message="密文长度 \{payload.length()} 不是 16 的倍数，无法解密",
            )
          }
          pkcs7_unpad(aes128_cbc_decrypt(key, iv, payload))
        }
        NoKey => {
          raise CryptoUnavailable(
            mode="AES128",
            message="帧声明 AES128，但未提供密钥；拒绝解析而不是按明文处理",
          )
        }
      }
    }
    Rsa => {
      raise CryptoUnavailable(
        mode="RSA",
        message="RSA 解密需要部署方注入私钥实现；未注入时拒绝该帧",
      )
    }
    Abnormal | InvalidMode | Unknown(_) => {
      raise CryptoUnavailable(
        mode=encryption.name(),
        message="加密方式字节非法，拒绝处理",
      )
    }
  }
}
