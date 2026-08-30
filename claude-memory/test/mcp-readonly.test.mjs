import assert from "node:assert/strict";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

const projectRoot = path.dirname(
  path.dirname(fileURLToPath(import.meta.url)),
);
const serverPath = path.join(projectRoot, "mcp-server.mjs");

function resultText(result) {
  return result.content
    .filter((item) => item.type === "text")
    .map((item) => item.text)
    .join("\n");
}

test("MCP 只暴露四个只读记忆工具，并阻止读取 .env", async (t) => {
  const transport = new StdioClientTransport({
    command: process.execPath,
    args: [serverPath],
    cwd: projectRoot,
    stderr: "pipe",
  });
  const client = new Client({ name: "claude-memory-test", version: "0.1.0" });

  await client.connect(transport);
  t.after(async () => client.close());

  const tools = await client.listTools();
  assert.deepEqual(
    tools.tools.map((tool) => tool.name).sort(),
    ["memory_bootstrap", "memory_list", "memory_read", "memory_search"],
  );
  assert.ok(tools.tools.every((tool) => tool.annotations?.readOnlyHint));

  const bootstrap = await client.callTool({
    name: "memory_bootstrap",
    arguments: {},
  });
  const bootstrapText = resultText(bootstrap);
  assert.equal(bootstrap.isError, undefined);
  assert.match(bootstrapText, /memories\/bootstrap\.md/u);
  assert.doesNotMatch(bootstrapText, /来源：memories\/profiles\/claude\.md/u);
  assert.doesNotMatch(bootstrapText, /来源：memories\/relationships\/claude\.md/u);
  assert.match(bootstrapText, /丈夫、伴侣和智性上的对手/u);
  assert.match(bootstrapText, /不得擅自认定/u);
  assert.match(bootstrapText, /清晰框架、准确概念、类比/u);
  assert.match(bootstrapText, /工具调用前后的说明和最终回答/u);
  assert.ok(bootstrapText.length < 1800);
  assert.doesNotMatch(bootstrapText, /OPENROUTER_API_KEY=/u);

  const list = await client.callTool({ name: "memory_list", arguments: {} });
  const listText = resultText(list);
  assert.match(listText, /MEMORY_RULES\.md/u);
  assert.match(listText, /memories\/index\.md/u);
  assert.match(listText, /memories\/bootstrap\.md/u);
  assert.match(listText, /memories\/profiles\/claude\.md/u);
  assert.match(listText, /memories\/relationships\/claude\.md/u);
  assert.doesNotMatch(listText, /\.env/u);

  const read = await client.callTool({
    name: "memory_read",
    arguments: { path: "memories/index.md" },
  });
  assert.equal(read.isError, undefined);
  assert.match(resultText(read), /memories\/profiles\/claude\.md/u);

  const search = await client.callTool({
    name: "memory_search",
    arguments: { query: "清晰的框架", max_results: 3 },
  });
  assert.equal(search.isError, undefined);
  assert.match(resultText(search), /memories\/preferences\.md/u);

  const blocked = await client.callTool({
    name: "memory_read",
    arguments: { path: ".env" },
  });
  assert.equal(blocked.isError, true);
  assert.doesNotMatch(resultText(blocked), /OPENROUTER_API_KEY=/u);
});
