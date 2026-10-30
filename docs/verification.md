# 验证记录

验证日期：2026-10-30。

## 环境与范围

本地 macOS 27.0.1（Apple Silicon），系统 Bash 3.2.57，Python 3 标准库。
管理脚本的安装目标全部使用项目 `.test-work/` 内的临时用户目录；
测试替代 launchctl，未对真实登录会话加载、暂停、卸载或运行任何任务。

重连脚本与原已使用的脚本逐字节一致。运行时测试在临时副本中仅替换
`/usr/bin/open` 和 `/bin/sleep` 的命令路径，验证顺序、参数和失败后的继续执行，
未发出真实 Loon URL。

## 本地检查

- `/bin/bash -n scripts/loon-reconnect.sh`：通过。
- `/bin/sh -n scripts/reconnect.sh`：通过。
- `python3 -B -m unittest discover -s tests -p 'test_*.py' -v`：15 项测试通过。
- 使用系统 plutil 生成并检查 plist，再使用 Python plistlib 独立解析验收。
- 检查源码文件的换行、尾部空白、仓库相对链接、可执行位与本机路径泄漏。

测试覆盖默认与自定义间隔、用户目录的中文/空格/引号/XML 特殊字符、权限、
参数错误、重复安装、保护已有修改、旧安装迁移、暂停/恢复/手动运行、
加载失败后的恢复、运行中拒绝卸载、保留备份、损坏脚本的停用和备份、
根用户/非 macOS/无图形会话拒绝、符号链接与外来配置保护、
状态输出不转储环境，以及三个 URL 各自调用失败时的执行结果。

## 验证边界

- 本次未替换实际用户的旧安装，也未进行真实 VPN 断开/重连或订阅更新。
- 尚未在第二台 Mac 或其他 macOS 版本上实机运行。
- 远端 CI 记录见 [GitHub Actions](https://github.com/Ezio0/loon-reconnect/actions)；
  本记录中的 15 项结果来自本地隔离测试。

跨机器安装后的实际效果，可由使用者主动执行 `run` 后结合 Loon 界面与日志确认。
日志中的 `sent` 和脚本退出码不能单独证明网络连通或订阅成功。
