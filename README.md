# rom-hamster

游戏 ROM 的收集、整理、元数据与资源全生命周期管理工具。纯 Bash 编写，兼容 Debian/Ubuntu（标准 `.deb` 安装）与 macOS（源码树运行），同时提供命令行子命令、交互式菜单与基于 zenity 的图形界面（GUI）。

> 本仓库为 Gitee 源仓库的 GitHub 镜像，由 GitHub Actions 每 30 分钟自动同步。提交代码请前往 Gitee：<https://gitee.com/goddog312/rom-hamster>

## 特性

- **标准 Debian 软件包**：FHS 安装（`/usr/bin`、`/usr/lib/rom-hamster`、`/usr/share`、`/etc/rom-hamster`），含 freedesktop 桌面入口与多尺寸图标，应用菜单点击即启动
- **单游戏独立目录 + 按类型分子目录**，内部结构可整体迁移，导出完全符合 [EmulationStation](https://emulationstation.org/) 标准
- **多碟游戏原生支持**：自动识别 `Disc N` / `Side A-B`，同主名合并，自动维护 m3u
- **No-Intro / Redump DAT 精确匹配**：CRC32（默认）/ MD5 / SHA1 哈希校验，自动填充官方元数据，标记 good/baddump/nodump；街机 ZIP 内多文件逐个匹配
- **全类型补丁管理**（只存储关联，**绝不自动打补丁/安装**）
- **压缩包智能三级分流**：纯补丁包（不解压直接入库）→ 街机标准多文件 ZIP（保留原 ZIP）→ 二义性/普通/混合包（确认或解压遍历）
- **全维度检索** 与 **EmulationStation 导出**（m3u 可见主条目 + hidden 单碟条目，卡带可选 ZIP/7Z 压缩）

## 安装

```bash
sudo dpkg -i rom-hamster_1.0.0_all.deb
sudo apt install -f
```

从源码构建：`./build.sh`（产物 `dist/rom-hamster_1.0.0_all.deb`）。macOS 可直接运行 `./rom-hamster-1.0.0/usr/bin/rom-hamster` 或执行 `./install.sh`。

## 命令

```bash
rom-hamster menu                 # 交互式菜单（--gui 为图形界面）
rom-hamster init --root /ROMs    # 初始化
rom-hamster import <文件/目录> -y # 导入
rom-hamster list / search / show <ID> / edit <ID> / delete <ID> [-y]
rom-hamster export /ES/roms --media --compress
rom-hamster stats / config
```

## 许可

MIT
