# 重连后隐藏 Loon 窗口

## 问题与范围

用户反馈：订阅更新请求执行后，Loon 窗口留在桌面上，影响原本后台运行的使用方式。
原脚本的 `open -g` 只请求后台打开，不保证隐藏应用已显示的窗口。
本次按既有自动化的缺陷修复处理，保留影响记录和回归测试，不改变网络连接策略。

## 修复方案

- URL 调用使用 `open -g -j`，请求后台、隐藏启动。
- 保留关闭、等待 3 秒、开启、等待 10 秒、更新订阅的顺序。
- 发出更新请求后再等待 2 秒，然后通过系统 AppKit API 隐藏处理 `loon://` 的应用。
- 用 NSWorkspace 和 NSBundle 解析当前处理程序，不固定应用名、安装位置或 bundle ID。
- 仅操作已运行的匹配应用；未运行时不启动应用，不退出进程，不改变 VPN。
- 通过 AppKit 运行循环更新可见状态，在 2 秒内确认隐藏；失败记入错误日志并返回非零。
- 使用系统自带 osascript 的 JavaScript/Objective-C 桥接，不使用 System Events、模拟按键或辅助功能控制。

## 兼容与风险

安装路径、LaunchAgent 标识、执行周期和管理命令不变；修改集中于现有重连脚本。
一次正常执行多出约 2 秒等待；固定等待不代表订阅更新已经完成。
隐藏失败不跳过或撤销已经尝试的网络操作。
本机实测曾出现隐藏请求即时返回 false、但后续状态已变为隐藏的情况；
因此结果以推进运行循环后读取的隐藏状态为准，不以请求的即时返回值判错。
隐藏结束后，用户仍可从 Dock 主动打开 Loon；不持续监控或强制隐藏窗口。

## 验证边界

覆盖 URL 失败后仍进行隐藏、隐藏失败的错误返回、无运行实例、已隐藏实例、多个实例、
错误处理程序信息和隐藏确认超时。使用隔离替身验证，不在回归测试中操作真实 VPN。
在得到系统工具授权后，可单独验证本机 Loon 的隐藏行为和进程存活，不调用 VPN URL。
用户已明确授权本机部署，以及提交并推送修复到 GitHub。
本机部署备份旧脚本后原子替换，不重载 LaunchAgent，不主动触发重连。

## 依据

- 本机 `man open` 的 `-g` 和 `-j` 说明。
- [NSRunningApplication](https://developer.apple.com/documentation/appkit/nsrunningapplication)：隐藏状态需要运行循环推进后更新。
- [hide](https://developer.apple.com/documentation/appkit/nsrunningapplication/hide%28%29)：隐藏已运行应用。
