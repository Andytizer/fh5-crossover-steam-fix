# ntdll RtlVirtualUnwind2 NULL-output fix

A one-file Perl patcher for the Wine `ntdll.dll` (x86_64-windows) of the Highball CrossOver 26.3 r28 runner.
It contains no Wine code and no binary; it edits a copy of your own `ntdll.dll`.

## What it fixes

Forza Horizon 5 calls `RtlVirtualUnwind2` directly and passes NULL for some output parameters
(`MachineFrameUnwound`, `HandlerData`, `EstablisherFrame`, `HandlerRoutine`). Windows tolerates that. Wine
writes through those pointers, so the game crashes with an access violation at the loading-tips screen
(write at ntdll + 0x3BE09 in this build).

The patch hooks the entry of `RtlVirtualUnwind2` (RVA 0x3b1a0). A 70-byte cave replaces each of those four
stack arguments that is NULL with a pointer to a private 8-byte scratch slot, runs the three displaced `push`
instructions and jumps back (RVA 0x3b1a6). Values written to the scratch slot are never read back.

## Which ntdll it expects

- File size exactly 1153043 bytes (the script refuses anything else).
- The r28 runner's ntdll that already carries the Steam-detour patch. The patcher puts its code cave at
  RVA 0x7a400 and its scratch slot at RVA 0x7bf00 and refuses to run if those areas are not zero, if the hook
  bytes (`41 57 41 56 41 55`) are not what it expects, or if it was already applied.
- It does not patch anything else; other ntdll builds will fail the checks.

## Use

    cp /path/to/runner/.../x86_64-windows/ntdll.dll ntdll.dll.orig
    perl patch_unwind.pl ntdll.dll.orig ntdll.dll.unwindfix
    # keep a backup of the runner's ntdll.dll, then replace it with ntdll.dll.unwindfix

Changed bytes: 70 (6 at the hook, 64 in the cave). Section headers are not touched.

## Caveats

- The PE checksum is not updated (Wine ignores it).
- Unwind info for `RtlVirtualUnwind2` still describes the original prologue, so a debugger stopping inside the
  cave sees a bogus frame. The cave only does stack-relative compares and stores.
- Tolerating a NULL `EstablisherFrame` is more lenient than Windows. Harmless.
- Not needed on a Wine build that already checks those pointers for NULL.
