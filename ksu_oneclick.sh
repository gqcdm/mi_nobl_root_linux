#!/usr/bin/env bash
set -euo pipefail

echo "═══════════════════════════════════════════════"
echo "  KernelSU 一键加载 v2 (Linux)"
echo "  每次开机后运行此脚本"
echo "═══════════════════════════════════════════════"
echo

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KO="$DIR/android15-6.6_kernelsu.ko"
PATCHED="$DIR/kernelsu_patched.ko"
KSUD="$DIR/ksud-aarch64-linux-android"
PATCHER="$DIR/patch_ksu_module.py"
KALLSYMS="$DIR/kallsyms.txt"

ADB_ARGS=()
if [[ $# -ge 2 && "$1" == "-s" ]]; then
    ADB_ARGS=("-s" "$2")
    shift 2
fi

if [[ $# -ne 0 ]]; then
    echo "用法: $0 [-s SERIAL]"
    exit 1
fi

adb_cmd() {
    adb "${ADB_ARGS[@]}" "$@"
}

fail() {
    echo
    echo "[X] 加载失败，请检查上面的错误信息"
    exit 1
}

require_file() {
    local path="$1"
    if [[ ! -f "$path" ]]; then
        echo "[X] 找不到文件: $path"
        fail
    fi
}

require_file "$KO"
require_file "$KSUD"
require_file "$PATCHER"
require_file "$DIR/ksu_step1.sh"
require_file "$DIR/ksu_step2.sh"

if ! command -v adb >/dev/null 2>&1; then
    echo "[X] 未找到 adb，请先安装 Android platform-tools"
    exit 1
fi

PYTHON_BIN=""
if command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
elif command -v python >/dev/null 2>&1; then
    PYTHON_BIN="python"
else
    echo "[X] 未找到 python3 / python，无法执行 patch_ksu_module.py"
    exit 1
fi

echo "检查 ADB 连接..."
if ! adb_cmd get-state >/dev/null 2>&1; then
    echo "[X] 没有 ADB 设备，请连接手机"
    fail
fi
echo "[OK] ADB 已连接"
echo

echo "推送文件到设备..."
adb_cmd push "$DIR/ksu_step1.sh" /data/local/tmp/ksu_step1.sh >/dev/null
adb_cmd push "$DIR/ksu_step2.sh" /data/local/tmp/ksu_step2.sh >/dev/null
adb_cmd push "$KSUD" /data/local/tmp/ksud-aarch64 >/dev/null
echo "[OK] 文件已推送"
echo

echo "═════════════════════════════════════"
echo "[1/5] 拉取 kallsyms..."
echo "═════════════════════════════════════"

rm -f "$KALLSYMS" "$PATCHED"

adb_cmd shell service call miui.mqsas.IMQSNative 21 i32 1 s16 "sh" i32 1 s16 "/data/local/tmp/ksu_step1.sh" s16 "/storage/emulated/0/ksu_result.txt" i32 60 >/dev/null 2>&1

echo "等待 kallsyms 拉取..."
sleep 15

if ! adb_cmd pull /data/local/tmp/kallsyms.txt "$KALLSYMS" >/dev/null 2>&1; then
    echo "[!] 第一次拉取失败，多等10秒重试..."
    sleep 10
    adb_cmd pull /data/local/tmp/kallsyms.txt "$KALLSYMS" >/dev/null 2>&1 || true
fi

if [[ ! -f "$KALLSYMS" ]]; then
    echo "[X] kallsyms 拉取失败"
    fail
fi
echo "[OK] kallsyms 已拉取"
echo

echo "═════════════════════════════════════"
echo "[2/5] 补丁内核模块 (PC端 Python)..."
echo "═════════════════════════════════════"

"$PYTHON_BIN" "$PATCHER" "$KO" "$KALLSYMS" "$PATCHED" || fail

if [[ ! -f "$PATCHED" ]]; then
    echo "[X] 补丁文件未生成"
    fail
fi
echo "[OK] 补丁完成"
echo

echo "═════════════════════════════════════"
echo "[3-5/5] 加载模块 + 部署ksud + 触发Manager..."
echo "═════════════════════════════════════"

adb_cmd push "$PATCHED" /data/local/tmp/kernelsu_patched.ko >/dev/null

adb_cmd shell service call miui.mqsas.IMQSNative 21 i32 1 s16 "sh" i32 1 s16 "/data/local/tmp/ksu_step2.sh" s16 "/storage/emulated/0/ksu_result.txt" i32 60 >/dev/null 2>&1

echo "等待加载完成..."
sleep 25

echo
echo "══════════ 执行结果 ══════════"
RESULT="$(adb_cmd shell cat /storage/emulated/0/ksu_result.txt 2>/dev/null || true)"
printf '%s\n' "$RESULT"
echo

if grep -q "ALL_DONE" <<<"$RESULT"; then
    echo "═══════════════════════════════════════════════"
    echo "  加载完成！打开 KernelSU Manager 检查状态"
    echo "  如需修复框架(LSPosed): 请运行 fix_lspd.sh 流程"
    echo "═══════════════════════════════════════════════"
else
    echo "═══════════════════════════════════════════════"
    echo "  [!] 可能未完全成功，请检查上面的输出"
    echo "═══════════════════════════════════════════════"
fi
