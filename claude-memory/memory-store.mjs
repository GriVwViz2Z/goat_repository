import { promises as fs } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

export const PROJECT_ROOT = path.dirname(fileURLToPath(import.meta.url));
export const MEMORY_ROOT = path.join(PROJECT_ROOT, "memories");
const RULES_FILE = path.join(PROJECT_ROOT, "MEMORY_RULES.md");
const BOOTSTRAP_PATHS = ["memories/bootstrap.md"];

function relativePath(absolutePath) {
  return path.relative(PROJECT_ROOT, absolutePath).split(path.sep).join("/");
}

async function walkMarkdownFiles(directory) {
  const entries = await fs.readdir(directory, { withFileTypes: true });
  const files = [];

  for (const entry of entries.sort((a, b) => a.name.localeCompare(b.name))) {
    if (entry.name.startsWith(".") || entry.isSymbolicLink()) continue;

    const absolutePath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      files.push(...(await walkMarkdownFiles(absolutePath)));
    } else if (entry.isFile() && entry.name.endsWith(".md")) {
      files.push(absolutePath);
    }
  }

  return files;
}

export async function listMemoryFiles() {
  const files = [RULES_FILE, ...(await walkMarkdownFiles(MEMORY_ROOT))];
  return files.map((absolutePath) => ({
    path: relativePath(absolutePath),
    absolutePath,
  }));
}

export async function resolveMemoryPath(requestedPath) {
  if (typeof requestedPath !== "string" || requestedPath.trim() === "") {
    throw new Error("请提供记忆文件路径。");
  }

  const cleanPath = requestedPath.trim().replaceAll("\\", "/");
  const normalized = path.posix.normalize(cleanPath);

  if (
    path.posix.isAbsolute(normalized) ||
    normalized === ".." ||
    normalized.startsWith("../") ||
    normalized.includes("\0")
  ) {
    throw new Error("路径不在允许的记忆目录中。");
  }

  const isRules = normalized === "MEMORY_RULES.md";
  const isMemoryMarkdown =
    normalized.startsWith("memories/") && normalized.endsWith(".md");

  if (!isRules && !isMemoryMarkdown) {
    throw new Error("只允许读取 MEMORY_RULES.md 和 memories/ 内的 Markdown 文件。");
  }

  const absolutePath = path.resolve(PROJECT_ROOT, ...normalized.split("/"));
  const fileInfo = await fs.lstat(absolutePath);
  if (!fileInfo.isFile() || fileInfo.isSymbolicLink()) {
    throw new Error("目标不是允许读取的普通文件。");
  }

  const realFile = await fs.realpath(absolutePath);
  const realMemoryRoot = await fs.realpath(MEMORY_ROOT);
  const realRulesFile = await fs.realpath(RULES_FILE);
  const insideMemoryRoot = realFile.startsWith(`${realMemoryRoot}${path.sep}`);

  if (realFile !== realRulesFile && !insideMemoryRoot) {
    throw new Error("文件解析后的真实路径越过了记忆目录边界。");
  }

  return { path: normalized, absolutePath: realFile };
}

export async function readMemoryFile(requestedPath, maxCharacters = 6000) {
  const file = await resolveMemoryPath(requestedPath);
  const content = await fs.readFile(file.absolutePath, "utf8");
  const limit = Math.min(Math.max(maxCharacters, 200), 12000);
  const truncated = content.length > limit;

  return {
    path: file.path,
    content: truncated ? content.slice(0, limit) : content,
    truncated,
    totalCharacters: content.length,
  };
}

export async function readMemoryBootstrap(maxCharacters = 12000) {
  const sections = [];

  for (const requestedPath of BOOTSTRAP_PATHS) {
    const file = await resolveMemoryPath(requestedPath);
    const content = await fs.readFile(file.absolutePath, "utf8");
    sections.push(`---\n来源：${file.path}\n\n${content.trim()}`);
  }

  const content = sections.join("\n\n");
  const limit = Math.min(Math.max(maxCharacters, 1000), 20000);
  const truncated = content.length > limit;

  return {
    paths: [...BOOTSTRAP_PATHS],
    content: truncated ? content.slice(0, limit) : content,
    truncated,
    totalCharacters: content.length,
  };
}

export async function searchMemories(query, maxResults = 5) {
  const cleanQuery = query.trim();
  if (!cleanQuery) throw new Error("搜索词不能为空。");

  const terms = [
    cleanQuery,
    ...cleanQuery.split(/\s+/u).filter((term) => term.length > 1),
  ];
  const uniqueTerms = [...new Set(terms.map((term) => term.toLocaleLowerCase()))];
  const limit = Math.min(Math.max(maxResults, 1), 10);
  const results = [];

  for (const file of await listMemoryFiles()) {
    const content = await fs.readFile(file.absolutePath, "utf8");
    const lines = content.split(/\r?\n/u);

    for (let index = 0; index < lines.length; index += 1) {
      const line = lines[index];
      const lowerLine = line.toLocaleLowerCase();
      const score = uniqueTerms.reduce(
        (total, term) => total + (lowerLine.includes(term) ? 1 : 0),
        0,
      );

      if (score > 0) {
        results.push({
          path: file.path,
          line: index + 1,
          snippet: line.slice(0, 240),
          score,
        });
      }
    }
  }

  return results
    .sort((a, b) => b.score - a.score || a.path.localeCompare(b.path) || a.line - b.line)
    .slice(0, limit);
}
