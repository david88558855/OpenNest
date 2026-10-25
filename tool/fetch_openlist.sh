#!/usr/bin/env bash
# 下载内嵌引擎（OpenList）二进制并放到打包位置。
#
# 用法：tool/fetch_openlist.sh windows|android
# 版本由 OPENLIST_VERSION 覆盖，默认锁定 4.2.8。
# 产物不入库（.gitignore 已忽略 assets/bin 与 jniLibs）。
set -euo pipefail

TARGET="${1:-windows}"
VERSION="${OPENLIST_VERSION:-4.2.8}"
BASE="https://github.com/OpenListTeam/OpenList/releases/download/v${VERSION}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fetch() {
  local asset="$1"
  echo "==> 下载 $asset"
  curl -fL --retry 3 --retry-delay 2 --connect-timeout 20 -o "$TMP/$asset" "$BASE/$asset"
}

case "$TARGET" in
  windows)
    ASSET="openlist-windows-amd64-lite.zip"
    fetch "$ASSET"
    unzip -tq "$TMP/$ASSET" >/dev/null
    unzip -q "$TMP/$ASSET" -d "$TMP/win"
    SRC="$(find "$TMP/win" -type f -name 'openlist.exe' | head -1)"
    [ -n "$SRC" ] || { echo "压缩包里没有 openlist.exe"; exit 1; }
    mkdir -p "$ROOT/assets/bin/windows"
    cp -f "$SRC" "$ROOT/assets/bin/windows/openlist.exe"
    echo "OK: assets/bin/windows/openlist.exe ($(du -h "$ROOT/assets/bin/windows/openlist.exe" | cut -f1))"
    ;;
  android)
    ASSET="openlist-android-arm64-lite.tar.gz"
    fetch "$ASSET"
    tar -tzf "$TMP/$ASSET" >/dev/null
    tar -xzf "$TMP/$ASSET" -C "$TMP" --one-top-level=and 2>/dev/null || {
      mkdir -p "$TMP/and"
      tar -xzf "$TMP/$ASSET" -C "$TMP/and"
    }
    SRC="$(find "$TMP/and" -type f -name 'openlist' | head -1)"
    [ -n "$SRC" ] || { echo "压缩包里没有 openlist 可执行文件"; exit 1; }
    DEST="$ROOT/android/app/src/main/jniLibs/arm64-v8a"
    mkdir -p "$DEST"
    cp -f "$SRC" "$DEST/libopenlist.so"
    echo "OK: android/app/src/main/jniLibs/arm64-v8a/libopenlist.so ($(du -h "$DEST/libopenlist.so" | cut -f1))"
    if command -v llvm-readelf >/dev/null 2>&1; then
      echo "==> 程序头对齐检查（16KB 页要求 Align >= 0x4000）"
      llvm-readelf -l "$DEST/libopenlist.so" | awk '/LOAD/ {print "  " $0}'
    fi
    ;;
  *)
    echo "未知目标：$TARGET（可选 windows | android）"
    exit 1
    ;;
esac
