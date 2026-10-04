#!/usr/bin/env python3
# ============================================================
# purge.py - 由 GitHub Actions 每小时调用
# 删除仓库中最后一次提交时间超过 3 小时的图片，并自动提交
# ============================================================
import os
import subprocess
import time

MAX_AGE = 3 * 3600      # 3 小时
IMAGES_DIR = "images"


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


def main():
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

    run(["git", "config", "user.name", "github-actions[bot]"])
    run(["git", "config", "user.email",
         "41898282+github-actions[bot]@users.noreply.github.com"])
    run(["git", "add", "-A"])
    c = run(["git", "commit", "-m", "auto-purge: remove images older than 3 hours"])
    print(c.stdout.strip(), c.stderr.strip())
    p = run(["git", "push"])
    print(p.stdout.strip(), p.stderr.strip())
    if p.returncode != 0:
        return 1
    print("purge complete")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
