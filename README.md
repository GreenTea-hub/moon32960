# moon32960

GB/T 32960.3-2025《电动汽车远程服务与管理系统技术规范 第 3 部分：通信协议及数据格式》的 MoonBit 实现：`$$` 起始符帧编解码、2025 信息类型全量解析、AES 加解密、车端/平台间两套应答语义、会话与补发。

符合性说明见 [docs/CONFORMANCE.md](docs/CONFORMANCE.md)，端到端案例见 [docs/EXAMPLES.md](docs/EXAMPLES.md)。

## 能力

- **帧层**：起始符 `$$`(0x24) 表 2025、`##`(0x23) 表 2016 并可拒绝错版本；命令单元、应答标志、17 位识别码、加密方式、大端长度、BCC（先加密后校验、先校验后解密）；
- **应答标志（表 4）**：0x01 成功、0x02 其他错误、0x03 VIN 重复、0x04 VIN 不存在、0x05 验签错误、0x06 数据结构错误、0x07 解密错误、0xFE 命令包；
- **应答构造**：按 6.3.2 / B.3.3.2「保留报文时间、删除其余内容」，数据单元固定 6 字节；
- **两套应答语义**：车端（附录 B）登入必应答、实时与补发正确时**不**应答；平台间（正文第 5 章）校验正确时**必须**应答；方向不符判 `conflicting-direction`；
- **登入**：表 6 新版模型（BMS 数 + 每系统包个数 + 24 位包编码 GB/T 34014）；\n- **新增命令**：表 31 密钥交换 0x0B、表 B.3/B.4 激活 0x09/0x0A、表 B.5~B.13 查询 0x80/设置 0x81/控制 0x82；\n- **信息类型（表 9）全量**：整车（18 字节 11 字段）、驱动电机（每项 10 字节、转矩 DWORD）、燃料电池发动机及车载氢系统（12 字节）、发动机（曲轴转速 2）、车辆位置（10 字节含坐标系）、报警（等级 0~4、五组列表）、蓄电池最小并联电压、蓄电池温度、燃料电池电堆、超级电容器、超级电容器极值、自定义数据；0xFF 签名信息解析保留；
- **加解密**：纯 MoonBit AES-128（ECB/CBC）+ PKCS#7，FIPS-197 向量验证；RSA/SM2/SM4 识别并拒绝；
- **会话**：登入/上报/心跳/登出、VIN 路由、补发计数、审计。

## 快速开始

```bash
moon check
moon test

moon run cmd/main -- case login       # 登入与应答（$$）
moon run cmd/main -- case encrypted   # AES 加密上报
moon run cmd/main -- case report      # 实时上报：车端不应答
moon run cmd/main -- case resend      # 断线补发
moon run cmd/main -- case platform    # 车端 vs 平台间\nmoon run cmd/main -- case keyexchange # 密钥交换（表 31）\nmoon run cmd/main -- case activate    # 激活（表 B.3/B.4）

moon run cmd/main -- decode 242401fe4c47574546344135364d463132333435360100251a0b19091e000001383938363036323031383030303132333435363701074241542d413031de
```

## 目录

```
moon32960/
├── command.mbt      命令、应答标志、加密方式、信息类型标志
├── frame.mbt        帧结构、版本判定、编解码、BCC
├── codec.mbt        大端读写、时间、VIN、ICCID、hex
├── crypto.mbt       AES-128、PKCS#7
├── cipher.mbt       加解密调度与密钥注入
├── login.mbt        车辆登入/登出、平台登入
├── telemetry.mbt    实时上报容器、信息体分派、签名
├── vehicle.mbt      0x01 整车
├── powertrain.mbt   0x02 驱动电机、0x03 燃料电池氢系统、0x04 发动机
├── position.mbt     0x05 车辆位置
├── alarm.mbt        0x06 报警
├── battery.mbt      0x07/0x08 蓄电池电压与温度
├── stack.mbt        0x30 燃料电池电堆
├── supercap.mbt     0x31/0x32 超级电容器与极值
├── session.mbt      会话状态机
├── response.mbt     应答形态、Scope、方向
├── gateway.mbt      两套应答规则、路由、审计
├── negative.mbt     密钥交换、激活、参数查询/设置、终端控制\n├── *_test.mbt       38 条测试
├── cmd/main/        CLI 与五个案例
└── docs/            符合性说明与案例
```

## 标准对齐状态

以 **GB/T 32960.3-2025** 为主线：报文结构、命令、应答标志、应答构造、信息类型 0x01~0x08 与 0x30~0x32、车端与平台间两套应答语义均已按正文表号实现。

**已实现**：表 31 密钥交换（0x0B）、表 B.3/B.4 激活（0x09/0x0A）、表 B.5~B.9 参数查询与设置、表 B.10~B.13 终端控制、表 6 新版登入（BMS 模型）。\n\n**外部配套**（非协议缺口，见 CONFORMANCE.md 第 5 节）：RSA/SM2/SM4 算法实现、验签、芯片签发体系、TCP 承载。**不兼容**：2016 版数据单元。

## 合规

- 仓库不收录标准原文，只描述字段语义与表号；
- 未移植任何第三方实现代码；
- 许可证：[Apache-2.0](LICENSE)。
