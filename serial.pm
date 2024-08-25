# Simplistic serialization functions for Perl data structures.
# The serial form looks as follows:
# 1. Each element starts with the length, which is in "w" format and includes the type byte.
# 2. Follows the type byte: 001=scalar, 002=array, 003=hash, 000=other
# 3. Follows the encoding:
#    a. scalar is encoded as itself,
#    b. arrayref is encoded as the concatenation of the serial forms of its elements in order,
#    c. hashref is encoded like its array form,
#    d. everything else is encoded as nothing and deserialized to undef.
#
# Author: olaf@bigred.inka.de. Public domain.

package serial;
use strict;
use warnings;
use Exporter 'import';
our $VERSION = "1.00";
our @EXPORT = qw(serialize deserialize prettyprint);

# Serialize a data structure.
# Parameter: a scalar, array ref or hash ref
# Return: serial form (scalar)
sub serialize {
  my ($x) = @_;
  if (defined($x)) {
    my $t = ref($x);
    if ($t eq '')      { return pack("w/a*", "\001" . $x); }
    if ($t eq 'ARRAY') { return pack("w/a*", "\002" . join("", map {serialize($_)} @$x)); }
    if ($t eq 'HASH')  { return pack("w/a*", "\003" . join("", map {serialize($_)} %$x)); }
  }
  return "\001\000";
}

# Deserialize a serialized form.
# Parameter: a scalar, as returned by serialize.
# Return: the original data structure, always a scalar which may be an array ref or hash ref
sub deserialize {
  my ($x) = @_;
  return defined($x) ? _deserialize(unpack("w/a*", $x)) : undef;
}

sub _deserialize {
  my ($t, $v) = (substr($_[0], 0, 1), substr($_[0], 1));
  if ($t eq "\001") { return $v; }
  if ($t eq "\002") { my @v = unpack("(w/a*)*", $v); my @x = (map {_deserialize($_)} @v); return \@x; }
  if ($t eq "\003") { my @v = unpack("(w/a*)*", $v); my %x = (map {_deserialize($_)} @v); return \%x; }
  return undef;
}

# Pretty-print a data structure.
# Parameter: a scalar, array ref or hash ref
# Return: string to print
sub prettyprint {
  # this works essentially the same way as serialize, except for the indentation.
  # Also used for testing (de)serialization.
  my ($x, $i) = @_;
  if (defined($x)) {
    my $t = ref($x);
    if ($t eq '')      { return (" " x $i) . $x . "\n"; }
    if ($t eq 'ARRAY') { return (" " x $i) . "[\n" . join("", map {prettyprint($_, $i+1)} @$x) . (" " x $i) . "]\n"; }
    if ($t eq 'HASH')  { return (" " x $i) . "{\n" . join("", map {prettyprint($_, $i+1)} %$x) . (" " x $i) . "}\n"; }
  }
  return " " x $i . "<undef>\n";
}

1;
