# 48H PIN Timer Reset

[![CI](https://github.com/shiftz300/pintimerreset/actions/workflows/ci.yml/badge.svg)](https://github.com/shiftz300/pintimerreset/actions/workflows/ci.yml)

Background PIN verification via GateKeeper HAL to reset the 48h strong auth timeout.
后台通过 GateKeeper HAL 验证 PIN，重置 Android 48 小时强认证超时。

---

## How It Works

```
service.sh (every N hours)
  → locksettings verify --old <PIN>
    → GateKeeper HAL (TEE) verifies PIN
      → LockSettingsService.onCredentialVerified()
        → mStrongAuth.reportSuccessfulStrongAuthUnlock()
          → 48h countdown reset to 0
```

### AOSP Source

| Step | Source File | Key Method |
|------|------------|------------|
| CLI entry | [`LockSettingsCmd.java`](https://cs.android.com/android/platform/superproject/+/main:frameworks/base/cmds/locksettings/src/com/android/commands/locksettings/LockSettingsCmd.java) | `locksettings verify` |
| TEE verification | [`LockSettingsService.java:2421`](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/services/core/java/com/android/server/locksettings/LockSettingsService.java) | `doVerifyCredential()` → `unlockLskfBasedProtector()` |
| Timer reset | [`LockSettingsService.java:3107`](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/services/core/java/com/android/server/locksettings/LockSettingsService.java) | `mStrongAuth.reportSuccessfulStrongAuthUnlock()` |

### Strong Auth Timeout Source

The system's "require PIN after X hours" value is stored in:

```
Settings.Secure.LOCK_TO_APP_EXPIRE  (milliseconds, default 259200000 = 72h)
```

Defined in [`LockPatternUtils.StrongAuthTracker`](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/core/java/com/android/internal/widget/LockPatternUtils.java) — OEMs (Samsung, etc.) override the default to 48h. This module can modify it:

```bash
action.sh set-timeout 24   # 24h
action.sh set-timeout 168  # 7 days
```

---

## Quick Start

```bash
# 1. Flash zip in KernelSU Manager

# 2. Set PIN
su -c sh /data/adb/modules/pin_timer_reset/action.sh set-pin 123456

# 3. Reboot
reboot
```

---

## Interactive Menu (Action Button)

Tap the module's **Action** button in KSU Manager:

```
  48H PIN Timer Reset  v1.0

  Vol+  = [1] View Status
  Vol-  = [2] Configuration
  (Wait 10s = default Status)
```

| Menu | Vol+ | Vol- | Timeout |
|------|------|------|---------|
| Main | View Status | Configuration | 10s → Status |
| Config | Set check interval | Change PIN | 8s → back |

---

## CLI Reference

```bash
action.sh                        # Interactive volume-key menu
action.sh set-pin <PIN>          # Set PIN directly
action.sh set-timeout <hours>    # Set system strong auth timeout (12/24/48/72/168/720)
action.sh --help                 # Show help
```

---

## Card Status (KSU Live Description)

Module card in KSU Manager dynamically updates after each refresh:

> `PIN OK | Last: 08:30 | Next: 14:30`

Updated by `service.sh` via `ksud module config set override.description`.

---

## Config

| Item | Location | Default |
|------|----------|---------|
| PIN | `pin.conf` (root-only, 0600) | required |
| Check interval | `CHECK_INTERVAL=` in `service.sh` | 21600s (6h) |
| System timeout | `action.sh set-timeout <h>` based on `Settings.Secure.LOCK_TO_APP_EXPIRE` | 48h (varies by OEM) |
| Log | `pin_reset.log` | rotated at 500 lines |

---

## Compatibility

- ✅ KernelSU (Action + card + volume-key CLI)
- ✅ Android 10–14 AOSP
- ⚠️ Magisk (basic only; card/action are KSU features)
- ⚠️ MIUI/HyperOS, Samsung OneUI — may vary

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `Config file not found` | Run `action.sh set-pin <PIN>` |
| `locksettings: not found` | ROM lacks the command |
| `Verification failed` | PIN in pin.conf doesn't match device PIN |
| Not working after flash | Reboot |

---

MIT License