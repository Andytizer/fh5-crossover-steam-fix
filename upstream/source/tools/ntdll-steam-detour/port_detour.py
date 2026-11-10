import struct, sys
# Usage: port_detour.py <patched-winecx-11.17-ntdll.dll> <highball-r28-ntdll.dll> <output-ntdll.dll>
if len(sys.argv) != 4:
    sys.exit("usage: port_detour.py <patched-winecx-ntdll.dll> <highball-ntdll.dll> <out.dll>")
SRC_PATH, HB_PATH, OUT_PATH = sys.argv[1:4]
# Port Bridgeplay's steamclient64 detour from WineCX 11.17 ntdll (patched.dll) to Highball's ntdll (hb.dll).
IMG = 0x170000000                       # image base of both builds; file offset == RVA (.text raw ptr == VA 0x1000)
SRC_CAVE, LEN = 0x83360, 0x340          # detour code + data in patched.dll
HB_CAVE = 0x7A0A0                       # end of hb .text VirtualSize; zero padding up to 0x7B000
HB_HOOK = 0x484F3                       # hb build_module: cmpq $0,0xf0(%rsp) after alloc_module
HB_BACK = 0x484FC                       # hb: the je that follows the cmpq
HB = {"LdrGetDllHandle": 0x14FE0, "LdrLoadDll": 0x15B50, "ZwProtectVirtualMemory": 0xF380}

p = bytearray(open(SRC_PATH, "rb").read())
h = bytearray(open(HB_PATH, "rb").read())
cave = bytearray(p[SRC_CAVE:SRC_CAVE + LEN])
assert h[HB_HOOK:HB_HOOK + 9] == bytes.fromhex("48833c24f000000000".replace("3c24", "bc24")), "hb hook site mismatch"
assert not any(h[HB_CAVE:HB_CAVE + LEN]), "hb cave area not empty"

def fix_rel32(off_in_cave, insn_len, target_rva):
    insn_rva = HB_CAVE + off_in_cave
    struct.pack_into("<i", cave, off_in_cave + insn_len - 4, target_rva - (insn_rva + insn_len))

# leaq disp32(%rip): 48 8d 05 <disp32>, 7 bytes, at cave +0x26/+0x32/+0x3e
for off, name in ((0x26, "LdrGetDllHandle"), (0x32, "LdrLoadDll"), (0x3E, "ZwProtectVirtualMemory")):
    assert cave[off:off + 3] == b"\x48\x8d\x05", hex(off)
    fix_rel32(off, 7, HB[name])
# movq %rbx,%rdx (48 89 da) -> movq %r15,%rdx (4c 89 fa): hb keeps the new module in r15
assert cave[0x4F:0x52] == b"\x48\x89\xda"; cave[0x4F:0x52] = b"\x4c\x89\xfa"
# jmp back (e9 rel32) at +0x76 -> hb's je after the cmpq
assert cave[0x76] == 0xE9; fix_rel32(0x76, 5, HB_BACK)

h[HB_CAVE:HB_CAVE + LEN] = cave
hook = bytearray(b"\xe9") + struct.pack("<i", HB_CAVE - (HB_HOOK + 5)) + b"\xcc" * 4
h[HB_HOOK:HB_HOOK + 9] = hook
open(OUT_PATH, "wb").write(h)
print("ok: cave at RVA %#x, hook at RVA %#x, %d bytes changed" % (HB_CAVE, HB_HOOK, sum(a != b for a, b in zip(h, open(HB_PATH, "rb").read()))))
