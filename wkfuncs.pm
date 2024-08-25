# Functions common to wifikey and wkmacs

package wkfuncs;
use strict;
use warnings;
use Exporter 'import';
our $VERSION = '0.00';
our @EXPORT = qw(pskfile macfile now genkey genkey256
 hasmac pskline parsepskline hostapd_list hostapd_status
 log_ log_get urlencode);

use Fcntl qw(O_RDONLY);
use open ":utf8";
$ENV{"PATH"} = $INC[0] . ":" . $ENV{"PATH"};

my $pskfilepat = "/etc/wifi/%s.psk";
my $macfilepat = "/etc/wifi/%s.mac";

# Return the PSK file name for an SSID
sub pskfile {
  my($s) = @_;
  return sprintf($pskfilepat, urlencode($s));
}

# Return the MAC file name for an SSID
sub macfile {
  my($s) = @_;
  return sprintf($macfilepat, urlencode($s));
}

my @_now = gmtime;
my $now = sprintf("%04d%02d%02d%02d%02d%02d",
  $_now[5]+1900, $_now[4]+1, $_now[3], $_now[2], $_now[1], $_now[0]);

# Return the current (as of program start) timestamp
# (format is YYYYMMDDhhmmss)
sub now {
  return $now;
}

# Create a new random key.
# Parameters: length, mode (0=digits, 1=letters, 2=all)
# Will insert a dot after each 4th character unless mode=2.
# Mode Entropy         for len=8  len=16  len=24 (rounded)
#   0  length * 3.322         26      53      79
#   1  length * 4.7           37      75     112
#   2  length * 6.426         51     102     154
sub genkey {
 my($l,$m) = @_;
 my $f = $m > 1 ? 1.9 : ($m > 0 ? 1.6 : 1.1);
 use open IO => ':raw';
 sysopen(R, "/dev/urandom", O_RDONLY) || die;
 sysread(R, my $r, $f * $l);
 close(R);
 if ($m == 0) {
  $r = unpack("H*", $r);
  $r =~ tr/0-9//cd;
 } elsif ($m == 1) {
  $r =~ s/(.)/chr( (ord($1) & 0x1F) + 0x60 )/gse;
  $r =~ tr/a-z//cd;
 } else {
  $r =~ s/(.)/chr( (ord($1) & 0x7F) )/gse;
  # remove nonprint, space, HTML-unsafe, shell-unsafe, qrcode-unsafe
  $r =~ tr/\x00-\x20\x7f<&\\'":;//d;
 }
 do { log_("genkey: retry-too-short $l $m"); return genkey($l, $m); } if (length($r) < $l);
 do { log_("genkey: retry-weak $l $m"); return genkey($l, $m); } if (isweak($r));
 $r = substr($r, 0, $l);
 if ($m < 2) {
  $r =~ s/(....)/$1./g;
  $r =~ s/\.$//;
 }
 return $r;
}

sub genkey256 {
 use open IO => ':raw';
 sysopen(R, "/dev/urandom", O_RDONLY) || die;
 sysread(R, my $r, 32);
 close(R);
 return unpack("H*", $r);
}

# Try to avoid easily guessable patterns.
sub isweak {
 my ($x) = @_;
 return 1 if ($x =~ /(.)\1\1\1/); # four equal characters
 return 2 if ($x =~ /(([0-6@-Wa-w])(??{chr(ord($2)+1).chr(ord($2)+2).chr(ord($2)+3)}))/); # four consecutive characters, e.g. "defg"
 return 0;
}

# Create a line of PSK file.
# Parameters: MAC, key, timestamp, vlanid, wps, comment, revoked
sub pskline {
 my ($m,$k,$t,$v,$w,$c,$d) = @_;
 my $r = $m;
 $r = "$r $k" if $k;
 $t = $t . "_" . $c if $c;
 $r = "keyid=$t $r" if $t;
 $r = "vlanid=$v $r" if $v;
 $r = "wps=$w $r" if $w;
 $r = "#REVOKED# $r" if $d;
 return $r;
}

my $macpat = qr/([0-9a-f]{2}:){5}[0-9a-f]{2}/in;

# Return true if the parameter contains a MAC address.
sub hasmac {
 my ($x) = @_;
 return $x =~ /$macpat/;
}

# Parse a line of PSK file.
# Parameters: line, arrayref
# Returns result by setting array to (MAC, key, timestamp, vlanid, wps, comment, revoked)
sub parsepskline {
 my ($l,$r) = @_;
 @$r = ("", "", "", "", "", "", 0);
 $l =~ /($macpat)/ && do { $r->[0] = $1; };
 $l =~ /$macpat\s+(.*)$/ && do { $r->[1] = $1; };
 $l =~ /keyid=([^\s]*)/ && do {
  my $k = $1;
  $k =~ /^(\d+)/ && do { $r->[2] = $1; };
  $k =~ /^\d+_(.*)/ && do { $r->[5] = $1; };
 };
 $l =~ /vlanid=([^\s]*)/ && do { $r->[3] = $1; };
 $l =~ /wps=([^\s]*)/ && do { $r->[4] = $1; };
 $l =~ /^#REVOKED#/ && do { $r->[6] = 1; };
}

# List the hostapd devices.
# Returns list of device names (like "phy0-ap1")
sub hostapd_list {
 my @l = split(/[\r\n]+/, qx(hostapd_cli interface));
 return sort map { if (/^phy/) {$_} else {} } @l;
}

# Get the status of a hostapd device.
# Parameter: device name
# Returns: hashref
sub hostapd_status {
 my ($dev) = @_;
 my %r = ();
 hostapd_call($dev, "get_config", \%r);
 hostapd_call($dev, "status", \%r);
 return \%r;
}

sub hostapd_call {
 my ($dev, $cmd, $r) = @_;
 open(C, "-|", "hostapd_cli -i $dev $cmd");
 while (<C>) {
  /^([^= ]+)\s*=\s*(.*)$/ && do { $r->{$1} = $2; };
 }
 close C;
}

my $LOG = "";

# Debug logging.
# Parameters: any number of lines to log
sub log_ {
  $LOG .= join("\n", @_);
  $LOG .= "\n";
}

# Returns and clears accumulated debug logs.
sub log_get {
  my $l = $LOG;
  $LOG = "";
  return $l;
}

# URL-encoding
sub urlencode {
  my ($x) = @_;
  utf8::encode($x);
  $x =~ s/([^ A-Za-z0-9._-])/sprintf("%%%02x",ord($1))/ge;
  $x =~ s/ /+/g;
  return $x;
}

1;
