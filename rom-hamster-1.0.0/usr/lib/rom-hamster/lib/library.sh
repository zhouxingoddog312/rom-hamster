# library.sh — 整库识别与批量导入（ES 原版 / ES-DE / Pegasus）
# 识别导入目标本身是否为完整前端导出目录：
#   ES/ES-DE  -> 各平台目录下的 gamelist.xml（含 path/name/desc/媒体字段）
#   Pegasus   -> 各目录下的 metadata.pegasus.txt（含 collection/game 块与 media 资产）
# 校验 ROM 与媒体文件存在后，批量创建游戏记录，避免逐个人工添加。

declare -a LIB_FOUND=()          # 发现的清单文件路径
LIB_TYPE="none"                  # es | esde | pegasus | none


# 在目录树中查找清单文件（最多向下 3 层）
library_find_manifests() { # <root>
  local root=$1
  LIB_FOUND=()
  local f
  while IFS= read -r -d '' f; do
    LIB_FOUND+=("$f")
  done < <(find "$root" -maxdepth 3 -type f \
      \( -name 'gamelist.xml' -o -name 'metadata.pegasus.txt' \) -print0 2>/dev/null)
  [ "${#LIB_FOUND[@]}" -gt 0 ]
}


# 判断清单类型（同一目录中 gamelist.xml 优先于 pegasus）
library_manifest_type() { # <manifest>
  local m=$1
  case "$(basename -- "$m")" in
    gamelist.xml)         echo es ;;
    metadata.pegasus.txt) echo pegasus ;;
    *)                    echo none ;;
  esac
}


# 从 gamelist.xml 中提取一个平台的游戏行
# 输出（制表符分隔）：rom_path \t name \t desc \t image \t marquee \t video \t developer \t publisher \t year \t genre \t rating
parse_gamelist_games() { # <gamelist.xml> <system_dir>
  local g=$1 sysdir=$2
  # 用 awk 逐 <game> 块抽取字段；path 相对 sysdir 解析
  awk -v sysdir="$sysdir" '
    function strip_cdata(s){ gsub(/<!\[CDATA\[/,"",s); gsub(/\]\]>/,"",s); return s }
    function field(tag,   s){
      if (match($0, "<" tag ">")) {
        s = $0
        sub(".*<" tag ">", "", s); sub("</" tag ">.*", "", s)
        return strip_cdata(s)
      }
      return ""
    }
    /<game / { ing=1; path="";name="";desc="";img="";marq="";vid="";dev="";pub="";yr="";gen="";rate="" }
    ing && /<path>/        { path=field("path") }
    ing && /<name>/        { name=field("name") }
    ing && /<desc>/        { desc=field("desc") }
    ing && /<image>/       { img=field("image") }
    ing && /<marquee>/     { marq=field("marquee") }
    ing && /<video>/       { vid=field("video") }
    ing && /<developer>/   { dev=field("developer") }
    ing && /<publisher>/  { pub=field("publisher") }
    ing && /<year>/        { yr=field("year") }
    ing && /<genre>/       { gen=field("genre") }
    ing && /<rating>/      { rate=field("rating") }
    /<\/game>/ {
      ing=0
      if (path != "") {
        # 去前导 ./ 与 URL 编码空格
        gsub(/^\.\//, "", path)
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n",
          path, name, desc, img, marq, vid, dev, pub, yr, gen, rate
      }
    }
  ' "$g"
}


# 从 metadata.pegasus.txt 提取游戏行（Pegasus 文本格式：game 块）
# 输出：rom_path \t name \t (desc 留空) \t media_dir 内封面 \t marquee \t video \t - \t - \t year \t genre \t -
parse_pegasus_games() { # <metadata.pegasus.txt> <dir>
  local m=$1 dir=$2
  awk -v d="$dir" '
    function esc(s){ gsub(/\\(.)/, "\\1", s); return s }
    /^game:/   { ing=1; rom=""; title=""; yr=""; gen="" }
    ing && /^\s*file:/   { rom=$0; sub(/^\s*file:\s*/,"",rom) }
    ing && /^\s*title:/  { title=$0; sub(/^\s*title:\s*/,"",title) }
    ing && /^\s*year:/    { yr=$0; sub(/^\s*year:\s*/,"",yr) }
    ing && /^\s*genre:/   { gen=$0; sub(/^\s*genre:\s*/,"",gen) }
    ing && /^$/ {
      if (rom != "") printf "%s\t%s\t\t%s/media/%s/boxFront.jpg\t%s/media/%s/wheel.png\t\t\t\t%s\t%s\t\n",
          rom, title, d, title, d, title, yr, gen
      ing=0
    }
  ' "$m"
}


# 校验一个 ROM 路径是否存在（相对清单所在目录）
library_check_rom() { # <sysdir> <relpath>
  local sysdir=$1 rel=$2
  [ -n "$rel" ] && [ -f "$sysdir/$rel" ]
}


# 判断某名是否为已知平台
is_known_platform() {
  local p; for p in "${PLATFORMS[@]}"; do [ "$p" = "$1" ] && return 0; done
  return 1
}


# 单条游戏入库：复用现有记录框架
library_import_one() { # <platform> <rom_relpath> <name> <desc> <img> <marq> <vid> <dev> <pub> <year> <genre> <rating> <sysdir>
  local plat=$1 rel=$2 name=$3 desc=$4 img=$5 marq=$6 vid=$7 dev=$8 pub=$9 year=${10} genre=${11} rating=${12} sysdir=${13}
  local rom="$sysdir/$rel"
  [ -f "$rom" ] || { warn "清单中 ROM 不存在，跳过：$rel"; return 1; }

  local main; main=$name
  [ -z "$main" ] && main=$(base_noext "$rel")

  new_record
  fset game_main_name "$main"
  fset platform "$plat"
  fset name "$name"
  [ -n "$desc" ]  && fset desc "$desc"
  [ -n "$dev" ]   && fset developer "$dev"
  [ -n "$pub" ]   && fset publisher "$pub"
  [ -n "$year" ]  && fset year "$year"
  [ -n "$genre" ] && fset genre "$genre"
  [ -n "$rating" ] && fset rating "$rating"
  if is_arcade_plat "$plat"; then fset is_arcade true; else fset is_arcade false; fi
  local e; e=$(ext_of "$rel"); local rf=raw
  case "$e" in .zip) rf=zip ;; .7z) rf=7z ;; .chd) rf=chd ;; esac
  fset rom_format "$rf"
  fset rom_status unknown
  fset dir_path "$plat/$(sanitize_dirname "$main")"

  local gdir="$ROM_ROOT/$(fget dir_path)"
  local mt; for mt in "${MTYPES[@]}"; do mkdir -p "$gdir/$mt"; done

  local target_name="$main$e"
  safe_copy "$rom" "$gdir/rom/$target_name" || { warn "复制失败：$rom"; return 1; }
  fset rom_files "$target_name"

  # 媒体文件拷贝（存在才收）
  [ -n "$img" ]  && [ -f "$sysdir/$img" ]  && safe_copy "$sysdir/$img"  "$gdir/covers/$main-image$e"  && fset cover_filename "$main-image$e"
  [ -n "$marq" ] && [ -f "$sysdir/$marq" ] && safe_copy "$sysdir/$marq" "$gdir/marquees/$main-marquee$e" && fset marquee_filename "$main-marquee$e"
  [ -n "$vid" ]  && [ -f "$sysdir/$vid" ]  && safe_copy "$sysdir/$vid"  "$gdir/videos/$main-video.mp4" && fset video_filename "$main-video.mp4"

  db_upsert_F
  info "整库入库：$plat/$main（$(basename -- "$rom")）"
  return 0
}


# 顶层入口：对一个导入目录做整库识别；是则批量导入，否则返回 0 走原有流程
maybe_import_library() { # <dir>
  local dir=$1
  [ -d "$dir" ] || return 1

  if ! library_find_manifests "$dir"; then
    return 1
  fi

  info "检测到前端清单文件 ${#LIB_FOUND[@]} 个，开始整库校验与批量导入…"
  local m sysdir type rel name desc img marq vid dev pub yr gen rate n
  local ok=0 bad=0
  for m in "${LIB_FOUND[@]}"; do
    sysdir=$(dirname -- "$m")
    type=$(library_manifest_type "$m")
    info "清单：$m（类型 $type）"
    while IFS=$'\t' read -r rel name desc img marq vid dev pub yr gen rate; do
      [ -n "$rel" ] || continue
      # 平台推断：先按清单所在目录名做前端别名解析；失败再按 ROM 后缀推断
      local plat; plat=$(resolve_platform_dir "$(basename -- "$sysdir")") || plat=""
      [ -z "$plat" ] && {
        local e; e=$(ext_of "$sysdir/$rel")
        plat=$(resolve_platform_for_rom "$e" "cartridge" "-")
      }
      if library_import_one "$plat" "$rel" "$name" "$desc" "$img" "$marq" "$vid" "$dev" "$pub" "$yr" "$gen" "$rate" "$sysdir"; then
        ok=$((ok+1))
      else
        bad=$((bad+1))
      fi
    done < <( [ "$type" = "pegasus" ] && parse_pegasus_games "$m" "$sysdir" || parse_gamelist_games "$m" "$sysdir" )
  done
  info "整库导入完成：成功 $ok，失败/跳过 $bad"
  [ "$ok" -gt 0 ]
}
