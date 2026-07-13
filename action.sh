#!/system/bin/sh
# ===================================================================
# KernelSU Action — 音量键交互式 CLI
# Vol+ = 查看状态    Vol- = 修改 PIN
# 无参数时进入交互模式；也支持命令行参数直接调用
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
T() { if is_zh; then echo "$2"; else echo "$1"; fi }

# ---- 加载状态配置 ----
CHECK_INTERVAL=21600
# shellcheck source=/dev/null
[ -f "$STATUS_CONF" ] && . "$STATUS_CONF"

# ====================== 参数解析 ======================
CMD="${1:-}"

# -- set-pin: 直接设置 PIN（命令行模式）
if [ "$CMD" = "set-pin" ]; then
    NEW_PIN="${2:-}"
    if [ -z "$NEW_PIN" ]; then
        echo "$(T 'Usage: action.sh set-pin <PIN>' '用法: action.sh set-pin <PIN>')"
        echo "$(T 'Example: action.sh set-pin 123456' '示例: action.sh set-pin 123456')"
        exit 1
    fi
    echo "$NEW_PIN" > "$PIN_CONF"
    chmod 600 "$PIN_CONF" 2>/dev/null
    echo "$(T 'PIN updated. Reboot to take effect.' 'PIN 已更新，重启后生效。')"
    exit 0
fi

# -- set-timeout: 修改强认证超时
if [ "$CMD" = "set-timeout" ]; then
    HOURS="${2:-}"
    if [ -z "$HOURS" ] || ! [ "$HOURS" -gt 0 ] 2>/dev/null; then
        echo "$(T 'Usage: action.sh set-timeout <hours>' '用法: action.sh set-timeout <小时>')"
        echo "$(T 'Common: 12 24 48 72 168(7d) 720(30d)' '常用: 12 24 48 72 168(7d) 720(30d)')"
        exit 1
    fi
    MS=$((HOURS * 3600 * 1000))
    settings put secure lock_to_app_exipire "$MS" 2>/dev/null
    echo "$(T 'Timeout set to' '超时已设为') ${HOURS}h."
    exit 0
fi

# -- help
if [ "$CMD" = "-h" ] || [ "$CMD" = "--help" ]; then
    echo "$(T 'Usage:' '用法:') action.sh [command] [args]"
    echo "  $(T '(none)              Interactive volume-key menu' '(无参数)            音量键交互菜单')"
    echo "  set-pin <PIN>         $(T 'Set unlock PIN directly' '直接设置解锁 PIN')"
    echo "  set-timeout <hours>   $(T 'Set strong auth timeout' '设置强认证超时')"
    echo "  -h, --help            $(T 'Show this help' '显示帮助')"
    exit 0
fi

# ====================== 以下：音量键交互模式 ======================

# ---- 格式化 ----
fmt_dur() {
    local s=$1 h m
    [ "$s" -lt 0 ] 2>/dev/null && { echo "--"; return; }
    h=$((s / 3600)); m=$(((s % 3600) / 60)); s=$((s % 60))
    [ "$h" -gt 0 ] && printf "%dh%dm%ds" "$h" "$m" "$s" && return
    [ "$m" -gt 0 ] && printf "%dm%ds" "$m" "$s" && return
    printf "%ds" "$s"
}
fmt_ts() { date -d "@$1" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "N/A"; }

# ---- 找音量键输入设备 ----
find_key_dev() {
    for dev in /dev/input/event*; do
        if getevent -p "$dev" 2>/dev/null | grep -q "KEY_VOLUMEUP"; then
            echo "$dev"
            return 0
        fi
    done
    return 1
}

# ---- 等待音量键（返回 0=UP, 1=DOWN, 2=超时） ----
wait_volkey() {
    local timeout=${1:-10}
    local dev
    dev=$(find_key_dev 2>/dev/null)
    [ -z "$dev" ] && return 2

    local start
    start=$(date +%s)
    local key
    while true; do
        key=$(timeout 1 getevent -l -c 1 "$dev" 2>/dev/null | grep -oE "KEY_VOLUME(UP|DOWN)")
        if echo "$key" | grep -q "UP"; then return 0; fi
        if echo "$key" | grep -q "DOWN"; then return 1; fi
        if [ "$(($(date +%s) - start))" -ge "$timeout" ]; then return 2; fi
    done
}

# ---- 显示状态 ----
show_status() {
    if pgrep -f "pin_timer_reset.*service\.sh" >/dev/null 2>&1; then
        SVC="[$(T 'Running' '运行中')]"
    else
        SVC="[$(T 'Stopped' '未运行')]"
    fi
    if [ -f "$PIN_CONF" ] && [ -s "$PIN_CONF" ]; then
        CFG="[$(T 'Set' '已配置')]"
    else
        CFG="[$(T 'Not set' '未配置')]"
    fi

    echo ""
    echo "$(T 'Service' '服务'): $SVC    $(T 'Config' '配置'): $CFG"
    echo "$(T 'Interval: every' '间隔: 每') $(fmt_dur "$CHECK_INTERVAL")"

    # 显示系统强认证超时
    SYS_TO=$(settings get secure lock_to_app_exipire 2>/dev/null)
    if [ -n "$SYS_TO" ] && [ "$SYS_TO" -gt 0 ] 2>/dev/null; then
        SYS_TO_H=$((SYS_TO / 3600000))
        echo "$(T 'Sys timeout' '系统超时'): ${SYS_TO_H}h  $(T '(change: set-timeout <h>)' '(修改: set-timeout <h>)')"
    fi

    if [ -f "$LAST_RESET" ]; then
        LAST_EPOCH=$(cat "$LAST_RESET" 2>/dev/null)
        if [ -n "$LAST_EPOCH" ] && [ "$LAST_EPOCH" -gt 0 ] 2>/dev/null; then
            NOW=$(date +%s)
            ELAPSED=$((NOW - LAST_EPOCH))
            REMAIN=$((CHECK_INTERVAL - ELAPSED))
            echo "$(T 'Last refresh' '上次刷新'): $(fmt_ts "$LAST_EPOCH")  ($(fmt_dur "$ELAPSED") $(T 'ago' '前'))"
            if [ "$REMAIN" -gt 0 ]; then
                echo "$(T 'Next refresh' '下次刷新'): $(fmt_ts "$((NOW + REMAIN))")  ($(T 'in' '还有') $(fmt_dur "$REMAIN"))"
            else
                echo "$(T 'Next refresh: due soon...' '下次刷新: 即将执行...')"
            fi
        fi
    else
        echo "$(T 'No refresh record yet, generated after service starts' '尚无刷新记录，服务启动后生成')"
    fi

    echo ""
    echo "── $(T 'Recent logs' '最近日志') ──"
    if [ -f "$LOG_FILE" ]; then
        tail -n 3 "$LOG_FILE" 2>/dev/null | while read -r line; do echo "$line"; done
    else
        echo "($(T 'none' '暂无'))"
    fi
}

# ---- 设置检查间隔（音量键选择） ----
set_interval_interactive() {
    echo ""
    echo "--- $(T 'Set Check Interval' '设置检查间隔') ---"
    echo ""
    echo "  $(T 'Vol+ = next value'  'Vol+ = 下一个值')"
    echo "  $(T 'Vol- = confirm'     'Vol- = 确认')"
    echo ""

    PRESETS="3 6 12 24"
    CUR_H=$((CHECK_INTERVAL / 3600))
    IDX=0; for v in $PRESETS; do [ "$v" = "$CUR_H" ] && break; IDX=$((IDX + 1)); done

    while true; do
        VAL=$(echo "$PRESETS" | cut -d' ' -f$((IDX + 1)))
        printf '\r  %s: [%sh]  ' "$(T 'Interval' '间隔')" "$VAL"

        WAIT=$(wait_volkey 8)
        case "$WAIT" in
            0) IDX=$(( (IDX + 1) % 4 )) ;;
            1) sed -i "s/^CHECK_INTERVAL=.*/CHECK_INTERVAL=$((VAL * 3600))/" "$MODDIR/service.sh"
               echo ""
               echo "$(T 'Interval set to' '间隔已设为') ${VAL}h. $(T 'Restart service or reboot.' '重启服务或重启设备生效。')"
               return 0 ;;
            2) echo ""; echo "$(T 'Cancelled.' '已取消。')"; return 0 ;;
        esac
    done
}

# ---- 交互式 PIN 修改（音量键输入数字） ----
change_pin_interactive() {
    echo ""
    echo "--- $(T 'Enter new PIN' '输入新 PIN') ---"
    echo ""
    echo "  $(T 'Vol+ = increase digit (0-9)' 'Vol+ = 数字 +1 (0~9)')"
    echo "  $(T 'Vol- = confirm digit / next' 'Vol- = 确认当前位 / 下一位')"
    echo "  $(T 'Wait 5s  = finish input'     '等待 5s = 结束输入')"
    echo ""

    PIN=""
    DIGIT=0
    while true; do
        printf '\r  PIN: %s[%d]' "$(echo "$PIN" | sed 's/./*/g')" "$DIGIT"

        WAIT=$(wait_volkey 5)
        case "$WAIT" in
            0) DIGIT=$(( (DIGIT + 1) % 10 )) ;;
            1) PIN="${PIN}${DIGIT}"; DIGIT=0 ;;
            2) PIN="${PIN}${DIGIT}"; break ;;
        esac
    done

    if [ -z "$PIN" ] || [ "$PIN" = "0" ]; then
        echo ""
        echo "$(T 'PIN empty or zero. Cancelled.' 'PIN 为空或全零。已取消。')"
        return 1
    fi

    echo "$PIN" > "$PIN_CONF"
    chmod 600 "$PIN_CONF" 2>/dev/null
    echo ""
    echo "$(T 'PIN saved! Reboot to take effect.' 'PIN 已保存！重启后生效。') ($(T 'length' '长度'): ${#PIN})"
}

# ---- 配置子菜单 ----
config_menu() {
    echo ""
    echo "--- $(T 'Configuration' '配置') ---"
    echo ""
    echo "  $(T 'Vol+  = Set check interval'   'Vol+  = 设置检查间隔')"
    echo "  $(T 'Vol-  = Change PIN'           'Vol-  = 修改 PIN')"
    echo "  $(T '(Wait 8s = back)'             '(等待8秒 = 返回)')"

    WAIT=$(wait_volkey 8)
    case "$WAIT" in
        0) set_interval_interactive ;;
        1) change_pin_interactive ;;
        2) echo "$(T 'Back.' '已返回。')" ;;
    esac
}

# ====================== 主交互菜单 ======================
echo ""
echo "  $(T '48H PIN Timer Reset  v1.0' '48H PIN Timer Reset  v1.0')"
echo ""
echo "  $(T 'Vol+  = [1] View Status'      'Vol+  = [1] 查看状态')"
echo "  $(T 'Vol-  = [2] Configuration'    'Vol-  = [2] 配置')"
echo "  $(T '(Wait 10s = default Status)'  '(等待10秒 = 默认显示状态)')"

WAIT=$(wait_volkey 10)
case "$WAIT" in
    0|2) show_status ;;
    1) config_menu ;;
esac

echo ""
echo "$(T 'CLI: set-pin <PIN> | set-timeout <h> | --help' 'CLI: set-pin <PIN> | set-timeout <h> | --help')"
