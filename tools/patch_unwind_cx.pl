#!/usr/bin/perl
# usage: perl patch_unwind_cx.pl IN_ntdll.dll OUT_ntdll.dll
#        perl patch_unwind_cx.pl IN_ntdll.dll --check      (verify only, write nothing)
# exit: 0 = patched (or patchable with --check), 3 = already patched, other = refused
#
# CrossOver port of fh5-d3dmetal-fix/tools/ntdll-unwindfix/patch_unwind.pl (GPL-3.0).
# Same fix, but locates everything instead of using Highball r28's fixed RVAs:
#   - hook:    RtlVirtualUnwind2 entry, found via the export table; must start with
#              41 57 41 56 41 55 (push r15; push r14; push r13), the 6 bytes displaced into the cave
#   - cave:    0x46 bytes in the .text padding after VirtualSize (must be all 0xCC or 0x00);
#              .text VirtualSize is raised to cover it so the loader maps it as code
#   - scratch: 16 bytes at the end of the last page of .data, past VirtualSize (zero-filled, writable, unused)
# The cave swaps a private scratch pointer in for a NULL MachineFrameUnwound / HandlerData /
# EstablisherFrame / HandlerRoutine stack argument (FH5 passes NULLs Windows tolerates), runs the displaced
# pushes and jumps back. Harmless if this Wine already NULL-checks those pointers.
use strict; use warnings;
my ($in, $out) = @ARGV; die "usage: $0 in out\n" unless $in && $out;
open my $f, '<:raw', $in or die "$in: $!"; local $/; my $d = <$f>; close $f;
sub u16 { unpack 'v', substr($d, $_[0], 2) } sub u32 { unpack 'V', substr($d, $_[0], 4) }
die "not MZ\n" unless substr($d, 0, 2) eq 'MZ';
my $pe = u32(0x3c); die "not PE\n" unless substr($d, $pe, 4) eq "PE\0\0";
die "not x86_64\n" unless u16($pe + 4) == 0x8664;
my ($nsec, $optsz, $opt) = (u16($pe + 6), u16($pe + 20), $pe + 24);
die "not PE32+\n" unless u16($opt) == 0x20b;
my $salign = u32($opt + 32);
my (%sec, @secs);
for my $i (0 .. $nsec - 1) {
    my $h = $opt + $optsz + 40 * $i; (my $n = substr($d, $h, 8)) =~ s/\0+$//;
    my $s = { name => $n, hdr => $h, vsize => u32($h + 8), va => u32($h + 12), rawsize => u32($h + 16), raw => u32($h + 20) };
    push @secs, $s; $sec{$n} //= $s;
}
sub off { my $r = shift; for (@secs) { return $r - $_->{va} + $_->{raw} if $r >= $_->{va} && $r < $_->{va} + $_->{rawsize} } undef }
sub cstr { my $o = shift; substr($d, $o, index($d, "\0", $o) - $o) }
# export lookup
my $erva = u32($opt + 112); my $e = off($erva);
my ($nn, $af, $an, $ao) = (u32($e + 24), u32($e + 28), u32($e + 32), u32($e + 36));
my $HOOK;
for my $i (0 .. $nn - 1) {
    next unless cstr(off(u32(off($an) + 4 * $i))) eq 'RtlVirtualUnwind2';
    $HOOK = u32(off($af) + 4 * u16(off($ao) + 2 * $i)); last;
}
die "RtlVirtualUnwind2 not exported\n" unless $HOOK;
my $want = pack 'H*', '415741564155';
my $hb = substr($d, off($HOOK), 6);
if (substr($hb, 0, 1) eq "\xe9") {
    my $tgt = $HOOK + 5 + unpack(q{l<}, substr($hb, 1, 4)); my $to = off($tgt);
    if (defined $to && substr($d, $to, 3) eq "\x4c\x8d\x15" && substr($d, $to + 0x3b, 6) eq pack(q{H*}, q{415741564155})) {
        printf "already patched: hook RVA 0x%x -> cave 0x%x\n", $HOOK, $tgt; exit 3 }
    die "hook site is a jmp but not to this patch's cave (other patch?)\n" }
die "hook site mismatch at RVA " . sprintf('%x', $HOOK) . ": " . unpack('H*', $hb) . "\n" unless $hb eq $want;
my $BACK = $HOOK + 6;
# cave in .text padding
my $t = $sec{'.text'} or die "no .text\n";
my $CAVE = ($t->{va} + $t->{vsize} + 15) & ~15;
my $LEN = 0x46;
die "no room in .text padding\n" if $CAVE + $LEN > $t->{va} + $t->{rawsize};
die "cave area not padding\n" if substr($d, off($CAVE), $LEN) =~ /[^\xcc\0]/;
# scratch in .data page slack
my $ds = $sec{'.data'} or die "no .data\n";
my $dend = $ds->{va} + (($ds->{vsize} + $salign - 1) & ~($salign - 1));
my $SCR = $dend - 16;
die "no slack in .data\n" if $SCR < $ds->{va} + $ds->{vsize};
die "scratch overlaps raw data\n" if $SCR < $ds->{va} + $ds->{rawsize};   # must be loader zero-fill, not file data
# build cave (identical instruction sequence to the Highball patch)
my $c = '';
$c .= pack('H*', '4c8d15') . pack('l<', $SCR - ($CAVE + 7));               # lea r10,[rip+scratch]
for my $o (0x30, 0x38, 0x40, 0x60) {                                       # entry-relative stack arg slots 6,7,8,12
    $c .= pack('H*', '48837c24') . chr($o) . "\0" . "\x75\x05" . pack('H*', '4c895424') . chr($o);
}                                                                           # cmp qword [rsp+o],0 ; jne +5 ; mov [rsp+o],r10
$c .= $want;                                                                # displaced pushes
$c .= "\xe9" . pack('l<', $BACK - ($CAVE + length($c) + 5));                # jmp back
die "cave len " . length($c) . "\n" unless length($c) == $LEN;
if ($out eq q{--check}) { printf "patchable: hook RVA 0x%x, cave 0x%x, scratch 0x%x\n", $HOOK, $CAVE, $SCR; exit 0 }
substr($d, off($CAVE), $LEN) = $c;
substr($d, off($HOOK), 6) = "\xe9" . pack('l<', $CAVE - ($HOOK + 5)) . "\x90"; # jmp cave ; nop
my $newv = $CAVE + $LEN - $t->{va};
substr($d, $t->{hdr} + 8, 4) = pack 'V', $newv if $newv > $t->{vsize};       # .text VirtualSize covers the cave
open my $o, '>:raw', $out or die "$out: $!"; print $o $d; close $o;
printf "ok: hook RVA 0x%x -> cave 0x%x (0x%x bytes), back 0x%x, scratch 0x%x, .text vsize 0x%x\n",
    $HOOK, $CAVE, $LEN, $BACK, $SCR, $newv > $t->{vsize} ? $newv : $t->{vsize};
