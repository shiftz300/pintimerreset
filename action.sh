#!/system/bin/sh
# ===================================================================
# KernelSU Action - 点击「操作」按钮查看/管理 PIN 计时器
# ksud 以 busybox sh 执行此脚本，stdout 弹窗显示给用户
# ===================================================================
# shellcheck disable=SC3043

MODDIR=${0%/*}
STATUS_CONF="$MODDIR/status.conf"
LAST_RESET="$MODDIR/last_reset.time"
LOG_FILE="$MODDIR/pin_reset.log"
PIN_CONF="$MODDIR/pin.conf"

# ---- Locale 检测 ----
is_zh() {
    local loc
    loc=$(getprop persist.sys.locale 2>/dev/null)
    [ -z "$loc" ] && loc=$(getprop ro.product.locale 2>/dev/null)
    case "$loc" in zh-*|zh_*) return 0 ;; *) return 1 ;; esac
}
# Translation: T "English" "中文"
T() { if is_zh; then echo "$2"; else echo "$1"; fi }

# ---- 加载状态配置 ----
CHECK_INTERVAL=21600
# shellcheck source=/dev/null
[ -f "$STATUS_CONF" ] && . "$STATUS_CONF"

# ====================== 参数解析 ======================
CMD="${1:-}"

# -- set-pin: 更新 PIN
if [ "$CMD" = "set-pin" ]; then
    NEW_PIN="${2:-}"
    if [ -z "$NEW_PIN" ]; then
        echo "$(T 'Usage: action.sh set-pin <PIN>' '用法: action.sh set-pin <PIN>')"
        echo "$(T 'Example: action.sh set-pin 123456' '示例: action.sh set-pin 123456')"
        exit 1
    fi

    echo "$NEW_PIN" > "$PIN_CONF"
    chmod 600 "$PIN_CONF" 2>/dev/null

    echo "$(T 'PIN updated' 'PIN 已更新')"
    echo ""
    echo "$(T 'Reboot to take effect' '重启设备后生效')"
    exit 0
fi

# -- set-timeout: 修改系统强认证超时
if [ "$CMD" = "set-timeout" ]; then
    HOURS="${2:-}"
    if [ -z "$HOURS" ] || ! [ "$HOURS" -gt 0 ] 2>/dev/null; then
        echo "$(T 'Usage: action.sh set-timeout <hours>' '用法: action.sh set-timeout <小时>')"
        echo "$(T 'Example: action.sh set-timeout 24' '示例: action.sh set-timeout 24')"
        echo ""
        echo "$(T 'Common values' '常用值'): 12h 24h 48h 72h 168h(7d) 720h(30d)"
        exit 1
    fi

    MS=$((HOURS * 3600 * 1000))
    settings put secure lock_to_app_exipire "$MS" 2>/dev/null

    if [ $? -eq 0 ]; then
        echo "$(T 'Strong auth timeout set to' '强认证超时已设为') ${HOURS}h ($(T 'takes effect on next auth cycle' '下次认证周期生效'))"
    else
        echo "$(T 'Failed to set timeout. Requires WRITE_SECURE_SETTINGS permission.' '设置超时失败。需要 WRITE_SECURE_SETTINGS 权限。')"
        exit 1
    fi
    exit 0
fi

# -- help
if [ "$CMD" = "-h" ] || [ "$CMD" = "--help" ]; then
    echo "$(T 'Usage: action.sh [command] [args]' '用法: action.sh [命令] [参数]')"
    echo ""
    echo "$(T 'Commands:' '命令:')"
    echo "  $(T '(none)              Show refresh status' '(无参数)            查看刷新状态')"
    echo "  $(T 'set-pin <PIN>        Set/update unlock PIN' 'set-pin <PIN>        设置/更新解锁 PIN')"
    echo "  $(T 'set-timeout <hours>  Set strong auth timeout' 'set-timeout <小时>  设置强认证超时')"
    echo "  $(T '-h, --help           Show this help' '-h, --help           显示此帮助')"
    exit 0
fi

# ====================== 以下: 默认状态显示 ======================

# ---- 格式化时长 ----
fmt_dur() {
    local s=$1 h m
    [ "$s" -lt 0 ] 2>/dev/null && { echo "--"; return; }
    h=$((s / 3600))
    m=$(((s % 3600) / 60))
    s=$((s % 60))
    [ "$h" -gt 0 ] && printf "%dh%dm%ds" "$h" "$m" "$s" && return
    [ "$m" -gt 0 ] && printf "%dm%ds" "$m" "$s" && return
    printf "%ds" "$s"
}

# ---- 格式化时间戳 ----
fmt_ts() {
    date -d "@$1" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "N/A"
}

# ---- 检查守护进程 ----
if pgrep -f "pin_timer_reset.*service\.sh" >/dev/null 2>&1; then
    SVC="[$(T 'Running' '运行中')]"
else
    SVC="[$(T 'Stopped' '未运行')]"
fi

# ---- 检查配置 ----
if [ -f "$PIN_CONF" ] && [ -s "$PIN_CONF" ]; then
    CFG="[$(T 'Set' '已配置')]"
else
    CFG="[$(T 'Not set' '未配置')]"
fi

# ====================== 输出 ======================
echo "  ╔══════════════════════════════════╗"
echo "  ║  48H PIN Timer Reset  v1.0     ║"
echo "  ╚══════════════════════════════════╝"
echo ""
echo "  $(T '[1] View Status    (current)' '[1] 查看状态    (当前)')"
echo "  $(T '[2] Change PIN     action.sh set-pin <PIN>' '[2] 修改 PIN     action.sh set-pin <PIN>')"
echo ""
echo "──────────────────────────────────────────────"

echo ""
echo "$(T 'Service' '服务'): $SVC    $(T 'Config' '配置'): $CFG"
echo "$(T 'Interval: every' '间隔: 每') $(fmt_dur "$CHECK_INTERVAL")"

# 读取上次刷新时间
if [ -f "$LAST_RESET" ]; then
    LAST_EPOCH=$(cat "$LAST_RESET" 2>/dev/null)
    if [ -n "$LAST_EPOCH" ] && [ "$LAST_EPOCH" -gt 0 ] 2>/dev/null; then
        NOW=$(date +%s)
        ELAPSED=$((NOW - LAST_EPOCH))
        REMAIN=$((CHECK_INTERVAL - ELAPSED))

        echo ""
        echo "$(T 'Last refresh' '上次刷新'): $(fmt_ts "$LAST_EPOCH")"
        echo "$(T 'Elapsed' '距上次'):     $(fmt_dur "$ELAPSED")"

        if [ "$REMAIN" -gt 0 ]; then
            echo "$(T 'Next refresh: in' '下次刷新: 约') $(fmt_dur "$REMAIN")"
            echo "          ($(fmt_ts "$((NOW + REMAIN))"))"
        else
            echo "$(T 'Next refresh: due soon...' '下次刷新: 即将执行...')"
        fi
    else
        echo ""
        echo "$(T 'Status file corrupted, waiting for service...' '状态文件异常，等待服务写入...')"
    fi
else
    echo ""
    echo "$(T 'No refresh record yet, generated after service starts' '尚无刷新记录，服务启动后生成')"
fi

# 最近日志
echo ""
echo "── $(T 'Recent logs' '最近日志') ──"
if [ -f "$LOG_FILE" ]; then
    tail -n 3 "$LOG_FILE" 2>/dev/null | while read -r line; do
        echo "$line"
    done
else
    echo "($(T 'none' '暂无'))"
fi
echo ""
echo "$(T 'Run in terminal to interact' '终端执行以交互'): su -c sh $MODDIR/action.sh"
