const apiKey = process.env.OPENROUTER_API_KEY?.trim();
const model =
  process.env.OPENROUTER_MODEL?.trim() || "anthropic/claude-haiku-4.5";

if (!apiKey || apiKey === "replace_with_your_openrouter_key") {
  console.error("还没有在本机 .env 文件中填写 OPENROUTER_API_KEY。");
  process.exit(1);
}

const response = await fetch(
  "https://openrouter.ai/api/v1/chat/completions",
  {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model,
      max_tokens: 40,
      messages: [
        {
          role: "user",
          content: "这是一次连接测试。请只回复：连接成功。",
        },
      ],
    }),
  },
);

const result = await response.json().catch(() => ({}));

if (!response.ok) {
  const message = result?.error?.message || "OpenRouter 没有返回错误说明。";
  console.error(`连接失败（HTTP ${response.status}）：${message}`);
  process.exit(1);
}

const content = result?.choices?.[0]?.message?.content;
if (!content) {
  console.error("连接成功，但响应里没有找到文字内容。");
  process.exit(1);
}

console.log(`模型：${model}`);
console.log(`回复：${content}`);
if (result.usage) {
  console.log(
    `用量：输入 ${result.usage.prompt_tokens ?? "未知"}，输出 ${result.usage.completion_tokens ?? "未知"} tokens`,
  );
}

