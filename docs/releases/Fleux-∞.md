Fleux ∞ kernel (4.19.325-Fleux-∞) for fleur/miel — POCO M4 Pro 4G / Redmi Note 11S 4G.

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

Fleux-∞.zip sha256: 6e98549b90e3209e89e563214059c714aab44bbf5ca8132741862b46432395c4
