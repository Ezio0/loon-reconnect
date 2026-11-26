# Loon Reconnect

用 macOS 用户级 LaunchAgent 定时重连 Loon，并更新全部订阅。
默认每 **6 小时**执行一次，安装或登录加载时不会立即执行。

```text
识别 Loon VPN 并确认状态可读 → 系统关闭 VPN → 等待 3 秒 → 系统开启（1/2）→ 等待 10 秒
    → 系统再次开启（2/2）→ 等待 10 秒 → URL 请求更新全部订阅 → 等待 2 秒
    → 确认 VPN 状态，必要时有限恢复 → 隐藏 Loon
```

重连脚本读取系统 VPN 状态，不访问网站或进行网络测速。
即使 VPN 被手动关闭，只要服务能被唯一识别且状态可读，到时间仍会执行完整流程。
VPN 开关使用 macOS 的 `scutil --nc stop/start`，不依赖 Loon 主应用处理开关 URL。
每轮固定发送两次系统开启请求，间隔 10 秒，为首次请求未生效留出第二次机会；
即使第一次调用返回成功，也会进行第二次调用。每轮只关闭一次 VPN，不重复更新订阅。
只有订阅更新使用 `loon://update?sub=all`，不再发送 `loon://off` 或 `loon://on`。

工具保留现有“按需连接 / Connect On Demand”设置，开启或关闭均可使用。
若系统在停止后自动重连，脚本照常继续；订阅更新允许在连接状态下进行，
不要求保持断开。固定延时不是网络恢复或更新完成的确认。

## 使用条件

- macOS，当前用户已登录图形桌面。
- 已安装、配置并正常使用支持 [官方 URL Scheme](https://nsloon.app/docs/Scheme/) 的 Loon。
- 使用当前用户的终端执行，**无需 sudo、Homebrew 或额外运行时**。
- 工具不会安装 Loon，也不需要读取你的订阅地址或凭证。

工具使用 macOS 自带 Bash、launchctl、plutil、osascript 和 scutil。
系统中需有一个启用的 Loon VPN 服务；工具按实际 URL 处理程序的标识匹配服务，
支持修改 VPN 显示名称。匹配缺失、匹配不唯一或状态不可读时会报错停止，不开始重连。
目前在 Apple Silicon、macOS 27.0.1、系统 Bash 3.2 上完成隔离验证；其他系统版本尚未实机验证。

## 安装

在 GitHub 仓库页面选择 **Code → Download ZIP** 并解压，也可以克隆仓库：

```bash
git clone https://github.com/Ezio0/loon-reconnect.git
cd loon-reconnect
```

在终端进入项目目录后，执行：

```bash
bash scripts/loon-reconnect.sh install
```

安装器会生成当前用户的绝对路径，设置文件权限并加载定时任务。
默认首次触发约在加载后的 6 小时，前提是用户仍登录且机器没有睡眠。
安装成功不会立即开关 VPN。

指定其他周期，例如每 3 小时：

```bash
bash scripts/loon-reconnect.sh install --hours 3
```

`--hours` 接受 1–8760 的整数。相同版本、相同周期重复安装不会覆盖文件。
如果已有不同版本、周期或手动修改的文件，安装器会停止并提示先备份卸载。

## 常用命令

以下命令均在项目目录内运行：

| 命令 | 作用 |
| --- | --- |
| `bash scripts/loon-reconnect.sh status` | 查看任务是否加载、运行次数、退出码与间隔 |
| `bash scripts/loon-reconnect.sh run` | 立即请求一轮重连，会实际开关 VPN |
| `bash scripts/loon-reconnect.sh pause` | 暂停任务，重启或重新登录后仍保持停用 |
| `bash scripts/loon-reconnect.sh resume` | 恢复定时任务，不立即重连 |
| `bash scripts/loon-reconnect.sh uninstall` | 停用任务并将脚本、配置和日志移入备份 |
| `bash scripts/loon-reconnect.sh help` | 查看帮助 |

安装后管理脚本也保存在用户目录，删除源码目录后仍可操作：

```bash
bash "$HOME/Library/Application Support/LoonAutomation/loon-reconnect.sh" status
```

手动请求执行后，通常等待约 30–40 秒查看日志；恢复可能额外等待最多 90 秒，
系统命令的执行或超时时间另计：

```bash
tail -n 20 "$HOME/Library/Logs/LoonAutomation/reconnect.log"
tail -n 20 "$HOME/Library/Logs/LoonAutomation/reconnect.err.log"
```

日志在首次实际运行时创建。正常日志依次包含：

```text
requested system VPN stop
requested system VPN start (attempt 1/2)
requested system VPN start (attempt 2/2)
sent loon://update?sub=all
vpn Connected (system status)
hidden loon:// handler
```

每条日志还包含时间戳。**requested 和 sent 只表示对应命令成功发出，不代表 VPN 已连通或订阅已更新。**
关闭调用失败也会继续尝试开启和更新；任一调用失败时，脚本最终返回非零退出码。
两次开启请求都记录各自的结果；第一次失败、第二次成功时，仍保留非零退出码，便于排查。

更新请求发出后，脚本等待 2 秒并确认系统 VPN 状态：

- 已连接：记录 `vpn Connected (system status)`，不再发送额外系统启动命令。
- 未连接：最多额外执行两次系统 VPN 启动，每次等待最多 30 秒确认结果。
- 正在连接或断开：先等待最多 30 秒；若仍在过渡状态则报错，不打断该过程。
- 状态读取失败或恢复仍未成功：写入错误日志并返回非零。

额外恢复的日志使用 `recovery attempt 1/2` 或 `2/2`，与固定两次开启区分。
系统恢复只发出开启请求，不再次关闭 VPN。`Connected` 只代表读取时系统认为隧道已连接，
不代表网站可访问或订阅已更新成功。即使恢复成功，之前的 URL 或系统命令错误仍会保留。

订阅更新 URL 调用允许 Loon 激活，以便被挂起的应用处理请求。执行期间 Loon 可能显示窗口并切到前台，
完成连接确认或恢复后，脚本会隐藏窗口，让应用继续在后台运行。
隐藏成功会记录 `hidden loon:// handler`；隐藏失败会写入错误日志并返回非零退出码。
隐藏使用系统 AppKit 接口，不退出 Loon，也不使用模拟按键或 System Events。
工具根据 `loon://` 的实际处理程序识别应用，无需填写应用名、安装路径或 bundle ID。

## 升级、改周期与迁移旧安装

任务标识继续使用 `com.ezio.loon-reconnect`，以兼容已有的手动安装。
这是固定的应用标识，与电脑的用户名无关。

从新的源码目录执行以下命令，先保留旧安装的备份，再安装：

```bash
bash scripts/loon-reconnect.sh uninstall
bash scripts/loon-reconnect.sh install --hours 6
```

修改周期时将最后一个参数改为所需小时数。管理命令发现一轮重连正在执行时，会拒绝卸载；
等该轮结束后重试。手动运行命令不使用 `kickstart -k`。

备份位于 `~/Library/Application Support/LoonAutomationBackups/` 下带时间戳的独立目录，
其中保留原 plist、`scripts/` 和 `logs/`。

## 文件位置

| 路径 | 内容 |
| --- | --- |
| `~/Library/Application Support/LoonAutomation/reconnect.sh` | 定时执行脚本 |
| `~/Library/Application Support/LoonAutomation/loon-reconnect.sh` | 管理工具 |
| `~/Library/LaunchAgents/com.ezio.loon-reconnect.plist` | 当前用户的定时配置 |
| `~/Library/Logs/LoonAutomation/reconnect.log` | 正常调用日志 |
| `~/Library/Logs/LoonAutomation/reconnect.err.log` | 调用错误日志 |

脚本与日志目录权限为 `700`，plist 为 `600`，任务的 umask 为 `077`。

## 调度与恢复边界

- 使用 `StartInterval = 小时数 × 3600`，不设置 `RunAtLoad` 或 `KeepAlive`。
- 任务属于当前用户的图形会话；注销、关机或睡眠期间不运行。
- 睡眠期间错过的间隔会跳过，不依赖唤醒补跑；详见本机 `man launchd.plist`。
- 这是按间隔运行的任务，不是每天固定钟点运行。重新加载会重新开始等待。
- 两次开启请求后各等待 10 秒，更新请求后等待 2 秒；都是固定延时，不代表网络已恢复或订阅更新已完成。
- 定时重连不能保证故障出现后立即恢复，也不能保证失去响应的 Loon 会处理 URL。
- [Issue #1](https://github.com/Ezio0/loon-reconnect/issues/1) 后续出现连续 URL 超时，
  以及打开应用后才断开 VPN 的现象。新版本使用系统接口开关 VPN，避免产生可能延迟执行的
  关闭 URL；保留系统状态确认与有限恢复。实际故障的根因尚未完全确定，
  详见 [影响记录](docs/impact/use-system-vpn-controls.md)。
- 新版不能撤销旧版可能已投递的 URL。系统开关版本已在本机完成两轮实测，
  按需连接保持开启；实测范围与限制见 [验证记录](docs/verification.md)。
- 状态确认发生在每轮流程末尾，不持续监控 VPN；之后再次断开不会立即触发恢复。

如果任务加载失败，工具会保留安装文件并尝试停用任务。处理系统报错后运行 `resume` 重试。
`status` 的 `state = not running` 通常表示当前空闲；它不表示 VPN 已关闭。

## 开发与验证

测试需要 macOS 和 Python 3，使用标准库，不安装第三方包：

```bash
/bin/bash -n scripts/loon-reconnect.sh
/bin/sh -n scripts/reconnect.sh
python3 -B -m unittest discover -s tests -p 'test_*.py' -v
```

测试使用项目内的临时用户目录和模拟系统命令，不会加载真实任务或开关 VPN。
GitHub Actions 配置会在 macOS runner 上执行相同检查。
验证范围见 [verification.md](docs/verification.md)。

## 许可证与项目关系

[MIT License](LICENSE)。本工具是独立的自动化辅助项目，与 Loon 官方没有隶属关系。
