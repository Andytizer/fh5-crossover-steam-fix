#!/usr/bin/perl
# Minimal PE helper (Perl port of the parts of tools/pe_tools.py and gen_def.py we need; no Python on the host).
#   pe.pl sections      <dll>                  list sections (name, va, vsize, raw, rawsize, flags)
#   pe.pl exports       <dll>                  list exports: ordinal name rva [-> forward]
#   pe.pl rva           <dll> <export>         print RVA and file offset of an export
#   pe.pl dump          <dll> <rva> <len>      hex dump bytes at RVA
#   pe.pl export-name   <dll>                  print the export-directory DLL name
#   pe.pl compare-wrapper <wrapper> <target>   check a forwarding wrapper's exports against another DLL
#   pe.pl rename-export <dll> <newname>        change the export-directory DLL name in place
use strict; use warnings;
my ($cmd, $path, @rest) = @ARGV;
die "usage: $0 cmd dll ...\n" unless $cmd && $path;
open my $f, '<:raw', $path or die "$path: $!"; local $/; my $d = <$f>; close $f;
sub u16 { unpack 'v', substr($d, $_[0], 2) }
sub u32 { unpack 'V', substr($d, $_[0], 4) }
die "not MZ\n" unless substr($d, 0, 2) eq 'MZ';
my $pe = u32(0x3c); die "not PE\n" unless substr($d, $pe, 4) eq "PE\0\0";
my $nsec = u16($pe + 6); my $optsz = u16($pe + 20); my $opt = $pe + 24;
my $magic = u16($opt); my $dd = $opt + ($magic == 0x20b ? 112 : 96);
my @secs;
for my $i (0 .. $nsec - 1) {
    my $s = $opt + $optsz + 40 * $i;
    (my $n = substr($d, $s, 8)) =~ s/\0+$//;
    push @secs, { name => $n, va => u32($s + 12), vsize => u32($s + 8), rawsize => u32($s + 16),
                  raw => u32($s + 20), flags => u32($s + 36) };
}
sub off { my $r = shift; for (@secs) { my $sz = $_->{vsize} > $_->{rawsize} ? $_->{vsize} : $_->{rawsize};
          return $r - $_->{va} + $_->{raw} if $r >= $_->{va} && $r < $_->{va} + $sz } undef }
sub cstr { my $o = shift; my $e = index($d, "\0", $o); substr($d, $o, $e - $o) }
my ($erva, $esz) = (u32($dd), u32($dd + 4));
sub exports {
    return () unless $erva;
    my $e = off($erva); my ($base, $nf, $nn, $af, $an, $ao) = map { u32($e + $_) } 16, 20, 24, 28, 32, 36;
    my %name; for my $i (0 .. $nn - 1) { $name{ u16(off($ao) + 2 * $i) } = cstr(off(u32(off($an) + 4 * $i))) }
    my @r;
    for my $i (0 .. $nf - 1) {
        my $rva = u32(off($af) + 4 * $i); next unless $rva;
        my $fw = ($rva >= $erva && $rva < $erva + $esz) ? cstr(off($rva)) : undef;
        push @r, [ $base + $i, $name{$i}, $rva, $fw ];
    }
    @r;
}
if ($cmd eq 'sections') {
    printf "%-8s va=%06x vsize=%06x raw=%06x rawsize=%06x flags=%08x\n", @$_{qw(name va vsize raw rawsize flags)} for @secs;
} elsif ($cmd eq 'exports') {
    for (exports()) { printf "%d %s %06x%s\n", $_->[0], $_->[1] // '-', $_->[2], $_->[3] ? " -> $_->[3]" : '' }
} elsif ($cmd eq 'rva') {
    for (exports()) { if (($_->[1] // '') eq $rest[0]) { printf "rva=%x off=%x\n", $_->[2], off($_->[2]); exit 0 } }
    die "no export $rest[0]\n";
} elsif ($cmd eq 'dump') {
    my ($r, $len) = (hex $rest[0], $rest[1]); my $o = off($r);
    for (my $i = 0; $i < $len; $i += 16) { printf "%06x: %s\n", $r + $i, join ' ', unpack '(H2)*', substr($d, $o + $i, $len - $i < 16 ? $len - $i : 16) }
} elsif ($cmd eq 'imports') {
    # print "dll!function" (or dll!#ordinal) for every import
    my $irva = u32($dd + 8); exit 0 unless $irva;
    for (my $i = off($irva); u32($i + 12); $i += 20) {
        my $dll = lc cstr(off(u32($i + 12)));
        my $t = u32($i) || u32($i + 16);
        for (my $o = off($t); ; $o += 8) {
            my ($lo, $hi) = (u32($o), u32($o + 4)); last unless $lo || $hi;
            print $hi & 0x80000000 ? "$dll!#" . ($lo & 0xffff) . "\n" : "$dll!" . cstr(off($lo) + 2) . "\n";
        }
    }
} elsif ($cmd eq 'export-name') {
    print cstr(off(u32(off($erva) + 12))), "\n";
} elsif ($cmd eq 'compare-wrapper') {
    # pe.pl compare-wrapper <wrapper.dll> <target.dll>: does a forwarding wrapper (built against one Wine's export
    # list) fit another Wine's DLL? Checks names and ordinals. Exit 0 = exact, 1 = only target extras, 2 = problems.
    my @w = exports();
    { open my $g, '<:raw', $rest[0] or die "$rest[0]: $!"; local $/; $d = <$g>; }
    # re-parse for the target
    $pe = u32(0x3c); $nsec = u16($pe + 6); $optsz = u16($pe + 20); $opt = $pe + 24; $dd = $opt + 112; @secs = ();
    for my $i (0 .. $nsec - 1) { my $s = $opt + $optsz + 40 * $i;
        push @secs, { va => u32($s + 12), vsize => u32($s + 8), rawsize => u32($s + 16), raw => u32($s + 20) } }
    ($erva, $esz) = (u32($dd), u32($dd + 4));
    my @t = exports();
    my %wn = map { (($_->[1] // "#$_->[0]") => $_->[0]) } @w;
    my %tn = map { (($_->[1] // "#$_->[0]") => $_->[0]) } @t;
    my ($bad, $extra) = (0, 0);
    for my $n (sort keys %wn) {
        if (!exists $tn{$n}) { print "MISSING in target: $n (wrapper forwards it; calls would fail)\n"; $bad++ }
        elsif ($tn{$n} != $wn{$n}) { print "ORDINAL differs: $n wrapper \@$wn{$n} target \@$tn{$n}\n"; $bad++ if $wn{$n} <= 117 }
    }
    for my $n (sort keys %tn) { next if exists $wn{$n}; print "EXTRA in target: $n \@$tn{$n} (not exported by wrapper)\n"; $extra++ }
    printf "summary: %d wrapper exports, %d target exports, %d problems (names/classic ordinals), %d extras\n", scalar @w, scalar @t, $bad, $extra;
    exit($bad ? 2 : $extra ? 1 : 0);
} elsif ($cmd eq 'rename-export') {
    my $new = $rest[0]; my $o = off(u32(off($erva) + 12)); my $old = cstr($o);
    die "new name too long (max " . length($old) . ")\n" if length($new) > length($old);
    substr($d, $o, length $old) = $new . ("\0" x (length($old) - length($new)));
    open my $w, '>:raw', $path or die $!; print $w $d; close $w;
    print "export name $old -> $new in $path\n";
} else { die "unknown command $cmd\n" }
