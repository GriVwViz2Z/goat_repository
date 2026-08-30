# 项目状态

这里保存需要跨会话继续的项目目标、已确认状态、未完成事项和来源。

## Claude 跨会话记忆实验

- 更新时间：2026-08-11
- 目标：让 Kelivo 中通过 OpenRouter 使用的 Claude，可以按需读取 GitHub 仓库中的长期记忆。
- 当前阶段：Mac 端 GitHub 单一原稿、Kelivo 只读调用版本已完成。

### 已确认完成

- GitHub 私有仓库 `claude-memory` 已建立并与本机同步。
- OpenRouter API Key 只保存在本机 `.env`；`.env` 已被 Git 忽略。
- 分层记忆文件与安全规则已经建立。
- 只读 MCP 服务已经通过自动测试；它只能列出、搜索和读取白名单记忆文件，不能读取 `.env`。
- macOS 版 Kelivo 已连接 MCP 服务 `Claude只读记忆`，界面显示“已连接”“STDIO”“工具 3/3”。
- Kelivo 中 OpenRouter 供应商已启用，Base URL 为 `https://openrouter.ai/api/v1`，API 路径为 `/chat/completions`。
- Kelivo 中的 OpenRouter API 已完成本机配置，并已选定 Claude Opus 模型；真实 API Key 未记录在仓库中。
- 已在 Kelivo 的新对话中完成跨会话读取测试：Claude 依次成功调用 `memory_list`、`memory_search` 和 `memory_read`，正确读取当前阶段与工具数量。
- Zhuo 已确认将 Claude 的角色提示、关系边界和通用偏好迁入 GitHub 私有仓库，并由仓库作为唯一可变化原稿。
- 本地 MCP 已新增第四个只读工具 `memory_bootstrap`，自动测试确认四个工具均为只读且仍不能读取 `.env`。
- Kelivo 已刷新为“工具 4/4”；助手“克”关闭了 Kelivo 内置记忆与历史聊天参考，只保留固定启动指令和 MCP 连接。
- 已在全新对话中验证：Claude 首次回复前自动调用 `memory_bootstrap`，并正确使用了关系框架、停止边界和学习偏好。

### 下一步

1. 继续保持 MCP 只读；日后只在 Zhuo 明确确认后，由 Codex 协助修改和测试记忆文件。
2. 调研 iPhone 访问方案。当前尚未确定技术路径。
3. Minecraft 协作建造目前仅为候选项目，尚未开始调研或实施。

### 安全提醒

- 不在聊天、截图、GitHub 或说明文件中展示真实 API Key。
- 记忆内容进入长期文件前需要人工确认。

## 星露谷物语协作探索

- 更新时间：2026-08-11
- 提出者：Zhuo
- 目标：探索 Claude 是否能通过 MCP 或其他接口读取《星露谷物语》状态，并以适合的方式参与游戏。
- 当前阶段：构想与调研阶段，尚未接入任何工具，也没有确定技术方案。
- 近期计划：Zhuo 准备在小红书和 GitHub 查找已有项目。
- 边界：当前尚不能确认 Claude 最终只能充当参谋，还是能够执行游戏操作；需要根据实际项目、接口能力和延迟测试判断。
