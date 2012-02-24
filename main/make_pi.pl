#################################################################################
# Copyright (C) 2011, 2012 - Mariano Spadaccini    mariano@marianospadaccini.it #
#                                                                               #
# This file is part of pi                                                       #
#                                                                               #
#  pi is free software; you can redistribute it and/or modify                   #
#  it under the terms of the GNU General Public License as published by         #
#  the Free Software Foundation; either version 2 of the License, or            #
#  (at your option) any later version.                                          #
#                                                                               #
#  pi is distributed in the hope that it will be useful,                        #
#  but WITHOUT ANY WARRANTY; without even the implied warranty of               #
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the                #
#  GNU General Public License for more details.                                 #
#                                                                               #
#  You should have received a copy of the GNU General Public License            #
#  along with Foobar; if not, write to the Free Software                        #
#  Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA   #
#################################################################################

#!/usr/bin/perl";

use warnings;
use strict;
use feature qw(say);

use Math::BigFloat;
use Log::Log4perl;
use Data::Dumper;
use Storable;
use DateTime;
use bigint;	# to fix problem line 149

my $pathRoot = '/home/mariano/perl/pigreco/';

Log::Log4perl::init_and_watch('inc/log_server.conf',10);
#our $log = Log::Log4perl::get_logger('Log');

unless ( defined($ARGV[0]) and grep(/^$ARGV[0]$/, qw/help info make_pi dump only_count clean/ ) ) {
    print "Please enter: perl make_pi.pl [info|make_pi|only_count|dump|clean]\n\n";
    exit 0;
}


if ($ARGV[0] eq 'help') {
    print "Please enter: perl make_pi.pl [info|make_pi|only_count|dump|clean]";
    print "\n\thelp\t\twrites these instructions";
    print "\n\tinfo\t\twrites a summary of pi and last calculated delta";
    print "\n\tmake_pi\t\tcalculates new pi by adding delta";
    print "\n\tonly_count\tsimulates the calculation of new pi by adding delta";
    print "\n\tdump\t\twrites to text the pi and last delta";
    print "\n\tclean\t\twrites the instructions to clean and re-init the calculus";
    print "\n";
    exit 0;
} elsif ($ARGV[0] eq 'clean') {
    system('cat schema/create.sql');
    print "\n\tType this sequence in directory db/.";
    print "\n\tIf presents remove the files in directory restore/\n";
    exit 0;
}

$|=1;
my $dt = DateTime->now(time_zone => 'Europe/Rome');
my $pathDir = $pathRoot.'data';
my $archive = $pathRoot.'archive/'.$dt->ymd('').'_'.$dt->hms('');
system("/bin/mkdir -p $archive") if $ARGV[0] eq 'make_pi';
my $pathDir_last = $pathRoot.'restore/last.store';
my $pathDir_pi = $pathRoot.'restore/pi.store';
chdir $pathDir;
my $last; my $pi;

if (-e $pathDir_pi and -e $pathDir_last) {
    $last = retrieve($pathDir_last);
    $pi = retrieve($pathDir_pi);
}
$last = -1 unless defined($last);
$pi = Math::BigFloat->new(0) unless defined($pi);

if ($ARGV[0] eq 'info' or $ARGV[0] eq 'dump') {
    my $pi_out = $pi;
    if ( $ARGV[0] eq 'info' and length($pi_out) > 100 ) {
	$pi_out = substr($pi,0,50) .'[...]'. substr($pi,length($pi)-50, 50);
    }
    print $pi_out,' -> ',length($pi),"\n";
    print 'last step -> ',$last, "\n";
    exit 0;
}

my @files = `/bin/ls`;
my @nums_unordered;
foreach (@files) {
    push @nums_unordered, $1 if ( /^(\d+).s$/ and $1 > $last);
}
my @nums = sort { $a <=> $b } @nums_unordered;
if (scalar @nums < 1) {
    print "Nothing because there isn't nothing in data or files in data are less recent of last delta\n";
    exit 0;
}
my $lastNum = $nums[0]-1;
foreach my $num ( sort { $a <=> $b } @nums ) {
    # open the file and set the dPi
    my $fh = $num.'.s';
    my $dPi = retrieve($fh);
    $pi += $dPi;

    # check increment
    my $copia_dPi = $dPi;
    $copia_dPi =~ s/[\+\-](\d+)/$1/;
    my $length_dPi = length($copia_dPi);
    my $length_pi = length($pi);
    $lastNum++;
    if ( ( $length_dPi*10/9 < $length_pi ) or ( $lastNum != $num ) ) {
	# was $length_dPi != $length_pi but `ls -l 164[789].txt
	# -rw-r--r-- 1 mariano mariano 5046 2011-09-21 10:24 1647.txt
	# -rw-r--r-- 1 mariano mariano 5043 2011-09-21 10:24 1648.txt
	# -rw-r--r-- 1 mariano mariano 5049 2011-09-21 10:24 1649.txt`
	print "\nThere is a problem... file analized ".$num.'.txt'."\n";
	print '$dPi = ' .$dPi ."\n";
	print '$copia_dPi = ' .$copia_dPi . "\n";
	print 'length pi -> '.$length_pi ."\n";
	print 'length absolute value $dPi -> '.$length_dPi ."\n";
	print 'last $num examinated -> '. ($lastNum-1) ."\n";
	print 'current $num examinated -> '. $num ."\n";
	exit 0;
    }
    print "\rstep ".$num .' -> figures '.$length_dPi;
    my $cmd = '/bin/mv '.$pathDir.'/'.$num.'.s '.$archive."\n";
    system($cmd) unless $ARGV[0] eq 'only_count';

    # verify file state... eventually exit
    shift @files;
}
print "\n\n".'Summary'."\n".'-'x60 ."\n";
my $stepIniziale = $last+1;
my $stepEffettuati = $lastNum-$stepIniziale;
print 'Calculated '.$lastNum .' total step, ('.$stepEffettuati.' now) from init step '. $stepIniziale . "\n";
my $pi_out = $pi;
if ( length($pi_out) > 100 ) {
    $pi_out = substr($pi,0,50) .'[...]'. substr($pi,length($pi)-50, 50);
}
print 'pi ~ '.$pi_out."\n";
print 'figures ~ '.length($pi);
print "\n".'-'x60 . "\n";

exit 0 if $ARGV[0] eq 'only_count';

print 'Dumping current state...';
store $pi, $pathDir_pi;
store $lastNum, $pathDir_last;
print "ok\n";
print "Historical archive in $archive\n";
print "Finish\n";
exit 0;
