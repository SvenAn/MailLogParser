#!/usr/bin/perl -w
###             mlp.pl v0.001                   ###
# MailLogParse by Sven Andreassen sven@tideli.com #
# a small utility to parse e-mail log files       #
# printing all necessary info about an e-mail     #
# in a simple, human readable format.             #
###                                             ###


use strict;
use warnings;
use Term::ANSIColor;
#use Compress::Zlib;


# Default colors
my $col_headline = 'YELLOW';
my $col_time     = 'WHITE';
my $col_from     = 'WHITE';
my $col_to       = 'WHITE';
my $col_id       = 'BLUE';
my $col_size     = 'BLUE';
my $col_info     = 'RESET BLUE';
#my $col_status   = 'GREEN';
my $col_bounced  = 'RED';
my $col_sent  = 'GREEN';
my $col_spam  = 'BOLD RED';
my $col_notspam  = 'GREEN';
my $col_quarantine  = 'BOLD RED';



my ( $verbose, $brief, $logfile, $help, $csv, $debug, $Xdebug, $color );
&ReadConfigFile(); # Read default config before processing command line options;

use Getopt::Long;
my $path = '';
my $NumberOfFiles = 7;
my $options = GetOptions ( "v|verbose"   => \$verbose,
                           "b|brief"     => \$brief,
                           "p|logpath:s" => \$path,
                           "l|logfile:s" => \$logfile,
                           "n|num:i"     => \$NumberOfFiles,
                           "c|csv"       => \$csv,
                           "d|debug"     => \$debug,
                           "xd|xdebug"   => \$Xdebug,
                           "a|ansicolor" => \$color,
                           "h|help"      => \$help
);
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
	#Compress::Zlib->import();
};
unless($@) { $gz_loaded = 1; print "Debug: Compress::Zlib loaded.\n" if $debug; }

# All sorts of variables
my ( $i, $j, $msg, $time, $server, $cmd, $id, $line, $Mailscanner, $mapper, $mapperid, $starttime, $endtime );
my ( $lines, $entries ) = 0;
my @config;


###
# Parcing configfiles.
sub ParceConfig {
#	$csv = 1;
}


###
# Reading config in /etc/mlp.conf and ~/.mlprc
sub ReadConfigFile() {
	if ( -e "/etc/mlp.conf" ) {
		open( CONF, "/etc/mlp.conf" ) || print "ERROR: Could not open /etc/mlp.conf!";
		@config = <CONF>;
		close( CONF );
		ParceConfig();
	}
	if ( -e "~.mlprc" ) {

	}
}


###
# Printing info in csv format.
sub PrintMailInfo_csv() {

	$msg->{$id}->{to} = join( ";", @{ $msg->{$id}->{to} } );
	if ( $msg->{$id}->{to} eq '' ) { $msg->{$id}->{to} = '<>'; }
	$msg->{$id}->{delay} = join( ";", @{ $msg->{$id}->{delay} } );
	$msg->{$id}->{relay} = join( ";", @{ $msg->{$id}->{relay} } );
	$msg->{$id}->{status} = join( ";", @{ $msg->{$id}->{status} } );
	$msg->{$id}->{info} = join( ";", @{ $msg->{$id}->{info} } );

	if ( defined( $msg->{$id}->{mailscanner} ) ) {
		if ( $verbose ) {
			$i = "%s,%s,%s,From:%s,To:%s,Spaminfo:%s,%s,%s,%s,Size:%s,Delay:%s,Status:%s,Relay:%s,Info:%s\n";
			printf "$i",
			       $msg->{$id}->{first_seen}, $msg->{$id}->{deleted_time}, $msg->{$id}->{id}, $msg->{$id}->{from}, $msg->{$id}->{to},
			       $msg->{$id}->{spam_status}, $msg->{$id}->{spam_score}, $msg->{$id}->{spam_score_required}, $msg->{$id}->{spam_score_detail},
			       $msg->{$id}->{size}, $msg->{$id}->{delay}, $msg->{$id}->{status}, $msg->{$id}->{relay}, $msg->{$id}->{info};
		}
        	elsif ( $brief ) {
                	$i = "%s,%s,%s,%s,From:%s,To:%s\n";
                	printf "$i",
                	        $msg->{$id}->{deleted_time}, $msg->{$id}->{id}, $msg->{$id}->{status}, $msg->{$id}->{spam_status}, $msg->{$id}->{from}, $msg->{$id}->{to};
	
        	}
	 	else {
                        $i = "%s,%s,%s,%s,From:%s,To:%s,Sent to:%s\n";
                	printf "$i",
                        	$msg->{$id}->{deleted_time}, $msg->{$id}->{id}, $msg->{$id}->{status}, $msg->{$id}->{spam_status}, $msg->{$id}->{from},
                        	$msg->{$id}->{to}, $msg->{$id}->{relay},
		}
	}
	else {
		if ( $verbose ) {
                        $i = "%s,%s,%s,From:%s,To:%s,Size:%s,Delay:%s,Status:%s,Relay:%s,Info:%s\n";
                        printf "$i",
                               $msg->{$id}->{first_seen}, $msg->{$id}->{deleted_time}, $msg->{$id}->{id}, $msg->{$id}->{from}, $msg->{$id}->{to},
                               $msg->{$id}->{size}, $msg->{$id}->{delay}, $msg->{$id}->{status}, $msg->{$id}->{relay}, $msg->{$id}->{info};
                }
                elsif ( $brief ) {
                        $i = "%s,%s,%s,From:%s,To:%s\n";
                        printf "$i",
                                $msg->{$id}->{deleted_time}, $msg->{$id}->{id}, $msg->{$id}->{status}, $msg->{$id}->{from}, $msg->{$id}->{to};

                }
                else {
                        $i = "%s,%s,%s,From:%s,To:%s,Sent to:%s\n";
                        printf "$i",
                                $msg->{$id}->{deleted_time}, $msg->{$id}->{id}, $msg->{$id}->{status}, $msg->{$id}->{from}, $msg->{$id}->{to}, $msg->{$id}->{relay},
                }
	}
}

sub checkstatuscolor {
	return $col_bounced if $_[0] =~ /bounced/;
	return $col_sent    if $_[0] =~ /sent/;
	return $col_spam    if $_[0] =~ /is spam/;
	return $col_notspam if $_[0] =~ /is not spam/;
	return 'MAGENTA';
}

###
# Printing the result in chosen format.
sub PrintMailInfo_visual {

	my $to = join( ", ", @{ $msg->{$id}->{to} } );
	if ( $to eq '' ) { $to = '<>'; }

	my $col_mystatus = checkstatuscolor( $msg->{$id}->{status}[$#{$msg->{$id}->{status}}] ) if $#{$msg->{$id}->{status}} > -1;

	print color "$col_time" if $color; printf "%-12s", $msg->{$id}->{deleted_time};
	unless( $brief ) { print color "$col_id" if $color; printf " %-12s", $msg->{$id}->{id}; }

        if ( $verbose ) {
		print color "$col_from" if $color; printf " From:%s", $msg->{$id}->{from};
		print color "$col_size" if $color; printf " Size:%s\n", $msg->{$id}->{size}; 

		if ( defined( $msg->{$id}->{mailscanner} ) ) {
			if ( $color ) {
				my $col_myspamstatus = checkstatuscolor( $msg->{$id}->{spam_status} );
				print color "$col_myspamstatus";
			}
			printf "\tSpam stat:'%s' score:%s required:%s\n", 
				$msg->{$id}->{spam_status}, $msg->{$id}->{spam_score}, $msg->{$id}->{spam_score_required};

			print color "$col_info" if $color;
			printf "\tchecks:%.120s\n", $msg->{$id}->{spam_score_detail};
		}

        	for $i ( 0..$#{ $msg->{$id}->{info} } ) {
			print color "$col_to"       if $color; printf "\tto:%s", $msg->{$id}->{to}[$i];
			print color "$col_info"     if $color; printf " Delay:%s", $msg->{$id}->{delay}[$i];

			$col_mystatus = checkstatuscolor( $msg->{$id}->{status}[$i] );
			print color "$col_mystatus" if $color; printf " Status:%s", $msg->{$id}->{status}[$i];

			print color "$col_info"     if $color;
			printf " Sent to:%s\n\tInfo:%s\n", $msg->{$id}->{relay}[$i], $msg->{$id}->{info}[$i];
        	}
	}
        else {
		print color "$col_mystatus" if $color; printf " Status:%s", $msg->{$id}->{status}[$#{$msg->{$id}->{status}}];
		print color "$col_from"     if $color; printf " From:%s", $msg->{$id}->{from};
		print color "$col_to"       if $color; printf " To:%s", $to;
        }
        unless ( $brief || $verbose ) {
		print color "$col_info"    if $color;
		printf " Sent to:%s", $msg->{$id}->{relay}[$#{$msg->{$id}->{relay}}];
        }
	print "\n";
}


###
# Printing the result in chosen format.
sub printmailinfo {

	# Filling the holes of incomplete records...
	if ( ! defined( $msg->{$id}->{from} )         ) { $msg->{$id}->{from}         =  '<!>'  }
	if ( ! defined( $msg->{$id}->{to} )           ) { $msg->{$id}->{to}           = ['<!>'] }
	if ( ! defined( $msg->{$id}->{id} )           ) { $msg->{$id}->{id}           =  '<!>'  }

	# Check if mail matches optional $address and return if not..
	$j = join( ", ", @{ $msg->{$id}->{to} } );
	return  if ( $address ne 'all' && ( $msg->{$id}->{from} !~ /$address/i && $j !~ /$address/i && $msg->{$id}->{id} !~ /$address/ ) );

	if ( ! defined( $msg->{$id}->{first_seen} )   ) { $msg->{$id}->{first_seen}   =  '<!>'  }
	if ( ! defined( $msg->{$id}->{deleted_time} ) ) { $msg->{$id}->{deleted_time} =  '<!>'  }
	if ( ! defined( $msg->{$id}->{size} )         ) { $msg->{$id}->{size}         =  '<!>'  }
	if ( ! defined( $msg->{$id}->{delay} )        ) { $msg->{$id}->{delay}        = ['<!>'] }
	if ( ! defined( $msg->{$id}->{status} )       ) { $msg->{$id}->{status}       = ['<!>'] }
	if ( ! defined( $msg->{$id}->{relay} )        ) { $msg->{$id}->{relay}        = ['<!>'] }
	if ( ! defined( $msg->{$id}->{info} )         ) { $msg->{$id}->{info}         = ['<!>'] }

	if ( defined( $msg->{$id}->{mailscanner} ) ) {
		if ( ! defined( $msg->{$id}->{spam_status} )       ) { $msg->{$id}->{spam_status}         = '<!>' }
		if ( ! defined( $msg->{$id}->{spam_score} )        ) { $msg->{$id}->{spam_score}          = '<!>' }
		if ( ! defined( $msg->{$id}->{spam_score_required})) { $msg->{$id}->{spam_score_required} = '<!>' }
		if ( ! defined( $msg->{$id}->{spam_score_detail} ) ) { $msg->{$id}->{spam_score_detail}   = '<!>' }
	}

	PrintMailInfo_csv() if $csv;
	PrintMailInfo_visual() unless $csv;

	delete $msg->{$id};
	delete $mapper->{$mapperid}; # Deleting mapper id as well.
	$entries++;
}


###
# Parsing the postfix log line extracting all necessary info into the mailbox hash.
sub parsepostfix {

	#Check if mail id is a mail requeued from Mailscanner switching id to original mail-id..
	if ( defined( $mapper->{$id} ) ) { 
		$mapperid = $id; # Saving the original id if we want to delete the entry below.
		$id = $mapper->{$id};
	 }

	# Find message or create new hash
	$msg->{$id} = $msg->{$id} ||= { id => $id, time => $1, server => $2, to => [ ] };

	if ( $cmd eq 'qmgr' ) {
		if ( $line =~ /^removed$/ ) {
			$msg->{$id}->{deleted_time} = $time;
			printmailinfo( $msg->{$id} ); 
		} 
		else {
			$msg->{$id}->{from} = $1 if $line =~ /^from=<([^>]+)>/;
			$msg->{$id}->{size} = $1 if $line =~ /size=(\d+)/;
			$msg->{$id}->{first_seen} = $time;
		}

	}
	elsif ( $cmd eq 'cleanup' ) {
		$msg->{$id}->{first_seen} = $time;
		$msg->{$id}->{msgid} = $1 if $line =~ /^message-id=(<[^>]+>)/;
		$msg->{$id}->{from} = $1 if $line =~ /from=<([^>]+)>/;
		#push @{ $msg->{$id}->{to} }, $1 if $line =~/to=<([^>]+)>/;
	}
	elsif ( $cmd =~ /(virtual|smtp|error|local)/) {
		push @{ $msg->{$id}->{to}  }, $1 if $line =~/to=<([^>]+)>/;
		push @{ $msg->{$id}->{delay}  }, $1 if $line =~ /delay=(\d+)/;
		push @{ $msg->{$id}->{delay}  }, $1 if $line =~ /delay=(\d+\.\d+)/;
		push @{ $msg->{$id}->{status} }, $1 if $line =~ /status=(\w+)/;
		push @{ $msg->{$id}->{relay} }, $1 if $line =~ /relay=(.*?), /;

		# Adjust relay info to "thrash" if mail is bounced.
		if ( defined( $msg->{$id}->{status}[$#{$msg->{$id}->{status}}] ) ) {
			if ( $msg->{$id}->{status}[$#{$msg->{$id}->{status}}] =~ /bounced/ ) {
				$msg->{$id}->{relay}[$#{$msg->{$id}->{relay}}] = 'thrashcan';
			}
		}
		push @{ $msg->{$id}->{info}   }, $1 if $line =~ /(\(.*\)$)/;
	}
}


###
# Parsing the mailscanner log line extracting all necessary info into the mailbox hash.
sub parsemailscanner {
	if ( $line =~ /Message ([0-9A-F]+)\.[0-9A-F]+/i ) {
		$id = $1;
		$msg->{$id} = $msg->{$id} ||= { id => $id, time => '<!>', server => '<!>', to => [ ] };
		$msg->{$id}->{mailscanner} = 'TRUE';
	}

	if ( $line =~ /\((.*\@.*)\) to .* (is not spam|is spam|is too big|is whitelisted|is blacklisted)/ ) {
		$msg->{$id}->{from} = $1;
		$msg->{$id}->{spam_status} = $2;
	
		$msg->{$id}->{spam_score} = $1 if $line =~ /score=(-?(\d+\.\d+|\d)),/;
		$msg->{$id}->{spam_score_required} = $1 if $line =~ /required (\d+.*?)/;
		if ( $line =~ /required \d+.*?, (.*)\)$/ ) {
			$msg->{$id}->{spam_score_detail}  = $1;
		}
		else { 
			$msg->{$id}->{spam_score_detail} = 'none';
		}
	}
	elsif ( $line =~ /Spam Actions: message .* actions are store$/ ) {
		$msg->{$id}->{relay} = ['Quarantine'];
		$msg->{$id}->{delay} = ['-'];
		$msg->{$id}->{size} = '-';
		$msg->{$id}->{status} = ["$msg->{$id}->{spam_status}"] if defined( $msg->{$id}->{spam_status} );
		$msg->{$id}->{info} = ['none'];
		$msg->{$id}->{deleted_time} = "$time";
		printmailinfo( $msg->{$id} );
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
		print "\tDebug: Parsing: <$_>\n" if $Xdebug;
		parsepostfix( $_ );
	}

	# Check if line is in a known Mailscanner format:
	elsif ( $_[0] =~ /^(\w\w\w\s{1,2}\d{1,2} \d\d:\d\d:\d\d) (\w+) MailScanner\[\d+\]: (.*)/ ) {
		( $time, $server, $line ) = ( $1, $2 ,$3 );
		$Mailscanner = 1;
		print "\tDebug: Parsing: <$_>\n" if $Xdebug;
		parsemailscanner( $_ );
	}
}


###
# opens non-compressed logfiles and pushes lines containing keyword to printresult:
sub readfile {
        open LOGFILE, $_[0];

        while (<LOGFILE>) {
		ParseLine( $_ );
        }
        close (LOGFILE);
}


###
# opens bzipped logfiles and pushes lines containing keyword to printresult:
sub readbzfile {
	my $errno;
        my $LOGFILE = bzopen($_[0],"r") or die "File not found.. $errno";

        while ($LOGFILE->bzreadline(my $line) > 0) {
		ParseLine( $line );
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
		ParseLine( $line );
        }
        $gz->gzclose() ;
}


####################################################################################
# Ok, Let's start the show!


unless ( $csv ) {
	$starttime = time;

	print color "$col_headline" if $color; 
	print "Reading log files..\n_____________________\n\n";
}


# If you want me to search logfiles:
if ( defined( $logfile ) ) {
	for $i ( 1 .. $NumberOfFiles-1 ) {	
		$i = $NumberOfFiles - $i;  # We want to parse oldest logs first.
		print "Reading $path$logfile.$i" if $debug;

		if ( -e "$path$logfile.$i.gz" ) {  print ".gz\n" if $debug; readgzfile( "$path$logfile.$i.gz" ); }
		elsif ( -e "$path$logfile.$i.bz" ) { print ".bz2\n" if $debug; readbzfile( "$path$logfile.$i.bz2" );  }
		elsif ( -e "$path$logfile.$i" ) { print "\n" if $debug; readfile( "$path$logfile.$i" ); }
		else { print "Warning!  File not found: $path$logfile.$i(or .gz or .bz2)!\n"; }
	}
	print "Reading $path$logfile\n" if $debug;
	if ( -e "$path$logfile" ) { &readfile( "$path$logfile" ); }
	else { print "Warning!  File not found: $path$logfile!\n"; }
}


# Or process whatever is thrown at us via STDIN:
else {
	while ( <STDIN> ) {
		&ParseLine( $_ );
	}
}


unless ( $csv ) {
	$endtime = time - $starttime;
	print color "$col_headline" if $color;
	print "_________________________________________________\n";
	print "Done. $lines lines parsed in $endtime seconds. $entries entries found.\n" if ! $debug;
	print color 'reset' if $color;
}


die("\n") if ! $debug;




###
# And when we are finished but debug is on, submit whatever unprocessed data there might be.
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
