#!/usr/bin/perl
# usage: perl patch_unwind.pl IN_ntdll.dll OUT_ntdll.dll.unwindfix
# Hooks RtlVirtualUnwind2 entry (RVA 0x3b1a0) -> cave (RVA 0x7a400, .text slack) which substitutes a private
# writable scratch qword (RVA 0x7bf00, .data page slack) for NULL MachineFrameUnwound/HandlerData/EstablisherFrame/
# HandlerRoutine stack args, runs the displaced 3 pushes and jumps back to RVA 0x3b1a6.
use strict; use warnings;
my ($in,$out)=@ARGV; die "usage: $0 in out\n" unless $in && $out;
open my $f,'<:raw',$in or die $!; local $/; my $d=<$f>; close $f;
die "size ".length($d)." != 1153043\n" unless length($d)==1153043;
die "not MZ/PE\n" unless substr($d,0,2) eq 'MZ' && substr($d,unpack('V',substr($d,0x3c,4)),4) eq "PE\0\0";
my ($HOOK,$BACK,$CAVE,$SCR)=(0x3b1a0,0x3b1a6,0x7a400,0x7bf00);   # RVA == file offset in .text/.data
my $want=pack('H*','415741564155');                              # push r15; push r14; push r13
sub at { substr($d,$_[0],$_[1]) }
die "hook site mismatch: ".unpack('H*',at($HOOK,6))."\n" unless at($HOOK,6) eq $want;
die "cave area not zero\n"   if at($CAVE,0x46)   =~ /[^\0]/;
die "scratch area not zero\n" if at($SCR,16)     =~ /[^\0]/;
# sanity: existing Steam-detour cave (0x7a0a0..0x7a3e0) must stay out of our range
die "overlap with detour cave\n" if $CAVE < 0x7a3e0;
my $c='';
$c.=pack('H*','4c8d15').pack('l<',$SCR-($CAVE+7));               # lea r10,[rip+scratch]
for my $o (0x30,0x38,0x40,0x60){                                  # entry-relative stack arg slots
  $c.=pack('H*','48837c24').chr($o).pack('H*','00').pack('H*','75').chr(5).pack('H*','4c895424').chr($o);
}   # cmp qword [rsp+o],0 ; jne +5 ; mov [rsp+o],r10
$c.=$want;                                                        # displaced instructions
my $je=$CAVE+length($c);
$c.="\xe9".pack('l<',$BACK-($je+5));                              # jmp back
die "cave len ".length($c) unless length($c)==0x46;
substr($d,$CAVE,0x46)=$c;
substr($d,$HOOK,6)="\xe9".pack('l<',$CAVE-($HOOK+5))."\x90";     # jmp cave ; nop
open my $o,'>:raw',$out or die $!; print $o $d; close $o;
print "ok: hook RVA 0x3b1a0 -> cave 0x7a400 (0x46 bytes), scratch 0x7bf00\n";
