/*
 * X Following Exporter (read-only)
 *
 * Usage:
 * 1. Open https://x.com/<your-old-account>/following while logged in.
 * 2. Open Chrome/Edge DevTools -> Sources -> Snippets -> New snippet.
 * 3. Paste this entire file into the snippet and run it.
 * 4. Keep the tab open and in the foreground until a Markdown file downloads.
 *
 * This script only reads the visible following list and scrolls the page.
 * It does not follow, unfollow, like, post, or send anything.
 */

(async () => {
  'use strict';

  if (!/^https:\/\/(x\.com|twitter\.com)\/[^/]+\/following\/?(?:\?.*)?$/.test(location.href)) {
    alert('请先打开旧账号的“正在关注”页面，再运行导出器。');
    return;
  }

  if (window.__xFollowingExporterRunning) {
    alert('导出器已经在运行。');
    return;
  }
  window.__xFollowingExporterRunning = true;

  const accounts = new Map();
  let roundsWithoutNewAccounts = 0;
  let previousScrollY = -1;
  let roundsWithoutScrolling = 0;

  const sleep = (milliseconds) =>
    new Promise((resolve) => setTimeout(resolve, milliseconds));

  const escapeMarkdown = (value) =>
    String(value || '')
      .replaceAll('\\', '\\\\')
      .replaceAll('|', '\\|')
      .replaceAll('\n', ' ')
      .trim();

  const collectVisibleAccounts = () => {
    const root =
      document.querySelector('main [data-testid="primaryColumn"]') ||
      document.querySelector('main');

    if (!root) return 0;

    let added = 0;
    for (const cell of root.querySelectorAll('[data-testid="UserCell"]')) {
      const lines = cell.innerText
        .split('\n')
        .map((line) => line.trim())
        .filter(Boolean);

      const handleIndex = lines.findIndex((line) => /^@[A-Za-z0-9_]{1,15}$/.test(line));
      if (handleIndex === -1) continue;

      const handle = lines[handleIndex].slice(1);
      const key = handle.toLowerCase();
      if (accounts.has(key)) continue;

      let displayName = '';
      for (let index = handleIndex - 1; index >= 0; index -= 1) {
        const candidate = lines[index];
        if (candidate && !candidate.startsWith('@')) {
          displayName = candidate;
          break;
        }
      }

      accounts.set(key, {
        handle,
        displayName,
        url: `https://x.com/${handle}`,
      });
      added += 1;
    }
    return added;
  };

  try {
    console.log('[X 导出器] 开始读取关注列表，请保持此标签页打开。');

    while (roundsWithoutNewAccounts < 12 && roundsWithoutScrolling < 12) {
      const added = collectVisibleAccounts();
      roundsWithoutNewAccounts = added === 0 ? roundsWithoutNewAccounts + 1 : 0;

      window.scrollBy({
        top: Math.max(600, Math.floor(window.innerHeight * 0.85)),
        behavior: 'smooth',
      });

      await sleep(1300 + Math.floor(Math.random() * 900));

      if (Math.abs(window.scrollY - previousScrollY) < 2) {
        roundsWithoutScrolling += 1;
      } else {
        roundsWithoutScrolling = 0;
      }
      previousScrollY = window.scrollY;

      console.log(`[X 导出器] 已收集 ${accounts.size} 个账号…`);
    }

    collectVisibleAccounts();

    const accountName = location.pathname.split('/').filter(Boolean)[0] || 'account';
    const date = new Date().toISOString().slice(0, 10);
    const rows = [...accounts.values()];
    const markdown = [
      `# @${accountName} 的关注列表`,
      '',
      `- 导出时间：${new Date().toLocaleString()}`,
      `- 账号数量：${rows.length}`,
      '',
      '| 序号 | 显示名称 | 用户名 | 主页 | 已迁移 |',
      '| ---: | --- | --- | --- | :---: |',
      ...rows.map((account, index) =>
        `| ${index + 1} | ${escapeMarkdown(account.displayName)} | @${account.handle} | [打开](${account.url}) | ☐ |`
      ),
      '',
    ].join('\n');

    const blob = new Blob([markdown], { type: 'text/markdown;charset=utf-8' });
    const downloadUrl = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = downloadUrl;
    link.download = `${accountName}-following-${date}.md`;
    document.body.appendChild(link);
    link.click();
    link.remove();
    setTimeout(() => URL.revokeObjectURL(downloadUrl), 5000);

    console.log(`[X 导出器] 完成：共 ${rows.length} 个账号。`);
    alert(`导出完成：共 ${rows.length} 个账号。\nMarkdown 文件已开始下载。`);
  } catch (error) {
    console.error('[X 导出器] 导出失败：', error);
    alert(`导出失败：${error?.message || error}`);
  } finally {
    window.__xFollowingExporterRunning = false;
  }
})();
