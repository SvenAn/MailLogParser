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

my ( $i, $j, $msg, $time, $server, $cmd, $id, $line, $Mailscanner );


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
			print "$mail->{deleted_time},$mail->{id},$mail->{from},$mail->{to},$mail->{size},$mail->{delay},$mail->{status},$mail->{spam_score}, $mail->{spam_score_required}, $mail->{spam_score_detail},$mail->{relay},$mail->{info}\n";
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
			printf "%-12s %-10s %-10s From:%s To:%s Sent to: %s\n", 
	       			$mail->{deleted_time},
	       			$mail->{id},
				$mail->{status},
	       			$mail->{from},
	       			$mail->{to},
				$mail->{relay},
		}
	}
}


###
# Parsing the postfix log line extracting all necessary info into the mailbox hash.
sub parsepostfix {
	# Find message or create new hash
	my $mail = $msg->{$id} ||= { id => $id, time => $1, server => $2, to => [ ] };

	if ( $cmd eq 'qmgr' ) {
		if ( $line =~ /^removed$/ ) {
			$mail->{deleted_time} = $time;
			&printmailinfo( $mail );
			delete $msg->{$id};
		} 
		else {
			$mail->{from} = $1 if $line =~ /^from=<([^>]+)>/;
			$mail->{size} = $1 if $line =~ /size=(\d+)/;
			$mail->{first_seen} = $time;
		}

	}
	elsif ( $cmd eq 'cleanup' ) {
		#print "\tLine=$line";
		$mail->{msgid} = $1 if $line =~ /^message-id=(<[^>]+>)/;
		$mail->{from} = $1 if $line =~ /from=<([^>]+)>/;
		push @{ $mail->{to}     }, $1 if $line =~/to=<([^>]+)>/;
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


###
# Parsing the mailscanner log line extracting all necessary info into the mailbox hash.
sub parsemailscanner {
	if ( $line =~ /Message ([0-9A-F]+)\.[0-9A-F]+/ ) {
		$id = $1;
	}

	if ( $line =~ /\((.*\@.*)\) to .* (is not spam|is spam|is too big|is whitelisted|is blacklisted)/ ) {
		$msg->{$id}->{from} = $1;
		$msg->{$id}->{spam_status} = $2;
		( $msg->{$id}->{spam_score}, $msg->{$id}->{spam_score_required}, $msg->{$id}->{spam_score_detail} ) = ( $1, $2, $3 ) if 
			$line =~ /\(score=(\d+\.\d+), required (\d+.*?), (.*)\)$/;
	}
	elsif ( $line =~ /Spam Actions: message .* actions are store$/ ) {
		$msg->{$id}->{relay} = ['Quarantine'];
		$msg->{$id}->{delay} = [''];
		$msg->{$id}->{status} = ["$msg->{$id}->{spam_status}"];
		$msg->{$id}->{info} = [''];
		$msg->{$id}->{deleted_time} = "$time";
		&printmailinfo( $msg->{$id} );
		delete $msg->{$id};

	}
}



##
# Ok, Let's start the show!

###
# Process whatever is thrown at us via STDIN:
while ( <STDIN> ) {

	# Check if line is in a known Postfix format:
	if ( $_ =~ m!^(\w\w\w\s{1,2}\d{1,2} \d\d:\d\d:\d\d) (\w+) postfix/(\w+)\[\d+\]: ([0-9A-F]+): (.*)! ) {
		( $time, $server, $cmd, $id, $line ) = ( $1, $2, $3, $4, $5 );
		&parsepostfix( $_ );
	}

	# Check if line is in a known Mailscanner format:
	elsif ( $_ =~ /^(\w\w\w\s{1,2}\d{1,2} \d\d:\d\d:\d\d) (\w+) MailScanner\[\d+\]: (.*)/ ) {
		( $time, $server, $line ) = ( $1, $2 ,$3 );
		$Mailscanner = 1;
		&parsemailscanner( $_ );
	}
}

die('done');
###
# And when we are finished, submit whatever unprocessed data there might be.
print"\nMail still in queue or not processed yet:\n";
for $i ( keys %$msg ) {
	$j = '';
	for ( keys %{$msg->{$i}} ) {
		if ( $_ eq 'to' ) { $msg->{$i}->{$_} = join( ", ", @{ $msg->{$i}->{$_} } ) };
		#$j .= "$msg->{$i}->{$_} ";
		$j .= "$_: $msg->{$i}->{$_}\n";
	}
	if ( $address eq 'all' ||  $j =~ /$address/i ) {
		print "$j\n";
	}
}
print "Done.\n\n";
