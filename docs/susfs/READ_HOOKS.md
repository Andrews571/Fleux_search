# SUSFS 4.19 kernel-side read hooks

Fleux runs **SUSFS 2.3.0** on a **Linux 4.19.325** base. Upstream's read-hook
layer targets newer kernels — the 4.19 `vfs_getattr`, directory-iteration and
`/proc` helpers differ — so it is backported here at the kernel level. This is
the mechanism that makes SUSFS hide *on read*, not only at list/mount time.

The backport was diffed against the authoritative 4.19 patch and applied
byte-faithfully across all 17 files.

## What it enables

| SUSFS feature (config / CLI) | Read path it hooks |
|---|---|
| `SUS_PATH` | dentry lookup + directory listing (readdir/getdents) for flagged pathnames |
| `SUS_MOUNT` | `/proc/<pid>/mountinfo` and `/proc/<pid>/mounts` filtering, `statfs` |
| `SUS_KSTAT` | `stat`/`getattr` spoofing (ino, dev, size, blocks, times) of flagged inodes |
| `OPEN_REDIRECT` | `open()` redirection to a substitute target |
| `SPOOF_CMDLINE_OR_BOOTCONFIG` | fake `/proc/cmdline` for readers (see [`README.md`](README.md)) |
| symbol hiding | `susfs_*` symbols removed from `/proc/kallsyms` |
| AVC log spoofing | SELinux denial logs rewritten when the caller is the KSU domain |

## Per-process gating

Hiding must not apply to the root manager itself, so the hooks are gated:

- **`TIF_PROC_UMOUNTED`** — a per-task flag set by KernelSU/BakaSU for
  zygote-forked app and isolated processes. Plain shell/CLI processes do **not**
  carry it, which is why the `SUS_MOUNT` read paths are only reachable from app
  processes and cannot be driven from `adb shell`.
- **`susfs_is_current_app_uid()`** — true when
  `(current_uid().val % 100000) >= 10000`.
- **runtime toggles** — `susfs_is_*_enabled` static branches, set through
  `ksu_susfs` or the BakaSU SUSFS menu.

## Files touched

| File | Purpose |
|---|---|
| `fs/susfs.c` | core lists, enable flags, path/mount/kstat bookkeeping |
| `include/linux/susfs.h`, `include/linux/susfs_def.h` | hook prototypes, flags, `DEFAULT_KSU_MNT_ID` |
| `fs/namei.c` | sus-pathname filtering on lookup |
| `fs/readdir.c` | sus-path/mount filtering on directory listing |
| `fs/stat.c` | `vfs_getattr` SUS_KSTAT spoofing |
| `fs/statfs.c` | `statfs` spoofing over non-sus mounts |
| `fs/namespace.c` | mount hiding helper + `/proc` mount plumbing |
| `fs/super.c` | mount/superblock support hooks |
| `fs/proc_namespace.c` | `/proc/<pid>/mountinfo` \| `mounts` filtering |
| `fs/proc/task_mmu.c` | `/proc/<pid>/maps` \| `smaps` filtering |
| `fs/proc/base.c`, `fs/proc/fd.c`, `fs/notify/fdinfo.c` | `/proc/<pid>/fd` and fdinfo filtering |
| `mm/memory.c` | memory-map access helpers used by the proc hooks |
| `kernel/kallsyms.c` | symbol hiding |
| `security/selinux/avc.c` | AVC denial-log spoofing (ksu sid) |

## Review fixes

Two defensive defects were found in review and fixed (`e3fc45115310`):

1. **`fs/namespace.c` — `susfs_get_non_sus_vfsmnt_from_vfsmnt()`**: the
   `mnt_root` invalid/error path returned its argument without taking a
   reference, while `vfs_statfs()` unconditionally `dput()`/`mntput()`s the
   result — underflowing the mount refcount. It now returns a *referenced*
   original vfsmount (`mntget(&real_mount(vfsmnt)->mnt)`).
2. **`security/selinux/avc.c`** — the ksu-sid spoof branch jumped past the
   `kfree(scontext)` that `security_sid_to_context()` allocates, leaking on every
   spoofed denial. The `kfree(scontext)` is now reached on that path.

Neither is confirmed to be the trigger of the earlier hard hang; both are
correctness fixes.

## Version

A build carrying the backport plus these fixes reports:

```
4.19.325-Fleux-V6-SuSFS-HotFix
```

The trailing `+` that the kernel normally appends when `HEAD` is not at an
annotated tag is suppressed for this build via an empty `.scmversion` in the
source root.

## Stress test

[`susstress.sh`](susstress.sh) exercises the hooks under load: six root/ksu
readers, an app-uid reader, concurrent `SUS_KSTAT` / sus-path list churn, and an
app-launch loop that generates zygote/umounted traffic.

```sh
# run as root (e.g. su 0 -c ...)
sh susstress.sh 180        # duration in seconds
```

A 180 s run exercised `susfs_sus_kstat_spoof_generic_fillattr` (~290 calls),
`susfs_update_sus_kstat` (~340), `susfs_mark_inode_sus_kstat` and
`susfs_add_sus_path_loop` (~170 each) with **no** lockup, hung task, `BUG:`,
`WARNING` or call trace.
