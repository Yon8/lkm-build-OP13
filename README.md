# NoHello LKM Demo

NoHello is a small Android arm64 / GKI external kernel module demo. It hides
configured file paths from common filesystem operations by resolving target
inodes at load time and installing kretprobes around VFS-related paths.

This repository is intended for controlled lab/demo use on your own device or
another device where you have explicit permission.

## What It Builds

- `kernel/nohello.c`: kernel module source.
- `kernel/Kbuild`: declares the external module target.
- `kernel/Makefile`: invokes the Android/GKI kernel build tree.
- `ksu-module/`: a minimal KernelSU module wrapper that loads `nohello.ko`.
- `ksu-module/webroot/`: KernelSU WebUI for editing paths and App blacklist.
- `tools/package_ksu.ps1` and `tools/package_ksu.sh`: package helpers.
- `.github/workflows/`: GitHub Actions builds for multiple Android KMI targets.

The default demo target is:

```text
/data/local/tmp/nohello
```

You can override it at load time with the legacy single-path parameter:

```sh
insmod /data/local/tmp/nohello.ko target_path=/data/local/tmp/nohello
```

For multiple paths, use `target_paths` with comma-separated absolute paths:

```sh
insmod /data/local/tmp/nohello.ko target_paths=/data/local/tmp/a,/data/local/tmp/b
```

Directory listing filtering can be disabled while keeping direct access hidden:

```sh
insmod /data/local/tmp/nohello.ko target_paths=/data/local/tmp/a,/data/local/tmp/b hide_dirents=0
```

To hide only from selected app UIDs, use deny scope:

```sh
insmod /data/local/tmp/nohello.ko target_paths=/data/local/tmp/a scope_mode=deny deny_uids=10123,10124
```

## Current Status

The project is demo-ready, but it is not a production hardening project.

Implemented:

- Hides direct access through `security_inode_permission`.
- Hides stat/getattr-style checks through `security_inode_getattr`.
- Filters `getdents64` results so the target is removed from directory lists.
- Supports up to 16 configured target paths per module load.
- Supports `scope_mode=global` and `scope_mode=deny`. Deny scope hides only
  from configured app UIDs.
- Provides a KernelSU wrapper template for boot-time loading.
- Provides a KernelSU WebUI for managing paths, App blacklist, direct UID
  blacklist, scope mode, and `hide_dirents`.
- Provides a `hide_dirents` fallback parameter. Set it to `0` if directory
  enumeration is unstable on a device.

Known limitations:

- At least one target path must exist before `insmod`, because the module
  stores `(dev, inode)` identities at load time. Missing paths are skipped.
- Directory-list filtering compares `d_ino`, because `getdents64` does not
  expose the device id in each returned entry. A same-inode file on another
  filesystem could be hidden from a listing, though direct access checks still
  use both dev and inode.
- Existing open file descriptors are not hidden retroactively.
- The module must match the device KMI/kernel version and arm64 ABI.
- `scope_mode=deny` requires app UIDs to be resolved before module load. The
  KernelSU service resolves package names from `deny_packages.conf`.
- Directory-list filtering is the riskiest part of this demo because it edits
  the `getdents64` user buffer after the syscall returns. If `ls` appears to
  hang, unload the module and retry with `hide_dirents=0`.

## Build

### GitHub Actions

Push to `main` or run the `Build LKM for All KMI Targets` workflow manually.
Artifacts are named like:

```text
android15-6.6_nohello.ko
```

Pick the artifact that matches your device KMI.

### Local DDK/Kernel Build

If your DDK container exports `KDIR`, run:

```sh
cd kernel
CONFIG_KSU=m CC=clang make
```

If you have a kernel build directory locally, pass it explicitly:

```sh
cd kernel
make KDIR=/path/to/kernel/build
```

The output is:

```text
kernel/nohello.ko
```

## Manual Test

On the device:

```sh
adb shell
su
echo "demo secret" > /data/local/tmp/nohello
ls -l /data/local/tmp/nohello
cat /data/local/tmp/nohello
```

Push and load the module:

```sh
adb push kernel/nohello.ko /data/local/tmp/nohello.ko
adb shell
su
insmod /data/local/tmp/nohello.ko target_path=/data/local/tmp/nohello
dmesg | grep nohello
```

To hide multiple paths manually:

```sh
insmod /data/local/tmp/nohello.ko target_paths=/data/local/tmp/a,/data/local/tmp/b
```

To hide only from one app UID:

```sh
insmod /data/local/tmp/nohello.ko target_paths=/data/local/tmp/a scope_mode=deny deny_uids=10123
```

Verify:

```sh
ls -l /data/local/tmp/nohello
cat /data/local/tmp/nohello
stat /data/local/tmp/nohello
ls -la /data/local/tmp
```

Unload:

```sh
rmmod nohello
```

## KernelSU Package

`nohello.ko` is not installed directly in KernelSU. KernelSU installs a module
zip, and that zip contains `nohello.ko` plus a `service.sh` script that calls
`insmod`.

Windows PowerShell:

```powershell
.\tools\package_ksu.ps1 -KoPath .\kernel\nohello.ko -Output .\out\nohello-ksu.zip -TargetPath /data/local/tmp/nohello
```

Pass comma-separated values to `-TargetPath` for a multi-path package:

```powershell
.\tools\package_ksu.ps1 -KoPath .\kernel\nohello.ko -Output .\out\nohello-ksu.zip -TargetPath "/data/local/tmp/a,/data/local/tmp/b"
```

Use `-HideDirents 0` if you want direct-access hiding only.

Use `-ScopeMode deny` and `-DenyPackage` / `-DenyUid` for a blacklist package:

```powershell
.\tools\package_ksu.ps1 -KoPath .\kernel\nohello.ko -Output .\out\nohello-ksu.zip -TargetPath "/system_ext/app/SoterService,/system/app/EasterEgg" -ScopeMode deny -DenyPackage "com.example.detector"
```

Linux/macOS shell:

```sh
TARGET_PATH=/data/local/tmp/nohello ./tools/package_ksu.sh kernel/nohello.ko out/nohello-ksu.zip
```

For multiple paths:

```sh
TARGET_PATHS=/data/local/tmp/a,/data/local/tmp/b ./tools/package_ksu.sh kernel/nohello.ko out/nohello-ksu.zip
```

Use `HIDE_DIRENTS=0` if you want direct-access hiding only.

Use `SCOPE_MODE=deny` with package names or UIDs for blacklist mode:

```sh
SCOPE_MODE=deny DENY_PACKAGES=com.example.detector DENY_UIDS=10123 ./tools/package_ksu.sh kernel/nohello.ko out/nohello-ksu.zip
```

Inside the KernelSU module, `target_path.conf` supports one path per line:

```text
/data/local/tmp/a
/data/local/tmp/b
```

Blacklist config files:

```text
scope_mode.conf       # global or deny
deny_packages.conf    # one package name per line
deny_uids.conf        # one UID per line
target_wait_seconds.conf
package_wait_seconds.conf
```

The WebUI is available from KernelSU Manager after installing the module. It
edits these files and can reload `nohello.ko` without requiring a reboot.

In deny scope, `service.sh` waits for package UID resolution before loading.
It also waits for configured paths so late-created `/dev` entries have a chance
to exist before `nohello.ko` resolves target inodes.

Paths that do not exist when `nohello.ko` loads are skipped. For dynamic paths
such as `/data/incremental/...`, open the WebUI and use `Save & Reload` after
the path exists, or reload manually. The WebUI uses short waits during manual
reloads to keep the page responsive.

Install `out/nohello-ksu.zip` in KernelSU Manager, reboot, then check:

```sh
su
dmesg | grep nohello
```

To package a safer direct-access-only build:

```powershell
.\tools\package_ksu.ps1 -KoPath .\kernel\nohello.ko -Output .\out\nohello-ksu-direct.zip -TargetPath /data/local/tmp/nohello -HideDirents 0
```

You can also change it on the device after installation:

```sh
su
echo 0 > /data/adb/modules/nohello-demo/hide_dirents.conf
reboot
```

## Use Your Own Module

Replace `kernel/nohello.c` with your module source and update `kernel/Kbuild`.
For a single source file:

```makefile
obj-m += mymod.o
```

For multiple source files:

```makefile
obj-m += mymod.o
mymod-y := mymod_main.o mymod_hook.o mymod_util.o
```

Then update the KernelSU template and package scripts if your output module is
not named `nohello.ko`.
