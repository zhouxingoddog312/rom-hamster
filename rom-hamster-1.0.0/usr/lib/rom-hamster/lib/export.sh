# export.sh — EmulationStation 兼容导出
# shellcheck shell=bash

EX_COVERS=0; EX_SHOTS=0; EX_VIDEOS=0; EX_MARQUEES=0; EX_MIX=0
EX_INTRO=0; EX_PATCH=0; EX_KEEPDIR=0; EX_M3U=1; EX_HIDDEN=1
EX_COMPRESS=0; EX_FMT="zip"
EX_PLATS=""; EX_IDS=""
EX_FRONT="es"   # es | esde | pegasus
EXPORT_GAMES=0; EXPORT_SKIP=0


xml_esc() { printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g; s/'"'"'/\&#39;/g'; }



es_releasedate() {
  local y=$1
  if [[ "$y" =~ ^[0-9]{4}$ ]]; then printf '%s0101T000000' "$y"
  elif [[ "$y" =~ ^[0-9]{8} ]]; then printf '%sT000000' "$y"
  else printf '%s' "$y"; fi
}



es_rating() {
  [ -z "$1" ] && return 0
  awk -v r="$1" 'BEGIN{printf "%.2f", r/10}'
}



es_game_node() {
  local path=$1 name=$2 desc=$3 dev=$4 pub=$5 year=$6 genre=$7 players=$8 rating=$9 hidden=${10}
  local image=${11} video=${12} marquee=${13}
  local hattr=""; [ "$hidden" = "1" ] && hattr=' hidden="true"'
  printf '    <game%s>\n' "$hattr"
  printf '      <path>%s</path>\n' "$(xml_esc "$path")"
  [ -n "$name" ] && printf '      <name>%s</name>\n' "$(xml_esc "$name")"
  [ -n "$desc" ] && printf '      <desc>%s</desc>\n' "$(xml_esc "$desc")"
  [ -n "$image" ] && printf '      <image>%s</image>\n' "$(xml_esc "$image")"
  [ -n "$video" ] && printf '      <video>%s</video>\n' "$(xml_esc "$video")"
  [ -n "$marquee" ] && printf '      <marquee>%s</marquee>\n' "$(xml_esc "$marquee")"
  [ -n "$rating" ] && printf '      <rating>%s</rating>\n' "$(es_rating "$rating")"
  [ -n "$year" ] && printf '      <releasedate>%s</releasedate>\n' "$(es_releasedate "$year")"
  [ -n "$dev" ] && printf '      <developer>%s</developer>\n' "$(xml_esc "$dev")"
  [ -n "$pub" ] && printf '      <publisher>%s</publisher>\n' "$(xml_esc "$pub")"
  [ -n "$genre" ] && printf '      <genre>%s</genre>\n' "$(xml_esc "$genre")"
  [ -n "$players" ] && printf '      <players>%s</players>\n' "$(xml_esc "$players")"
  printf '    </game>\n'
}



export_one_game() {
  local dest=$1
  local plat main gdir roms_raw
  plat=$(fget platform); main=$(fget game_main_name)
  gdir="$ROM_ROOT/$(fget dir_path)"
  roms_raw=$(fget rom_files)
  local roms=(); local IFS_SAVE=$IFS; IFS=';'; roms=($roms_raw); IFS=$IFS_SAVE
  if [ "${#roms[@]}" -eq 0 ]; then warn "游戏无 ROM，导出时跳过：$main"; EXPORT_SKIP=$((EXPORT_SKIP+1)); return 0; fi

  local arcade=0; is_arcade_plat "$plat" && arcade=1
  local compress_here=0
  if [ "$EX_COMPRESS" = "1" ] && [ "$arcade" -eq 0 ] && plat_compress_ok "$plat"; then compress_here=1; fi

  local pdir="$dest/$(export_platform_name "$plat" "$EX_FRONT")"
  local romdir metadir leaf
  leaf=$(basename -- "$(fget dir_path)")
  if [ "$EX_KEEPDIR" = "1" ]; then
    romdir="$pdir/$leaf/rom"; metadir="$pdir/$leaf"
  else
    romdir="$pdir"; metadir="$pdir"
  fi
  mkdir -p "$romdir"

  # ROM 复制 / 压缩，记录 原名->导出名
  declare -A MAP=()
  local r outname
  for r in "${roms[@]}"; do
    [ -z "$r" ] && continue
    if [ ! -f "$gdir/rom/$r" ]; then warn "ROM 文件缺失，跳过：$r"; continue; fi
    outname=$r
    if [ "$arcade" -eq 0 ] && [ "$compress_here" -eq 1 ]; then
      case "$r" in
        *.zip|*.7z) : ;;
        *)
          if [ "$EX_FMT" = "7z" ]; then
            outname="$(base_noext "$r").7z"
            if ! sevenz_junk "$romdir/$outname" "$gdir/rom" "$r"; then
              warn "7z 压缩失败，原样复制：$r"; outname=$r; cp -p -- "$gdir/rom/$r" "$romdir/$outname"
            fi
          else
            outname="$(base_noext "$r").zip"
            if ! zip_junk "$romdir/$outname" "$gdir/rom" "$r"; then
              warn "zip 压缩失败，原样复制：$r"; outname=$r; cp -p -- "$gdir/rom/$r" "$romdir/$outname"
            fi
          fi ;;
      esac
    else
      cp -p -- "$gdir/rom/$r" "$romdir/$outname"
    fi
    MAP[$r]=$outname
  done

  # 导出的 ROM 相对路径（相对平台目录），按碟号排序
  local -a rels=()
  local rel_prefix=""; [ "$EX_KEEPDIR" = "1" ] && rel_prefix="./$leaf/rom/"
  for r in "${roms[@]}"; do
    [ -n "${MAP[$r]:-}" ] && rels+=("${rel_prefix}./${MAP[$r]}")
  done
  # 修正双 ./
  local i; for i in "${!rels[@]}"; do rels[$i]=${rels[$i]//.\//}; rels[$i]="./${rels[$i]}"; done

  # m3u
  local m3u_rel=""
  if [ "${#roms[@]}" -gt 1 ] && [ "$EX_M3U" = "1" ]; then
    local m3u_name="$main.m3u"
    local m3u_abs="$romdir/$m3u_name"
    { for r in "${roms[@]}"; do
        [ -z "${MAP[$r]:-}" ] && continue
        parse_disc_name "$(base_noext "$r")"; local dn=${DISC_NUM:-0}; [ "$dn" -eq 0 ] && dn=999
        printf '%03d\t%s\n' "$dn" "${MAP[$r]}"
      done; } | sort -t$'\t' -k1,1n | cut -f2- > "$m3u_abs"
    if [ "$EX_KEEPDIR" = "1" ]; then m3u_rel="./$leaf/rom/$m3u_name"
    else m3u_rel="./$m3u_name"; fi
  fi

  # 媒体复制
  local img_rel="" video_rel="" marquee_rel=""
  copy_media() { # field folder toggle
    local field=$1 folder=$2 toggle=$3
    [ "$toggle" = "1" ] || return 0
    local list; list=$(fget "$field")
    [ -z "$list" ] && return 0
    local target
    if [ "$EX_KEEPDIR" = "1" ]; then target="$metadir/$folder"
    else target="$pdir/media/$folder"; fi
    mkdir -p "$target"
    local f firstrel="" saveifs=$IFS
    local IFS=';'; local arr=($list); IFS=$saveifs
    for f in "${arr[@]}"; do
      [ -z "$f" ] && continue
      if [ -f "$gdir/$folder/$f" ]; then
        cp -p -- "$gdir/$folder/$f" "$target/$f"
        local rel
        if [ "$EX_KEEPDIR" = "1" ]; then rel="./$leaf/$folder/$f"
        else rel="./media/$folder/$f"; fi
        [ -z "$firstrel" ] && firstrel=$rel
      fi
    done
    printf '%s' "$firstrel"
  }
  img_rel=$(copy_media cover_filename covers "$EX_COVERS")
  copy_media screenshot_filename screenshots "$EX_SHOTS" >/dev/null
  video_rel=$(copy_media video_filename videos "$EX_VIDEOS")
  marquee_rel=$(copy_media marquee_filename marquees "$EX_MARQUEES")
  copy_media miximage_filename miximages "$EX_MIX" >/dev/null

  if [ "$EX_INTRO" = "1" ] && [ -n "$(fget intro_filename)" ]; then
    local t; if [ "$EX_KEEPDIR" = "1" ]; then t="$metadir/intro"; else t="$pdir/intro"; fi
    mkdir -p "$t"
    local saveifs=$IFS; IFS=';'; local arr=($(fget intro_filename)); IFS=$saveifs
    local x; for x in "${arr[@]}"; do [ -f "$gdir/intro/$x" ] && cp -p -- "$gdir/intro/$x" "$t/$x"; done
  fi
  if [ "$EX_PATCH" = "1" ] && [ -n "$(fget patcher_filename)" ]; then
    mkdir -p "$pdir/patcher"
    local saveifs=$IFS; IFS=';'; local arr=($(fget patcher_filename)); IFS=$saveifs
    local x; for x in "${arr[@]}"; do [ -f "$gdir/patcher/$x" ] && cp -p -- "$gdir/patcher/$x" "$pdir/patcher/$x"; done
  fi

  # gamelist 节点
  local nodes="$WORK_TMP/nodes_$plat"
  local nm; nm=$(fget name); [ -z "$nm" ] && nm=$main
  if [ "${#roms[@]}" -gt 1 ]; then
    local main_path; if [ -n "$m3u_rel" ]; then main_path=$m3u_rel; else main_path="${rels[0]}"; fi
    es_game_node "$main_path" "$nm" "$(fget desc)" "$(fget developer)" "$(fget publisher)" \
      "$(fget year)" "$(fget genre)" "$(fget players)" "$(fget rating)" 0 \
      "$img_rel" "$video_rel" "$marquee_rel" >>"$nodes"
    if [ -n "$m3u_rel" ] && [ "$EX_HIDDEN" = "1" ]; then
      local d=1 r2
      for r2 in "${rels[@]}"; do
        es_game_node "$r2" "$nm ($DISC_PREFIX $d)" "$(fget desc)" "$(fget developer)" "$(fget publisher)" \
          "$(fget year)" "$(fget genre)" "$(fget players)" "$(fget rating)" 1 "" "" "" >>"$nodes"
        d=$((d+1))
      done
    fi
  else
    es_game_node "${rels[0]}" "$nm" "$(fget desc)" "$(fget developer)" "$(fget publisher)" \
      "$(fget year)" "$(fget genre)" "$(fget players)" "$(fget rating)" 0 \
      "$img_rel" "$video_rel" "$marquee_rel" >>"$nodes"
  fi
  EXPORT_GAMES=$((EXPORT_GAMES+1))
}



write_gamelists() {
  local dest=$1 nodes p out
  for nodes in "$WORK_TMP"/nodes_*; do
    [ -f "$nodes" ] || continue
    p=${nodes##*nodes_}
    if [ "$EX_FRONT" = "pegasus" ]; then
      out="$dest/$(export_platform_name "$p" pegasus)/metadata.pegasus.txt"
      { printf '# Pegasus frontend metadata\ncollection: %s\n\n' "$p"
        cat -- "$nodes"
      } >"$out"
    else
      out="$dest/$p/gamelist.xml"
      { printf '<?xml version="1.0" encoding="UTF-8"?>\n<gameList>\n'
        cat -- "$nodes"
        printf '</gameList>\n'
      } >"$out"
    fi
    info "已生成：$out"
  done
}



scope_has_compressible() {
  while IFS=$US read -r -a F; do
    [ -z "$(fget id)" ] && continue
    [ -n "$EX_PLATS" ] && ! in_list "$(fget platform)" $EX_PLATS && continue
    if [ "$(fget is_arcade)" != true ] && plat_compress_ok "$(fget platform)"; then return 0; fi
  done < <(db_tsv)
  return 1
}



ask_export_options() {
  local opts=(
    "导出封面（默认关）" "导出截图（默认关）" "导出预览视频（默认关）" "导出标题横幅（默认关）"
    "导出合成混合图（默认关）" "导出说明文本（默认关）" "导出补丁文件（默认关）"
    "保留游戏独立目录结构（默认 ES 扁平结构）"
    "多碟生成 m3u 播放列表（默认开）" "多碟生成单碟隐藏条目（默认开）"
  )
  local picks
  picks=$(ui_menu_multi "导出选项（勾选需要的项目；8/9 勾选表示关闭默认开启项）" "${opts[@]}") || return 1
  local p
  for p in $picks; do
    case "$p" in
      0) EX_COVERS=1;; 1) EX_SHOTS=1;; 2) EX_VIDEOS=1;; 3) EX_MARQUEES=1;; 4) EX_MIX=1;;
      5) EX_INTRO=1;; 6) EX_PATCH=1;; 7) EX_KEEPDIR=1;; 8) EX_M3U=0;; 9) EX_HIDDEN=0;;
    esac
  done
  if scope_has_compressible; then
    if ui_confirm "检测到支持直读压缩的家用机平台，是否压缩卡带 ROM（默认 ZIP）？" n; then
      EX_COMPRESS=1
      local fi; fi=$(ui_menu "压缩格式" "ZIP（兼容性最好，推荐）" "7Z（体积更小，兼容性略低）") || fi=0
      [ "$fi" = "1" ] && EX_FMT=7z || EX_FMT=zip
    fi
  else
    info "街机/光盘/现代主机平台不提供通用 ZIP/7Z 压缩；街机 ZIP 导出时原样保留。"
  fi
}



cmd_export() {
  ensure_ready
  local dest=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --platform) EX_PLATS="$EX_PLATS $2"; shift 2 ;;
      --id) EX_IDS="$EX_IDS $2"; shift 2 ;;
      --media) EX_COVERS=1; EX_SHOTS=1; EX_VIDEOS=1; EX_MARQUEES=1; EX_MIX=1; shift ;;
      --covers) EX_COVERS=1; shift ;; --screenshots) EX_SHOTS=1; shift ;;
      --videos) EX_VIDEOS=1; shift ;; --marquees) EX_MARQUEES=1; shift ;;
      --miximages) EX_MIX=1; shift ;; --intro) EX_INTRO=1; shift ;; --patcher) EX_PATCH=1; shift ;;
      --keep-dirs) EX_KEEPDIR=1; shift ;;
      --no-m3u) EX_M3U=0; shift ;;
      --no-hidden-discs) EX_HIDDEN=0; shift ;;
      --compress) EX_COMPRESS=1; shift ;;
      --format) EX_FMT=$2; shift 2 ;;
      --frontend) EX_FRONT=$2; shift 2 ;;
      -y|--yes|--non-interactive) NONINTERACTIVE=true; shift ;;
      -*) die "未知导出选项：$1" ;;
      *) dest=$1; shift ;;
    esac
  done
  EX_PLATS=$(trim "$EX_PLATS"); EX_IDS=$(trim "$EX_IDS")
  case "$EX_FRONT" in es|esde|pegasus) ;; *) die "未知前端类型：$EX_FRONT（可选 es/esde/pegasus）" ;; esac

  if [ -z "$dest" ]; then
    local scope
    scope=$(ui_menu "导出范围" "全部游戏" "指定平台" "指定游戏") || return 1
    case "$scope" in
      1) local pi; pi=$(ui_menu_multi "选择要导出的平台（多选）" "${PLATFORMS[@]}") || return 1
         local x; for x in $pi; do EX_PLATS="$EX_PLATS ${PLATFORMS[$x]}"; done; EX_PLATS=$(trim "$EX_PLATS") ;;
      2) reset_filters; interactive_filter || true
         local res; res=$(query_games)
         local opts=(); local idsarr=()
         while IFS=$US read -r id nm pl _; do [ -n "$id" ] && { opts+=("$nm [$pl]"); idsarr+=("$id"); }; done <<<"$res"
         [ "${#opts[@]}" -eq 0 ] && { ui_msg warning "没有选中任何游戏"; return 1; }
         local gi; gi=$(ui_menu_multi "选择要导出的游戏（多选）" "${opts[@]}") || return 1
         local g; for g in $gi; do EX_IDS="$EX_IDS ${idsarr[$g]}"; done; EX_IDS=$(trim "$EX_IDS") ;;
    esac
    dest=$(ui_pick_dir "选择导出目标根目录（EmulationStation 的 ROM 目录）" "$HOME") || return 1
    ask_export_options || return 1
  fi
  dest=$(expand_path "$dest")
  mkdir -p "$dest" || { ui_msg error "无法创建导出目录：$dest"; return 1; }
  [ -n "$WORK_TMP" ] || init_workspace
  rm -f "$WORK_TMP"/nodes_*

  while IFS=$US read -r -a F; do
    [ -z "$(fget id)" ] && continue
    [ -n "$EX_PLATS" ] && ! in_list "$(fget platform)" $EX_PLATS && continue
    [ -n "$EX_IDS" ] && ! in_list "$(fget id)" $EX_IDS && continue
    export_one_game "$dest"
  done < <(db_tsv)

  write_gamelists "$dest"
  ui_msg info "导出完成：$EXPORT_GAMES 个游戏，跳过 $EXPORT_SKIP 个；目标目录：$dest"
}



