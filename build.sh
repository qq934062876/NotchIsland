#!/bin/bash
# NotchIsland 构建脚本
# 用法：./build.sh
# 可选环境变量：
#   SDK=<sdk 路径>        默认自动挑一个与当前 swiftc 匹配的 SDK
#                         （xcrun 默认 SDK 可能比编译器新，会报 "this SDK is not supported by the compiler"）
#   OUT=<二进制路径>      默认仓库根目录的 NotchIsland
#   APP_DIR=<app 包路径>  默认仓库根目录的 NotchIsland.app
#   SKIP_SIGN=1           跳过临时签名
#   MACOS_MIN=<版本>      最低系统版本，默认 14.0（与 Info.plist 的 LSMinimumSystemVersion 一致）
# 运行期诊断：NOTCH_DEBUG=1 ./NotchIsland.app/Contents/MacOS/NotchIsland
#             （从终端启动才看得到 stderr；日志分类见 IslandDebug.swift）
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="NotchIsland"
MACOS_MIN="${MACOS_MIN:-14.0}"
ARCH="$(uname -m)"
ICON="Assets/AppIcon.icns"

SOURCES=(main.swift AppSettings.swift AppWindows.swift AppMenuBar.swift \
         MediaStore.swift MediaSources.swift MediaBridge.swift \
         ChannelSupport.swift \
         MusicGate.swift CDPClient.swift CDPPlayerSource.swift NeteaseSource.swift SodaSource.swift \
         PlayerLauncher.swift \
         IslandMediaColumn.swift \
         AudioActivity.swift WeatherSource.swift CalendarSource.swift \
         TrayStore.swift TrayScene.swift DropReceiver.swift \
         IslandLayout.swift IslandShape.swift PointerMonitor.swift \
         IslandDebug.swift NotchGeometry.swift \
         IslandView.swift HomeScene.swift IslandChrome.swift SystemStatus.swift)
BIN="${OUT:-$PWD/$APP_NAME}"
APP="${APP_DIR:-$PWD/$APP_NAME.app}"

for f in "${SOURCES[@]}" Info.plist; do
  if [ ! -f "$f" ]; then
    echo "缺少文件：$f（请在仓库根目录运行）" >&2
    exit 1
  fi
done

# 用一次最小编译探测 SDK 与编译器是否配套；SDK 由更新的 Swift 编译时 swiftc 会直接报错
sdk_works() {
  local sdk="$1" tmp
  [ -d "$sdk" ] || return 1
  tmp="$(mktemp -d)"
  printf 'let probe = 1\n' > "$tmp/probe.swift"
  if swiftc -sdk "$sdk" -o "$tmp/probe" "$tmp/probe.swift" >/dev/null 2>&1; then
    rm -rf "$tmp"
    return 0
  fi
  rm -rf "$tmp"
  return 1
}

SDK_PATH=""
if [ -n "${SDK:-}" ]; then
  if ! sdk_works "$SDK"; then
    echo "指定的 SDK 无法使用：$SDK" >&2
    echo "换成 macosx 版本不高于当前 swiftc 的 SDK 再试。" >&2
    exit 1
  fi
  SDK_PATH="$SDK"
else
  CANDIDATES=()
  DEFAULT_SDK="$(xcrun --show-sdk-path 2>/dev/null || true)"
  if [ -n "$DEFAULT_SDK" ]; then
    CANDIDATES+=("$DEFAULT_SDK")
  fi
  SDK_ROOT="$(xcode-select -p)/SDKs"
  while IFS= read -r d; do
    if [ -n "$d" ]; then
      CANDIDATES+=("$d")
    fi
  done < <(ls -d "$SDK_ROOT"/MacOSX*.sdk 2>/dev/null | sort -V -r || true)

  for d in "${CANDIDATES[@]:-}"; do
    if sdk_works "$d"; then
      SDK_PATH="$d"
      [ "$d" = "$DEFAULT_SDK" ] || echo "提示：默认 SDK（${DEFAULT_SDK}）与 swiftc 不匹配，改用 $d"
      break
    fi
  done

  if [ -z "$SDK_PATH" ]; then
    echo "找不到与当前 swiftc 匹配的 SDK；可用 SDK：" >&2
    ls -d "$SDK_ROOT"/MacOSX*.sdk 2>/dev/null >&2 || true
    echo "可用环境变量手动指定，例如：SDK=${SDK_ROOT}/MacOSX26.5.sdk ./build.sh" >&2
    exit 1
  fi
fi

echo "SDK: $SDK_PATH"
echo "目标: ${ARCH}-apple-macos${MACOS_MIN}"
mkdir -p "$(dirname "$BIN")"
echo "编译 -> $BIN"
swiftc -swift-version 5 -O \
  -sdk "$SDK_PATH" \
  -target "${ARCH}-apple-macos${MACOS_MIN}" \
  -framework Cocoa -framework SwiftUI -framework IOKit -framework CoreAudio -framework EventKit \
  -o "$BIN" \
  "${SOURCES[@]}"

echo "组装 app -> $APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp -f Info.plist "$APP/Contents/Info.plist"
cp -f "$BIN" "$APP/Contents/MacOS/$APP_NAME"
# 图标由 tools/make-icon.swift 生成；缺失时只警告，不影响构建
if [ -f "$ICON" ]; then
  cp -f "$ICON" "$APP/Contents/Resources/AppIcon.icns"
else
  echo "提示：未找到 ${ICON}，先运行 swift tools/make-icon.swift 生成"
fi

if [ "${SKIP_SIGN:-0}" = "1" ]; then
  echo "跳过签名"
elif command -v codesign >/dev/null 2>&1; then
  codesign --force --sign - "$APP" >/dev/null 2>&1 \
    && echo "已临时签名（ad-hoc）" \
    || echo "警告：临时签名失败，可在系统设置里手动放行"
fi

echo "完成。运行：open \"$APP\""