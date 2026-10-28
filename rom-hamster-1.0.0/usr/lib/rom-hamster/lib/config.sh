# config.sh — 配置分层加载与平台规则查询
# rom-hamster 的函数库模块，由 /usr/bin/rom-hamster 加载
# shellcheck shell=bash

CONFIG_FILE="$HOME/.rom-hamster.conf"

# 运行期配置（load_config 填充）
ROM_ROOT=""
AUTO_DELETE_SOURCE="false"
DUP_THRESHOLD="70"
ARCHIVE_EXPORT_FORMAT="zip"
DAT_DIR=""
DAT_HASH="crc32"
DAT_AUTO_MULTI="true"
AUTO_M3U="true"
EXPORT_HIDDEN_DISCS="true"
DISC_PREFIX="Disc"

declare -A MEDIA_DIR=()
declare -A MEDIA_EXTS=()
ARCADE_SUFFIXES=""
ARCHIVE_EXTS=""
GENERIC_PATCH_EXTS=""

declare -a PLATFORMS=()
declare -A PLAT_EXTS=()
declare -A PLAT_COMPRESS=()
declare -A PLAT_REC=()
declare -A PLAT_ARCADE=()
declare -A PLAT_PATCH=()
declare -A PLAT_AMBIG=()
declare -A PLAT_ALIASES=()


write_default_config() { # 从模板生成用户配置；$1 为初始 ROM_ROOT（可空）
  local root="${1:-}" tpl="$RH_DATA_DIR/templates/rom-hamster.conf.template"
  if [ -f "$tpl" ]; then
    sed "s#^ROM_ROOT=.*#ROM_ROOT=\"$root\"#; s#^dat_dir=.*#dat_dir=\"\$ROM_ROOT/dats\"#" "$tpl" > "$CONFIG_FILE"
  else
    cat >"$CONFIG_FILE" <<EOF
ROM_ROOT="$root"
dat_dir="\$ROM_ROOT/dats"
archive_extensions=".zip;.7z;.rar"
archive_compress_export_format="zip"
duplicate_check_threshold=70
dat_match_hash="crc32"
dat_auto_match_multi_disc=true
auto_generate_m3u=true
export_hidden_discs=true
disc_label_prefix="Disc"
auto_delete_source=false
EOF
  fi
  log "[rom-hamster] 已生成用户配置：$CONFIG_FILE"
}



_conf_unquote() {
  local v=$1
  case "$v" in
    \"*\") v=${v#\"}; v=${v%\"} ;;
    \'*\') v=${v#\'}; v=${v%\'} ;;
  esac
  printf '%s' "$v"
}

_conf_expand() {
  local v=$1
  v=${v//\$\{HOME\}/$HOME}; v=${v//\$HOME/$HOME}
  v=${v//\$\{ROM_ROOT\}/$ROM_ROOT}; v=${v//\$ROM_ROOT/$ROM_ROOT}
  printf '%s' "$v"
}

_conf_code_defaults() {
  MEDIA_DIR=([rom]=rom [covers]=covers [screenshots]=screenshots [videos]=videos \
             [marquees]=marquees [miximages]=miximages [intro]=intro [patcher]=patcher)
  MEDIA_EXTS=([covers]=".jpg .jpeg .png .webp" [screenshots]=".jpg .jpeg .png .webp" \
              [videos]=".mp4 .webm .mkv .avi" [marquees]=".png .jpg .jpeg .webp" \
              [miximages]=".png .jpg .jpeg .webp" [intro]=".txt .md" \
              [patcher_generic]=".ips .bps .ups .ppf .xdelta .xdelta3 .patch .ips32")
  ARCADE_SUFFIXES=".rom .bin .chr .prg .snd .vram .m68k .z80 .gfx"
  ARCHIVE_EXTS=".zip .rar .7z"
  GENERIC_PATCH_EXTS=${MEDIA_EXTS[patcher_generic]}
}

_conf_add_platform() {
  local pname=$1 pbody=$2
  local compress=true rec=raw arcade=false patches="" ambig="" rom_exts="" aliases=""
  local IFS_SAVE=$IFS; IFS=';'
  local parts=($pbody); IFS=$IFS_SAVE
  local segmode=rom part fld fval
  for part in "${parts[@]}"; do
    part=$(trim "$part"); [ -z "$part" ] && continue
    if [[ "$part" == *=* ]]; then
      fld=${part%%=*}; fval=${part#*=}
      case "$fld" in
        compress_supported) compress=$fval; segmode=meta ;;
        recommended_format) rec=$fval; segmode=meta ;;
        arcade) arcade=$fval; segmode=meta ;;
        patch_formats) segmode=patch ;;
        ambiguous_formats) segmode=ambig ;;
        aliases) aliases=$fval; segmode=meta ;;
        *) segmode=meta ;;
      esac
    else
      case "$segmode" in
        rom|*) rom_exts+="$part " ;;
      esac
    fi
  done
  patches=$(printf '%s' "$pbody" | awk '{
    if (match($0, /patch_formats=/)) {
      s=substr($0, RSTART+RLENGTH);
      sub(/ambiguous_formats=.*/, "", s);
      sub(/;compress_supported.*$/, "", s);
      printf "%s", s
    }}')
  ambig=$(printf '%s' "$pbody" | awk '{
    if (match($0, /ambiguous_formats=/)) printf "%s", substr($0, RSTART+RLENGTH)}')
  # 已存在则覆盖（自定义平台覆盖内置），否则追加
  local found=0 p
  for p in "${PLATFORMS[@]:-}"; do [ "$p" = "$pname" ] && found=1; done
  [ "$found" = "0" ] && PLATFORMS+=("$pname")
  PLAT_EXTS[$pname]=$(printf '%s' "$rom_exts" | tr '[:upper:]' '[:lower:]' | tr -s ' ' | sed 's/^ //;s/ $//')
  PLAT_COMPRESS[$pname]=$compress
  PLAT_REC[$pname]=$rec
  PLAT_ARCADE[$pname]=$arcade
  PLAT_PATCH[$pname]=$(_semicolon_to_spaces "$patches")
  PLAT_AMBIG[$pname]=$(_semicolon_to_spaces "$ambig")
  PLAT_ALIASES[$pname]=$(printf '%s' "$aliases" | tr ',' ' ' | tr -s ' ' | sed 's/^ //;s/ $//')
}

_parse_conf_file() {
  local file=$1
  [ -f "$file" ] || return 0
  local section="" line key val
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}; line=$(trim "$line")
    [[ -z "$line" || "$line" == \#* ]] && continue
    if [[ "$line" =~ ^\[(.+)\]$ ]]; then
      section=${BASH_REMATCH[1]}; continue
    fi
    if [ "$section" = "platform_extensions" ] && [[ "$line" == *:* ]]; then
      _conf_add_platform "$(trim "${line%%:*}")" "${line#*:}"
      continue
    fi
    case "$section" in
      arcade_rom_suffixes)
        [[ "$line" != *"="* ]] && ARCADE_SUFFIXES=$(_semicolon_to_spaces "$line") ; continue ;;
      archive_extensions)
        [[ "$line" != *"="* ]] && ARCHIVE_EXTS=$(_semicolon_to_spaces "$line") ; continue ;;
      media_type_dirs)
        if [[ "$line" == *=* ]]; then key=$(trim "${line%%=*}"); val=$(_conf_unquote "${line#*=}"); MEDIA_DIR[$key]=$(trim "$val"); fi
        continue ;;
      media_suffix_rules)
        if [[ "$line" == *=* ]]; then key=$(trim "${line%%=*}"); val=$(_conf_unquote "${line#*=}"); MEDIA_EXTS[$key]=$(_semicolon_to_spaces "$val"); fi
        continue ;;
    esac
    # 顶层 KEY=value（shell 风格，允许引号、$HOME/$ROM_ROOT）
    if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
      key=${line%%=*}; val=$(_conf_unquote "${line#*=}"); val=$(_conf_expand "$val"); val=$(trim "$val")
      case "$key" in
        ROM_ROOT) ROM_ROOT=$(expand_path "$val") ;;
        auto_delete_source) AUTO_DELETE_SOURCE=$val ;;
        duplicate_check_threshold) DUP_THRESHOLD=$val ;;
        archive_compress_export_format) ARCHIVE_EXPORT_FORMAT=$val ;;
        dat_dir) DAT_DIR=$(expand_path "$val") ;;
        dat_match_hash) DAT_HASH=$val ;;
        dat_auto_match_multi_disc) DAT_AUTO_MULTI=$val ;;
        auto_generate_m3u) AUTO_M3U=$val ;;
        export_hidden_discs) EXPORT_HIDDEN_DISCS=$val ;;
        disc_label_prefix) DISC_PREFIX=$val ;;
        archive_extensions) ARCHIVE_EXTS=$(_semicolon_to_spaces "$val") ;;
        arcade_rom_suffixes) ARCADE_SUFFIXES=$(_semicolon_to_spaces "$val") ;;
        platform_*) _conf_add_platform "${key#platform_}" "$val" ;;
      esac
    fi
  done <"$file"
}

load_config() {
  PLATFORMS=()
  PLAT_EXTS=(); PLAT_COMPRESS=(); PLAT_REC=(); PLAT_ARCADE=(); PLAT_PATCH=(); PLAT_AMBIG=(); PLAT_ALIASES=()
  MEDIA_DIR=(); MEDIA_EXTS=()
  _conf_code_defaults
  _parse_conf_file "$RH_DATA_DIR/platforms.conf"
  [ -n "${RH_SYS_CONF:-}" ] && _parse_conf_file "$RH_SYS_CONF"
  _parse_conf_file "$CONFIG_FILE"
  if [ -z "$ROM_ROOT" ]; then
    DAT_DIR=""
  elif [ -z "${DAT_DIR:-}" ] || [ "$DAT_DIR" = "/dats" ]; then
    DAT_DIR="$ROM_ROOT/dats"
  fi
  GENERIC_PATCH_EXTS=${MEDIA_EXTS[patcher_generic]:-$GENERIC_PATCH_EXTS}
}



print_config() {
  cat <<EOF
rom-hamster $VERSION
内置规则库：$RH_DATA_DIR/platforms.conf
系统配置：${RH_SYS_CONF:-（无）}
用户配置：$CONFIG_FILE
ROM 主存储目录：${ROM_ROOT:-（未设置）}
元数据库：${ROM_ROOT:+$ROM_ROOT/romhamsterdb.csv}
DAT 目录：${DAT_DIR:-}
哈希算法：$DAT_HASH    重复阈值：$DUP_THRESHOLD%    自动删源：$AUTO_DELETE_SOURCE
自动 m3u：$AUTO_M3U    导出隐藏碟片条目：$EXPORT_HIDDEN_DISCS
已配置平台（${#PLATFORMS[@]}）：${PLATFORMS[*]}
EOF
}



persist_config_key() { # key value
  local key=$1 val=$2 tmp
  tmp=$(mktemp "${CONFIG_FILE}.XXXXXX")
  awk -v k="$key" -v v="$val" '
    BEGIN{p=0}
    substr($0,1,length(k)+1)==k"=" {print k"="v; p=1; next}
    {print}
    END{if(!p) print k"="v}' "$CONFIG_FILE" >"$tmp" && mv -f "$tmp" "$CONFIG_FILE"
}



ensure_ready() {
  [ -f "$CONFIG_FILE" ] || write_default_config ""
  load_config
  if [ -z "$ROM_ROOT" ]; then
    local def="$HOME/ROMs" r
    if [ "$NONINTERACTIVE" = "true" ]; then r=$def
    elif [ "$GUI" = "1" ]; then
      ensure_zenity || die "需要 zenity 才能使用 GUI 模式"
      r=$(zenity --file-selection --directory --save --title="选择/新建 ROM 主存储目录" --filename="$def/" 2>/dev/null) || die "已取消"
    else
      read -r -p "首次运行，请设置 ROM 主存储目录 [$def]: " r
      r=${r:-$def}
    fi
    r=$(expand_path "$r")
    mkdir -p "$r" || die "无法创建目录：$r"
    ROM_ROOT=$r
    persist_config_key ROM_ROOT "$r"
    DAT_DIR="$r/dats"
  fi
  if [ ! -d "$ROM_ROOT" ]; then
    if ui_confirm "ROM 主存储目录不存在：$ROM_ROOT ，是否创建？" y; then
      mkdir -p "$ROM_ROOT" || die "无法创建目录：$ROM_ROOT"
    else die "ROM 主存储目录无效：$ROM_ROOT"; fi
  fi
  db_ensure
}



ext_platforms() {
  local e
  e=$(lower "$1")
  local p out=""
  for p in "${PLATFORMS[@]}"; do
    local exts=" ${PLAT_EXTS[$p]} "
    case "$exts" in *" $e "*) out+="$p " ;; esac
  done
  printf '%s' "${out% }"
}



is_arcade_plat() { [ "${PLAT_ARCADE[$1]:-false}" = "true" ]; }


# 前端目录名约定表：规范ID -> "es:esde:pegasus" 三段目录名
# es 与 esde 基本一致；pegasus 用 "厂商 主机名" 风格
FRONTEND_DIRNAMES='
nes:nes:nes:Nintendo Entertainment System
snes:snes:snes:Super Nintendo Entertainment System
n64:n64:n64:Nintendo 64
gb:gb:gb:Nintendo Game Boy
gbc:gbc:gbc:Nintendo Game Boy Color
gba:gba:gba:Nintendo Game Boy Advance
ngp:ngp:ngp:SNK Neo Geo Pocket
ngpc:ngpc:ngpc:SNK Neo Geo Pocket Color
wswan:wswan:wswan:Bandai WonderSwan
pcengine:pcengine:pcengine:NEC PC Engine
ngcd:ngcd:ngcd:SNK Neo Geo CD
megadrive:megadrive:megadrive:Sega Mega Drive
segacd:segacd:segacd:Sega CD
saturn:saturn:saturn:Sega Saturn
dreamcast:dreamcast:dreamcast:Sega Dreamcast
psx:psx:psx:Sony PlayStation
ps2:ps2:ps2:Sony PlayStation 2
psp:psp:psp:Sony PlayStation Portable
ps3:ps3:ps3:Sony PlayStation 3
psvita:psvita:psvita:Sony PlayStation Vita
gc:gc:gc:Nintendo GameCube
wii:wii:wii:Nintendo Wii
wiiu:wiiu:wiiu:Nintendo Wii U
n3ds:n3ds:n3ds:Nintendo 3DS
switch:switch:switch:Nintendo Switch
fbneo:fbneo:fbneo:FinalBurn Neo
neogeo:neogeo:neogeo:SNK Neo Geo
mame:mame:mame:MAME
'

# 导入：前端目录名 -> 规范ID（小写化、去空格/连字符后匹配）
resolve_platform_dir() { # <目录名>
  local name=$1
  local norm; norm=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | tr -d ' -_')
  local p aliases a an
  for p in "${PLATFORMS[@]}"; do
    [ "$(printf '%s' "$p" | tr '[:upper:]' '[:lower:]' | tr -d ' -_')" = "$norm" ] && { echo "$p"; return 0; }
    for a in ${PLAT_ALIASES[$p]:-}; do
      an=$(printf '%s' "$a" | tr '[:upper:]' '[:lower:]' | tr -d ' -_')
      [ "$an" = "$norm" ] && { echo "$p"; return 0; }
    done
  done
  return 1
}

# 导出：规范ID + 前端 -> 该前端约定的平台目录名
export_platform_name() { # <规范ID> <es|esde|pegasus>
  local canon=$1 fe=$2 line
  case "$fe" in
    es)   echo "$canon"; return 0 ;;
    esde) echo "$canon"; return 0 ;;
  esac
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    # 字段：canon:es:esde:pegasus
    local c rest; c=${line%%:*}; rest=${line#*:}
    [ "$c" = "$canon" ] || continue
    case "$fe" in
      pegasus) printf '%s\n' "${line##*:}" ;;
      *)       printf '%s\n' "${line%%:*}" ;;
    esac
    return 0
  done <<<"$FRONTEND_DIRNAMES"
  echo "$canon"
}



plat_compress_ok() { [ "${PLAT_COMPRESS[$1]:-false}" = "true" ]; }



ext_in_list() { # ext_in_list <ext> <space-separated list>
  local e; e=$(lower "$1")
  case " $2 " in *" $e "*) return 0 ;; *) return 1 ;; esac
}



is_generic_patch() { ext_in_list "$1" "$GENERIC_PATCH_EXTS"; }



is_archive()       { ext_in_list "$1" "$ARCHIVE_EXTS"; }



is_arcade_suffix() { ext_in_list "$1" "$ARCADE_SUFFIXES"; }



is_plat_patch_ext() { # is_plat_patch_ext <plat> <ext>
  ext_in_list "$2" "$(plat_patch_exts "$1")"
}



is_ambiguous_ext() { # is_ambiguous_ext <plat> <ext>
  ext_in_list "$2" "$(plat_ambig_exts "$1")"
}



patch_ext_platforms() {
  local e; e=$(lower "$1")
  local p out=""
  for p in "${PLATFORMS[@]}"; do
    case " $(plat_patch_exts "$p") " in *" $e "*) out+="$p " ;; esac
  done
  printf '%s' "${out% }"
}



plat_patch_exts()  { printf '%s' "${PLAT_PATCH[$1]:-}"; }



plat_ambig_exts()  { printf '%s' "${PLAT_AMBIG[$1]:-}"; }



media_type_by_keyword() {
  local n; n=$(lower "$(base_noext "$1")")
  case "$n" in
    *miximage*|*mix-img*|*"mix image"*|*-mix*|*_mix*) echo miximages; return ;;
    *marquee*|*banner*|*logo*|*wheel*|*横幅*) echo marquees; return ;;
    *screenshot*|*snap*|*screen*|*shot*|*scan*|*截图*|*标题画面*) echo screenshots; return ;;
    *cover*|*box*|*front*|*cart*|*label*|*封面*) echo covers; return ;;
  esac
  local e; e=$(ext_of "$1")
  case " ${MEDIA_EXTS[videos]:-} " in *" $e "*) echo videos; return ;; esac
  case " ${MEDIA_EXTS[intro]:-} " in *" $e "*) echo intro; return ;; esac
  echo unknown
}



cmd_init() {
  local root=""
  while [ $# -gt 0 ]; do
    case "$1" in --root) root=$2; shift 2 ;; -y) NONINTERACTIVE=true; shift ;; *) shift ;; esac
  done
  if [ ! -f "$CONFIG_FILE" ]; then write_default_config "$root"; fi
  if [ -n "$root" ]; then
    root=$(expand_path "$root"); mkdir -p "$root" || die "无法创建：$root"
    persist_config_key ROM_ROOT "$root"
  fi
  load_config
  ensure_ready
  print_config
  ui_msg info "初始化完成。DAT 文件可放入：$DAT_DIR"
}



cmd_change_root() {
  ensure_ready
  local n; n=$(ui_pick_dir "选择新的 ROM 主存储目录" "$ROM_ROOT") || return 1
  n=$(expand_path "$n")
  [ "$n" = "$ROM_ROOT" ] && return 0
  if [ -f "$n/romdb.csv" ]; then
    ROM_ROOT=$n; persist_config_key ROM_ROOT "$n"; ui_msg info "已切换到已有存储库：$n"; return 0
  fi
  if ! ui_confirm "将把当前存储库整体移动到 $n ，确认？" y; then return 1; fi
  mkdir -p "$n" || { ui_msg error "无法创建目标目录"; return 1; }
  if mv -- "$ROM_ROOT"/* "$ROM_ROOT"/.[!.]* "$n"/ 2>/dev/null; then :; fi
  ROM_ROOT=$n; DAT_DIR="$n/dats"
  persist_config_key ROM_ROOT "$n"
  ui_msg info "存储目录已迁移到：$n"
}

cmd_config() {
  [ -f "$CONFIG_FILE" ] || write_default_config ""
  load_config
  print_config
}
