#!/bin/sh
# HLCamSwap 配置脚本
# 用法（在 iPhone 上通过 SSH 或 Filza 的终端执行）：
#   sh config.sh enable            启用插件
#   sh config.sh disable           停用插件
#   sh config.sh list              列出可用图片
#   sh config.sh use <文件名>       指定当前使用的图片
#   sh config.sh rotate <角度>      设置旋转角度 (0/90/180/270)
#   sh config.sh push <本地图片>    推送图片（需从 PC 用 scp）
#   sh config.sh status            查看当前状态
#   sh config.sh log               查看日志

DIR="/var/mobile/Library/HLCamSwap"
mkdir -p "$DIR"

case "$1" in
  enable)
    echo "1" > "$DIR/enable.txt"
    echo "[OK] 已启用"
    echo "    生效需重启货拉拉 App（或 respring）"
    ;;

  disable)
    echo "0" > "$DIR/enable.txt"
    echo "[OK] 已停用"
    ;;

  list)
    echo "=== $DIR 下的图片 ==="
    ls -la "$DIR" 2>/dev/null | grep -iE '\.(jpg|jpeg|png)$' || echo "  (没有图片)"
    echo ""
    echo "=== 当前使用 ==="
    if [ -f "$DIR/active.txt" ]; then
      cat "$DIR/active.txt"
    else
      echo "  (未指定，自动取第一张)"
    fi
    ;;

  use)
    if [ -z "$2" ]; then
      echo "用法: sh config.sh use <文件名>"
      exit 1
    fi
    if [ ! -f "$DIR/$2" ]; then
      echo "[!] 文件不存在: $DIR/$2"
      exit 1
    fi
    echo "$2" > "$DIR/active.txt"
    echo "[OK] 当前图片 -> $2"
    ;;

  rotate)
    if [ -z "$2" ]; then
      echo "用法: sh config.sh rotate <0|90|180|270>"
      exit 1
    fi
    echo "$2" > "$DIR/rotate.txt"
    echo "[OK] 旋转角度 -> $2°"
    ;;

  status)
    echo "========== HLCamSwap 状态 =========="
    echo "目录:     $DIR"
    echo "启用:     $(cat "$DIR/enable.txt" 2>/dev/null || echo '未设置(等于停用)')"
    echo "当前图片: $(cat "$DIR/active.txt" 2>/dev/null || echo '未指定(自动取第一张)')"
    echo "旋转角度: $(cat "$DIR/rotate.txt" 2>/dev/null || echo '0')°"
    echo ""
    echo "--- 图片池 ---"
    ls -la "$DIR" 2>/dev/null | grep -iE '\.(jpg|jpeg|png)$' || echo "  (空)"
    ;;

  log)
    if [ -f "$DIR/hl.log" ]; then
      tail -60 "$DIR/hl.log"
    else
      echo "(还没有日志，说明插件未运行过)"
    fi
    ;;

  clear)
    rm -f "$DIR/hl.log"
    echo "[OK] 日志已清空"
    ;;

  *)
    echo "HLCamSwap 配置工具"
    echo ""
    echo "  sh config.sh enable           启用"
    echo "  sh config.sh disable          停用"
    echo "  sh config.sh list             列出图片"
    echo "  sh config.sh use <文件名>      指定图片"
    echo "  sh config.sh rotate <角度>     设置旋转 (0/90/180/270)"
    echo "  sh config.sh status           查看状态"
    echo "  sh config.sh log              查看日志"
    echo "  sh config.sh clear            清空日志"
    echo ""
    echo "图片目录: $DIR"
    ;;
esac
