# claude-memory

一个由 Zhuo 掌管、供 Kelivo 中的 Claude 按需读取的 GitHub 记忆文件系统。

目前已经完成 Mac 端只读版本：安全保存 OpenRouter API Key、建立分层记忆结构、保存已确认的 Claude 角色与关系边界，并通过只读 MCP 向 Kelivo 提供启动、列出、搜索和读取能力。尚未加入候选写入、Ombre、Dynamic Mind 或主动推送。

## 文件地图

- `.env`：只留在这台 Mac 的秘密抽屉，保存真实 API Key；Git 会忽略它。
- `.env.example`：可以上传的空白示范，不含真实 Key。
- `.gitignore`：Git 的禁止上传清单。
- `MEMORY_RULES.md`：记忆的读取、候选写入、人工确认和安全边界。
- `memories/index.md`：轻量索引，只负责指向相关原文。
- `memories/bootstrap.md`：每个新对话只加载一次的高频启动卡。
- `memories/core.md`：经过确认的长期核心记忆。
- `memories/preferences.md`：经过确认的偏好。
- `memories/profiles/claude.md`：Claude 的长期角色、交流方式和记忆使用约定。
- `memories/relationships/claude.md`：Zhuo 与 Claude 的关系框架和停止边界。
- `memories/projects.md`：跨会话项目状态。
- `memories/daily/`：按日期保留具体事实、来源和不确定之处。
- `memory-store.mjs`：只允许访问记忆白名单的本地文件读取层。
- `mcp-server.mjs`：让 Kelivo 能够列出、搜索和读取记忆的只读 MCP 服务。
- `test/mcp-readonly.test.mjs`：验证工具只读并且无法读取 `.env`。
- `chat.mjs`：向 OpenRouter 发送一句测试消息，并显示 Claude 的回复与 Token 用量。
- `package.json`：保存项目名称和测试命令。

角色、关系和偏好内容由 Zhuo 明确确认后写入；仓库可能包含私人内容，因此应保持私有。MCP 只读取这些文件，不自动修改。

## 只读 MCP 记忆桥

MCP 提供四个只读工具：

- `memory_bootstrap`：每个新对话加载一次精简的高频角色、关系边界、偏好和检索规则。
- `memory_list`：查看允许读取的记忆文件。
- `memory_search`：按关键词搜索少量相关片段。
- `memory_read`：读取一个白名单内的记忆原文。

它不能写入或删除文件，也不能操作 Git。运行本地自检：

```sh
npm test
```

本机启动命令：

```sh
npm run mcp:start
```

## Kelivo 固定启动指令

Kelivo 不保存需要频繁维护的角色或长期记忆，只保留下面这条固定指令：

> 每个新对话首次回复前，调用 `memory_bootstrap` 读取长期角色、关系边界和记忆规则。后续只在相关时调用 `memory_search` 和 `memory_read`。文件未记录的内容不要假装记得；不得声称已经写入记忆。

以后修改本机仓库中的记忆文件，新对话会在下一次启动读取时获得新版。已经打开的对话需要再次调用 `memory_bootstrap`。如果直接在 GitHub 网页修改，应先在 GitHub Desktop 中 Pull 到本机。

`memory_bootstrap` 只返回 `memories/bootstrap.md`，避免每轮聊天反复携带完整档案。角色、关系、偏好、项目和日记原文仍完整保留，并由 Claude 在相关时通过 `memory_search` 与 `memory_read` 按需读取。

## 第一次连接测试

1. 只在本机 `.env` 中填写 `OPENROUTER_API_KEY`，不要把 Key 发到聊天、截图或 GitHub。
2. 保持测试模型为 `anthropic/claude-haiku-4.5`。
3. 在这个文件夹中运行：

   ```sh
   npm run test:connection
   ```

测试最多请求 40 个输出 Token。成功时会显示模型名称、简短回复和本次 Token 用量。

## 安全规则

- 永远不要把真实 Key 写进 `.env.example`、代码或 README。
- 每次提交前检查 GitHub Desktop 的 Changes 列表，确认没有 `.env`。
- 如果 Key 曾出现在提交、聊天或截图中，应立即在 OpenRouter 撤销并重新创建。
