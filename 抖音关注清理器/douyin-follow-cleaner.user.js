// ==UserScript==
// @name         抖音关注半自动清理器
// @namespace    codex.local
// @version      0.1.0
// @description  采集、筛选并经确认后限速取消关注；不做无人值守批量操作。
// @match        https://www.douyin.com/user/self*
// @grant        none
// @run-at       document-idle
// ==/UserScript==

(() => {
  'use strict';

  const APP_ID = 'codex-dy-follow-cleaner';
  const STORE_KEY = 'codex:dy-follow-cleaner:v1';
  const DEFAULTS = {
    minDelayMs: 9000,
    maxDelayMs: 15000,
    batchLimit: 20,
    autoScrollMs: 1400,
    maxNoGrowth: 8,
  };
  const state = loadState();
  let running = false;
  let stopRequested = false;
  let scanTimer = null;
  let noGrowthRounds = 0;

  if (document.getElementById(APP_ID)) return;

  function loadState() {
    try {
      return Object.assign({ accounts: {}, settings: DEFAULTS }, JSON.parse(localStorage.getItem(STORE_KEY) || '{}'));
    } catch {
      return { accounts: {}, settings: { ...DEFAULTS } };
    }
  }

  function saveState() {
    localStorage.setItem(STORE_KEY, JSON.stringify(state));
  }

  function cleanText(value) {
    return String(value || '').replace(/\s+/g, ' ').trim();
  }

  function userIdFromHref(href) {
    const match = String(href || '').match(/\/user\/([^/?#]+)/);
    return match ? match[1] : '';
  }

  function cardFromButton(button) {
    let node = button;
    for (let depth = 0; depth < 5 && node; depth += 1, node = node.parentElement) {
      const links = node.querySelectorAll('a[href*="/user/"]');
      const buttons = Array.from(node.querySelectorAll('button')).filter((b) => cleanText(b.textContent) === '已关注');
      if (links.length >= 1 && buttons.length === 1) return node;
    }
    return null;
  }

  function scoreAccount(name, bio, verified) {
    const text = `${name} ${bio}`.toLowerCase();
    const reasons = [];
    let score = 0;
    const rules = [
      [/带货|好物|橱窗|选品|商行|门店|招商|加盟|厂家|批发|供应链|官方旗舰|品牌合作|商务合作|合作.{0,8}(v|微|wx|qq|邮箱|备注)/i, 3, '营销/商业关键词'],
      [/加微|私信.{0,6}(咨询|合作|领取)|免费领取|课程咨询|代理|招募/i, 3, '引流关键词'],
      [/影视剪辑|搬运|解说合集|每日更新|头像壁纸|素材分享/i, 1, '内容聚合关键词'],
      [/^用户\d{5,}$/i, 2, '默认用户名'],
      [/^\.|暂无简介|这个人很懒/i, 1, '信息很少'],
    ];
    for (const [pattern, points, reason] of rules) {
      if (pattern.test(text)) {
        score += points;
        reasons.push(reason);
      }
    }
    if (verified) {
      score = Math.max(0, score - 1);
      reasons.push('已认证（降权）');
    }
    return { score, reasons };
  }

  function collectVisible() {
    const buttons = Array.from(document.querySelectorAll('button')).filter((b) => cleanText(b.textContent) === '已关注');
    let added = 0;
    for (const button of buttons) {
      const card = cardFromButton(button);
      if (!card) continue;
      const links = Array.from(card.querySelectorAll('a[href*="/user/"]'));
      const link = links.find((a) => cleanText(a.textContent)) || links[0];
      if (!link) continue;
      const href = new URL(link.getAttribute('href'), location.href).href;
      const id = userIdFromHref(href);
      if (!id) continue;
      const lines = String(card.innerText || '').split('\n').map(cleanText).filter(Boolean);
      const name = cleanText(link.textContent) || cleanText(link.querySelector('img')?.alt).replace(/头像$/, '') || id;
      const verified = lines.some((line) => line.includes('认证徽章'));
      const bio = lines.filter((line) => ![name, '已关注', '认证徽章'].includes(line) && !/作品未看$/.test(line)).join(' · ');
      const scored = scoreAccount(name, bio, verified);
      const previous = state.accounts[id];
      state.accounts[id] = {
        id, name, bio, href, verified,
        score: scored.score,
        reasons: scored.reasons,
        selected: previous?.selected || false,
        status: previous?.status || 'pending',
        seenAt: new Date().toISOString(),
      };
      if (!previous) added += 1;
    }
    if (added) saveState();
    render();
    return added;
  }

  function findScrollContainer() {
    const followed = Array.from(document.querySelectorAll('button')).find((b) => cleanText(b.textContent) === '已关注');
    let node = followed?.parentElement;
    while (node && node !== document.body) {
      const style = getComputedStyle(node);
      if (/(auto|scroll)/.test(style.overflowY) && node.scrollHeight > node.clientHeight + 40) return node;
      node = node.parentElement;
    }
    return document.scrollingElement || document.documentElement;
  }

  async function startScan() {
    if (scanTimer || running) return;
    noGrowthRounds = 0;
    setStatus('正在采集；保持关注列表弹层打开…');
    const step = () => {
      const before = Object.keys(state.accounts).length;
      collectVisible();
      const after = Object.keys(state.accounts).length;
      noGrowthRounds = after === before ? noGrowthRounds + 1 : 0;
      const scroller = findScrollContainer();
      scroller.scrollTop += Math.max(420, scroller.clientHeight * 0.8);
      if (noGrowthRounds >= state.settings.maxNoGrowth) {
        stopScan('采集暂停：连续多轮没有新账号。可向下滚动后继续。');
        return;
      }
      scanTimer = window.setTimeout(step, state.settings.autoScrollMs);
    };
    step();
  }

  function stopScan(message = '采集已暂停') {
    if (scanTimer) clearTimeout(scanTimer);
    scanTimer = null;
    setStatus(message);
    render();
  }

  function dangerDetected() {
    const text = cleanText(document.body.innerText).slice(-12000);
    return /验证码|操作频繁|账号异常|安全验证|请完成验证|访问过于频繁/.test(text);
  }

  function locateButton(account) {
    const links = Array.from(document.querySelectorAll('a[href*="/user/"]'))
      .filter((a) => userIdFromHref(a.getAttribute('href')) === account.id);
    for (const link of links) {
      let node = link;
      for (let depth = 0; depth < 5 && node; depth += 1, node = node.parentElement) {
        const button = Array.from(node.querySelectorAll('button')).find((b) => cleanText(b.textContent) === '已关注');
        if (button && cardFromButton(button) === node) return button;
      }
    }
    return null;
  }

  function randomDelay() {
    const { minDelayMs, maxDelayMs } = state.settings;
    return minDelayMs + Math.floor(Math.random() * Math.max(1, maxDelayMs - minDelayMs));
  }

  async function executeSelected() {
    if (running) return;
    stopScan();
    const queue = Object.values(state.accounts)
      .filter((a) => a.selected && a.status === 'pending')
      .slice(0, state.settings.batchLimit);
    if (!queue.length) return setStatus('没有已勾选且待处理的账号。');
    const names = queue.map((a) => a.name).join('、');
    if (!confirm(`即将在抖音取消关注 ${queue.length} 个账号：\n\n${names}\n\n每次点击间隔 9–15 秒。是否确认？`)) return;

    running = true;
    stopRequested = false;
    render();
    let completed = 0;
    for (const account of queue) {
      if (stopRequested || dangerDetected()) break;
      const button = locateButton(account);
      if (!button) {
        setStatus(`找不到 ${account.name}，请在关注列表中滚动到该账号后再继续。`);
        break;
      }
      button.scrollIntoView({ block: 'center', behavior: 'smooth' });
      await new Promise((resolve) => setTimeout(resolve, 800));
      if (cleanText(button.textContent) !== '已关注') {
        account.status = 'skipped';
        continue;
      }
      button.click();
      await new Promise((resolve) => setTimeout(resolve, 1200));
      if (dangerDetected()) break;
      if (cleanText(button.textContent) === '关注' || !button.isConnected) {
        account.status = 'unfollowed';
        account.selected = false;
        account.unfollowedAt = new Date().toISOString();
        completed += 1;
        saveState();
        render();
      } else {
        setStatus(`${account.name} 的按钮状态没有按预期变化，已停止。`);
        break;
      }
      if (completed < queue.length) {
        const wait = randomDelay();
        setStatus(`已完成 ${completed}/${queue.length}，等待 ${Math.ceil(wait / 1000)} 秒…`);
        await new Promise((resolve) => setTimeout(resolve, wait));
      }
    }
    running = false;
    const warning = dangerDetected() ? '检测到验证或频率提示，已停止。' : stopRequested ? '已手动停止。' : `本轮完成 ${completed} 个。`;
    setStatus(warning);
    saveState();
    render();
  }

  function exportCsv() {
    const rows = [['账号名', '简介', '认证', '风险分', '理由', '状态', '主页']];
    for (const a of Object.values(state.accounts)) rows.push([a.name, a.bio, a.verified ? '是' : '否', a.score, a.reasons.join('|'), a.status, a.href]);
    const csv = rows.map((row) => row.map((cell) => `"${String(cell ?? '').replace(/"/g, '""')}"`).join(',')).join('\n');
    const blob = new Blob(['\ufeff', csv], { type: 'text/csv;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const link = Object.assign(document.createElement('a'), { href: url, download: `douyin-following-${new Date().toISOString().slice(0, 10)}.csv` });
    link.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }

  function setStatus(text) {
    const el = document.querySelector(`#${APP_ID} [data-status]`);
    if (el) el.textContent = text;
  }

  function createUi() {
    const root = document.createElement('section');
    root.id = APP_ID;
    root.innerHTML = `
      <style>
        #${APP_ID}{position:fixed;z-index:2147483647;right:16px;top:72px;width:390px;max-height:76vh;background:#18181b;color:#f4f4f5;border:1px solid #3f3f46;border-radius:14px;box-shadow:0 16px 50px #0009;font:13px/1.4 system-ui,-apple-system,sans-serif;overflow:hidden}
        #${APP_ID} *{box-sizing:border-box} #${APP_ID} header{display:flex;justify-content:space-between;align-items:center;padding:12px 14px;background:#27272a;font-weight:700}
        #${APP_ID} .body{padding:12px} #${APP_ID} .stats,#${APP_ID} .actions{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:10px}
        #${APP_ID} button{border:0;border-radius:8px;padding:7px 10px;cursor:pointer;background:#3f3f46;color:#fff} #${APP_ID} button.primary{background:#fe2c55} #${APP_ID} button:disabled{opacity:.45;cursor:not-allowed}
        #${APP_ID} input[type=search]{width:100%;padding:8px;border:1px solid #52525b;border-radius:8px;background:#09090b;color:#fff;margin-bottom:8px}
        #${APP_ID} .filters{display:flex;gap:10px;margin-bottom:8px;color:#d4d4d8} #${APP_ID} .list{max-height:39vh;overflow:auto;border-top:1px solid #3f3f46}
        #${APP_ID} .row{display:grid;grid-template-columns:22px 1fr auto;gap:7px;padding:8px 2px;border-bottom:1px solid #27272a;align-items:start} #${APP_ID} .name{font-weight:650;color:#fff;text-decoration:none}
        #${APP_ID} .bio{color:#a1a1aa;font-size:12px;margin-top:2px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:255px} #${APP_ID} .score{background:#3f3f46;border-radius:999px;padding:2px 7px;font-size:11px}
        #${APP_ID} .status{color:#fbbf24;min-height:20px;margin-top:8px} #${APP_ID} .muted{color:#a1a1aa}
      </style>
      <header><span>关注清理器</span><button data-collapse>—</button></header>
      <div class="body">
        <div class="stats" data-stats></div>
        <div class="actions">
          <button data-collect>采集当前</button><button data-scan>自动滚动采集</button><button data-stop>停止</button>
          <button data-export>导出 CSV</button>
        </div>
        <input type="search" data-search placeholder="搜索账号名或简介">
        <div class="filters"><label><input type="checkbox" data-risk> 只看疑似营销</label><label><input type="checkbox" data-selected> 只看已选</label></div>
        <div class="list" data-list></div>
        <div class="actions" style="margin-top:10px"><button class="primary" data-execute>确认并执行（每轮最多20）</button><button data-clear>清空记录</button></div>
        <div class="status" data-status>只读模式：先采集并勾选候选。</div>
      </div>`;
    document.body.appendChild(root);
    root.querySelector('[data-collect]').onclick = collectVisible;
    root.querySelector('[data-scan]').onclick = startScan;
    root.querySelector('[data-stop]').onclick = () => { stopRequested = true; stopScan('已请求停止。'); };
    root.querySelector('[data-export]').onclick = exportCsv;
    root.querySelector('[data-execute]').onclick = executeSelected;
    root.querySelector('[data-search]').oninput = render;
    root.querySelector('[data-risk]').onchange = render;
    root.querySelector('[data-selected]').onchange = render;
    root.querySelector('[data-collapse]').onclick = () => { root.querySelector('.body').hidden = !root.querySelector('.body').hidden; };
    root.querySelector('[data-clear]').onclick = () => {
      if (!confirm('只清空本脚本的采集记录，不会改变抖音关注。确认？')) return;
      state.accounts = {}; saveState(); render();
    };
  }

  function render() {
    const root = document.getElementById(APP_ID);
    if (!root) return;
    const all = Object.values(state.accounts);
    const query = cleanText(root.querySelector('[data-search]').value).toLowerCase();
    const onlyRisk = root.querySelector('[data-risk]').checked;
    const onlySelected = root.querySelector('[data-selected]').checked;
    const shown = all.filter((a) => (!query || `${a.name} ${a.bio}`.toLowerCase().includes(query)) && (!onlyRisk || a.score >= 2) && (!onlySelected || a.selected));
    root.querySelector('[data-stats]').innerHTML = `<span>已采集 <b>${all.length}</b></span><span>疑似营销 <b>${all.filter((a) => a.score >= 2).length}</b></span><span>已选 <b>${all.filter((a) => a.selected && a.status === 'pending').length}</b></span><span>已取关 <b>${all.filter((a) => a.status === 'unfollowed').length}</b></span>`;
    root.querySelector('[data-list]').innerHTML = shown.slice(0, 500).map((a) => `
      <label class="row">
        <input type="checkbox" data-id="${escapeHtml(a.id)}" ${a.selected ? 'checked' : ''} ${a.status !== 'pending' ? 'disabled' : ''}>
        <span><a class="name" href="${escapeHtml(a.href)}" target="_blank">${escapeHtml(a.name)}</a><div class="bio" title="${escapeHtml(a.bio)}">${escapeHtml(a.bio || '暂无简介')}</div><div class="muted">${escapeHtml(a.reasons.join('、') || '未命中规则')} · ${escapeHtml(a.status)}</div></span>
        <span class="score">${a.score}分</span>
      </label>`).join('') || '<p class="muted">还没有数据。先打开“关注 (4051)”弹层并采集。</p>';
    for (const checkbox of root.querySelectorAll('[data-id]')) checkbox.onchange = () => {
      state.accounts[checkbox.dataset.id].selected = checkbox.checked;
      saveState(); render();
    };
    root.querySelector('[data-execute]').disabled = running;
  }

  function escapeHtml(value) {
    return String(value ?? '').replace(/[&<>"']/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char]));
  }

  createUi();
  collectVisible();
})();
