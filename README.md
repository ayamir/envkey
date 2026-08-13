# envkey — 安全存储密钥并透明注入各 shell 环境（macOS / Linux）

把 API 密钥 / 凭据安全存储，并让 bash / zsh / fish 在启动时自动加载为环境变量。
**磁盘上只写「变量名清单」，真实值存密钥后端，明文永不落盘。**

## 平台与后端

存储后端由 `envkey-backend` 自动探测，命令行与 shell 接线完全一致：

| 平台 | 后端 | 存储位置 | 依赖 |
|---|---|---|---|
| macOS | `macos` | 登录 Keychain（受系统保护） | 只需 `security`（自带） |
| Linux | `file` | openssl aes-256-cbc 加密文件 `~/.local/share/envkey/secrets.bin` (0600) | 只需 `openssl` |

可用 `ENVKEY_BACKEND=macos|file` 强制指定。

### Linux file 后端（加密文件）说明

- 加密文件 `~/.local/share/envkey/secrets.bin`，权限 0600
- 口令来源优先级：`ENVKEY_PASS` 环境变量 > `~/.local/share/envkey/keyfile` (0600) > 交互询问
- 首次 `envkey set` 会要求设定口令，并（无口令文件时）询问两次后写入 `keyfile`（0600），之后可免交互
- 适合 headless 服务器 / CI / 容器；安全性取决于口令强度 + 文件权限

## 特性

- 一处管理，三 shell 通用：bash / zsh / fish
- 幂等安装/卸载
- 可整体迁移到新机器（克隆本目录 → 跑 `install.sh` → 重填密钥值）
- 不依赖第三方工具，只用 macOS 自带 `security`

## 安装

```bash
./install.sh             # 正常安装（自动探测 shell 并接线）
./install.sh --dry-run   # 预览，不改动
./install.sh --uninstall # 反安装（Keychain 密钥保留）
```

它会把：
- `envkey` 命令 → `~/.local/bin/envkey`
- 启动片段 → `~/.local/share/envkey/`
- 空清单 → `~/.config/fish/secret-names`（只有变量名）
然后自动向已安装 shell 的启动文件（`.bash_profile` / `.zshrc` / fish `config.fish`）
追加一段被 `### envkey ###` 标记包住的接线，重复运行不会重复追加。

`~/.local/bin` 需在 `PATH` 中（install 会自动检测并提醒）。

## 用法

```bash
envkey set MY_KEY [value]   # 存/改；不带 value 则交互输入（不回显）
envkey del MY_KEY           # 删
envkey list                 # 看清单（只有名字）
envkey export MY_KEY        # 打印 "export MY_KEY=..."，可 eval 注入当前会话
envkey backend              # 打印当前存储后端 (macos|file)
envkey redact [--dry-run]   # 抹掉 shell 历史中残留的明文密钥值（见下）
```

`set` / `del` 后**当前会话立即生效**；后续新终端由启动文件自动加载。

### envkey redact — 清理 shell 历史中的密钥

扫描 `~/.bash_history`、`~/.zsh_history`、fish `fish_history`，把其中的密钥实际值
替换为 `ENVREDACTED`（改前先备份到 `*.redact.bak`）：

```bash
envkey redact --dry-run          # 先预览会改哪些，不实际写入
envkey redact                    # 实际清理默认的三个历史文件
envkey redact /path/to/hist      # 也可显式指定文件
```

覆盖两类泄露：`envkey set NAME value` 的值，以及直接出现在历史里的明文密钥
（如 `export DS_KEY=sk-...`、`export PG_PASSWORD=...`、`export AWS_ACCESS_KEY_ID=AKIA...`）。
误伤控制：只在键名意为敏感项（key/token/secret/password 等）且值为疑似 token 形态
（`sk-`/`ghp_`/`AKIA`/`ya29`/`xox…` 或 20+ 位随机串）时替换，URL、路径、普通值不碰。
> 注意：redact 不能抹掉已同步到云/备份里的历史，建议立即轮换泄露的密钥。

## 安全模型

- macOS 真实值存于系统 Keychain；Linux 存于 openssl 加密文件（0600）
- 磁盘上只有 `secret-names`：纯变量名列表，无任何明文值
- 各 shell 启动时逐条从后端读出并 `export`，`printenv` 已存在则跳过
- 启动文件中的接线块不含密钥，提交 git 也无泄露风险

## 迁移 / 多机使用

密钥真值**不随迁移传输**（出于安全，也不该跨机器拷贝）：

```bash
# 新机器上
git clone <repo-url> 或 scp -r envkey user@host:~
cd envkey && ./install.sh          # 自动探测平台与后端
# 逐个重新填入密钥值（存落到新机后端）
envkey set CODE_COMPANION_KEY
envkey set AIDEN_NOTIFY_FEISHU_WEBHOOK_URL
envkey set AIDEN_NOTIFY_FEISHU_SECRET
# Linux 首次 set 会先设置加密文件口令
```

> 想预置"该有哪些变量"而不填值：安装后在 `~/.config/fish/secret-names`
> 里逐行写下变量名即可，启动时若后端无值会给出提示。

## 目录结构

```
envkey/
├── install.sh               # 安装/卸载（可分发，自动探测平台）
├── README.md
└── src/
    ├── envkey               # 核心命令（后端无关）
    ├── envkey-backend       # 存储后端抽象 (macos/security | file/openssl)
    ├── envkey.collect       # bash/zsh 启动片段
    └── envkey.collect.fish  # fish 启动片段
```

## 排错

- **macOS set 提示 authorization canceled**：`security` 需要 macOS 图形授权弹窗，
  在无 GUI 的纯 ssh/后台会话里会失败。用真实终端跑即可（Linux file 后端无此限制）。
- **启动时 warning keychain item not found**：清单里有名字但后端无值，
  用 `envkey set NAME <value>` 补上。
- **PATH 里找不到 envkey**：确认 `~/.local/bin` 已在 `$PATH`。
