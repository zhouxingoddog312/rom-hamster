# rom-hamster

游戏 ROM 的收集、整理、元数据与资源全生命周期管理工具。纯 Bash 编写，兼容 Debian/Ubuntu（标准 `.deb` 安装）与 macOS（源码树运行），同时提供命令行子命令、交互式菜单与基于 zenity 的图形界面（GUI）。

## 特性

- **标准 Debian 软件包**：FHS 安装（`/usr/bin`、`/usr/lib/rom-hamster`、`/usr/share`、`/etc/rom-hamster`），含 freedesktop 桌面入口与多尺寸图标，应用菜单点击即启动
- **单游戏独立目录 + 按类型分子目录**，内部结构可整体迁移
- **三前端双向兼容**：
  - **导入**：直接指向一个已有的 EmulationStation / ES-DE / Pegasus ROM 目录，自动识别 `gamelist.xml` 或 `metadata.pegasus.txt`，连同 ROM、封面、截图、视频、横幅、合成图一并入库，无需逐文件添加
  - **导出**：生成 EmulationStation（原版）、ES-DE、或 Pegasus 标准目录；多碟游戏 ES 用 m3u + hidden 条目，Pegasus 每碟独立 game 块
  - 平台目录名自动双向映射（如 ES 的 `psx` ↔ Pegasus 的 `Sony PlayStation`）
- **~90 个内置平台**：任天堂全系列（含 FDS/GB 家族/N64DD/Satellaview/VB/3DS/Switch）、世嘉全系列（含 GameGear/SMS/32X/Naomi/Model3/ST-V/Atomiswave）、Atari 全系列、Commodore 全系列（C64/Amiga/CD32）、NEC 全系列（PC-Engine/CD/PC-FX/SuperGrafx/PC-88/98）、街机基板（CPS1/2/3/Triforce/Daphne/MAME/FBNeo）、家用电脑（ZX Spectrum/MSX/Amstrad/BBC/X68000）、模拟引擎（ScummVM/OpenBOR/Doom/EasyRPG/CHIP-8/PICO-8/TIC-80/WASM-4）
- **多碟游戏原生支持**：自动识别 `Disc N` / `Disk A-B` / `Side A-B` / `CD 1-2`，同主名合并，自动维护 m3u
- **No-Intro / Redump DAT 精确匹配**：CRC32（默认）/ MD5 / SHA1 哈希校验，自动填充官方元数据，标记 good/baddump/nodump；街机 ZIP 内多文件逐个匹配
- **全类型补丁管理**（只存储关联，**绝不自动打补丁/安装**）：
  - 通用字节补丁：`.ips .bps .ups .ppf .xdelta .xdelta3 .patch .ips32`
  - 平台专属更新/DLC：`.cia .nsp .nsz .xci .pkg .wad .wud .wux .vpk .3dsx ...`
  - 补丁压缩包整体保留
  - 二义性格式（`.cia/.nsp/.pkg/.wad ...`）一律弹窗由你决定「本体 / 补丁」
- **压缩包智能三级分流**：纯补丁包（不解压直接入库）→ 街机标准多文件 ZIP（保留原 ZIP）→ 二义性/普通/混合包（确认或解压遍历）
- **单游戏详情**：ROM、封面、截图、视频、横幅、合成图、说明、补丁的存在/缺失一目了然
- **全维度检索**：平台/类型/厂商/年份/地区/评分/标签/多碟/ROM 状态/补丁类型/存储格式 + 关键词，多字段排序
- **CSV 元数据库**：内存缓存 + 批量落盘，数千条库批量导入无卡顿；flock 防并发写坏
- **库完整性检测**：整个存储目录视为整体游戏库，核对 `romhamsterdb.csv` 记录与各平台子目录 ROM/媒体文件一一对应；孤儿记录（记录存在、文件缺失）确认后仅删数据库记录、未入库目录提示导入、未登记文件提示附属文件流程
- **存储目录智能切换**：设置/更改 ROM 主存储目录时，空目录=新建空库，已有库=自动执行完整性检测后按需修正 CSV（原库保留原位，不再自动迁移）
- **自动化测试**：`tests/run_tests.sh` 覆盖 CSV/碟片解析/平台规则/数据库/库完整性/工具函数 76 断言

## 安装

### Debian / Ubuntu（推荐）

```bash
# 缺依赖时执行 sudo apt install -f 补全
sudo dpkg -i rom-hamster_1.0.0_all.deb
sudo apt install -f
```

安装后：

- 命令行全局可用 `rom-hamster`
- 应用菜单出现 **ROM Hamster**，点击在终端中打开交互菜单
- 系统配置：`/etc/rom-hamster/rom-hamster.conf`（conffile，升级保留你的修改）
- 普通卸载：`sudo dpkg -r rom-hamster`；完全卸载（含系统配置）：`sudo dpkg -P rom-hamster`
- 用户 ROM 库、`~/.rom-hamster.conf`、`~/.cache/rom-hamster` 在任何卸载方式下都不会被删除

### 从源码构建 deb

```bash
git clone https://gitee.com/goddog312/rom-hamster.git
cd rom-hamster
./build.sh                     # 产物：dist/rom-hamster_1.0.0_all.deb
```

### macOS / 其它发行版（源码树运行）

```bash
# 依赖：bash 4+、coreutils、findutils、grep、sed、gawk、zip/unzip、zenity、p7zip
# （程序首次启动会自动按系统包管理器安装缺失的依赖；以下为手动安装示例）
brew install bash coreutils findutils grep gawk zip unzip zenity p7zip
# 直接从源码树运行（自动按相对路径加载模块与数据）
./rom-hamster-1.0.0/usr/bin/rom-hamster help
# 或安装到 ~/.local（PREFIX=/usr/local ./install.sh 可装到系统目录）
./install.sh
```

### 依赖自动安装支持的系统

依赖检测与安装函数会识别系统包管理器并自动安装缺失组件（必装缺失→自动安装、失败报错退出；建议组件缺失→自动安装、失败仅提示），无需手工干预：

| 系统 | 包管理器 | 示例 |
|---|---|---|
| Debian / Ubuntu | `apt` | `sudo apt-get install -y bash coreutils findutils ...` |
| Fedora / RHEL | `dnf` | `sudo dnf install -y ...` |
| Arch Linux | `pacman` | `sudo pacman -S --noconfirm ...` |
| macOS (Homebrew) | `brew` | `brew install ...` |
| Entware（QNAP NAS 等） | `opkg` | `opkg install ...`（装到 `/opt`，无需 sudo） |

> 注：macOS 系统自带 bash 3.2 不满足程序要求（需 bash 4+），请用 `brew install bash` 安装新版；Entware 标准版不内置 busybox，`bash` 等基础命令需用 `opkg` 补齐。未识别到包管理器的系统会提示手动安装。

## 命令

```bash
rom-hamster menu                 # 交互式菜单（默认；加 --gui 为图形界面）
rom-hamster init --root /ROMs    # 初始化（首次运行也会引导）
rom-hamster import <文件/目录> -y # 导入：文件、多文件、递归目录、ZIP/7Z/RAR
                                  # 目录含 gamelist.xml 或 metadata.pegasus.txt 时自动按整库识别
rom-hamster list [筛选]          # 列表；search <词> 搜索；show <ID> 详情
rom-hamster edit <ID>            # 编辑元数据（改名/换平台会联动移动文件）
rom-hamster delete <ID> [-y]     # 删除游戏
rom-hamster export /目标/目录 --frontend es|esde|pegasus --media --compress
rom-hamster stats                # 统计概览
rom-hamster config               # 查看各级配置与路径
rom-hamster menu                 # 交互菜单 → 设置：更改存储目录 / 依赖检测与安装 / 库完整性检测
rom-hamster --help / --version
```

## 配置体系（优先级从低到高）

1. 代码内置默认值
2. 内置平台规则库 `/usr/share/rom-hamster/platforms.conf`（随包升级覆盖）
3. 系统配置 `/etc/rom-hamster/rom-hamster.conf`（升级保留）
4. 用户配置 `~/.rom-hamster.conf`（首次运行从模板生成，优先级最高）
5. 命令行参数

用户配置为 shell 风格，支持引号与 `$HOME` / `$ROM_ROOT` 变量，例如：

```bash
ROM_ROOT="$HOME/roms"
dat_dir="$ROM_ROOT/dats"
duplicate_check_threshold=70
dat_match_hash="crc32"
# 自定义/覆盖平台规则：
# platform_nes=".nes;.unf;compress_supported=true;recommended_format=zip;arcade=false;patch_formats=.ips;.bps;ambiguous_formats="
```

## 目录与数据

```
ROM_ROOT/
├── <平台>/<游戏目录>/
│   ├── rom/            # ROM（多碟 + m3u；街机 ZIP；二义性格式）
│   ├── covers/ screenshots/ videos/ marquees/ miximages/
│   ├── intro/          # 说明文本
│   └── patcher/        # 通用补丁、平台专属补丁/DLC、补丁压缩包
├── dats/               # No-Intro / Redump DAT
└── romhamsterdb.csv    # 元数据库（RFC 4180，随库迁移）

~/.cache/rom-hamster/   # 临时文件，异常退出自动清理
```

- 家用机 ROM 命名遵循 No-Intro/Redump：`<主名> (Disc N).ext`；媒体为 `<主名>-image/-shotN/-video/-marquee/-mix/-intro.ext`
- 街机 ROM 保留 MAME/FBNeo 标准 ZIP 文件名
- 补丁只归集、不执行；平台专属补丁请用对应平台专用工具安装

### 库完整性检测

整个存储目录视为一个整体游戏库。在「设置 → 库完整性检测」（或更改主存储目录时对已有库自动执行）会核对 CSV 记录与磁盘文件：

- **孤儿记录**：数据库有记录但 ROM/媒体文件已缺失 → 确认后仅删除数据库记录，不动磁盘
- **未入库目录**：磁盘有 ROM 但数据库无记录 → 提示用"添加"导入
- **未登记文件**：已入库游戏目录内存在但数据库未登记 → 提示可走附属文件流程

更改主存储目录时：目标为空目录 → 新建空库；目标已有 `romhamsterdb.csv` → 切换过去并提示执行完整性检测。原库保留原位，不再自动迁移。

## 测试

```bash
bash tests/run_tests.sh     # 纯函数单元测试（CSV/碟片/平台规则/DB/库完整性/工具），76 断言
```

## 软件包内容

```
/usr/bin/rom-hamster
/usr/lib/rom-hamster/lib/{common,config,db,ui,archive,dat,import,manage,export,library}.sh
/usr/share/rom-hamster/platforms.conf
/usr/share/rom-hamster/templates/rom-hamster.conf.template
/usr/share/applications/rom-hamster.desktop
/usr/share/icons/hicolor/{16x16,32x32,48x48,256x256,scalable}/apps/rom-hamster.{png,svg}
/usr/share/doc/rom-hamster/{README.md,changelog}
/etc/rom-hamster/rom-hamster.conf
```

## 许可

MIT
