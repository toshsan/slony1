#!@@PERL@@
# $Id: merge_sets.pl,v 1.7 2005-02-10 04:32:49 smsimms Exp $
# Author: Christopher Browne
# Copyright 2004 Afilias Canada

use Getopt::Long;

$SLON_ENV_FILE = 'slon.env'; # Where to find the slon.env file
$SHOW_USAGE    = 0;          # Show usage, then quit

# Read command-line options
GetOptions("config=s"  => \$SLON_ENV_FILE,
	   "help"      => \$SHOW_USAGE);

my $USAGE =
"Usage: merge_sets.pl [--config file] node# set# set#

    Merges the contents of the second set into the first one.

";

if ($SHOW_USAGE) {
  print $USAGE;
  exit 0;
}

require 'slon-tools.pm';
require $SLON_ENV_FILE;

my ($node, $set1, $set2) = @ARGV;
if ($node =~ /^(?:node)?(\d+)$/) {
  # Set name is in proper form
  $node = $1;
} else {
  print "Valid node names are node1, node2, ...\n\n";
  die $USAGE;
}

if ($set1 =~ /^(?:set)?(\d+)$/) {
  $set1 = $1;
} else {
  print "Valid set names are set1, set2, ...\n\n";
  die $USAGE;
}

if ($set2 =~ /^(?:set)?(\d+)$/) {
  $set2 = $1;
} else {
  print "Valid set names are set1, set2, ...\n\n";
  die $USAGE;
}

my ($dbname, $dbhost) = ($DBNAME[$MASTERNODE], $HOST[$MASTERNODE]);

open(SLONIK, ">", "/tmp/slonik.$$");
print SLONIK genheader();
print SLONIK "  try {\n";
print SLONIK "    merge set (id = $set1, add id = $set2, origin = $node);\n";
print SLONIK "  } on error {\n";
print SLONIK "    echo 'Failure to merge sets $set1 and $set2 with origin $node';\n";
print SLONIK "    exit 1;\n";
print SLONIK "  }\n";
print SLONIK "  echo 'Replication set $set2 merged in with $set1 on origin $node';\n";
close SLONIK;
run_slonik_script("/tmp/slonik.$$");
