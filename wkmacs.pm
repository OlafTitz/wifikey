package wkmacs;
use strict;
use 5.012;
use warnings;
use Exporter 'import';
our $VERSION = '0.00';
our @EXPORT = qw(wkmacs);

use open ':std', ':utf8';
use Fcntl qw(:flock SEEK_SET);
use wkfuncs;

# Collect known MAC associations. Queries for associated clients,
# and if any of them is unknown, records them with a current timestamp
# in the MAC files.
#
# This is to be run regularly as a cron job, and also by wkkey
# just before switching keys.
#
# This is the only program writing to the MAC files.
#

sub wkmacs {
  # Loop over all device instances
  for my $dev (&hostapd_list) {
    &processdev($dev);
  }
}

# Process one device instance (like phy0-ap1)
sub processdev {
  my ($dev) = @_;
  # Query the device for SSID and clients
  my $status = hostapd_status($dev);
  my $ssid = $status->{"ssid"};
  # For all clients, collect them into %macs
  # as MAC->timestamp, if they are authenticated
  my %macs = ();
  my $mac = "";
  open(C, "-|", "hostapd_cli -i $dev all_sta");
  while (<C>) {
    chomp;
    if (hasmac($_)) {
      $mac = $_;
    }
    if (/^flags=.*\[AUTHORIZED\]/) {
      $macs{$mac} = &now if ($mac);
      $mac = "";
    }
  }
  close C;
  # Now record the collected MACs
  &rewritemacfile($ssid, \%macs);
}

# Maintain the MAC file. Purge entries which are also
# in the PSK file, add new entries as collected.
# Parameters: SSID, MAC->timestamp map of found MACs
sub rewritemacfile {
  my ($ssid, $macs) = @_;
  my @L = ();
  # Read the PSK file
  open(K, "<", &pskfile($ssid)) || return;
  flock(K, LOCK_SH);
  while (<K>) {
    parsepskline($_, \@L);
    $macs->{$L[0]} = "!";
  }
  close K;
  # Now macs contains a "!" for an entry to delete
  # or the timestamp for an entry to add
  open(M, "+<", &macfile($ssid)) || open(M, "+>", &macfile($ssid)) || die;
  flock(M, LOCK_EX);
  # Read the MAC file
  while (<M>) {
    parsepskline($_, \@L);
    # Keep the existing timestamps, unless in the PSK file
    if (!defined($macs->{$L[0]}) || $macs->{$L[0]} ne "!") {
      $macs->{$L[0]} = $L[2];
    }
  }
  # Now macs has the contents for the new MAC file. Rewrite it.
  seek(M, 0, SEEK_SET);
  truncate(M, 0);
  for my $mac (keys %$macs) {
    printf(M "%s\n", pskline($mac, undef, $macs->{$mac}))
      unless $macs->{$mac} eq "!";
  }
  close(M);
}

1;
