# moon32960

GB/T 32960.3-2016《电动汽车远程服务与管理系统技术规范 第 3 部分：通信协议及数据格式》的 MoonBit 实现：帧编解码、九类信息体解析、AES128 加解密、会话状态机、平台应答与网关路由。

目标版本、覆盖矩阵、加解密责任与兼容性终点见 [docs/CONFORMANCE.md](docs/CONFORMANCE.md)；端到端案例见 [docs/EXAMPLES.md](docs/EXAMPLES.md)。

## 能力

- **帧层**：起始符、命令单元、应答标志（0xFE 命令包）、17 位 VIN、加密方式、大端长度、**BCC 校验码**；校验码在密文之上计算，先加密再校验；
- **两套应答规则，按 `Scope` 区分**：车端（附录 B）登入必须应答、校验失败忽略不应答、**实时与补发正确时不做应答**；平台间（正文第 5 章）**校验正确也必须应答 0x01**；方向不符的命令一律拒绝；
- **加解密**：纯 MoonBit AES-128（ECB / CBC），FIPS-197 向量验证，PKCS#7 填充；密钥经 `KeyMaterial` 显式注入；RSA 私钥由部署方注入，未注入时拒绝该帧并应答 0x02，绝不当明文解析；
- **数据单元**：车辆登入（含 ICCID 与储能子系统编码 `n×m`）、车辆登出、平台登入、心跳；
- **九类信息体全量**：整车数据（20 字节 13 字段）、驱动电机、燃料电池（探针变长）、发动机、车辆位置（含状态位）、极值数据、报警数据（五组故障列表）、储能电压、储能温度；
- **字段语义**：异常码与无效码按 BYTE/WORD/DWORD 分级保留，换算函数返回 `None`；
- **会话**：登入 → 在线 → 上报/心跳/补发 → 登出 → 关闭，顺序错误拒绝，补发按 7 日窗口校验；
- **审计**：每次接收留一条记录。

## 快速开始

```bash
# 需要 MoonBit 工具链（moonc >= 0.10.7）
moon check
moon test

# 端到端案例
moon run cmd/main -- case login       # 登入应答：命令包 0xFE → 应答 0x01 / 0x03
moon run cmd/main -- case encrypted   # AES128 加密上报：加密 → 解密 → 字段 → 不应答
moon run cmd/main -- case report      # 实时上报：校验正确时平台不应答
moon run cmd/main -- case resend      # 断线补发
moon run cmd/main -- case platform    # 车端 vs 平台间应答规则对比

# 解析明文帧
moon run cmd/main -- decode 232301fe4c47574546344135364d463132333435360100251a0b12091e000001383938363036323031383030303132333435363701074241542d413031d5

# 解析加密帧（提供 16 字节密钥）
moon run cmd/main -- decode 232302fe4c47574546344135364d463132333435360300304c2229bb4dc2e406c63d054d69f47cbc725f02e50d74f0e58f4b78c3309bcaf466c0da206dbc7e84c0580854cd83ea3af4 --aes128 000102030405060708090a0b0c0d0e0f
```

## 目录

```
moon32960/
├── moon.mod / moon.pkg
├── errors.mbt         FrameError：带字段定位的错误
├── internal.mbt       边界检查、异常/无效码判定
├── codec.mbt          大端读写、时间、VIN、ICCID、hex、BCC
├── crypto.mbt         AES-128（ECB/CBC）、密钥扩展、PKCS#7
├── cipher.mbt         加密接入责任与加解密调度
├── frame.mbt          帧结构、报头视图、编解码、校验码
├── command.mbt        命令单元 / 应答标志 / 加密方式 / 信息类型标志
├── login.mbt          车辆登入、登出、平台登入
├── telemetry.mbt      实时/补发上报容器与信息体分派
├── vehicle.mbt        0x01 整车数据
├── powertrain.mbt     0x02 驱动电机、0x03 燃料电池、0x04 发动机
├── position.mbt       0x05 车辆位置、0x06 极值数据
├── alarm.mbt          0x07 报警数据
├── storage.mbt        0x08 储能电压、0x09 储能温度
├── session.mbt        会话状态机与补发窗口
├── response.mbt       应答形态、Scope 与命令方向
├── gateway.mbt        两套应答规则、方向检查、路由、审计
├── *_test.mbt         59 条黑盒测试
├── cmd/main/          CLI 与五个案例
└── docs/              符合性说明、协议对照、端到端案例
```

## 标准对齐状态

以 **GB/T 32960.3-2016** 为达标基线：明文帧逐字段可解；AES128 帧注入密钥后逐字段可解；RSA 帧待部署方注入私钥解密实现；应答语义按附录 B 分命令处理；畸形帧拒绝并回 0x02。

**尚未实现**：RSA 大数解密（责任外置）、TCP 传输层与粘包拆包、GB/T 32960.3-2025 新增信息类型、平台间会话表。完整清单见 CONFORMANCE.md 第 8 节。

## 合规

- 仓库不收录 GB/T 标准原文（标准文本受版权保护），只描述字段语义并引用表号；
- 未移植任何第三方实现代码；
- 许可证：[Apache-2.0](LICENSE)。

## 路线图

1. RSA（PKCS#1 v1.5）解密与密钥注入契约；
2. TCP 网关：监听、粘包拆包、连接管理、落库；
3. GB/T 32960.3-2025 分支：新增信息类型与登入字段；
4. 一致性测试仪：畸形帧库、fuzz、与第三方实现互操作回放。
