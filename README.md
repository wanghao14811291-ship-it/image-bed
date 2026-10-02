# image-bed — 永久免费图床

用 GitHub 公开仓库存放图片，生成永久直链给 AI（多模态）查看。

## 链接格式

假设图片路径为 `images/2026-10/xxx.png`：

- **RAW 直链（发给 AI，推荐；海外访问最稳）**
  `https://raw.githubusercontent.com/wanghao14811291-ship-it/image-bed/main/images/2026-10/xxx.png`
- **国内镜像（国内浏览器直接打开）**
  `https://cdn.jsdmirror.com/gh/wanghao14811291-ship-it/image-bed@main/images/2026-10/xxx.png`
- **GCORE 备用镜像**
  `https://gcore.jsdelivr.net/gh/wanghao14811291-ship-it/image-bed@main/images/2026-10/xxx.png`

## 使用方法（Windows）

1. 把要上传的图片放进桌面 `图床\待上传` 文件夹（数量不限）；
2. 双击桌面 `图床\双击上传.bat`；
3. 脚本自动上传，RAW 链接自动复制到剪贴板，并显示在窗口中；
4. 历史链接保存在桌面 `图床\links.txt`。

也可以直接把图片（或含图片的文件夹）拖到 `双击上传.bat` 图标上上传。

## 说明

- 支持格式：png / jpg / jpeg / gif / webp / bmp / svg
- 单文件建议 < 50MB；GitHub 单文件硬上限 100MB
- 仓库请保持 Public，否则直链无法匿名访问
- jsDelivr 对同名文件的更新有缓存；新文件首次打开即自动回源，无需处理
