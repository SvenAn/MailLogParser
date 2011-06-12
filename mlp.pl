#!/usr/bin/perl
###             mlp.pl v0.001                   ###
# MailLogParse by Sven Andreassen sven@tideli.com #
# a small utility to parse e-mail log files       #
# printing all necessary info about an e-mail     #
# in a simple, human readable format.             #
###                                             ###


use strict;
use warnings;
use Getopt::Long;


my ( $verbose, $brief, $help, $csv );
my $options = GetOptions ( "v|verbose" => \$verbose,
                           "b|brief"   => \$brief,
                           "c|csv"     => \$csv,
                           "h|help"    => \$help );

my $address = $ARGV[0] || 'all';

my ( $mailbox, $time, $server, $cmd, $id, $line );


###
# Printing the result in chosen format.
sub printmailinfo {
	my $mail = $_[0];

	$mail->{to} = join( ", ", @{ $mail->{to} } );
	if ( $mail->{to} eq '' ) { $mail->{to} = '<>'; }
	$mail->{delay} = join( ", ", @{ $mail->{delay} } );
	$mail->{relay} = join( ", ", @{ $mail->{relay} } );
	$mail->{status} = join( ", ", @{ $mail->{status} } );
	$mail->{info} = join( ", ", @{ $mail->{info} } );

	if ( ! defined( $mail->{from} ) ) { $mail->{from} = '<>'; }
	
	return  if ( $address ne 'all' && ( $mail->{from} !~ /$address/i && $mail->{to} !~ /$address/i ) );

	if ( $verbose ) {
		if ( $csv ) {
			print "$mail->{deleted_time},$mail->{id},$mail->{from},$mail->{to},$mail->{size},$mail->{delay},$mail->{status},$mail->{relay},$mail->{info}\n";
		}
		else {
			printf "%-12s %-12s From:%s To:%s Size:%s Delay:%s.\n\tStatus:%s Relay: %s\n\tInfo: %s\n", 
	       			$mail->{deleted_time},
	       			$mail->{id},
	       			$mail->{from},
	       			$mail->{to},
	       			$mail->{size},
				$mail->{delay},
				$mail->{status},
				$mail->{relay},
				$mail->{info};
		}
	}
	elsif ( $brief ) {
		if ( $csv ) {
			print "$mail->{deleted_time},$mail->{id},$mail->{from},$mail->{to}\n";
		}
		else {
			printf "%-12s %-11s From:%s  To:%s\n", 
	       			$mail->{deleted_time},
	       			$mail->{id},
	       			$mail->{from},
	       			$mail->{to};
		}
	}
	else {
		if ( $csv ) {
			print "$mail->{deleted_time},$mail->{id},$mail->{from},$mail->{to},$mail->{status},$mail->{relay}\n";
		}
		else {
			printf "%-12s %-12s From:%s To:%s Status:%s Sent to: %s\n", 
	       			$mail->{deleted_time},
	       			$mail->{id},
	       			$mail->{from},
	       			$mail->{to},
				$mail->{status},
				$mail->{relay},
		}
	}
}


###
# Parsing the postfix log line extracting all necessary info into the mailbox hash.
sub parsepostfix {
	# Find message or create new hash
	my $mail = $mailbox->{messages}->{$server, $id} ||= { id => $id, time => $1, server => $2, to => [ ] };

	if ( $cmd eq 'qmgr' ) {
		if ( $line =~ /^removed$/ ) {
			$mail->{deleted_time} = $time;
			&printmailinfo( $mail );
			delete $mailbox->{messages}->{$server, $id};
		} 
		else {
			$mail->{from} = $1 if $line =~ /^from=<([^>]+)>/;
			$mail->{size} = $1 if $line =~ /size=(\d+)/;
			$mail->{first_seen} = $time;
		}

	}
	elsif ( $cmd eq 'cleanup' ) {
		$mail->{msgid} = $1 if $line =~ /^message-id=(<[^>]+>)/;
	}
	elsif ( $cmd eq 'virtual' || $cmd eq 'smtp' || $cmd eq 'error' ) {
		push @{ $mail->{to}     }, $1 if $line =~/^to=<([^>]+)>/;
		push @{ $mail->{delay}  }, $1 if $line =~ /delay=(\d+)/;
		push @{ $mail->{delay}  }, $1 if $line =~ /delay=(\d+\.\d+)/;
		push @{ $mail->{relay}  }, $1 if $line =~ /relay=(.*?), /;
		push @{ $mail->{status} }, $1 if $line =~ /status=(\w+)/;
		push @{ $mail->{info}   }, $1 if $line =~ /(\(.*\)$)/;
	}
}


while ( <STDIN> ) {

	# Check if line is in a known Postfix format:
	if ( $_ =~ m!^(\w\w\w\s{1,2}\d{1,2} \d\d:\d\d:\d\d) (\w+) postfix/(\w+)\[\d+\]: ([0-9A-F]+): (.*)! ) {
		( $time, $server, $cmd, $id, $line ) = ( $1, $2, $3, $4, $5 );
		&parsepostfix( $_ );
	}
}
