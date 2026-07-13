#!/system/bin/sh
# ===================================================================
# 48H PIN Timer Reset — 安装脚本
# ===================================================================
# shellcheck disable=SC3043

# ---- Locale 检测 ----
is_zh() {
    local loc
    loc=$(getprop persist.sys.locale 2>/dev/null)
    [ -z "$loc" ] && loc=$(getprop ro.product.locale 2>/dev/null)
    case "$loc" in zh-*|zh_*) return 0 ;; *) return 1 ;; esac
}
T() { if is_zh; then echo "$2"; else echo "$1"; fi }

ui_print ""
ui_print "  ╔══════════════════════════════════════╗"
ui_print "  ║   48H PIN Timer Reset Module v1.0   ║"
ui_print "  ╚══════════════════════════════════════╝"
ui_print ""
ui_print "  $(T '- Auto-verify PIN every 6h to reset 48h timeout' '- 每 6 小时自动验证 PIN，重置 48h 超时')"
ui_print "  $(T '- KSU card shows real-time refresh status' '- KernelSU 卡片实时显示刷新状态')"
ui_print ""

# ---- 配置 PIN 引导 ----
PIN_CONF="$MODPATH/pin.conf"

ui_print "  ────── $(T 'Configure PIN' '配置解锁 PIN') ──────"
ui_print ""
ui_print "  $(T 'After install, run in terminal:' '安装后通过终端执行:')"
ui_print "    su -c sh $MODPATH/action.sh set-pin $(T 'YOUR_PIN' '你的PIN')"
ui_print ""
ui_print "  $(T 'Or edit pin.conf directly then reboot' '或直接编辑 pin.conf 后重启')"
ui_print ""

# 创建模板 pin.conf
printf '%s\n' '# Replace this line with your device unlock PIN' > "$PIN_CONF"

# 设置权限
set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/service.sh"  0 0 0755
set_perm "$MODPATH/action.sh"   0 0 0755
set_perm "$MODPATH/pin.conf"    0 0 0600

ui_print "  $(T 'Install complete - configure PIN then reboot' '安装完成 — 配置 PIN 后重启生效')"
ui_print ""
