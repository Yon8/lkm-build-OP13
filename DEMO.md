# Demo Guide

This guide shows the shortest path from a built `nohello.ko` to a visible demo.

Use only a device you own or have permission to test. Avoid system files. The
safe demo target used here is:

```text
/data/local/tmp/nohello
```

## 1. Check The Device

```sh
adb shell uname -r
adb shell getprop ro.product.device
adb shell getprop ro.build.version.release
```

Use the kernel release to choose the matching GitHub Actions artifact, for
example `android15-6.6_nohello.ko` for an Android 15 / 6.6 GKI target.

## 2. Create The Demo File

```sh
adb shell
su
echo "demo secret" > /data/local/tmp/nohello
ls -l /data/local/tmp/nohello
cat /data/local/tmp/nohello
exit
exit
```

Expected: the file exists and prints `demo secret`.

## 3. Push And Load

```sh
adb push nohello.ko /data/local/tmp/nohello.ko
adb shell
su
insmod /data/local/tmp/nohello.ko target_path=/data/local/tmp/nohello
dmesg | grep nohello
```

Expected logs include:

```text
nohello: target ino=...
nohello: hooked security_inode_permission
nohello: hooked security_inode_getattr
nohello: loaded -- /data/local/tmp/nohello is now hidden
```

If the `getdents64` hook is unavailable, direct access should still be hidden,
but the file may remain visible in directory listings.

If a device hangs while listing the parent directory, unload and retry without
directory-list filtering:

```sh
rmmod nohello
insmod /data/local/tmp/nohello.ko target_path=/data/local/tmp/nohello hide_dirents=0
```

To hide more than one path manually, use `target_paths`:

```sh
echo "demo secret a" > /data/local/tmp/nohello-a
echo "demo secret b" > /data/local/tmp/nohello-b
insmod /data/local/tmp/nohello.ko target_paths=/data/local/tmp/nohello-a,/data/local/tmp/nohello-b
```

To hide only from selected app UIDs:

```sh
insmod /data/local/tmp/nohello.ko target_paths=/data/local/tmp/nohello-a scope_mode=deny deny_uids=10123
```

## 4. Verify Hiding

```sh
ls -l /data/local/tmp/nohello
cat /data/local/tmp/nohello
stat /data/local/tmp/nohello
ls -la /data/local/tmp | grep nohello
```

Expected:

- `ls`, `cat`, and `stat` report that the target does not exist.
- The final directory-list command prints nothing.

## 5. Unload And Verify Recovery

```sh
rmmod nohello
ls -l /data/local/tmp/nohello
cat /data/local/tmp/nohello
dmesg | grep nohello
```

Expected: the file is visible again.

## 6. Package For KernelSU

After building `nohello.ko`, package the wrapper zip.

Windows:

```powershell
.\tools\package_ksu.ps1 -KoPath .\kernel\nohello.ko -Output .\out\nohello-ksu.zip -TargetPath /data/local/tmp/nohello
```

Multi-path package:

```powershell
.\tools\package_ksu.ps1 -KoPath .\kernel\nohello.ko -Output .\out\nohello-ksu.zip -TargetPath "/data/local/tmp/nohello-a,/data/local/tmp/nohello-b"
```

Direct-access-only fallback package:

```powershell
.\tools\package_ksu.ps1 -KoPath .\kernel\nohello.ko -Output .\out\nohello-ksu-direct.zip -TargetPath /data/local/tmp/nohello -HideDirents 0
```

Blacklist package:

```powershell
.\tools\package_ksu.ps1 -KoPath .\kernel\nohello.ko -Output .\out\nohello-ksu-deny.zip -TargetPath "/system_ext/app/SoterService,/system/app/EasterEgg" -ScopeMode deny -DenyPackage "com.example.detector"
```

Linux/macOS:

```sh
TARGET_PATH=/data/local/tmp/nohello ./tools/package_ksu.sh kernel/nohello.ko out/nohello-ksu.zip
```

Multi-path package:

```sh
TARGET_PATHS=/data/local/tmp/nohello-a,/data/local/tmp/nohello-b ./tools/package_ksu.sh kernel/nohello.ko out/nohello-ksu.zip
```

After installing the KernelSU package, open its WebUI to edit paths, switch
between global and blacklist mode, select packages, and reload the module.

For late-created `/dev` paths, increase the wait time while packaging:

```powershell
.\tools\package_ksu.ps1 -KoPath .\kernel\nohello.ko -Output .\out\nohello-ksu.zip -TargetPath "/dev/example,/system_ext/app/SoterService" -ScopeMode deny -DenyPackage "com.example.detector" -TargetWaitSeconds 90 -PackageWaitSeconds 90
```

For very dynamic paths such as `/data/incremental/...`, the path must exist at
reload time. If boot-time loading skips it, create or trigger the path first,
then use WebUI `Save & Reload`.

Install `out/nohello-ksu.zip` from KernelSU Manager and reboot. The bundled
`service.sh` loads `nohello.ko` only when the target file already exists, which
keeps the demo easier to recover from.

## Troubleshooting

`insmod: failed: No such file or directory`

The target path did not exist when the module loaded. Create the file first, or
change `target_path` / `target_paths`.

`Exec format error` or `Invalid module format`

The module does not match the device kernel/KMI. Check `dmesg` for `vermagic`
details and rebuild for the correct target.

`Operation not permitted`

Root was not granted, module loading is blocked, or the kernel does not allow
this external module.

Direct access is hidden but `ls` still shows the file

The `__arm64_sys_getdents64` probe failed to register on that kernel. Check
`dmesg | grep nohello`.

`ls /parent | grep target` does not finish

Unload the module with `rmmod nohello`. Rebuild with the latest source, or load
with `hide_dirents=0` to keep direct `ls/stat/cat` hiding while leaving parent
directory listings unfiltered.
