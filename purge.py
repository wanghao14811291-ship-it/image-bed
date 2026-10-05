#!/usr/bin/env python3
# ============================================================
# purge.py - 由 GitHub Actions 每小时调用
# 删除仓库中最后一次提交时间超过 3 小时的图片，并自动提交
# 推送前自动同步远端；若期间有新上传，自动变基并重试
# ============================================================
import os
import subprocess
import sys
import time

MAX_AGE = 3 * 3600      # 3 小时
IMAGES_DIR = "images"
PUSH_RETRIES = 3


def run(cmd, check=False):
    print("+ " + " ".join(cmd), flush=True)
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.stdout:
        print(p.stdout, end="", flush=True)
    if p.stderr:
        print(p.stderr, end="", file=sys.stderr, flush=True)
    if check and p.returncode != 0:
        raise SystemExit(p.returncode)
    return p


def current_branch():
    return subprocess.check_output(
        ["git", "rev-parse", "--abbrev-ref", "HEAD"], text=True
    ).strip()


def sync_with_remote(branch):
    """把本地提交变基到远端最新版本，避免和用户上传互相覆盖。"""
    if run(["git", "fetch", "origin", branch]).returncode != 0:
        print("fetch remote failed", file=sys.stderr)
        return False

    if run(["git", "rebase", f"origin/{branch}"]).returncode != 0:
        print("rebase failed; aborting rebase", file=sys.stderr)
        run(["git", "rebase", "--abort"])
        return False

    return True


def push_with_retry(branch):
    for attempt in range(1, PUSH_RETRIES + 1):
        print(f"purge push attempt {attempt}/{PUSH_RETRIES}", flush=True)
        if not sync_with_remote(branch):
            return False

        if run(["git", "push", "origin", branch]).returncode == 0:
            return True

        if attempt < PUSH_RETRIES:
            time.sleep(2)

    return False


def main():
    branch = current_branch()

    run(["git", "config", "user.name", "github-actions[bot]"])
    run(["git", "config", "user.email",
         "41898282+github-actions[bot]@users.noreply.github.com"])

    # 开始扫描前先尽量同步到最新，减少工作流排队/定时延迟造成的分叉
    if not sync_with_remote(branch):
        return 1

    now = int(time.time())
    changed = False

    for root, _, files in os.walk(IMAGES_DIR):
        for fn in files:
            path = os.path.relpath(os.path.join(root, fn))
            r = run(["git", "log", "-1", "--format=%ct", "--", path])
            try:
                ts = int(r.stdout.strip() or "0")
            except ValueError:
                ts = 0
            if ts and now - ts > MAX_AGE:
                print("delete:", path)
                os.remove(path)
                changed = True

    # 清理空目录
    for root, _, _ in os.walk(IMAGES_DIR, topdown=False):
        if os.path.isdir(root) and not os.listdir(root):
            os.rmdir(root)

    if not changed:
        print("nothing to purge")
        return 0

    run(["git", "add", "-A"], check=True)
    c = run(["git", "commit", "-m", "auto-purge: remove images older than 3 hours"])
    if c.returncode != 0:
        return c.returncode

    if not push_with_retry(branch):
        return 1

    print("purge complete")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
