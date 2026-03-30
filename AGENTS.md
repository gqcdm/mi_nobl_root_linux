# PROJECT KNOWLEDGE BASE

**Generated:** 2026-03-30 22:32:04 CST
**Commit:** 8ced930
**Branch:** main

## OVERVIEW
This repository is an operational toolkit for loading KernelSU on Xiaomi 15 without unlocking the bootloader, then repairing LSPosed/ZygiskSU state when needed. It is not a conventional source project with build, CI, or test layers; the main working surface is a small set of root-level scripts plus deployment artifacts.

## STRUCTURE
```text
mi_nobl_root_linux/
├── README.md                  # canonical workflow, prerequisites, device/version assumptions
├── ksu_oneclick.bat           # Windows orchestrator for the full KernelSU load flow
├── ksu_oneclick.sh            # Linux orchestrator for the full KernelSU load flow
├── patch_ksu_module.py        # PC-side ELF patcher for unresolved KernelSU symbols
├── ksu_step1.sh               # device-side kallsyms collection stage
├── ksu_step2.sh               # device-side insmod + ksud + Manager trigger stage
├── fix_lspd.sh                # LSPosed/ZygiskSU reinjection and framework recovery flow
├── do_chmod.sh                # fixes mqsas output file permissions before adb pull
├── read_logs.sh               # pulls high-level LSPosed log context
├── read_verbose.sh            # extracts focused verbose log evidence for debugging
├── *.ko / *.apk / ksud-*      # deployment artifacts, not source modules
└── python/                    # vendored Windows Python runtime used by ksu_oneclick.bat
```

## WHERE TO LOOK
| Task | Location | Notes |
|------|----------|-------|
| Understand the whole flow | `README.md` | Most complete source of prerequisites, invariants, and command examples |
| Main entrypoint behavior | `ksu_oneclick.bat` / `ksu_oneclick.sh` | Orchestrates push → kallsyms pull → patch → push patched `.ko` → step2 |
| Patch unresolved kernel symbols | `patch_ksu_module.py` | Parses kallsyms and rewrites ELF symbol table entries |
| Inspect device stage 1 | `ksu_step1.sh` | Pulls `/proc/kallsyms`, marks `ALREADY_LOADED`, writes `STEP1_DONE` |
| Inspect device stage 2 | `ksu_step2.sh` | Loads module, deploys `ksud`, removes `magisk` symlink, emits `ALL_DONE` |
| Recover LSPosed / lspd | `fix_lspd.sh` | Reinjects ZygiskSU, starts `lspd`, restarts zygote/system_server safely |
| Permission repair before `adb pull` | `do_chmod.sh` | Required because mqsas outputs are commonly `root:system 600` |
| Read LSPosed logs quickly | `read_logs.sh` | Summarizes latest verbose/modules logs |
| Read focused verbose evidence | `read_verbose.sh` | Greps bridge / manager / module / bootstrap signals |
| Understand bundled runtime boundary | `python/` | Treat as embedded runtime payload, not as a maintained source subtree |

## CONVENTIONS
- Root-level scripts are the real maintenance surface; there is no `src/`, `tests/`, `package.json`, `pyproject.toml`, or CI workflow tree.
- Device-side scripts target Android shell and use `#!/system/bin/sh`; preserve that environment assumption.
- Windows-side patch logic is invoked via the bundled `python/python.exe` from `ksu_oneclick.bat`, while the Linux counterpart uses the host Python runtime.
- Logging is human-oriented and step-based. Preserve explicit section headers and sentinel strings like `STEP1_DONE`, `ALREADY_LOADED`, `LOAD_FAILED`, `ALL_DONE`, and `DONE`.
- Validation in this repo is runtime/log driven, not test-suite driven. Prefer documenting how to verify via ADB output, process state, and LSPosed logs.
- README and most operator-facing documentation are primarily Chinese, while commands, file paths, tool names, and API names stay in original form.

## ANTI-PATTERNS (THIS PROJECT)
- Do not treat `python/` as an ordinary source module. It is a vendored Windows Python runtime; avoid cleanup, refactors, upgrades, or reformatting unless a task explicitly targets it.
- Do not assume standard build/test/lint commands exist. None are declared in-repo.
- Do not rely on `ro.dalvik.vm.native_bridge` or `service check` to decide whether this repo's ZygiskSU injection worked; README explicitly says this flow does not use the native-bridge property path.
- Do not use `/data/adb/lspd/config/monitor`; the documented monitor path is `/data/adb/lspd/monitor`.
- Do not keep or recreate `$KSU_DIR/bin/magisk`; `ksu_step2.sh` removes the compatibility symlink because Manager may falsely detect a Magisk conflict and disable modules.
- Do not kill zygote before reinjecting ZygiskSU. The documented safe order is reinject first, then restart zygote/framework.
- Do not bind to `system_server` immediately after killing zygote; wait for the old process to die first to avoid the documented race.
- Do not start `lspd` without `setsid` and `nsenter -t 1 -m`; README documents both as required for survival and correct namespace access.
- Do not `adb pull` mqsas output files before fixing permissions when needed.
- Do not describe this repository as production-safe; README marks it as security-research-only.

## UNIQUE STYLES
- This repo is organized by execution phase, not by language package boundaries.
- The canonical split is: host orchestration (`ksu_oneclick.bat` / `ksu_oneclick.sh` + `patch_ksu_module.py`), device load stages (`ksu_step1.sh`, `ksu_step2.sh`), LSPosed repair (`fix_lspd.sh`), and log triage (`read_logs.sh`, `read_verbose.sh`).
- A large share of project knowledge lives in README invariants instead of machine-readable config.
- Binary artifacts (`.ko`, `.apk`, `ksud-*`) are present alongside scripts as part of the deployment workflow.

## COMMANDS
```bash
# Main host entrypoint (run on PC after each reboot)
ksu_oneclick.bat
./ksu_oneclick.sh

# Patch a KernelSU module manually (generic Python environment)
python patch_ksu_module.py android15-6.6_kernelsu.ko kallsyms.txt kernelsu_patched.ko

# Push and run LSPosed repair flow
adb push fix_lspd.sh /data/local/tmp/
adb shell "chmod 755 /data/local/tmp/fix_lspd.sh"
adb shell "service call miui.mqsas.IMQSNative 21 i32 1 s16 '/system/bin/sh' i32 1 s16 '/data/local/tmp/fix_lspd.sh' s16 '/data/local/tmp/lspd_fix_out.txt' i32 180"

# Fix permissions before pulling output
adb shell "service call miui.mqsas.IMQSNative 21 i32 1 s16 'sh' i32 1 s16 '/data/local/tmp/do_chmod.sh' s16 '/dev/null' i32 5"
adb pull /data/local/tmp/lspd_fix_out.txt

# Read logs on device
sh /data/local/tmp/read_logs.sh
sh /data/local/tmp/read_verbose.sh
```

## NOTES
- `README.md` is the source of truth for device model, Android/HyperOS/kernel version assumptions, and tool versions.
- KASLR means kallsyms-derived addresses change after every reboot; reusing stale patched data is a known bad path.
- The repo assumes SELinux permissive in its documented flow.
- mqsas execution is asynchronous; success is established by waiting, then reading/pulling output artifacts.
- If behavior or operator-visible output changes, update `README.md` in the same change.
