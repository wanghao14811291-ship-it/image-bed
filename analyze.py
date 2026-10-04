#!/usr/bin/env python3
# ============================================================
# analyze.py - 让编程类 AI (如 Codex) 在沙箱里直接“看”图
# 用法:  python analyze.py images/2026-10/xxx.png
# 依赖:  Pillow (pip install pillow)；OCR 可选 pytesseract
# ============================================================
import sys

def main():
    if len(sys.argv) < 2:
        print("用法: python analyze.py <图片路径> [图片路径2 ...]")
        return 1

    try:
        from PIL import Image
    except ImportError:
        print("缺少 Pillow，请先运行: pip install pillow")
        return 1

    for path in sys.argv[1:]:
        print("=" * 60)
        print("图片:", path)
        try:
            im = Image.open(path)
        except Exception as e:
            print("打开失败:", e)
            continue
        print("尺寸: %dx%d  模式: %s  格式: %s" % (im.width, im.height, im.mode, im.format))

        # 主色调(缩小后取平均色)，帮助判断画面明暗/类型
        small = im.convert("RGB").resize((1, 1))
        print("平均色 RGB:", small.getpixel((0, 0)))

        # 可选 OCR：提取图中文字(中英文)
        try:
            import pytesseract
            text = pytesseract.image_to_string(im, lang="chi_sim+eng")
            print("--- OCR 文字(若有) ---")
            print(text.strip() if text.strip() else "(未识别到文字)")
        except Exception:
            print("(OCR 不可用；如需识别文字可 pip install pytesseract 并安装 tesseract)")

        # 另存一张缩小版，便于快速查看/二次分析
        try:
            thumb = im.copy()
            thumb.thumbnail((1024, 1024))
            out = path.rsplit(".", 1)[0] + ".thumb.jpg"
            thumb.convert("RGB").save(out, quality=85)
            print("缩小版已保存:", out)
        except Exception as e:
            print("缩小版保存失败:", e)

    return 0

if __name__ == "__main__":
    sys.exit(main())
