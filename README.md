# 48H PIN Timer Reset — KernelSU Module

[![CI](https://github.com/shiftz300/pintimerreset/actions/workflows/ci.yml/badge.svg)](https://github.com/shiftz300/pintimerreset/actions/workflows/ci.yml)

Periodically resets the Android 48-hour PIN timeout by verifying your device PIN in the background via the GateKeeper HAL. Prevents forced PIN entry after extended inactivity without compromising security.

定期通过 GateKeeper HAL 后台验证设备 PIN，重置 Android 48 小时超时计时器，防止长时间未解锁后强制要求输入 PIN。

---

## How It Works / 工作原理

```
┌──────────────┐    every 6h    ┌──────────────────┐     GateKeeper     ┌──────────────┐
│  service.sh  │ ────────────→ │ locksettings      │ ────────────────→ │  TEE (Trusted │
│  (daemon)    │               │ verify --old <PIN>│                   │  Execution)   │
└──────────────┘               └───────┬────────────┘                   └──────┬───────┘
                                       │  RESPONSE_OK                         │
                                       ▼                                      ▼
                               ┌──────────────────┐                   ┌──────────────┐
                               │ LockSettingsService│                  │ Auth Token   │
                               │ onCredentialVerified│                 │ refreshed    │
                               │ → reportSuccessful │                 │ 48h countdown│
                               │   StrongAuthUnlock │                 │ reset to 0   │
                               └──────────────────┘                   └──────────────┘
```

### AOSP Source depending

The entire verification chain is traceable in the Android Open Source Project:

#### 1. `locksettings verify` CLI → LockSettingsService

**Source:** [`frameworks/base/cmds/locksettings/src/com/android/commands/locksettings/LockSettingsCmd.java`](https://cs.android.com/android/platform/superproject/+/main:frameworks/base/cmds/locksettings/src/com/android/commands/locksettings/LockSettingsCmd.java)

```
locksettings verify --old <PIN>
  → LockSettingsCmd.main()
    → ILockSettings.shellCommand()
      → LockSettingsShellCommand dispatches "verify"
        → LockSettingsService.verifyCredential()
```

#### 2. PIN verification via GateKeeper HAL (TEE)

**Source:** [`LockSettingsService.java:2421-2492 — doVerifyCredential()`](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/services/core/java/com/android/server/locksettings/LockSettingsService.java)

```java
// doVerifyCredential() — verifies the credential through GateKeeper HAL
long protectorId = getCurrentLskfBasedProtectorId(userId);
authResult = mSpManager.unlockLskfBasedProtector(
    getGateKeeperService(), protectorId, credential, userId, progressCallback);
```

This sends the PIN to the TEE (Trusted Execution Environment) via the GateKeeper HAL for hardware-backed verification — the same path used by the lockscreen UI.

#### 3. StrongAuth timer reset on successful verification (THE KEY LINE)

**Source:** [`LockSettingsService.java:3077-3110 — onCredentialVerified()`](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/services/core/java/com/android/server/locksettings/LockSettingsService.java)

```java
// Line 3107 — THIS resets the 48h countdown
mStrongAuth.reportSuccessfulStrongAuthUnlock(userId);
```

`reportSuccessfulStrongAuthUnlock()` clears the strong authentication timeout flags in `LockSettingsStrongAuth`, resetting the 48-hour countdown to zero. This is the exact same method called when you unlock your device through the lockscreen.

## Features / 功能

- **Interactive CLI menu** — Action button shows [1] View Status / [2] Change PIN menu
- **Live card status** — Module card dynamically shows: `PIN OK | Last: 08:30 | Next: 14:30`
- **action set-pin** — Configure PIN with a single command, no file editing needed
- **Auto locale** — Chinese UI on zh-CN systems, English otherwise
- **Zero dependencies** — Uses only built-in `locksettings` command

---

## Quick Start / 快速开始

### 1. Install / 安装

Package the module:

```bash
cd PinTimerReset
zip -r ../PinTimerReset.zip . -x ".git/*" ".github/*" "README.md"
```

or just download zip from relese

then flash it in KernelSU Manager

### 2. Configure PIN / 配置 PIN

```bash
# Via action script (recommended / 推荐)
su -c sh /data/adb/modules/pin_timer_reset/action.sh set-pin 123456

# Or edit directly / 或直接编辑
echo "123456" > /data/adb/modules/pin_timer_reset/pin.conf
```

### 3. Reboot / 重启

---

## Action Menu / 操作菜单

Click the **Action** button in KSU Manager / 在 KSU 管理器点击「操作」按钮:

```
╔══════════════════════════════════╗
║  48H PIN Timer Reset  v1.0     ║
╚══════════════════════════════════╝

[1] View Status    (current)
[2] Change PIN     action.sh set-pin <PIN>
──────────────────────────────────────────
Service: [Running]    Config: [Set]
Interval: every 6h0m0s

Last refresh: 2026-07-14 08:31:45
Next refresh: in 3h44m30s
...
```

---

## View Logs / 查看日志

```bash
tail -f /data/adb/modules/pin_timer_reset/pin_reset.log
```

Sample log / 日志示例：
```
[07-14 08:30:45] System booted, starting PIN timer daemon
[07-14 08:31:45] Verifying PIN...
[07-14 08:31:45] Timer reset successful - 48h countdown refreshed
[07-14 08:31:45]   Next check: 07-14 14:31:45
```

---

## Configuration / 配置

### Check Interval / 检查间隔

Edit `CHECK_INTERVAL` in `service.sh` (default: 21600s = 6h):

```bash
CHECK_INTERVAL=10800   # 3 hours / 3 小时
CHECK_INTERVAL=43200   # 12 hours / 12 小时
```

### Config File / 配置文件

`/data/adb/modules/pin_timer_reset/pin.conf`:

| Line / 行 | Content / 内容 | Required / 必填 |
|---|---|---|
| 1 | Device unlock PIN (digits only) / 设备解锁 PIN（纯数字） | ✅ |

> **Security / 安全**: `/data/adb/modules/` is only accessible by root (UID 0) and shell (UID 2000). Regular apps cannot read it.

---

## Compatibility / 兼容性

- ✅ KernelSU (Action button + live card status + action config)
- ✅ Android 10 ~ 14 (AOSP)
- ⚠️ Magisk (basic compatibility; card description & action are KSU-only)
- ⚠️ MIUI/HyperOS — may need to disable MIUI optimization
- ⚠️ Samsung OneUI — lock screen policy may differ
- ❌ Devices without lock screen (this module is unnecessary)

---

## Troubleshooting / 故障排查

| Problem / 问题 | Cause / 原因 | Solution / 解决方法 |
|---|---|---|
| `Config file not found` | pin.conf not created | Run `action.sh set-pin <PIN>` |
| `locksettings command not found` | ROM stripped the command | Incompatible; try alternative ROM |
| `Verification failed (exit code: 1)` | PIN mismatch | Check pin.conf matches unlock PIN |
| Module not working after flash | Not rebooted | Reboot the device |

---

## Uninstall / 卸载

Remove the module in KernelSU Manager and reboot. No persistent system modifications are made.

在 KernelSU 管理器中移除模块并重启。模块不会对系统做任何持久性修改。

---

## License / 许可证

MIT License