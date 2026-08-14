# X Following Exporter

A tiny, read-only browser script that exports the accounts shown on your X
**Following** page to a Markdown checklist.

一个只读的浏览器小脚本：自动滚动你在 X 上的「正在关注」页面，并把账号整理成
Markdown 清单。

## What it does / 功能

- Collects display names, handles, and profile links from the Following page.
- Keeps the order in which accounts are discovered and removes duplicates.
- Downloads a local Markdown table with a migration checkbox.
- Runs entirely in your browser.

它会收集显示名称、`@用户名`和主页链接，自动去重，并下载一份带迁移勾选栏的
Markdown 表格。数据只在你的浏览器中处理。

## What it does not do / 不会做什么

This script does **not** follow or unfollow accounts, post, like, send messages,
read private messages, or upload your list to a server. It does not ask for your
password, cookies, or API keys.

脚本不会关注、取消关注、发帖、点赞、发送或读取私信，也不会把名单上传到服务器。
它不需要密码、Cookie 或 API 密钥。

## Usage / 使用方法

Desktop Chrome or Edge is recommended.

1. Sign in to X and open your old account's Following page:
   `https://x.com/YOUR_HANDLE/following`
2. Open Developer Tools (`Option + Command + I` on macOS or `F12` on Windows).
3. Press `Command + Shift + P` on macOS or `Ctrl + Shift + P` on Windows.
4. Search for **Show Snippets**, then create a new snippet.
5. Copy all of [`x-following-exporter.js`](./x-following-exporter.js) into the
   snippet and run it with `Command + Enter` or `Ctrl + Enter`.
6. Keep the page open and in the foreground. A `.md` file will download when the
   export finishes.

推荐使用桌面版 Chrome 或 Edge：

1. 登录 X，打开旧账号的关注页面：`https://x.com/你的用户名/following`
2. 打开开发者工具（macOS：`⌥⌘I`；Windows：`F12`）。
3. 打开命令菜单（macOS：`⌘⇧P`；Windows：`Ctrl + Shift + P`）。
4. 搜索 **Show Snippets**，新建一个 Snippet。
5. 把 [`x-following-exporter.js`](./x-following-exporter.js) 的全部内容粘贴进去，
   按 `⌘↵` 或 `Ctrl + Enter` 运行。
6. 保持页面在前台，完成后浏览器会自动下载 `.md` 文件。

## Verify the result / 核对结果

Compare the exported count with the Following count shown by X. A small mismatch
may come from suspended, deactivated, protected, or temporarily unavailable
accounts. If the gap is large, wait for the page to recover and run the exporter
again.

请将导出数量与 X 页面显示的关注总数进行比较。停用、受限或暂时无法加载的账号可能
导致少量差异；如果差距较大，可以稍后重新运行。

## Privacy and safety / 隐私与安全

- Review browser-console code before running it.
- Do not publish the generated Markdown list unless you intend to make your
  social graph public.
- This project is not affiliated with or endorsed by X Corp.
- X may change its website structure at any time, which can break the exporter.
- Use the tool only on accounts and data you are authorized to access.

运行任何浏览器控制台代码前都应先检查内容。不要误把生成的关注名单提交到公开仓库，
除非你确实希望公开自己的社交关系。本项目与 X Corp. 无关联，也未获得其认可；X 的
页面结构变化可能导致脚本失效。请只导出你有权访问的账号和数据。

## License

[MIT](./LICENSE)
