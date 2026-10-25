#!/usr/bin/env sh
# 云端构建脚本：产物命名 + 校验和。
# 只在 CI 中执行；本地不编译（见 README「构建」）。
set -eu

FLUTTER=${FLUTTER:-flutter}
VERSION=$(sed -n 's/^version: *\([0-9][^+]*\).*/\1/p' pubspec.yaml | head -1)
[ -n "$VERSION" ] || VERSION=0.0.0

echo "== OpenNest $VERSION · Android arm64 =="

"$FLUTTER" config --no-analytics
"$FLUTTER" --version
"$FLUTTER" pub get
"$FLUTTER" build apk --release --target-platform android-arm64

mkdir -p dist
OUT="dist/OpenNest-${VERSION}-android-arm64.apk"
cp build/app/outputs/flutter-apk/app-release.apk "$OUT"

if command -v sha256sum >/dev/null 2>&1; then
  # v1.0.58：校验文件里只写文件名，不带 dist/ 前缀。
  # 用户把 APK 与 .sha256 下载到同一目录后，`sha256sum -c` 要能直接通过；
  # 之前写的是 "dist/xxx.apk"，那个路径在下载目录里不存在，必然报 No such file。
  ( cd dist && sha256sum "$(basename "$OUT")" ) | tee "$OUT.sha256"
fi
ls -lh dist/
