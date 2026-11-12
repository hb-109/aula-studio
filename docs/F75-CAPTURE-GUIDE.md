# How the F75 Pro's onboard commands were recorded

AULA Studio only sends the F75 Pro commands that were seen coming from AULA's own Windows driver. Guessing isn't safe: the keyboard's SinoWealth chip has commands that wipe its settings or put it into firmware-update mode. This is how those commands were recorded, so the work can be repeated or extended.

## Setup

- A Windows 11 for Arm virtual machine in [UTM](https://mac.getutm.app) (QEMU backend, with UTM's guest tools), with the F75 Pro passed through to it from UTM's USB menu.
- AULA's F75 driver, `AULA F75 Setup v2.0 20260514.exe`, from [aulagaming.com/pages/download](https://www.aulagaming.com/pages/download).
- A recorder. USBPcap has no signed driver for Windows on Arm, so the recording comes from `tools/hidlogger` instead: a logging stand-in for Windows' `hid.dll`. AULA's driver (`OemDrv.exe`, 32-bit) does all of its keyboard I/O through `HidD_SetFeature` and `HidD_GetFeature`, and Windows loads a DLL from an application's own folder first. The logger writes each report to `aula-hid-log.txt` on the Windows desktop and passes every call on to the real `hid.dll` unchanged.

Build the logger on a Mac with [Zig](https://ziglang.org):

```bash
zig cc -target x86-windows-gnu -shared -O2 -o hid.dll tools/hidlogger/hidlogger.c tools/hidlogger/hid.def -lkernel32
```

Copy `hid.dll` next to `OemDrv.exe` and restart AULA's driver. Remove the file to uninstall it.

`tools/vm_transfer.py` moves files between the Mac and the VM over UTM's private network (`192.168.64.1:8765`), with an upload page for sending the log back.

## Recording

Change one setting at a time in AULA's driver, apply it, and wait about ten seconds before the next, noting what you changed. The gaps separate the steps in the log.

## Decoding

`tools/gen_f75_templates.py` turns a recording into `Sources/AulaCore/F75Captured.swift`: the factory tables AULA writes, and the recorded packets that `swift run SelfCheck` requires AULA Studio to reproduce byte for byte. The command format is described in `Sources/AulaCore/F75Onboard.swift`.
