#################################################################################
# Copyright (C) 2011, 2012 - Mariano Spadaccini    mariano@marianospadaccini.it #
#										#
# This file is part of pi							#
#										#
#  pi is free software; you can redistribute it and/or modify			#
#  it under the terms of the GNU General Public License as published by		#
#  the Free Software Foundation; either version 2 of the License, or		#
#  (at your option) any later version.						#
#										#
#  pi is distributed in the hope that it will be useful,			#
#  but WITHOUT ANY WARRANTY; without even the implied warranty of		#
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the		#
#  GNU General Public License for more details.					#
#										#
#  You should have received a copy of the GNU General Public License		#
#  along with Foobar; if not, write to the Free Software			#
#  Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA	#
#################################################################################

#!/usr/bin/perl";

use warnings;
use strict;
use feature qw(say);

use IO::Socket;
use Proc::Daemon;
use Math::BigFloat;
use Log::Log4perl;
use Data::Dumper;
use Storable;
use DBI;
use DateTime;

# management signal
$SIG{CHLD} = 'IGNORE';
$SIG{INT} = \&info;
$SIG{INT} = \&quit;
$SIG{QUIT} = \&quit;
$SIG{TRAP} = \&dump;
$SIG{USR1} = \&setDebug;
$SIG{TERM} = \&quit;
$SIG{ALRM} = \&timed_out;

# prototype
sub openServerSocket($);
sub info();
sub dump();
sub setDebug();
sub quit();
sub myDie($);
sub timeout();

# socket
my $port = 4431;
my $timeout = 60;

Log::Log4perl::init_and_watch('inc/log_server.conf',10);
our $log = Log::Log4perl::get_logger('Log');

#daemonize
#Proc::Daemon::Init;
our $debug = 1;
my $pid = $$;
my $infLim = -10_000;
my $factorMaxClient = 25; # max step up waiting = 100 and $pi{$1} = -10_000 if exists $pi{$1};
$log->debug('Launch daemon -> pid ' . $pid);
my $dbh = DBI->connect("dbi:SQLite:dbname=db/pi.sqlite","","");

$log->trace('Try to open server sockets...');
my $socket = openServerSocket( $port );
$log->debug('Open socket (GET) on port ' . $port);

$|=1;

# set init value
$log->trace('Set init step ($i=0)');
my $i;

$log->trace('Start loop while(1)');
while (1) {
#    print 'pi -> '.Dumper(\%pi);
    $log->trace("I'm waiting for a new client...");
    my $client = $socket->accept();
    next unless defined($client);
    $client->autoflush(1);

    my $clientIp = $client->peerhost();
    my $clientIpPort = $client->peerhost() . '|' . $client->peerport();
    $log->debug( 'connection from [' . $clientIpPort.']' );

    myDie("can't fork: $!") unless defined (my $child = fork());
    unless ( $child ) {
	my $pid = $$;
	$log->debug("fork [$pid] for [$clientIpPort]");
	eval {
	    alarm $timeout;
	    while (my $msg = <$client>) {
		chomp($msg);
		$log->info( "[$clientIpPort] -> '$msg'" );

		if ( $msg =~ /^GET/ ) {
		    insertClient($dbh,$clientIp);
		    $i = incStep($dbh);
		    $log->debug( 'GET request from [' . $clientIpPort.']' );
		    $log->trace("send key to [$clientIpPort]: $i");
		    say $client $i;
		} elsif ( $msg =~ /^PUT.+for (\d+)$/ ) {
		    decWait($dbh,$1);
		    $log->debug( 'PUT request from [' . $clientIpPort .']');
		} elsif ( $msg =~ /^BYE/ ) {
		    $log->debug( 'BYE request from [' . $clientIpPort .']');
		    last;
		} else {
		     $log->error( 'Unknown request from [' . $clientIpPort .']' );
		     my $msg = 'I can break the rules too';
		     say $client $msg;
		}
	    }
	    alarm(0);
	};
	if ( $@ ) {
	    if ( $@ =~ /^GOT TIRED OF WAITING/ ) {
		$log->error( 'DROP session: [' . $clientIpPort .']');
	    } else {
		myDie($@);
	    }
	} else {
	    incWait($dbh);
	    $log->debug( 'Completed session: [' . $clientIpPort .']');
	}
	close($client);
	$log->debug("quit [$pid] for [$clientIpPort]");
	exit 0;
    } else {
	deletePi($dbh);
	$log->debug( 'Next step -> '.maxStep($dbh) );
    }
}

quit();
exit 0;

sub openServerSocket ($) {
    my $port = shift;
    my $socket = IO::Socket::INET->new(
			LocalPort => $port,
			Reuse     => 1,
			Listen    => 10
	) or myDie("Couldn't be a tcp server on port $port: $@");
    return $socket;
}

sub info() {
    $log->info("received signal (kill -2) -> info");
#    say 'pi -> ', $pi;
#    say 'digit(pi) -> ', length($pi)-2, ' 'x5, 'md5(current pi) -> ', md5_hex($pi);
    say 'SIGINT:   kill -2 ', $$, ' (info)';
    say 'SIGQUIT:  kill -3 ', $$, ' (quit)';
    say 'SIGTRAP:  kill -5 ', $$, ' (dump)';
    say 'SIGUSR1:  kill -10 ', $$, ' (set debug): now ', $debug;
    say 'SIGCHILD: for internal use', ' (don\'t use)';
}

sub dump() {
    $log->info("received signal (kill -5) -> dump");
    print 'Saving...';
    say ' ok';
}

sub setDebug() {
    $debug = $debug ? 0 : 1;
}

sub quit() {
    $log->info("received signal (kill -5) -> quit");
    exit 0;
};

sub myDie($) {
    my $msg = shift;
    say $msg;

    my $log = Log::Log4perl::get_logger('Log');
    $log->fatal($msg);
    exit 1;
} 

sub timed_out {
    die 'GOT TIRED OF WAITING';
}

sub maxRetard {
    my %pi = shift;
    my @ordered = sort { $pi{$b} <=> $pi{$a} } keys %pi;
    return shift @ordered;
}

sub incStep {
    my $dbh = shift;
    my ($i,$wait) = getMaxWait($dbh);
    my $max;
    if ($wait > countClient($dbh)*$factorMaxClient) {
	$max = $i;
    } else {
	$max = maxStep($dbh);
    }
    my $query = q/REPLACE INTO pi (i, wait) VALUES (?,0)/;
    my $sth = $dbh->prepare($query);
    my $rv = $sth->execute($max);
    return $max;
}

sub maxStep {
    my $dhb = shift;
    my $query = q/SELECT max(i) AS max FROM pi/;
    my $sth = $dbh->prepare($query);
    my $rv = $sth->execute;
    my $row = $sth->fetchrow_hashref;
    my $max = defined($row->{'max'}) ? $row->{'max'} : -1;
    return ++$max;
}

sub incWait {
    my $dbh = shift;
    my $query = q/UPDATE pi SET wait = wait+1/;
    my $sth = $dbh->prepare($query);
    my $rv = $sth->execute();
    return 0;
}

sub decWait {
    my $dbh = shift;
    my $i = shift;
    my $query = q/UPDATE pi SET wait = ? WHERE i=?/;
    my $sth = $dbh->prepare($query);
    my $rv = $sth->execute($infLim, $i);
    return 0;
}

sub deletePi {
    my $dbh = shift;
    my $max = maxStep($dbh);
    my $query = q/DELETE FROM pi WHERE wait < 0 AND wait > ? AND i != ?/;
    my $sth = $dbh->prepare($query);
    my $rv = $sth->execute($infLim+5, --$max);
    return 0;
}

sub countClient {
    my $dbh = shift;
    my $query = q/SELECT count(*) AS count FROM client/;
    my $sth = $dbh->prepare($query);
    my $rv = $sth->execute;
    my $row = $sth->fetchrow_hashref;
    return defined($row->{'count'}) ? $row->{'count'} : 0;
}

sub insertClient {
    my $dbh = shift;
    my $clientIp = shift;
    my $dt = DateTime->now();
    my $query = q/REPLACE INTO client (clientIpPort,last) VALUES (?,?)/;
    my $sth = $dbh->prepare($query);
    my $rv = $sth->execute($clientIp, $dt->ymd.' '.$dt->hms);
    return 0;
}

sub deleteClient {
    my $dbh = shift;
    my $clientIp = shift;
    my $dt = DateTime->now();
    $dt->subtract( hours => 1 );
    my $query = q/DELETE FROM client WHERE last < ?/;
    my $sth = $dbh->prepare($query);
    my $rv = $sth->execute($dt->ymd.' '.$dt->hms);
    return 0;
}

sub getMaxWait {
    my $dbh = shift;
    my $query = q/SELECT i, wait FROM pi ORDER by 2 DESC LIMIT 1/;
    my $sth = $dbh->prepare($query);
    my $rv = $sth->execute;
    my $row = $sth->fetchrow_hashref;
    return ( defined( $row->{'i'}) ? $row->{'i'} : 0,
	defined( $row->{'wait'} ) ? $row->{'wait'} : 0
    );
}
