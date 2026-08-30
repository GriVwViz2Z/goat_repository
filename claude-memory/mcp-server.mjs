import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

import {
  listMemoryFiles,
  readMemoryBootstrap,
  readMemoryFile,
  searchMemories,
} from "./memory-store.mjs";

const readOnlyAnnotations = {
  readOnlyHint: true,
  destructiveHint: false,
  idempotentHint: true,
  openWorldHint: false,
};

function textResult(text) {
  return { content: [{ type: "text", text }] };
}

function errorResult(error) {
  const message = error instanceof Error ? error.message : "未知错误";
  return {
    isError: true,
    content: [{ type: "text", text: `读取失败：${message}` }],
  };
}

const server = new McpServer(
  { name: "claude-memory-readonly", version: "0.1.0" },
  {
    instructions:
      "这是只读记忆库。每个新对话先调用一次 memory_bootstrap；之后只按当前问题搜索或读取少量相关原文。没有任何写入、删除或 Git 操作。",
  },
);

server.registerTool(
  "memory_bootstrap",
  {
    title: "加载长期角色与记忆规则",
    description:
      "每个新对话首次回复前调用一次。加载精简的高频角色、关系边界、通用偏好和检索规则；详细记忆按需搜索和读取。不会读取密钥或写入内容。",
    inputSchema: {},
    annotations: readOnlyAnnotations,
  },
  async () => {
    try {
      const result = await readMemoryBootstrap();
      const truncationNote = result.truncated
        ? `\n\n[启动包已截断：原文共 ${result.totalCharacters} 个字符]`
        : "";
      return textResult(
        `长期角色与记忆启动包：\n\n${result.content}${truncationNote}`,
      );
    } catch (error) {
      return errorResult(error);
    }
  },
);

server.registerTool(
  "memory_list",
  {
    title: "查看记忆目录",
    description: "列出允许读取的记忆 Markdown 文件，不返回隐藏文件或密钥文件。",
    inputSchema: {},
    annotations: readOnlyAnnotations,
  },
  async () => {
    try {
      const files = await listMemoryFiles();
      return textResult(
        ["允许读取的记忆文件：", ...files.map((file) => `- ${file.path}`)].join(
          "\n",
        ),
      );
    } catch (error) {
      return errorResult(error);
    }
  },
);

server.registerTool(
  "memory_search",
  {
    title: "搜索记忆",
    description:
      "在允许的记忆文件中按关键词搜索，返回少量带路径和行号的匹配片段。",
    inputSchema: {
      query: z.string().min(1).max(100).describe("要查找的主题或关键词"),
      max_results: z.number().int().min(1).max(10).optional().describe("最多返回几条，默认 5 条"),
    },
    annotations: readOnlyAnnotations,
  },
  async ({ query, max_results }) => {
    try {
      const results = await searchMemories(query, max_results ?? 5);
      if (results.length === 0) {
        return textResult(`没有找到与“${query}”相关的已保存记忆。`);
      }

      return textResult(
        [
          `与“${query}”相关的记忆片段：`,
          ...results.map(
            (result) =>
              `- ${result.path}:${result.line} — ${result.snippet || "（空行）"}`,
          ),
        ].join("\n"),
      );
    } catch (error) {
      return errorResult(error);
    }
  },
);

server.registerTool(
  "memory_read",
  {
    title: "读取记忆原文",
    description:
      "读取一个白名单内的记忆 Markdown 文件。只接受 MEMORY_RULES.md 或 memories/ 下的路径。",
    inputSchema: {
      path: z.string().min(1).max(300).describe("例如 memories/index.md"),
      max_characters: z
        .number()
        .int()
        .min(200)
        .max(12000)
        .optional()
        .describe("最多读取字符数，默认 6000"),
    },
    annotations: readOnlyAnnotations,
  },
  async ({ path, max_characters }) => {
    try {
      const result = await readMemoryFile(path, max_characters ?? 6000);
      const truncationNote = result.truncated
        ? `\n\n[内容已截断：原文共 ${result.totalCharacters} 个字符]`
        : "";
      return textResult(
        `来源：${result.path}\n\n${result.content}${truncationNote}`,
      );
    } catch (error) {
      return errorResult(error);
    }
  },
);

const transport = new StdioServerTransport();
await server.connect(transport);
console.error("claude-memory read-only MCP server is running");
