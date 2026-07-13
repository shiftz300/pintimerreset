#!/system/bin/sh
# ===================================================================
# 48H PIN Timer Reset — 核心服务脚本
# 定时通过 locksettings 验证 PIN，重置 TEE 侧的 48 小时超时计时器
# ===================================================================
# shellcheck disable=SC3043

MODDIR=${0%/*}
CONFIG_FILE="$MODDIR/pin.conf"
LOG_FILE="$MODDIR/pin_reset.log"

# ---- Locale 检测 ----
is_zh() {
    local loc
    loc=$(getprop persist.sys.locale 2>/dev/null)
    [ -z "$loc" ] && loc=$(getprop ro.product.locale 2>/dev/null)
    case "$loc" in zh-*|zh_*) return 0 ;; *) return 1 ;; esac
}
T() { if is_zh; then echo "$2"; else echo "$1"; fi }

# ====================== 可配置项 ======================
# 检查间隔（秒），默认 6 小时 = 21600 秒
CHECK_INTERVAL=21600
# 日志文件最大行数（超过后轮转）
LOG_MAX_LINES=500
# ======================================================

# ---- 日志函数 ----
log() {
    echo "[$(date '+%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# ---- 日志轮转 ----
rotate_log() {
    LINE_COUNT=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "$LINE_COUNT" -gt "$LOG_MAX_LINES" ]; then
        tail -n "$LOG_MAX_LINES" "$LOG_FILE" > "${LOG_FILE}.tmp" 2>/dev/null
        mv -f "${LOG_FILE}.tmp" "$LOG_FILE" 2>/dev/null
    fi
}

# ---- 等待系统启动完成 ----
wait_for_boot() {
    log "--- $(T 'Waiting for boot to complete' '等待系统启动完成') ---"
    while [ "$(getprop sys.boot_completed)" != "1" ]; do
        sleep 5
    done
    sleep 30
    log "$(T 'System booted, starting PIN timer daemon' '系统已启动，开始 PIN 计时器守护')"
}

# ---- 检查 locksettings 命令是否可用 ----
check_locksettings() {
    if command -v locksettings >/dev/null 2>&1; then
        return 0
    fi
    # 部分 ROM 可能放在非标准路径
    if [ -x /system/bin/locksettings ]; then
        return 0
    fi
    return 1
}

# ---- 从配置文件读取 PIN ----
# 配置文件格式: 一行纯数字 PIN
read_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        log "$(T 'Config file not found' '配置文件不存在'): $CONFIG_FILE"
        log "  $(T 'Please run: action.sh set-pin <PIN>' '请执行: action.sh set-pin <PIN>')"
        return 1
    fi

    CRED=$(head -n 1 "$CONFIG_FILE" 2>/dev/null | tr -d '\n\r ')

    if [ -z "$CRED" ]; then
        log "$(T 'PIN is empty in config file' '配置文件中 PIN 为空')"
        return 1
    fi

    return 0
}

# ---- 核心: 重置 PIN 计时器 ----
# 原理: 调用 locksettings verify 触发一次真实的 PIN 验证
# gatekeeper HAL 验证成功后会刷新 auth token，将 48h 计时归零
reset_timer() {
    if ! check_locksettings; then
        log "$(T 'locksettings command not found, cannot verify' '系统无 locksettings 命令，无法执行验证')"
        return 1
    fi

    if ! read_config; then
        return 1
    fi

    log "$(T 'Verifying PIN...' '正在验证 PIN...')"

    RESULT=$(locksettings verify --old "$CRED" 2>&1)
    EXIT_CODE=$?

    if [ $EXIT_CODE -eq 0 ]; then
        NOW_EPOCH=$(date +%s)
        log "$(T 'Timer reset successful - 48h countdown refreshed' '计时器重置成功 — 48h 倒计时已刷新')"
        log "  $(T 'Next check' '下次检查'): $(date -d "@$(( NOW_EPOCH + CHECK_INTERVAL ))" '+%m-%d %H:%M:%S' 2>/dev/null || echo "~$((CHECK_INTERVAL / 3600))h $(T 'later' '后')")"
        # 写入状态文件供 action.sh 读取
        echo "$NOW_EPOCH" > "$MODDIR/last_reset.time"

        # 更新 KSU 模块卡片描述
        if command -v ksud >/dev/null 2>&1 && [ "$KSU" = "true" ]; then
            NEXT_TS=$(date -d "@$(( NOW_EPOCH + CHECK_INTERVAL ))" '+%H:%M' 2>/dev/null || echo "?")
            if is_zh; then
                CARD_DESC="PIN 正常 | 上次: $(date +%H:%M) | 下次: ${NEXT_TS}"
            else
                CARD_DESC="PIN OK | Last: $(date +%H:%M) | Next: ${NEXT_TS}"
            fi
            ksud module config set override.description "$CARD_DESC" 2>/dev/null || true
        fi

        return 0
    else
        log "$(T 'Verification failed (exit code' '验证失败 (退出码'): $EXIT_CODE)"
        log "  $(T 'Output' '输出'): $RESULT"
        log "  $(T 'Please check that the PIN in pin.conf matches your device PIN' '请确认 pin.conf 中的 PIN 与设备解锁 PIN 一致')"
        return 1
    fi
}

# ---- 备选方案: 通过 settings 命令操作 ----
alt_reset_timer() {
    log "$(T 'Trying alternative method (settings)...' '尝试备选方案 (settings 命令)...')"
    settings put secure lock_screen_lock_after_timeout 5000 2>/dev/null
    sleep 1
    settings put secure lock_screen_lock_after_timeout 0 2>/dev/null
    log "  $(T 'Alternative method executed (effects vary by ROM)' '备选方案已执行（效果因 ROM 而异）')"
}

# ====================== 主守护循环 ======================
main() {
    wait_for_boot

    log "=========================================="
    log "  48H PIN Timer Reset Service v1.0"
    log "  $(T 'Check interval' '检查间隔'): ${CHECK_INTERVAL}s ($((CHECK_INTERVAL / 3600))h)"
    log "  $(T 'Config file' '配置文件'): $CONFIG_FILE"
    log "  $(T 'Log file' '日志文件'): $LOG_FILE"
    log "=========================================="

    # 写出状态配置供 action.sh / WebUI 读取
    cat > "$MODDIR/status.conf" << STATEFILE
CHECK_INTERVAL=$CHECK_INTERVAL
STATEFILE

    # 启动后等待 60s 确保 locksettings 服务就绪
    sleep 60

    # 首次重置
    if ! reset_timer; then
        log "$(T 'First verification failed, retrying in 60s...' '首次验证失败，60s 后重试...')"
        sleep 60
        reset_timer || true
    fi

    # 循环定时重置
    FAIL_COUNT=0
    while true; do
        sleep "$CHECK_INTERVAL"
        rotate_log

        if reset_timer; then
            FAIL_COUNT=0
        else
            FAIL_COUNT=$((FAIL_COUNT + 1))
            # 连续失败 3 次后尝试备选方案
            if [ $FAIL_COUNT -ge 3 ]; then
                log "$(T 'Failed' '连续失败') $FAIL_COUNT $(T 'times, trying alternative' '次，尝试备选方案')"
                alt_reset_timer
                FAIL_COUNT=0
            else
                log "  $(T 'Will retry in 5 minutes...' '将在 5 分钟后重试...')"
                sleep 300
            fi
        fi
    done
}

main
