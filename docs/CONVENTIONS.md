# 文件约定

- `scripts/`：macOS Shell 工具；兼容系统自带的 Bash 3.2 和 POSIX sh。
- `tests/`：使用 Python 标准库的隔离测试；临时文件只写入 `.test-work/`。
- `docs/`：维护说明与交付记录，文件名使用 kebab-case。
- 根目录仅保留 GitHub 常规入口文件：README、LICENSE 和 Git 配置。
- 安装时生成用户路径；不提交本机 plist、日志、订阅、凭证或用户配置。
- 测试不得实际调用 Loon URL 或改变本机 LaunchAgent。
