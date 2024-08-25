package wkkey;
use strict;
no strict 'refs';
use warnings;
use Exporter 'import';
our $VERSION = '0.00';
our @EXPORT = qw(wkkey);

use Fcntl qw(:flock SEEK_SET);
use wkfuncs;

my %IN = ();
my %OUT = ();
my $allmac = "00:00:00:00:00:00";

sub wkkey {
  %IN = %{$_[0]};
  checkarg("action");
  &{"action_$IN{'action'}"};
  return \%OUT;
}

sub checkarg {
    for my $x (@_) {
        die "$x missing" unless defined($IN{$x});
    }
}

sub action_genkey {
    &checkarg("length", "type");
    my $key = ($IN{"type"} < 0) ? undef : &genkey($IN{"length"}, $IN{"type"});
    $OUT{"key"} = $key;
    return $key;
}

sub action_newkey {
    &checkarg("ssid", "dev");
    my $newkey = &action_genkey;
    my $ssid = $IN{"ssid"};
    require wkmacs;
    &wkmacs::wkmacs;
    my $oldkey;
    my @L = ();
    my %M = ();
    open(M, "<", &macfile($ssid));
    flock(M, LOCK_SH);
    open(K, "+<", &pskfile($ssid));
    flock(K, LOCK_EX);

    while (<K>) {
        parsepskline($_, \@L);
        $oldkey = $L[1] if $L[0] eq $allmac;
        my @X = @L;
        $M{$X[0]} = \@X;
    }

    if (defined($oldkey)) {
      while (<M>) {
        parsepskline($_, \@L);
        unless (defined($M{$L[0]})) {
            my @X = @L;
            $X[1] = $oldkey;
            $M{$X[0]} = \@X;
        }
      }
    }

    if (defined($newkey)) {
      $M{$allmac} = [$allmac, $newkey, &now];
    } else {
      undef $M{$allmac};
    }

    seek(K, 0, SEEK_SET);
    truncate(K, 0);
    for my $m (keys %M) {
        my $L = $M{$m};
        printf(K "%s\n", pskline(@$L));
    }

    close K;
    close M;

    my $r = qx(hostapd_cli -i $IN{'dev'} reload_wpa_psk);
    log_("reload: $r");
}

sub changepsk {
    my ($action) = @_;
    &checkarg("ssid", "mac","dev");
    my $ssid = $IN{"ssid"};
    require wkmacs;
    &wkmacs::wkmacs;
    my @L = ();
    my %M = ();
    open(K, "+<", &pskfile($ssid));
    flock(K, LOCK_EX);
    while (<K>) {
        parsepskline($_, \@L);
        my @X = @L;
        $M{$X[0]} = \@X;
    }
    &{$action}(\%M);
    seek(K, 0, SEEK_SET);
    truncate(K, 0);
    for my $m (keys %M) {
        my $L = $M{$m};
        printf(K "%s\n", pskline(@$L));
    }
    close K;
    my $r = qx(hostapd_cli -i $IN{'dev'} reload_wpa_psk);
    log_("reload: $r");
    $OUT{"keys"} = \%M;
}

sub action_update {
    &checkarg("comment", "vlanid");
    &changepsk(\&_update);
}

sub _update {
    my ($M) = @_;
    my ($mac) = $IN{"mac"};
    if (defined($M->{$mac})) {
      my ($c) = $IN{"comment"};
      $c =~ s/[^A-Za-z0-9._-]+/_/g;
      $M->{$mac}[5] = substr($c, 0, 15);
      my ($v) = $IN{"vlanid"};
      $v =~ tr/0-9//cd;
      $v = "" unless ($v > 0 && $v < 4096);
      $M->{$mac}[3] = $v;
      $M->{$mac}[2] = &now unless $M->{$mac}[2];
    } else {
      $OUT{"error"} = "Unknown MAC";
    }
}

sub action_revoke {
  $IN{"revoke"} = 1;
  &changepsk(\&_revoke);
  my $r = qx(hostapd_cli -i $IN{'dev'} disassociate $IN{'mac'});
  log_("disassociate: $r");
}

sub action_unrevoke {
  $IN{"revoke"} = 0;
  &changepsk(\&_revoke);
}

sub _revoke {
    my ($M) = @_;
    my ($mac) = $IN{"mac"};
    if (defined($M->{$mac})) {
      my ($r) = $IN{"revoke"};
      $M->{$mac}[6] = $r;
    } else {
      $OUT{"error"} = "Unknown MAC";
    }
}

sub action_recallkey {
    &changepsk(\&_recallkey);
}

sub _recallkey {
    my ($M) = @_;
    my ($mac) = $IN{"mac"};
    if (defined($M->{$mac})) {
      my $L = $M->{$mac};
      $M->{$allmac} = [$allmac, $L->[1], &now];
    } else {
      $OUT{"error"} = "Unknown MAC";
    }
}

sub action_status {
    &checkarg("ssid");
    my @L = ();
    open(K, "<", &pskfile($IN{"ssid"}));
    flock(K, LOCK_SH);
    while (<K>) {
        parsepskline($_, \@L);
        $OUT{"key"} = $L[1] if $L[0] eq $allmac;
    }
    close K;
    &action_wpsstatus;
}

sub action_wpsstatus {
    &checkarg("dev");
    open(S, "-|", "hostapd_cli -i $IN{'dev'} wps_get_status");
    my ($pbcstatus, $wpsresult) = (1, 2);
    while (<S>) {
      chomp;
      /PBC Status:\s*(.*)$/i && do { $pbcstatus = $1; };
      /WPS result:\s*(.*)$/i && do { $wpsresult = $1; };
    }
    close S;
    if ($pbcstatus eq "Disabled") {
        $OUT{"wps"} = ($wpsresult eq "None") ? "Disabled" : $wpsresult;
    } else {
        $OUT{"wps"} = $pbcstatus;
    }
}

sub action_startwps {
    &checkarg("dev");
    my $r = qx(hostapd_cli -i $IN{'dev'} wps_pbc);
    log_("action_startwps $IN{'dev'}: $r");
    &action_status;
}

sub action_stopwps {
    &checkarg("dev");
    my $r = qx(hostapd_cli -i $IN{'dev'} wps_cancel);
    log_("action_stopwps $IN{'dev'}: $r");
    &action_status;
}

sub action_keylist {
    &checkarg("ssid");
    my @L = ();
    my %M = ();
    open(K, "<", &pskfile($IN{"ssid"}));
    flock(K, LOCK_SH);
    while (<K>) {
      parsepskline($_, \@L);
      my @X = @L;
      $M{$X[0]} = \@X;
    }
    close K;
    $OUT{"keys"} = \%M;
}

1;
