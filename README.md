# envkey — 经 macOS Keychain 安全管理密钥，透明注入各 shell

把 API 密钥 / 凭据安全存进 macOS 登录钥匙串（Keychain），并让 bash / zsh / fish
三个 shell 在启动时自动加载为环境变量。**磁盘上只写「变量名清单」，真值只存
Keychain，明文密钥永不落盘。**

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
```

`set` / `del` 后**当前会话立即生效**；后续新终端由启动文件自动加载。

## 安全模型

- 真值（value）只存在于 macOS Keychain，`security` 加密存储
- 磁盘上只有 `secret-names`：纯变量名列表，无任何明文值
- 各 shell 启动时逐条从 Keychain 读出并 `export`，`printenv` 已存在则跳过
- 启动文件中的接线块不含密钥，提交 git 也无泄露风险

## 迁移 / 多机使用

密钥真值**不随迁移传输**（出于安全，也不该跨机器拷贝）：

```bash
# 新机器上
git clone <repo-url> 或 scp -r envkey user@host:~
cd envkey && ./install.sh
# 逐个重新填入密钥值（值存落到新机 Keychain）
envkey set CODE_COMPANION_KEY
envkey set AIDEN_NOTIFY_FEISHU_WEBHOOK_URL
envkey set AIDEN_NOTIFY_FEISHU_SECRET
```

> 想预置"该有哪些变量"而不填值：安装后在 `~/.config/fish/secret-names`
> 里逐行写下变量名即可，启动时若 Keychain 无值会给出提示。

## 目录结构

```
envkey/
├── install.sh               # 安装/卸载（可分发）
├── README.md
└── src/
    ├── envkey               # 核心命令（Keychain 读写 + 清单管理）
    ├── envkey.collect       # bash/zsh 启动片段
    └── envkey.collect.fish  # fish 启动片段
```

## 排错

- **set 提示 authorization canceled**：`security` 需要 macOS 图形授权弹窗，
  在无 GUI 的纯 ssh/后台会话里会失败。用真实终端跑即可。
- **启动时 warning keychain item not found**：清单里有名字但 Keychain 无值，
  用 `envkey set NAME <value>` 补上。
- **PATH 里找不到 envkey**：确认 `~/.local/bin` 已在 `$PATH`。
