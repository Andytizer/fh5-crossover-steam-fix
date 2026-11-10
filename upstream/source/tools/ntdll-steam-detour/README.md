# ntdll Steam detour port

Bridgeplay runs Steam games through a Windows `steamclient64.dll`; for that it patches its WineCX 11.17 `ntdll.dll`
with a small detour (a hook in `build_module`, after `alloc_module`, jumping to a code cave). When
`steamclient64.dll` loads, the detour makes Wine load `lsteamclient.dll` and patch it in. Bridgeplay only ships that
detour for the runners it bundles. The Highball CrossOver 26.3 r28 runner has no such detour, so Steam games on it
exit after about 14 seconds with `steam_client_init: CreateSteamPipe failed`.

`port_detour.py` copies the detour from **your own** Bridgeplay WineCX 11.17 `ntdll.dll` into the Highball r28
`ntdll.dll`. It reads both DLLs from disk and writes a third file; it contains no Bridgeplay code and no binary.

## Use

    python3 port_detour.py <bridgeplay-winecx-11.17-ntdll.dll> <highball-r28-ntdll.dll> <output-ntdll.dll>

Python 3 standard library only. Typical paths (see the main README, Step 6):

- input 1 (`patched`): `~/Library/Application Support/bridgeplay/runners/crossover-winecx-11.17/CrossOver/lib/wine/x86_64-windows/ntdll.dll`
- input 2 (`hb`): the Highball runner's own `ntdll.dll`, kept as `ntdll.dll.orig`
- output: a new file; the script never writes to its inputs

## Expected inputs and output

| File | Size | SHA-256 |
|---|---|---|
| Bridgeplay WineCX 11.17 `ntdll.dll` (input 1) | 1230841 | `4573d521671a48212670e7543aa9ebf0921e383dada69477f677f435df2bef5a` |
| Highball CX26.3 r28 `ntdll.dll` (input 2) | 1153043 | `e606762e531e8d749cb4075a3fea2ba063f4833dad9903074ec1762f91efc1a3` |
| Output of this script | 1153043 | `ff8bcf2574bc0b571509401729bb7545446f753c612eb47d015bfbb669feff10` |
| After `../ntdll-unwindfix/patch_unwind.pl` | 1153043 | `1cd92d93a4569ef9486c506479d8c4162022eb64c5dbb84449c72bf55f2ec522` |

With these inputs the script prints `ok: cave at RVA 0x7a0a0, hook at RVA 0x484f3, 723 bytes changed`. The output was
checked to be byte-identical to the file used on the author's working setup, and the unwind fix on top gives the
final hash above. A different Bridgeplay version may carry a different `ntdll.dll`; the script then either stops on
its checks or its result is untested.

## What it changes in the Highball `ntdll.dll`

- Copies 0x340 bytes (detour code and data) from file offset 0x83360 of the Bridgeplay DLL to RVA 0x7A0A0 of the
  Highball DLL (unused padding at the end of `.text`; the script checks that it is zero).
- Fixes the three `rip`-relative references in the copied code to Highball's `LdrGetDllHandle` (RVA 0x14FE0),
  `LdrLoadDll` (0x15B50) and `ZwProtectVirtualMemory` (0xF380), changes one register (`rbx` to `r15`, where Highball
  keeps the new module) and retargets the jump back to Highball's `je` at RVA 0x484FC.
- Replaces the 9 bytes at RVA 0x484F3 (`cmpq $0,0xf0(%rsp)`) with a jump to the copied code.

It refuses to run if the hook site bytes or the cave area are not what it expects, so it only works on that exact
Highball r28 build. It does not update the PE checksum (Wine ignores it).

## Licensing

- The script is part of this repository (GPL-3.0, see the top-level `LICENSE`).
- The **output** contains machine code copied from Bridgeplay's patched `ntdll.dll`, and the rest of it is Wine
  (LGPL-2.1-or-later) code from Highball's build. Bridgeplay is GPL-3.0 (its `LICENSE` and `LICENSE.wine` are in
  `Bridgeplay.app/Contents/Resources`; its `NOTICE` lists the rest). Do not redistribute the output file: make it
  on your own machine from your own copies, as the install steps do. This README is not legal advice.
