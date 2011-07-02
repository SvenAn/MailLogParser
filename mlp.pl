#!/usr/bin/perl -w
###             mlp.pl v0.001                   ###
# MailLogParse by Sven Andreassen sven@tideli.com #
# a small utility to parse e-mail log files       #
# printing all necessary info about an e-mail     #
# in a simple, human readable format.             #
###                                             ###


use strict;
use warnings;
use Getopt::Long;

my ( $verbose, $brief, $logfile, $help, $csv, $debug );
my $path = '';
my $NumberOfFiles = 7;
my $options = GetOptions ( "v|verbose" => \$verbose,
                           "b|brief"   => \$brief,
                           "p|logpath:s" => \$path,
                           "l|logfile:s" => \$logfile,
                           "n|num:i"     => \$NumberOfFiles,
                           "c|csv"     => \$csv,
                           "d|debug"   => \$debug,
                           "h|help"    => \$help );

my $address = $ARGV[0] || 'all';


#Loading Compress::Bzip2 if module is present.
my $bz2_loaded;
eval {
	require Compress::Bzip2;
	Compress::Bzip2->import();
};
unless($@) { $bz2_loaded = 1; print "Debug: Compress::Bzip2 loaded.\n" if $debug; }

#Loading Compress::Zlib if module is present.
my $gz_loaded;
eval {
	require Compress::Zlib;
	Compress::Zlib->import();
};
unless($@) { $gz_loaded = 1; print "Debug: Compress::Zlib loaded.\n" if $debug; }


my ( $i, $j, $msg, $time, $server, $cmd, $id, $line, $mailscanner, $mapper );
my $lines = 0;


###
# Printing the result in chosen format.
sub printmailinfo {

	my $mail = $_[0];

	# Filling the holes of incomplete records...
	if ( ! defined( $mail->{id} )                ) { $mail->{id}           =  '<!>'  }
	if ( ! defined( $mail->{first_seen} )        ) { $mail->{first_seen}   =  '<!>'  }
	if ( ! defined( $mail->{deleted_time} )      ) { $mail->{deleted_time} =  '<!>'  }
	if ( ! defined( $mail->{from} )              ) { $mail->{from}         =  '<!>'  }
	if ( ! defined( $mail->{to} )                ) { $mail->{to}           = ['<!>'] }
	#if ( ! defined( $mail->{size} )              ) { $mail->{size}         =  '<!>'  }
	if ( ! defined( $mail->{delay} )             ) { $mail->{delay}        = ['<!>'] }
	if ( ! defined( $mail->{status} )            ) { $mail->{status}       = ['<!>'] }
	if ( ! defined( $mail->{relay} )             ) { $mail->{relay}        = ['<!>'] }
	if ( ! defined( $mail->{info} )              ) { $mail->{info}         = ['<!>'] }

	if ( defined( $mail->{mailscanner} ) ) {
		if ( ! defined( $mail->{spam_status} )       ) { $mail->{spam_status}         = '<!>' }
		if ( ! defined( $mail->{spam_score} )        ) { $mail->{spam_score}          = '<!>' }
		if ( ! defined( $mail->{spam_score_required})) { $mail->{spam_score_required} = '<!>' }
		if ( ! defined( $mail->{spam_score_detail} ) ) { $mail->{spam_score_detail}   = '<!>' }
	}


	$j = join( ", ", @{ $mail->{to} } );
	return  if ( $address ne 'all' && ( $mail->{from} !~ /$address/i && $j !~ /$address/i && $mail->{id} !~ /$address/ ) );

	if ( $verbose ) {
		if ( defined( $mail->{mailscanner} ) ) {
			if ( $csv ) {
				$mail->{to} = join( ", ", @{ $mail->{to} } );
				if ( $mail->{to} eq '' ) { $mail->{to} = '<>'; }
				$mail->{delay} = join( ", ", @{ $mail->{delay} } );
				$mail->{relay} = join( ", ", @{ $mail->{relay} } );
				$mail->{status} = join( ", ", @{ $mail->{status} } );
				$mail->{info} = join( "\n", @{ $mail->{info} } );
                       		$i = "%s,%s,%s,From:%s,To:%s,Spaminfo:%s,%s,%s,%s,Size:%s,Delay:%s,Status:%s,Relay:%s,Info:%s\n";
                		printf "$i",
                        		$mail->{first_seen},
                        		$mail->{deleted_time},
                        		$mail->{id},
                        		$mail->{from},
                        		$mail->{to}[0],
                        		$mail->{spam_status},
                        		$mail->{spam_score},
                        		$mail->{spam_score_required},
                        		$mail->{spam_score_detail},
                        		$mail->{size};
                        		$mail->{delay},
                        		$mail->{status},
                        		$mail->{relay},
                        		$mail->{info};
                	}
                	else {
                        	$i = "%-12s %-12s From:%s To:%s Size %s\n\tSpam stat:%s, score:%s, required:%s\n\tchecks:%.120s\n";
                		printf "$i",
                        		$mail->{first_seen},
                        		$mail->{id},
                        		$mail->{from},
                        		$mail->{to}[0],
                        		$mail->{size},
                        		$mail->{spam_status},
                        		$mail->{spam_score},
                        		$mail->{spam_score_required},
                        		$mail->{spam_score_detail};

				$j = "\tto:%s Delay:%s Status:%s Relay:%s\n\tInfo:%s\n";
				for $i ( 0..$#{ $mail->{info} } ) {
                			printf "$j",
                        			$mail->{to}[$i],
                        			$mail->{delay}[$i],
                        			$mail->{status}[$i],
                        			$mail->{relay}[$i],
                        			$mail->{info}[$i];
				}
			}
				
		} 
		else {
			if ( $csv ) {
				$i = "%s,%s,%s,From:%s,To:%s,Size:%s,Delay:%s,Status:%s,Relay:%s,Info:%s\n";
			}
			else {
				$i = "%-12s %-12s From:%s To:%s Size:%s\n";
				printf "$i",
       					$mail->{first_seen},
       					$mail->{id},
       					$mail->{from},
       					$mail->{to}[0],
       					$mail->{size};
				$j = "\tto:%s Delay:%s Status:%s Relay:%s\n\tInfo:%s\n";
				for $i ( 0..$#{ $mail->{info} } ) {
                			printf "$j",
                       				$mail->{to}[$i],
                       				$mail->{delay}[$i],
                       				$mail->{status}[$i],
                       				$mail->{relay}[$i],
                       				$mail->{info}[$i];
				}
			}
		}
	}
	elsif ( $brief ) {
		if ( $csv ) {
			$i = "%s,%s,%s,From:%s,To:%s\n";
		}
		else {
			$i = "%-12s %-11s %-10s From:%-25s  To:%-30s\n";
		}
		printf "$i",
	       		$mail->{deleted_time},
	       		$mail->{id},
			$mail->{status}[$#{$mail->{status}}],
	       		$mail->{from},
	       		$mail->{to}[0];
	}
	else {
		if ( $csv ) {
			$i = "%s,%s,%s,From:%s,To:%s,Sent to:%s\n";
		}
		else {
			$i = "%-12s %-10s %-10s From:%-25s To:%-30s Sent to: %s\n";
		}
		printf "$i",
	       		$mail->{deleted_time},
	       		$mail->{id},
			$mail->{status}[$#{$mail->{status}}],
	       		$mail->{from},
	       		$mail->{to}[0],
			$mail->{relay}[$#{$mail->{relay}}],
	}
}


###
# Parsing the postfix log line extracting all necessary info into the mailbox hash.
sub parsepostfix {

	#Check if mail id is a mail requeued from Mailscanner switching id to original mail-id..
	if ( defined( $mapper->{$id} ) ) { 
		$id = $mapper->{$id};
	 }

	# Find message or create new hash
	my $mail = $msg->{$id} ||= { id => $id, time => $1, server => $2, to => [ ] };

	if ( $cmd eq 'qmgr' ) {
		if ( $line =~ /^removed$/ ) {
			$mail->{deleted_time} = $time;
			&printmailinfo( $mail );
			delete $msg->{$id};
		} 
		else {
			#print "\tDebug: Parsing: <$line>\n" if $debug;
			$mail->{from} = $1 if $line =~ /^from=<([^>]+)>/;
			$mail->{size} = $1 if $line =~ /size=(\d+)/;
			$mail->{first_seen} = $time;
		}

	}
	elsif ( $cmd eq 'cleanup' ) {
		$mail->{first_seen} = $time;
		$mail->{msgid} = $1 if $line =~ /^message-id=(<[^>]+>)/;
		$mail->{from} = $1 if $line =~ /from=<([^>]+)>/;
		push @{ $mail->{to} }, $1 if $line =~/to=<([^>]+)>/;
	}
	elsif ( $cmd eq 'virtual' || $cmd eq 'smtp' || $cmd eq 'error' ) {
		if ( $line =~/to=<([^>]+)>/ ) {
			#$j = '';
			# All this is to avoid duplicate recepients..
			#for $i ( 0..$#{$mail->{to}} ) {
			#	$j = 'TRUE' if $mail->{to}[$i] eq $1;
			#}
			push @{ $mail->{to}  }, $1;# if $j ne 'TRUE';
		}
		push @{ $mail->{delay}  }, $1 if $line =~ /delay=(\d+)/;
		push @{ $mail->{delay}  }, $1 if $line =~ /delay=(\d+\.\d+)/;
		push @{ $mail->{status} }, $1 if $line =~ /status=(\w+)/;

		push @{ $mail->{relay} }, $1 if $line =~ /relay=(.*?), /;
		if ( defined( $mail->{status}[$#{$mail->{status}}] ) ) {
			if ( $mail->{status}[$#{$mail->{status}}] =~ /bounced/ ) {
				$mail->{relay}[$#{$mail->{relay}}] = 'thrashcan';
			}
		}

		push @{ $mail->{info}   }, $1 if $line =~ /(\(.*\)$)/;
	}
}


###
# Parsing the mailscanner log line extracting all necessary info into the mailbox hash.
sub parsemailscanner {
	if ( $line =~ /Message ([0-9A-F]+)\.[0-9A-F]+/ ) {
		$id = $1;
		$msg->{$id}->{mailscanner} = 'TRUE';
	}

	if ( $line =~ /\((.*\@.*)\) to .* (is not spam|is spam|is too big|is whitelisted|is blacklisted)/ ) {
		$msg->{$id}->{from} = $1;
		$msg->{$id}->{spam_status} = $2;
		( $msg->{$id}->{spam_score}, $msg->{$id}->{spam_score_required}, $msg->{$id}->{spam_score_detail} ) = ( $1, $2, $3 ) if 
			$line =~ /score=(-?\d+\.\d+), required (\d+.*?), (.*)\)$/;
	}
	elsif ( $line =~ /Spam Actions: message .* actions are store$/ ) {
		$msg->{$id}->{relay} = ['Quarantine'];
		$msg->{$id}->{delay} = ['-'];
		$msg->{$id}->{size} = '-';
		$msg->{$id}->{status} = ["$msg->{$id}->{spam_status}"] if defined( $msg->{$id}->{spam_status} );
		$msg->{$id}->{info} = ['none'];
		$msg->{$id}->{deleted_time} = "$time";
		&printmailinfo( $msg->{$id} );
		delete $msg->{$id};

	}
	elsif ( $line =~ /^Requeue: ([0-9A-F]+)\.[0-9A-F]+ to ([0-9A-F]+)$/ ) {
		$mapper->{$2} = $1;
	}
}


sub ParseLine {
	$lines++;
	# Check if line is in a known Postfix format:
	if ( $_[0] =~ /^(\w\w\w\s{1,2}\d{1,2} \d\d:\d\d:\d\d) (\w+) postfix\/(\w+)\[\d+\]: ([0-9A-F]+): (.*)/ ) {
		( $time, $server, $cmd, $id, $line ) = ( $1, $2, $3, $4, $5 );
		#print "\tDebug: Parsing: <$_>\n" if $debug;
		&parsepostfix( $_ );
	}

	# Check if line is in a known Mailscanner format:
	elsif ( $_[0] =~ /^(\w\w\w\s{1,2}\d{1,2} \d\d:\d\d:\d\d) (\w+) MailScanner\[\d+\]: (.*)/ ) {
		( $time, $server, $line ) = ( $1, $2 ,$3 );
		$mailscanner = 1;
		#print "\tDebug: Parsing: <$_>\n" if $debug;
		&parsemailscanner( $_ );
	}
}


###
# opens non-compressed logfiles and pushes lines containing keyword to printresult:
sub readfile {
        open LOGFILE, $_[0];

        while (<LOGFILE>) {
		&ParseLine( $_ );
        }
        close (LOGFILE);
}


###
# opens bzipped logfiles and pushes lines containing keyword to printresult:
sub readbzfile {
	my $errno;
        my $LOGFILE = bzopen($_[0],"r") or die "File not found.. $errno";

        while ($LOGFILE->bzreadline(my $line) > 0) {
		&ParseLine( $line );
        }
        warn "Error reading from $_[0]: $errno\n" if ($errno ne "OK (0)") ;

        $LOGFILE->bzclose() ;
}


###
# opens gzipped logfiles and pushes lines containing keyword to printresult:
sub readgzfile {
	my ( $errno, $line );
        my $gz = gzopen($_[0], "r") or die "Cannot open $_[0]: $errno\n" ;
   
        while ($gz->gzreadline( $line ) > 0) {
		#print "line: $line\n";		
		&ParseLine( $line );
        }
        $gz->gzclose() ;
}


####################################################################################
# Ok, Let's start the show!


# If you want me to search logfiles:
if ( defined( $logfile ) ) {
	for $i ( 1 .. $NumberOfFiles-1 ) {	
		$i = $NumberOfFiles - $i;  # We want to parse oldest logs first.
		print "Reading $path$logfile.$i" if $debug;

		if ( -e "$path$logfile.$i.gz" ) {  print ".gz\n" if $debug; &readgzfile( "$path$logfile.$i.gz" ); }
		elsif ( -e "$path$logfile.$i.bz" ) { print ".bz2\n" if $debug; &readbzfile( "$path$logfile.$i.bz2" );  }
		elsif ( -e "$path$logfile.$i" ) { print "\n" if $debug; &readfile( "$path$logfile.$i" ); }
		else { print "Warning!  File not found: $path$logfile.$i(or .gz or .bz2)!\n"; }
	}
	print "Reading $path$logfile\n" if $debug;
	if ( -e "$path$logfile" ) { &readfile( "$path$logfile" ); }
	else { print "Warning!  File not found: $path$logfile!\n"; }
}


# Process whatever is thrown at us via STDIN:
else {
	while ( <STDIN> ) {
		&ParseLine( $_ );
	}
}

die("Done. $lines lines parsed.\n") if ! $debug;


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
print "Done. $lines lines parsed.\n\n";
