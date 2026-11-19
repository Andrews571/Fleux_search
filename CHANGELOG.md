# Fleux kernel changelog

Fleux kernels for `fleur` / `miel` (POCO M4 Pro 4G / Redmi Note 11S 4G, MT6781).
The newest release is first. The same notes are published as GitLab release
descriptions, which the Fleux app renders in its update screen.

## Fleux ∞

Kernel: `4.19.325-Fleux-∞`  
Package: `Fleux-∞.zip`

Changes since V9:
- sched/fair: initialise `se->slice` in `place_entity()` before deriving the
  virtual slice, matching upstream EEVDF. New group entities no longer start
  with a zero-length request and an immediately expired deadline.
- sched/fair: scope the vendor `arch_get_cluster_cpus()` helper to
  `CONFIG_MTK_SCHED_EXTENSION`, removing an unused-function warning when the
  MTK scheduler extension is disabled.
- susfs: take the missing dentry reference on the non-SUS vfsmount fallback
  path, balancing the callers' unconditional `dput()` and preventing a dentry
  refcount underflow.
- build: switch `CONFIG_LOCALVERSION` to `-Fleux-∞`.
- app: treat `∞` as a version token and include the short token in the kernel
  status badge (`Fleux ∞` / `Fleux V9`), instead of always showing only
  "Fleux".
- release: merge manifest entries by tag instead of replacing the manifest,
  derive the kernel version from the full `kernelrelease`, and reject
  tag/LOCALVERSION mismatches.
- docs: correct the memfd_secret (returns `-ENOSYS` on arm64), ZRAM (lzo by
  default; LZ4 optional) and MGLRU descriptions.

SHA-256: `6e98549b90e3209e89e563214059c714aab44bbf5ca8132741862b46432395c4`

## V9

Kernel: `4.19.325-Fleux-V9`  
Package: `Fleux-V9.zip`

Changes since V8:
- Backport `rtmutex: Use waiter::task instead of current in remove_waiter()`
  (CVE-2026-43499, "GhostLock").
- `fs/nomount`: update to NoMount v2.2.0 (driver protocol 22).
- build: bump `LOCALVERSION` to `-Fleux-V9`.

Security: CVE-2026-43499 is a use-after-free (CWE-416, CVSS 3.1 7.8 High) in
the PI-futex/rtmutex proxy-lock rollback path, reachable from unprivileged
userspace via `futex(FUTEX_CMP_REQUEUE_PI)`. Updating from V8 is recommended.

SHA-256: `b6a53a3974ad6e2bc8ca75c869b60081166f9c2167183e30aaed68a0da0af5a3`

## V8

Kernel: `4.19.325-Fleux-V8`  
Package: `Fleux-V8.zip`

Changes since V7:
- KernelSU: sync to BakaSU `d5e9e025` (UAPI 6).
- KernelSU: fully branded as FleuxSU.
- KernelSU: only allow the FleuxSU manager.
- KernelSU: bump the submodule to include the ksud banner rebrand.
- build: point the KernelSU submodule at the Fleux mirror (`daliboss/FleuxSU`).
- build: declare Baseband-guard as a submodule.
- arm64/fleux: pin KernelSU to the local Fleux manager signature commit.
- arch/arm64: `fleur_defconfig`: enable KSPP slab/page hardening.
- mm/secretmem: fix use-after-free ordering and refuse direct-map-less arches.
- arch/arm64: `fleur_defconfig`: bump `LOCALVERSION` to `-Fleux-V8`.

SHA-256: `0bd36a3222a94058a1c29c9064a200ccb55a0d9c0b9d0c8e6695df3fd5153fda`

## V7

Kernel: `4.19.325-Fleux-V7`  
Package: `Fleux-V7.zip`

- arm64/configs: enable slab hardening (`SLAB_FREELIST_RANDOM`,
  `SLAB_FREELIST_HARDENED`) and zero-on-alloc
  (`INIT_ON_ALLOC_DEFAULT_ON`).
- mm/secretmem: fix use-after-free ordering in the fault handler and return
  `-ENOSYS` when the arch cannot remove pages from the direct map.

SHA-256: `43ab32c04481de568fb316d72740edb91e5a9f4f64e065ebc2f4d8207e1e8f92`

## V6 ManagerFix

Kernel: `4.19.325-Fleux-V6-SuSFS-HotFix-ManagerFix`  
Package: `Fleux-V6-ManagerFix.zip`

The kernel trusts a manager only when its APK signing certificate matches one
of the keys compiled into the kernel. On this tree that list held the upstream
BakaSU key, so a build signed with the Fleux release key was rejected and the
FleuxSU screen fell back to "No KernelSU driver detected — wrong kernel?".

- `kernel/manager/manager_sign.h`: add `EXPECTED_SIZE_FLEUX` /
  `EXPECTED_HASH_FLEUX`.
- `kernel/manager/apk_sign.c`: add the Fleux entry to `apk_sign_keys[]`.
- The build banner now reports Fleux among the supported managers.

Includes SUSFS v2.3.0 with the kernel-side read hooks (unchanged from V6 SuSFS
HotFix).

SHA-256: `be65dcf0baeb532ef8c0a50572801e71f1a661edd0d49ab74ec22dd9b6deacb4`

## V6 SuSFS HotFix

Kernel: `4.19.325-Fleux-V6-SuSFS-HotFix`  
Package: `Fleux-V6-SuSFS-HotFix.zip`

- SUSFS 2.3.0 kernel-side read hooks, backported to Linux 4.19 (17 files): the
  read-path layer behind `SUS_PATH`, `SUS_MOUNT`, `SUS_KSTAT` and
  `OPEN_REDIRECT`, plus `/proc/<pid>/mountinfo|mounts|maps|fd` filtering,
  `susfs_*` kallsyms hiding and SELinux AVC log spoofing.
- Fix a mount-refcount underflow in
  `susfs_get_non_sus_vfsmnt_from_vfsmnt()` (`fs/namespace.c`).
- Fix an `scontext` leak on the ksu-sid AVC spoof path
  (`security/selinux/avc.c`).

SHA-256: `a448ad7bb34bdff0a3ea03a60c1ab695c5f386e5411918f1f9ccb0d2de4d118a`

## V6

Kernel: `4.19.325-Fleux-V6`  
Package: `Fleux-V6.zip`

Changes since V5:
- EEVDF scheduler: committed to the EEVDF pick/preempt policy (backported to
  Linux 4.19), default-on, including the `uclamp` `UCLAMP_FLAG_IDLE` fix.
- GPU top OPP raised to 1.00 GHz (measured hardware ceiling ≈ 1.004 GHz; 1.00
  GHz chosen for margin, zero clock-switch asserts).
- SUSFS cmdline/bootconfig spoof: wire the read path so `/proc/cmdline` can
  present a fake locked/green line. Affects `/proc/cmdline` readers only;
  `ro.boot.*` properties are unchanged.

SHA-256: `699cf379a3ee5c45f5ad64dce3b678e5171d6fd05989e863aef0d34aa7c90386`

## V5

Kernel: `4.19.325-Fleux-V5`  
Package: `Fleux-V5.zip`

Changes since V4:
- Baseband-guard (BBG): lightweight LSM blocking unauthorized writes to
  critical partitions and device nodes (baseband + boot chain protection).
- BakaSU: KernelSU updated to BakaSU (`e5423590`), with SUSFS and multi-manager
  support.
- MGLRU (Multi-Gen LRU): multi-gen LRU page reclaim backported to Linux 4.19;
  on by default, toggle at `/sys/kernel/mm/lru_gen/enabled`.
- WireGuard enabled (`CONFIG_WIREGUARD=y`).

SHA-256: `5b84f3597bc561c4ad34be331f6d12a33703bd7f84c2668af03249602eb1f6e8`

## RSU / V4

Kernel: `4.19.325-Fleux-V4`  
Package: `Fleux-V4.zip`

Baseline release:
- Core / memory / I/O: KSM, BFQ, io_uring, uclamp, EROFS, LZ4, XATTR / POSIX
  ACL / security support, per-CPU decompression workers, HIPRI workers.
- Modern syscalls / APIs: `clone3()`, `waitid(P_PIDFD)`, `pidfd_open()`,
  `pidfd_send_signal()`, `pidfd_getfd()`, `openat2()`, `faccessat2()`,
  `epoll_pwait2()`, `memfd_secret()`.
- Android / performance: PSI (Pressure Stall Information).
- Filesystem / security: fs-verity, FUSE passthrough.
- Synchronization: futex improvements.

Note: `memfd_secret()` is wired into the syscall table but returns `-ENOSYS` on
arm64 because the linear map uses block mappings.

SHA-256: `fc1f3afdf370fefeeb9d7eb68c7511f575971537b4dca35ae62815acf174ddd8`
