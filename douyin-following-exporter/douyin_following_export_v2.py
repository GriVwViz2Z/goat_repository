#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
抖音关注列表批量导出 v2
适合关注数很多（例如 4000+）的情况。

核心改动：
1. 不再只跑 220 轮；最大允许 3000 轮。
2. “连续无新增”阈值从 10 提高到 40，避免抖音懒加载时误判结束。
3. 遇到加载停滞会自动：
   - 多等一会
   - 轻微回滚
   - 再滚到底部
   - 重新检测滚动容器
4. 每新增一批数据会保存 checkpoint，哪怕中途 Ctrl+C 也不会白跑。
5. 终端会显示总数、滚动位置、连续无新增次数。

安装：
    python3 -m pip install playwright
    python3 -m playwright install chromium

运行：
    python3 douyin_following_export_v2.py
"""

import csv
import json
import random
import re
import time
from datetime import datetime
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit

from playwright.sync_api import sync_playwright


HOME = Path.home()
WORKDIR = HOME / "douyin-following-export"
PROFILE_DIR = WORKDIR / "browser-profile"
OUTPUT_DIR = WORKDIR / "exports"

# 4000+ 关注时，220 轮经常不够。
MAX_ROUNDS = 3000

# 抖音有时会卡几秒甚至十几秒再继续加载。
NO_NEW_LIMIT = 40

WAIT_NORMAL_MIN = 0.7
WAIT_NORMAL_MAX = 1.2

WAIT_STALL_MIN = 1.8
WAIT_STALL_MAX = 3.0

CHECKPOINT_EVERY_NEW_USERS = 100


def normalize_user_url(url: str) -> str:
    try:
        p = urlsplit(url)
        return urlunsplit((p.scheme, p.netloc, p.path.rstrip("/"), "", ""))
    except Exception:
        return url


def clean_name(text: str) -> str:
    if not text:
        return ""

    text = re.sub(r"\s+", " ", text).strip()

    for sep in ["已关注", "互相关注", "关注", "私信"]:
        if sep in text:
            text = text.split(sep, 1)[0].strip()

    return text[:120]


def detect_scroll_container(page):
    """
    找到最可能承载“关注列表”的滚动容器。
    给它打 data-dy-export-scroll="1" 标记。
    """
    return page.evaluate(
        """
        () => {
          document.querySelectorAll('[data-dy-export-scroll="1"]')
            .forEach(el => el.removeAttribute('data-dy-export-scroll'));

          const all = [...document.querySelectorAll('body *')];
          let best = null;
          let bestScore = -1;

          for (const el of all) {
            const style = getComputedStyle(el);
            const isScrollable =
              el.scrollHeight > el.clientHeight + 100 &&
              ['auto', 'scroll'].includes(style.overflowY);

            if (!isScrollable) continue;

            const userLinks = el.querySelectorAll('a[href*="/user/"]').length;
            if (userLinks === 0) continue;

            const score =
              userLinks * 1000000 +
              Math.min(el.scrollHeight, 1000000) +
              el.clientHeight;

            if (score > bestScore) {
              best = el;
              bestScore = score;
            }
          }

          if (best) {
            best.setAttribute('data-dy-export-scroll', '1');
            return {
              type: 'element',
              links: best.querySelectorAll('a[href*="/user/"]').length,
              scrollTop: best.scrollTop,
              scrollHeight: best.scrollHeight,
              clientHeight: best.clientHeight
            };
          }

          const root = document.scrollingElement || document.documentElement;
          return {
            type: 'document',
            links: document.querySelectorAll('a[href*="/user/"]').length,
            scrollTop: root.scrollTop,
            scrollHeight: root.scrollHeight,
            clientHeight: root.clientHeight
          };
        }
        """
    )


def get_scroll_state(page):
    return page.evaluate(
        """
        () => {
          const marked = document.querySelector('[data-dy-export-scroll="1"]');
          const el = marked || document.scrollingElement || document.documentElement;

          return {
            hasMarked: !!marked,
            scrollTop: Number(el.scrollTop || 0),
            scrollHeight: Number(el.scrollHeight || 0),
            clientHeight: Number(el.clientHeight || window.innerHeight || 0)
          };
        }
        """
    )


def collect_users(page):
    rows = page.evaluate(
        """
        () => {
          const anchors = [...document.querySelectorAll('a[href*="/user/"]')];

          return anchors.map(a => {
            let text = (a.innerText || a.textContent || '').trim();

            // 如果 a 本身没有昵称，尝试在附近父级找文本。
            if (!text) {
              const parent = a.closest('li, [role="listitem"], div');
              if (parent) {
                text = (parent.innerText || parent.textContent || '').trim();
              }
            }

            return {
              href: a.href || '',
              text
            };
          });
        }
        """
    )

    users = []

    for row in rows:
        href = (row.get("href") or "").strip()

        if "/user/" not in href:
            continue

        path = urlsplit(href).path

        if not re.search(r"/user/[^/?#]+", path):
            continue

        users.append(
            {
                "name": clean_name(row.get("text") or ""),
                "url": normalize_user_url(href),
            }
        )

    return users


def normal_scroll(page):
    """
    正常滚动：每次约 0.9~1.25 个视窗高度。
    既不会跳太远，也比旧版更快。
    """
    page.evaluate(
        """
        () => {
          const el =
            document.querySelector('[data-dy-export-scroll="1"]') ||
            document.scrollingElement ||
            document.documentElement;

          const step = Math.max(
            600,
            (el.clientHeight || window.innerHeight || 800) * (0.9 + Math.random() * 0.35)
          );

          el.scrollBy({
            top: step,
            behavior: 'auto'
          });
        }
        """
    )


def recovery_scroll(page, stall_level: int):
    """
    长时间没有新增时，不立刻结束。
    用不同方式重新触发无限滚动加载。
    """
    mode = stall_level % 4

    if mode == 0:
        # 直接滚到底
        page.evaluate(
            """
            () => {
              const el =
                document.querySelector('[data-dy-export-scroll="1"]') ||
                document.scrollingElement ||
                document.documentElement;

              el.scrollTo({
                top: el.scrollHeight,
                behavior: 'auto'
              });
            }
            """
        )

    elif mode == 1:
        # 小幅回滚再向下，常能重新触发 IntersectionObserver
        page.evaluate(
            """
            () => {
              const el =
                document.querySelector('[data-dy-export-scroll="1"]') ||
                document.scrollingElement ||
                document.documentElement;

              const h = el.clientHeight || window.innerHeight || 800;

              el.scrollBy({top: -h * 0.35, behavior: 'auto'});
              setTimeout(() => {
                el.scrollBy({top: h * 1.4, behavior: 'auto'});
              }, 120);
            }
            """
        )

    elif mode == 2:
        # 重新标记滚动容器
        detect_scroll_container(page)
        normal_scroll(page)

    else:
        # End 键作为额外兜底
        page.keyboard.press("End")


def export_files(users, suffix="final"):
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    stamp = datetime.now().strftime("%Y-%m-%d_%H%M%S")
    base = OUTPUT_DIR / f"douyin_following_{stamp}_{suffix}"

    rows = list(users.values())

    csv_path = base.with_suffix(".csv")
    json_path = base.with_suffix(".json")
    md_path = base.with_suffix(".md")

    with csv_path.open("w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["name", "url"])
        writer.writeheader()
        writer.writerows(rows)

    with json_path.open("w", encoding="utf-8") as f:
        json.dump(rows, f, ensure_ascii=False, indent=2)

    with md_path.open("w", encoding="utf-8") as f:
        f.write("# 抖音关注列表导出\n\n")
        f.write(f"- 导出时间：{datetime.now().isoformat(timespec='seconds')}\n")
        f.write(f"- 共抓取：{len(rows)} 个账号\n\n")

        for i, row in enumerate(rows, 1):
            name = row["name"] or "（未识别昵称）"
            f.write(f"{i}. [{name}]({row['url']})\n")

    return csv_path, json_path, md_path


def save_checkpoint(users):
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    csv_path = OUTPUT_DIR / "douyin_following_checkpoint.csv"
    json_path = OUTPUT_DIR / "douyin_following_checkpoint.json"

    rows = list(users.values())

    with csv_path.open("w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["name", "url"])
        writer.writeheader()
        writer.writerows(rows)

    with json_path.open("w", encoding="utf-8") as f:
        json.dump(rows, f, ensure_ascii=False, indent=2)


def main():
    WORKDIR.mkdir(parents=True, exist_ok=True)
    PROFILE_DIR.mkdir(parents=True, exist_ok=True)
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    print("\n=== 抖音关注列表导出器 v2 ===\n")
    print("适合关注数很多的账号（例如 4000+）。")
    print()
    print("步骤：")
    print("1. 浏览器会打开抖音。")
    print("2. 你自己登录。")
    print("3. 手动进入自己的“关注”列表。")
    print("4. 确保屏幕上真的出现了一批关注账号。")
    print("5. 回终端按 Enter。\n")
    print("运行中如果你想提前停：按 Ctrl+C。")
    print("脚本会尽量保存当前已经抓到的数据。\n")

    users = {}
    last_checkpoint_count = 0

    with sync_playwright() as p:
        context = p.chromium.launch_persistent_context(
            user_data_dir=str(PROFILE_DIR),
            headless=False,
            viewport={"width": 1280, "height": 900},
            args=["--disable-blink-features=AutomationControlled"],
        )

        page = context.pages[0] if context.pages else context.new_page()

        try:
            page.goto("https://www.douyin.com/", wait_until="domcontentloaded")
        except Exception:
            pass

        input("准备好后按 Enter 开始导出：")

        info = detect_scroll_container(page)

        print(
            f"\n已检测滚动区域：{info.get('type')}，"
            f"当前区域 user 链接约 {info.get('links', 0)} 个。\n"
        )

        no_new_rounds = 0
        best_count = 0

        try:
            for round_no in range(1, MAX_ROUNDS + 1):
                before = len(users)

                current = collect_users(page)

                for item in current:
                    url = item["url"]

                    if not url:
                        continue

                    if url not in users:
                        users[url] = item
                    elif not users[url]["name"] and item["name"]:
                        users[url]["name"] = item["name"]

                after = len(users)
                added = after - before

                if after > best_count:
                    best_count = after

                if added == 0:
                    no_new_rounds += 1
                else:
                    no_new_rounds = 0

                # 自动 checkpoint
                if after - last_checkpoint_count >= CHECKPOINT_EVERY_NEW_USERS:
                    save_checkpoint(users)
                    last_checkpoint_count = after

                state = get_scroll_state(page)

                max_scroll = max(
                    0,
                    state["scrollHeight"] - state["clientHeight"]
                )

                pct = (
                    (state["scrollTop"] / max_scroll * 100)
                    if max_scroll > 0
                    else 0
                )

                print(
                    f"\r"
                    f"轮次 {round_no:04d} | "
                    f"已收集 {after:5d} | "
                    f"本轮 +{added:3d} | "
                    f"无新增 {no_new_rounds:02d}/{NO_NEW_LIMIT} | "
                    f"滚动 {pct:5.1f}%",
                    end="",
                    flush=True,
                )

                if no_new_rounds >= NO_NEW_LIMIT:
                    print(
                        "\n\n连续多轮没有新增，判断可能已经到底，停止。"
                    )
                    break

                if no_new_rounds == 0:
                    normal_scroll(page)
                    time.sleep(
                        random.uniform(
                            WAIT_NORMAL_MIN,
                            WAIT_NORMAL_MAX
                        )
                    )
                else:
                    # 停滞后降低速度，给抖音更多加载时间
                    recovery_scroll(page, no_new_rounds)

                    time.sleep(
                        random.uniform(
                            WAIT_STALL_MIN,
                            WAIT_STALL_MAX
                        )
                    )

                    # 滚动容器 DOM 可能被重建
                    if no_new_rounds in {5, 10, 20, 30}:
                        detect_scroll_container(page)

            else:
                print(
                    f"\n\n已达到最大轮次 {MAX_ROUNDS}。"
                )

        except KeyboardInterrupt:
            print("\n\n收到 Ctrl+C，正在保存当前结果……")

        except Exception as e:
            print(f"\n\n运行时出现异常：{type(e).__name__}: {e}")
            print("正在保存目前已经抓到的数据……")

        finally:
            if users:
                save_checkpoint(users)

                csv_path, json_path, md_path = export_files(
                    users,
                    suffix="final"
                )

                print(f"\n共保存 {len(users)} 个关注账号：")
                print(f"CSV : {csv_path}")
                print(f"JSON: {json_path}")
                print(f"MD  : {md_path}")
                print()
                print("同时还有持续覆盖保存的 checkpoint：")
                print(OUTPUT_DIR / "douyin_following_checkpoint.csv")
                print(OUTPUT_DIR / "douyin_following_checkpoint.json")
            else:
                print(
                    "\n没有抓到任何用户。请确认你已经打开了关注列表。"
                )

            print("\n浏览器登录状态仍保存在：")
            print(PROFILE_DIR)

            try:
                input("\n按 Enter 关闭浏览器：")
            except KeyboardInterrupt:
                pass

            context.close()


if __name__ == "__main__":
    main()
