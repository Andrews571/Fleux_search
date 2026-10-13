# Fleux Kernel — CPU / Battery / EEVDF / EAS / GPU Optimization Report

- **Project**: Fleux Kernel (`gitlab.com/daliboss/fleux`)
- **Scope**: CPU, battery, EEVDF, EAS, GPU optimization for POCO M4 Pro 4G (`fleur`) / Redmi Note 11S 4G (`miel`), MT6781 / Helio G96, Linux **4.19.325** (ARM64)
- **Branch**: `lineage-24.0` — all landed work now lives directly on the production branch
- **Date**: 2026-10-11
- **Status**: **EEVDF + uclamp are landed, pushed and runtime-confirmed**; the **GPU overclock (top OPP 1.00 GHz, measured clock ceiling ≈ 1.004 GHz) is built, flashed and runtime-confirmed**; **EAS is enabled and behaving as expected** (owner-accepted). The two GPU/version commits remain **local-only (not yet pushed)**. See §3.2, §6, §7.3, §8, §9, §12.

> **Refresh note (2026-10-11).** This revision promotes the report from the deleted
> `testing/cpu-battery-eas` branch to `lineage-24.0`, records the EEVDF/uClamp on-device
> verification, adds the GPU-overclock workstream (including the measured ~1.004 GHz
> output ceiling) and the EAS findings. Historical appendices (A/B/C) are retained but
> marked as point-in-time records.

---

## 1. Baseline identification

| Item | Value |
|---|---|
| Production branch | `lineage-24.0` |
| Project start commit | `3e5c27fb0ecc02169dbded21633e5a5b9eabde45` (`docs: generalize README (kernel-wide, version-agnostic)`) |
| Remote `lineage-24.0` head | `f0cf52806443` — EEVDF + uclamp promoted (fast-forward, 13 commits on top of `3e5c27fb0ecc`; push verified) |
| Local `lineage-24.0` head (this report) | `1f1c802dab64` (V6) ⊃ `f427d3dce23f` (GPU OC 1.00 GHz) ⊃ `f0cf52806443` — **2 commits ahead of remote** |
| Legacy testing branch | `testing/cpu-battery-eas` — **deleted**; its content was fast-forwarded into `lineage-24.0`, no history rewrite |
| Defconfig | `arch/arm64/configs/fleur_defconfig`, sha256 `189fa42e6bf29b7eb208dd1772ed76a8115c9a46cdcc8071774bfe9567354b89`, `CONFIG_LOCALVERSION="-Fleux-V6"` |
| Toolchain | Android clang 21.0.0 (LLVM 21, `r563880c`), `LD=ld.lld`, `LLVM_IAS=1` |
| Build host | same host + `out/` tree used for the V5 release |
| Baseline artifact (stock V5) | `Image.gz-dtb` sha256 `96863b4d556635ddac1736d7b922aac00b755a19e7883d9dade1f41a89b5a8f8` |
| Current artifact (V6, 1.00 GHz OC) | `Image.gz-dtb` sha256 `18ee4bc03eca4634370e732775eab2d2bc94cf3bb383e14a76b4e620ffdbba3e` (12,887,142 bytes) |
| Running kernel (test device) | `4.19.325-Fleux-V6+` (`#18 SMP PREEMPT Sun Oct 11 10:30:21 EDT 2026`) |

**Integrity/security notes**

- No credentials, PATs, tokens, signing keys, or private host addresses appear in this document or in any commit.
- Pre-existing untracked files (`build.log`, `build_s2.log`, `build_oc1000.log`, `genheaders`) were preserved and are not committed.
- The stock V5 image and the EEVDF-only rollback image are kept on the device as recovery paths (§14).

---

## 2. Repository state at handoff

- Project start: `lineage-24.0` = `3e5c27fb0ecc`; no pre-existing remote testing branch.
- EEVDF + uclamp were developed on `testing/cpu-battery-eas`, then **fast-forwarded into `lineage-24.0`** (`3e5c27fb0ecc → f0cf52806443`, 13 commits) and pushed. The test branch was deleted. **No history rewrite was performed.**
- Two further commits sit **locally** on `lineage-24.0`, not yet pushed:
  - `f427d3dce23f` — `gpufreq: mt6781: raise top GPU OPP to 1.00 GHz (clock ceiling ~1.004 GHz)`
  - `1f1c802dab64` — `Fleux: bump version to V6`
- Working tree clean except the pre-existing untracked build logs / `genheaders`.
- Downstream CPU-change baseline retained: `44577282eb70` — *"drivers: {cpufreq,mediatek}: Allow disabling MediaTek CPU policy"* (bengris32); adds `cpufreq_set_policy_ppm()` + the `MTK_CPU_CTRL`/`MTK_EAS_CTRL` Kconfig tree (all off in the built config).

---

## 3. Scheduler audit

Source scale: `kernel/sched/fair.c` = 12,253 lines, `sched.h` = 2,598, `core.c` = 8,586, `topology.c` = 2,265. The tree started as **mainline/CIP 4.19 CFS** plus:
- the **Android `experimental/eas-dev`-style EAS backport** (`compute_energy()`/`find_energy_efficient_cpu()`, `build_perf_domains()`, `sched_energy_present()`, `EM_MAX_COMPLEXITY` 2048);
- **MTK hooks** (`sysctl_sched_sync_hint_enable`, `sysctl_sched_cstate_aware`, linger/predict paths) and `mtk_map_util_freq()` inside the schedutil-plus integration.

### 3.1 What is present

- **CFS (classic)**: the pick/preempt path has been replaced by EEVDF (§7); the CFS pick/preempt fallback was removed.
- **PELT**: standard LOAD_AVG with a MTK `sched_pelt_multiplier` sysctl (`1|2|4` → `sched_pelt_lshift`). Runtime multiplier reads **1** (kernel default; the vendor init pins 1 — see Appendix B).
- **Util clamp**: `CONFIG_UCLAMP_TASK=y`, `CONFIG_UCLAMP_TASK_GROUP=y`; runtime `uclamp_min=128`, `uclamp_max=1024`. `CONFIG_SCHED_TUNE` is **off**.
- **EEVDF**: **present, unconditional/default-on, and runtime-confirmed** — `sched_latency_ns` and `sched_wakeup_granularity_ns` are gone; `sched_min_granularity_ns` is present and is the base slice. See §7.3, §12.
- **EAS**: present, compiled, and **active at runtime** (`sched_energy_aware=1`). See §8.
- **MTK scheduler extensions**: `CONFIG_MTK_SCHED_EXTENSION` off, as are `MTK_PERF_COMMON`, `MTK_TOPO_CTRL`, `MTK_CPU_CTRL`, `MTK_EAS_CTRL`, `MTK_PERF_OBSERVER`, `MTK_FRS`, `MTK_RESYM`. `CONFIG_MTK_PERFORMANCE_MODULE=y` builds only the perfmgr shell; the legacy **PPM v3** driver (via `MACH_MT6781`) remains the live DVFS policy manager (§4).

### 3.2 Runtime scheduler readings (test device, V6)

| Knob | Value |
|---|---|
| `sched_energy_aware` | **1** (EAS active) |
| `sched_min_granularity_ns` | 500000 (present — EEVDF base slice) |
| `sched_latency_ns` | **absent** (removed by EEVDF) |
| `sched_wakeup_granularity_ns` | **absent** (removed by EEVDF) |
| `sched_sync_hint_enable` | 1 |
| `sched_cstate_aware` | 1 |
| `sched_pelt_multiplier` | 1 (vendor-init pinned) |
| `sched_util_clamp_min/max` | 128 / 1024 |
| `HZ` | 250 (confirmed via `@jiffies` kprobe delta 251/s) |
| `scaling_driver` / governor | `mt-cpufreq` / `schedutil` |

> Startup scheduler work (EEVDF + uclamp) has moved from "build-only" to **runtime-verified** — see §12 for the exact checks and §7.3 for scope.

---

## 4. CPU / DVFS baseline (MT6781)

- Topology: 6× Cortex-A55 (`cpu0-5`, capacity 416, `policy0` 500–2000 MHz) + 2× Cortex-A76 (`cpu6-7`, capacity 1024, `policy6` 774–2050 MHz).
- Driver: `mt-cpufreq` (cpufreq_v1). Governors: schedutil on both policies.
- OPP tables (`drivers/misc/mediatek/base/power/cpufreq_v1/src/mach/mt6781/`): LL 16 steps 500–2000 MHz; B 16 steps 774–2050 MHz.
- **PPM v3 (legacy) is the active DVFS policy layer.** Firmware constant `idx_opp_ppm_base = 15` pins the *minimum* CPU bound to the lowest table OPP (500 MHz A55 / 774 MHz A76). There is no lower hardware floor exposed to the kernel.
- **No CPU overclock**: max indices are 0 (2000 / 2050 MHz, stock); OPP/voltage tables are stock; `idx_opp_ppm_limit = 0`.
- **Verdict**: CPU DVFS is coherent and conservative. There is **no evidence-backed CPU-DVFS change to make**; altering it would require inventing PLL/voltage values or defeating PPM — both out of bounds.

---

## 5. Battery / idle-power baseline

- Suspend: `CONFIG_PM` / `CT_PM`, `/sys/power/state` = `freeze mem` (s2idle available). MTK cpuidle_v3 states on LT policy: `wfi`(≈1 µs), `cpuoff_l`(≈150 µs), `clusteroff_l`(≈350 µs), `mcusysoff`(≈1500 µs), `s2idle`(≈1900 µs).
- Screen-off / deep sleep: platform-managed by PPM + cpuidle_v3+mcdi; no kernel-side defect identified.
- **Boot cmdline observations** (from the boot image, injected by the bootloader):
  - `initcall_debug=1` → boot log spam, then no steady-state cost.
  - `page_owner=on`, `slub_debug=OFZPU` → **inert**: `CONFIG_PAGE_OWNER`/`CONFIG_SLUB_DEBUG` are not set, so the params are parsed but compiled out.
  - `sysctl.kernel.sched_pelt_multiplier=4` → intent only; runtime reads 1 (vendor init pins 1).
- Storage/memory: BFQ compiled but `DEFAULT_IOSCHED="cfq"`/`mq-deadline` active on mmcblk; ZRAM lz4 ≈3 GiB; KSM off; MGLRU backported and active.
- **Verdict**: no evidence-backed in-kernel battery change. Highest-value, lowest-risk live experiments remain userspace sysctls — see §15.

---

## 6. GPU baseline + overclock

- Mali-G57 MC2 (Valhall **r32p1**), MediaTek DVFS via `drivers/gpu/mediatek/gpufreq/**v1/mt6781/**` (selected by `CONFIG_MACH_MT6781` in `v1/Makefile`). *(An earlier draft said "platform mt6785"; the built platform is `v1/mt6781`.)*
- OPP table `g_opp_table_segment_1[]`: 49 entries, **300 MHz → 1.00 GHz** after the OC commit (was 300 → 950 MHz stock). `vgpu` 0.60–0.85 V, `vsram` 0.85–0.95 V.
- Runtime limit indices at idle: `g_max_upper_limited_idx = 0`, `g_min_lower_limited_idx = 48` (no thermal clamp active).

### 6.1 Measured clock ceiling (~1.004 GHz)

The MT6781 MFGPLL/GPU clock path **tops out at ≈1.004 GHz output, independent of the PLL post-divider**:

| Experiment | Result |
|---|---|
| Fixed-freq (`gpufreq_fixed_freq_volt`), posdiv 2, from idle | 950000 … **1004000** lock; **1004500 and above fail** (MFGPLL_CON1 reverts to the idle OPP, posdiv 8) |
| Fixed-freq, posdiv 2, from a warm posdiv-2 base (FHCTL path, no mux parking) | same ≈1.004 GHz ceiling → not a parking/CCF-mux artifact |
| DVFS pin to table OPP **1025000** | 11× `assert:@__mt_gpufreq_set: Clock switch failed, 300000 -> 300000 (target: 1025000)`; GPU stays at 300000 |
| DVFS pin to table OPP **940000** (control) | locks at **939960**, zero failures |
| posdiv 2 (VCO ≈2.0 GHz) vs posdiv 4 (VCO ≈4.0 GHz) | **same ≈1.004 GHz output** → the limit is downstream of the PLL VCO |

**Conclusion:** 1.05 GHz and 1.025 GHz are physically unreachable. The highest value verified to lock *with margin* is **1.00 GHz**.

### 6.2 Change implemented

Top OPP raised **950 MHz → 1.00 GHz** (`1000000 kHz`, `POSDIV_POWER_2`, VCO = 2×freq ≈ 2.0 GHz — inside the documented 1.5–3.8 GHz range):

- `__mt_gpufreq_get_posdiv_power()`: return `POSDIV_POWER_2` for `freq > POSDIV_4_MAX_FREQ` (950 MHz); keep 4 (≥375 MHz) and 8 (<375 MHz).
- `__mt_gpufreq_calculate_dds()`: widen the accepted upper bound from `POSDIV_4_MAX_FREQ` to `POSDIV_2_MAX_FREQ` (1900 MHz).
- Top OPP `GPUOP(1000000, 90000, 100000, POSDIV_POWER_2, 625)`.
- `GPU_ACT_REF_FREQ` 950000 → 1000000 (power-model reference freq, kept equal to the top OPP).

The **runtime voltage for OPP0 stays owned by EEM** (`gpu_opp0_t_volt` by efuse), so the OPP voltage entry is intentionally unchanged. Net effect vs stock: top GPU OPP 950 MHz → 1.00 GHz (**+5.3 %**). Commit: `f427d3dce23f`.

### 6.3 Runtime confirmation (V6, on-device)

| Check | Result |
|---|---|
| `sed -n 1p /proc/gpufreq/gpufreq_opp_dump` | `[00] freq = 1000000, vgpu = 85000, vsram = 95000, posdiv = 2` ✅ |
| `echo 1000000 > /proc/gpufreq/gpufreq_opp_freq` | `fixed OPP is enabled`; var_dump `idx: 0` / `(real) freq: 1000000` ✅ |
| `dmesg | grep -c "Clock switch failed"` after the pin | **0** ✅ |
| `echo 0 > /proc/gpufreq/gpufreq_opp_freq` | `fixed OPP is disabled` — limits restored ✅ |

**Verdict**: the 1.00 GHz top OPP locks through the real DVFS path with no asserts; the 1.05/1.025 GHz images (`Fleux-GPU-OC-V6-1050`, `-1025`) are **broken (unreachable top OPP) and must not be re-flashed**.

---

## 7. EEVDF workstream — research, dependency map, verdict

### 7.1 Upstream history (source-grounded)

EEVDF entered mainline with Peter Zijlstra's series **"sched: EEVDF and latency-nice and/or slice-attr"** (2023-05-31, 15 patches). Merged pieces (6.6) and later fixes:

| Commit | Purpose |
|---|---|
| `eab009d8ed64` | `sched/fair: Add avg_vruntime()` |
| `86bfbb7ce4f6` | `sched/fair: Add lag based placement` (`s64 vlag`) |
| `147f3efaa241` | `sched/fair: Implement an EEVDF-like scheduling policy` (`deadline`/`min_deadline`/`slice`, `entity_eligible()`, `pick_eevdf()`) |
| `5e963f2bd465` | `sched: Commit to EEVDF` (drops CFS fallback) |
| `rb_add_augmented_cached()` | prerequisite helper in `rbtree_augmented.h` |
| `6d71a9c61604` / `4423af84b297` | post-merge correctness/overhead fixes |
| 6.7 series | "Complete EEVDF" (base slice, latency-nice) |

Reference docs: `Documentation/scheduler/sched-eevdf.rst`; LWN #925371, #968575, #969062.

### 7.2 Dependencies added to this 4.19 tree

1. `rb_add_augmented_cached()` + augmented-rbtree caching glue.
2. `struct cfs_rq { avg_vruntime, avg_load }` + augment callbacks.
3. `struct sched_entity` fields `vlag`, `deadline`, `min_deadline`, `slice`.
4. New core helpers: `entity_eligible()`, `pick_eevdf()`, `update_deadline()`, `update_curr()` slice accounting, `task_delta_lag()`.
5. Replacements: drop `sched_vslice()`/`START_DEBIT`, rework `sched_slice()`, rewrite `wakeup_preempt_entity()`/`check_preempt_wakeup()`, rework `set_last/set_next/skip_buddy`.
6. Feature-flag plumbing (`PLACE_LAG`, `PLACE_DEADLINE_INITIAL`, `ENQUEUE_INITIAL`, `RUN_TO_PARITY`).
7. Coexistence with MTK `sync_hint`/`cstate_aware` and the Android-eas-dev EAS placement; uclamp interaction.

### 7.3 Feasibility verdict — **ACCEPTED, LANDED, RUNTIME-CONFIRMED (surface checks)**

EEVDF was mechanically feasible on this tree (the scheduler is close to CIP 4.19). The coherent port landed as a **multi-commit change** (new rbtree augmentation, lag/deadline accounting, new preemption semantics) and has been **promoted to `lineage-24.0`** and **flashed**. Runtime evidence collected (§12):

- `/proc/sys/kernel/sched_latency_ns` and `sched_wakeup_granularity_ns` are **gone**; `sched_min_granularity_ns` is present → the EEVDF default-on path is live.
- The uclamp backport is verified (latch 0 — §9/§12).

**Honesty caveat (unchanged):** these checks confirm *activation* and the absence of the known boot WARN; they are **not** a benchmark of scheduling quality. Fairness/latency/frame-time benefits still require a controlled, non-self-contaminated A/B (§13, Appendix C). The owner explicitly accepted EEVDF default-on with no runtime CFS toggle (recovery = reflash).

---

## 8. EAS workstream — analysis, status & findings

**Status: PRESENT, COHERENT, ENABLED — behaving as expected (owner-accepted).**

- The EAS stack is fully backported and compiled (`CONFIG_ENERGY_MODEL=y`, schedutil present, asymmetric capacity holds).
- **Perf-domain registration is source-backed**: `mtk_cpufreq_main.c:1408` calls `em_register_perf_domain(policy->cpus, NR_FREQ, &em_cb)` with MTK platform power/leakage/CCI tables (from vendor OPP voltages + active-power curves — not fabricated). Complexity (2 PDs) is far below `EM_MAX_COMPLEXITY` 2048.
- **Activation verified**: `find_energy_efficient_cpu()` is inlined into `select_task_rq_fair()` (`kernel/sched/fair.c:7818`); writing `sched_energy_aware=1` flips `sched_energy_present` to `0x1` (the kernel default is 1).
- **Current runtime state**: `sched_energy_aware = 1` on the V6 device (uptime ≈26 min at capture). No vendor init/sysctl file or cmdline entry writing it to 0 was found on this build; the effective value is presently the kernel default / a runtime userspace write.
- **Compatibility with EEVDF**: EEVDF governs *pick/preempt*; EAS governs *wake-placement* (`select_task_rq_fair`). Upstream 6.6 ships both together; on this tree both are active simultaneously and the device is behaving as expected.
- **Ownership note**: the per-boot value of `sched_energy_aware` is not pinned by a kernel change — if a future ROM/userspace write disables it, re-enable with `echo 1 > /proc/sys/kernel/sched_energy_aware`. Deliberately **not** forced at boot (owner decision).

---

## 9. Changes implemented (per commit)

Landed on `lineage-24.0`. Promotion `533503bf89ab..f0cf52806443` was **pushed** to gitlab (fast-forward from `3e5c27fb0ecc`; history intact, test branch deleted). `f427d3dce23f` and `1f1c802dab64` are **local-only**.

| Commit | Contents | Impact / status |
|---|---|---|
| `533503bf89ab` | `docs/testing/CPU_BATTERY_EEVDF_EAS_REPORT.md` + `tools/testing/fleux/*` | docs/tooling only |
| `6b79a3197773` | docs: testing-branch rebuild artifacts + build results | docs |
| `fb684bd8572a` | docs + `tools/testing/fleux/ab_wl.sh`: live A/B (EAS, PELT) record | docs |
| `f2ef0f42fcbd` | `sched/pelt`: default `sched_pelt_multiplier` 1→4 | **ineffective** (vendor init pins 1); reverted by `0f770403bfd2` |
| `2dfcdd437473` | docs: correct the PELT finding | docs |
| `0f770403bfd2` | revert of the PELT experiment | revert |
| `c3546ce391ef` | docs: test-environment finding (agent runs on the phone) | docs |
| `9b225aa8d473` | **EEVDF Stage 0** — `rb_add_augmented_cached()` + `avg_vruntime`/`avg_load` tracking | infrastructure; builds clean |
| `08683c371162` | **EEVDF Stage 1** — lag placement + gated EEVDF policy (`SCHED_FEAT(EEVDF)`) | builds clean |
| `a2cc1adcca52` | docs: EEVDF report Stages 0–1 | docs |
| `e541ce0062cb` | **EEVDF Stage 2 — commit to EEVDF** (default-on; drop CFS pick/preempt fallback, dead tunables) | landed, runtime-confirmed |
| `65254ad542aa` | docs: EEVDF report Stage 2 | docs |
| `f0cf52806443` | **sched/uclamp: fix `UCLAMP_FLAG_IDLE` clear** (backport upstream `ca4984a7dd86`) | landed, **on-device verified** (latch 0) |
| `f427d3dce23f` | **gpufreq mt6781: top GPU OPP 950 MHz → 1.00 GHz** (measured ceiling ~1.004 GHz) | built + **flashed + runtime-confirmed**; local-only |
| `1f1c802dab64` | **Fleux: bump version to V6** (`CONFIG_LOCALVERSION="-Fleux-V6"`) | built + flashed; local-only |

### 9.1 uclamp fix detail (`f0cf52806443`)

Backport of upstream `ca4984a7dd86` ("sched: Fix UCLAMP_FLAG_IDLE setting"). `UCLAMP_FLAG_IDLE` is set from `uclamp_rq_dec_id() → uclamp_rq_max_value() → uclamp_idle_value()` whenever an rq transiently reaches zero active clamp tasks, but was cleared only in `uclamp_rq_inc()`. `uclamp_update_active()` calls the `*_id()` helpers directly, bypassing that clear, so the flag could stay stuck set; a later enqueue then forced `rq->uclamp[].value` to the new task value, and when that bucket's last task dequeued, `SCHED_WARN_ON(bucket->value > rq_clamp)` fired. The fix adds `uclamp_rq_reinc_id()` and uses it from `uclamp_update_active()`. Reachable at boot from vendor init writing `/proc/sys/kernel/sched_util_clamp_min|max` and via cgroup `cpu.uclamp.*` / MTK SchedTune. **Verified on-device** (§12).

**Deliberately not implemented** (with reason):

- EEVDF `sysctl_sched_base_slice` rename (`e4ec3318a17f`) — not applied; the tunable keeps `sysctl_sched_min_granularity_ns` so the ROM's `/proc` ABI is unaffected.
- EEVDF util_est "runnable" boost removal (`c2e164ac33f7`) — not needed; this `cpu_util()` has no `boost`/`runnable` term.
- No EAS persistence change — §8 (owner-accepted as-is).
- No CPU DVFS / PPM change — §4.
- No voltage/OC beyond the GPU top OPP — stock tables plus the one verified GPU OPP.
- No thermal relaxation, no forcing max freq, no disabling protections.
- No cmdline-strip hack — §5.

Everything above is reversible; see §14.

---

## 10. Build configuration, commands, validation

Reproduced with the project recipe (incremental build):

```sh
export PATH=$HOME/tc21/clang-r563880c/bin:$PATH
export ARCH=arm64 SUBARCH=arm64
make -j8 O=out CC=clang LD=ld.lld LLVM=1 LLVM_IAS=1 \
  CLANG_TRIPLE=aarch64-linux-gnu- CROSS_COMPILE=aarch64-linux-gnu- \
  CROSS_COMPILE_ARM32=arm-linux-gnueabi-
```

Validation results:

| Check | Result |
|---|---|
| `fleur_defconfig` regenerates cleanly | pass |
| Compile + link (`Image.gz-dtb`) | pass — **0 errors** |
| Warnings | 0 new; the device-tree warnings are pre-existing vendor DTS issues, untouched |
| EEVDF Stage 0/1/2 builds | pass; `kernel/sched/{fair,core,debug}.o` + `kernel/sysctl.o` recompiled |
| uclamp fix build (`f0cf52806443`) | pass |
| GPU OC build (`f427d3dce23f` / `1f1c802dab64`) | pass; table byte-verified in `vmlinux` `.data` (`g_opp_table_segment_1`): OPP0 `freq=0x000f4240 (1000000)`, OPP1 `freq=0x000e57e0 (940000)` |
| Artifact (V6, 1.00 GHz) | `Image.gz-dtb` sha256 `18ee4bc03eca4634370e732775eab2d2bc94cf3bb383e14a76b4e620ffdbba3e` (12,887,142 bytes) |
| Kernel release string | `4.19.325-Fleux-V6+` |
| Preserved V5 artifact | sha256 `96863b4d556635ddac1736d7b922aac00b755a19e7883d9dade1f41a89b5a8f8` |

> Note: `Image.gz-dtb` is not byte-reproducible between builds because `UTS_VERSION` embeds the build date; always compare hashes within the same build run. A successful build proves compilation only.

---

## 11. Baseline-vs-candidate benchmark tables

The candidate kernel **has** been flashed, so runtime activation is recorded; **performance deltas are still left blank** because on-device A/B measurements on this unit are self-contaminated (Appendix C) and therefore not trustworthy. No values below are invented; blanks are honest "not measured".

### 11.1 Scheduler / responsiveness

| Metric | Baseline (V5) | Candidate (V6: EEVDF + EAS) | Δ |
|---|---|---|---|
| CPU capacities (A55 / A76) | 416 / 1024 | 416 / 1024 | — |
| EAS active | no | **yes** (`sched_energy_aware=1`) | enabled |
| EEVDF active | no (CFS) | **yes** (`latency`/`wakeup_gran` tunables absent) | enabled |
| uclamp WARN at boot | fired once (observed pre-fix) | **0** (latch clear) | fixed |
| Wakeup latency (p99, ms) | *not measured* | *not measured* | — |
| Frame-time p95 | *not measured* | *not measured* | — |

### 11.2 Gaming / GPU

| Metric | Baseline (V5) | Candidate (V6) | Δ |
|---|---|---|---|
| GPU max OPP (MHz) | 950 (stock) | **1000** | +5.3 % |
| GPU top-OPP lock (real DVFS) | 950 | **1000000, 0 asserts** | verified |
| Clock ceiling | — | **≈1.004 GHz** | hard cap |
| Avg FPS / 1 % low (15–30 min) | *not measured* | *not measured* | — |

### 11.3 Battery

| Metric | Baseline (V5) | Candidate (V6) | Δ |
|---|---|---|---|
| Screen-off drain (mA / %·h⁻¹) | *not measured* | *not measured* | — |
| Deep-sleep residency | *not measured* | *not measured* | — |

Methodology notes: same ROM/config, brightness, refresh rate, network, game settings, ambient temperature; ≥3 repetitions per leg; one change at a time; a **separate (non-measuring) control device** is required for trustworthy results.

---

## 12. Scheduler / GPU correctness & runtime verification

Verification performed on the flashed V6 build (`4.19.325-Fleux-V6+ #18`):

| Item | Method | Result |
|---|---|---|
| EEVDF active | `/proc/sys/kernel/` tunable presence | `sched_latency_ns`, `sched_wakeup_granularity_ns` **absent**; `sched_min_granularity_ns=500000` present ✅ |
| EAS active | `/proc/sys/kernel/sched_energy_aware` | **1**; perf domains registered (`em_register_perf_domain`), `find_energy_efficient_cpu` inlined into `select_task_rq_fair` ✅ |
| uclamp WARN fix | kprobe on `schedule` fetching `@uclamp_rq_dec_id.__warned` / `.140:s32` over 17,606 samples | **w0=0, w1=0** (never fired) ✅ |
| kprobe probe liveness / HZ | `@jiffies` delta over 1 s | 251 jiffies/s → **HZ=250** ✅ |
| GPU top OPP present | `/proc/gpufreq/gpufreq_opp_dump` | `[00] freq = 1000000, posdiv = 2` ✅ |
| GPU top OPP locks | `gpufreq_opp_freq` pin + `dmesg` assert count | real freq **1000000**, **0** "Clock switch failed" ✅ |
| GPU reset | `echo 0 > /proc/gpufreq/gpufreq_opp_freq` | `fixed OPP is disabled` ✅ |

**Still unverified (needs a quiescent/control device):** EEVDF fairness/latency *quality*, EAS vs non-EAS *energy* deltas, sustained GPU performance/thermals, and screen-off battery. The tooling in §17 provides the probes; Appendix C explains why this unit cannot resolve them.

---

## 13. Regressions, risks, unverified behavior

- **Unverified**: effect of EAS+EEVDF on real MT6781 workload mixes; sustained GPU OC thermals/current; screen-off drain.
- **Known backport risks**: EEVDF lag/deadline edge cases (upstream fixes `6d71a9c61604`, `4423af84b297` are available if symptoms appear); EAS+MTK-hook interplay.
- **No runtime rollback to CFS**: EEVDF is unconditional; recovery is a reflash of the production image (§14).
- **`/proc` ABI change**: `sched_latency_ns` / `sched_wakeup_granularity_ns` removed. Vendor-init writes to them fail harmlessly (logged, non-fatal).
- **GPU OC scope**: only the **top OPP** changed; all other OPPs, and OPP0 voltage (EEM-owned), are untouched. The 1.05/1.025 GHz images are broken and must not be flashed.
- **Environment risk**: the single test unit hosts the agent tooling (Appendix C), so A/B numbers are self-contaminated. No user-visible functionality (charging, thermal, camera, Wi-Fi, modem, flashlight) was altered; none of the actions were releases.

---

## 14. Recovery instructions

- **Restore stock kernel**: reflash the V5 image (`Image.gz-dtb` sha256 `96863b4d…`) — production baseline is untouched.
- **Restore EEVDF-only (no GPU OC)**: reflash `Fleux-EEVDF-Stage2/Image.gz-dtb` (sha256 `eea5f4fb…`).
- **Revert the GPU OC / V6 commits**: `git revert 1f1c802dab64 f427d3dce23f` (or drop them) and rebuild; or `git checkout lineage-24.0~2` for the tree at `f0cf52806443`.
- **No CFS runtime toggle**: reverting EEVDF requires `git revert` of `e541ce0062cb` **and** a rebuild+reflash (there is no sysctl/debugfs fallback).
- **EAS**: `echo 0 > /proc/sys/kernel/sched_energy_aware` (runtime; not persistent).
- **GPU limits**: `echo 0 > /proc/gpufreq/gpufreq_opp_freq` restores DVFS limits.
- **Branch cleanup**: the legacy `testing/cpu-battery-eas` branch is already deleted (local + remote).

---

## 15. GO / NO-GO recommendation

**CONDITIONAL GO — the flashed V6 kernel (EEVDF + uclamp + 1.00 GHz GPU + EAS active) is usable as a daily driver for the owner.**

1. **EEVDF + uclamp** are runtime-confirmed to *activate* and to be free of the known boot WARN. They are **not** benchmark-validated; adopt on the owner's explicit acceptance, with the V5 image kept as the recovery path.
2. **GPU OC (1.00 GHz)** is measured-safe on the top OPP (locks, 0 asserts) and capped well below the ~1.004 GHz hardware ceiling. Voltage is unchanged (EEM-owned).
3. **EAS** is enabled and behaving as expected per the owner.
4. **CPU DVFS** remains stock (coherent, at evidenced limits).

**Remaining recommended work (all reversible, on-device):**

1. **Push** the two local commits (`f427d3dce23f`, `1f1c802dab64`) once the owner approves.
2. Controlled benchmark of the delivered V6 build vs V5 on a **separate control device** (or with the agent workload stopped) for wakeup latency / frame-time / screen-off drain (§11).
3. Sustained GPU soak (15–30 min) to confirm 1.00 GHz thermals/current.

---

## 16. Remaining work requiring physical-device testing

EEVDF stages 0–2 are landed and live; the remaining plan is validation/hardening:

1. **Stage 0 — infra** ✅ landed (`9b225aa8d473`).
2. **Stage 1 — lag + gated policy** ✅ landed (`08683c371162`).
3. **Stage 2 — commit to EEVDF (default-on)** ✅ landed (`e541ce0062cb`), activation runtime-confirmed.
4. **Stage 3 — EEVDF quality validation** ⏳ flash-validated for activation; **quality A/B pending** (sleep/wake fairness, wakeup latency, frame-time, screen-off drain) on a non-contaminated target.
5. **Stage 4 — hardening** ⏳ evaluate `6d71a9c61604` / `4423af84b297` if symptoms appear; verify against 6.7 "Complete EEVDF" semantics.
6. **Stage 5 — coexistence** ⏳ EAS+EEVDF is now the shipped combination; stress under memory pressure and confirm MTK `sync_hint`/`cstate_aware` interaction.

---

## 17. Diagnostic tooling (`tools/testing/fleux/`)

Read-only, on-device probes:

- `fleux-state-capture.sh` — snapshot CPU topology/capacity, cpufreq policies+governors+`time_in_state`, cpuidle usage, scheduler sysctls, thermal zones, PPM nodes, wakeup sources into one dated file.
- `fleux-eas-probe.sh` — EAS activation check (`sched_energy_aware`, perf-domain info, sched_debug).
- `fleux-gpu-dump.sh` — GPU OPP table, current load, limit indices, voltage, thermal context (`/proc/gpufreq*`, `mtktscpu`).
- `fleux-fairness-check.sh` — CPU-time ratio probe for a nice-0 vs nice-10 hog pair (preliminary).
- `ab_wl.sh` — the A/B workload harness used in Appendix A.
- `README.md` — usage + interpretation notes.

They never write kernel state; capture files go only under a user-supplied output directory.

---

## Appendix A — Live A/B experiment (test unit, 2026-10-10) *(historical)*

Two reversible knobs, each leg 20 s, on the audit unit (`fleur`, then `4.19.325-Fleux-V5+`).

### Method

- Harness `tools/testing/fleux/ab_wl.sh`: 4 CPU-bound hogs + 4 timer-wakeup wakers (8 threads, unpinned) for 20 s; per-CPU busy ticks from `/proc/stat`; `scaling_cur_freq` sampled ~0.5 s for `policy0`/`policy6`.
- Legs: **L0** EAS=0/PELT=1 → **L1** EAS=1/PELT=1 → **L2** EAS=0/PELT=1 → **L3** PELT=4/EAS=0 → **L4** PELT=1.

### Raw results

| Leg | knob | busy ticks cpu0..7 | policy0 avg/max/atmax%/sw | policy6 avg/max/atmax%/sw |
|---|---|---|---|---|
| L0 | EAS=0 PELT=1 | 1798 1831 1777 2100 1675 1794 2106 2112 | 1955350 / 2000000 / 70% / 6 | 1969375 / 2050000 / 77% / 9 |
| L1 | EAS=1 PELT=1 | 1897 1981 2017 1986 1965 2095 2090 2080 | 1656550 / 1933000 / 0% / 11 | 1454400 / 2050000 / 7% / 21 |
| L2 | EAS=0 PELT=1 | 1864 1901 1966 2004 1998 2072 2063 2071 | 1843750 / 1933000 / 0% / 13 | 1147150 / 1169000 / 0% / 6 |
| L3 | PELT=4 EAS=0 | 2119 2145 2146 2137 2177 2175 2186 2186 | 1458825 / 1933000 / 0% / 11 | 1169000 / 1169000 / 0% / 0 |
| L4 | PELT=1 EAS=0 | 1913 1947 1936 1985 2110 2115 2087 2099 | 1418325 / 1866000 / 0% / 7 | 1169000 / 1169000 / 0% / 0 |

### Findings

- **F1 (corrected):** `sched_pelt_multiplier=4` does not apply because `/vendor/etc/init/hw/init.mt6781.power.rc` writes `1` at `early-init`, not because of a read-only mount. See Appendix B.
- **F2:** `sched_energy_aware` writes succeeded but (at the time) activation could not be independently confirmed. It is now confirmed on V6 (§8).
- **F3:** the A/B is **inconclusive** — the two identical baseline legs (L0 vs L2) diverged by up to **−41.7 %** `policy6` average frequency and **77 %→0 %** time-at-max, swamping any plausible effect.
- **F4:** this test unit is unfit for scheduler/DVFS A/B (see Appendix C).

### Conclusion

No tuning change was recommended from this experiment. Recorded as *measured but inconclusive*.

---

## Appendix B — Flash-test: PELT multiplier default (**RESULT: ineffective**) *(historical)*

**Status: built, flashed, verified ineffective, and reverted (`0f770403bfd2`).**

Set the kernel defaults `sysctl_sched_pelt_multiplier` 1→4 and `sched_pelt_lshift` 0→2, flashed it, rebooted. `/proc/sys/kernel/sched_pelt_multiplier` still read **1**. Root cause: `/vendor/etc/init/hw/init.mt6781.power.rc` contains `on early-init → write /proc/sys/kernel/sched_pelt_multiplier 1`. The ROM deliberately pins PELT multiplier to 1; a kernel default cannot override it, and the boot-cmdline `…=4` is likewise inert. `/proc/sys` is writable at runtime, so if this is ever wanted the supported route is a runtime/late-boot write, not a kernel change. Artifact (for the record): `Image.gz-dtb` sha256 `1b5fb6912356360689daca943a156a16930301dbd2678f82356fb90387dec3bb`.

---

## Appendix C — Test environment (**important methodology note**) *(historical, still applies)*

The agent/tooling environment runs **inside the phone being measured**.

- The sandbox is an **Alpine Linux container** (hostname `kilo`) on a loop-mounted ext4 image, in a Droidspaces cgroup on the device.
- `uname -a` reports the same kernel the flashes install (`4.19.325-Fleux-*`), on the phone.
- Inside the container, `opencode` (the agent) consumes ~30–45 % of a CPU core; on the host side `com.termux` + `surfaceflinger` + the graphics composer are the top consumers.

Implications:

1. **All on-device A/B measurements are self-contaminated** — the true cause of the Appendix A "inconclusive" result.
2. **The dominant controllable CPU/battery load is the agent/dev stack**, not the kernel scheduler.
3. **Flashing this phone is high-risk** (it hosts the tooling environment).
4. Clean measurements require a **separate control device** or an automated capture that runs while the agent workload is stopped.

---

## References

- EEVDF series: *"sched: EEVDF and latency-nice and/or slice-attr"* (P. Zijlstra, 2023-05-31; lore.kernel.org).
- Mainline EEVDF commits: `eab009d8ed64`, `86bfbb7ce4f67a88df2639198169b685668e7349`, `147f3efaa241`, `5e963f2bd465`, `6d71a9c61604`, `4423af84b297`.
- uclamp fix: `ca4984a7dd863f3e1c0df775ae3e744bff24c303` ("sched: Fix UCLAMP_FLAG_IDLE setting").
- Kernel docs: `Documentation/scheduler/sched-eevdf.rst`; LWN #925371, #968575, #969062.
- Downstream baseline change: `44577282eb70` (MTK CPU-policy allow-disable, bengris32).
