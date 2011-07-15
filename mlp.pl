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
my ( $i, $j, $msg, $time, $server, $cmd, $id, $line, $mailscanner, $mapper );
my $lines = 0;
my $mail;
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

	$mail->{to} = join( ";", @{ $mail->{to} } );
	if ( $mail->{to} eq '' ) { $mail->{to} = '<>'; }
	$mail->{delay} = join( ";", @{ $mail->{delay} } );
	$mail->{relay} = join( ";", @{ $mail->{relay} } );
	$mail->{status} = join( ";", @{ $mail->{status} } );
	$mail->{info} = join( ";", @{ $mail->{info} } );

	if ( defined( $mail->{mailscanner} ) ) {
		if ( $verbose ) {
			$i = "%s,%s,%s,From:%s,To:%s,Spaminfo:%s,%s,%s,%s,Size:%s,Delay:%s,Status:%s,Relay:%s,Info:%s\n";
			printf "$i",
			       $mail->{first_seen}, $mail->{deleted_time}, $mail->{id}, $mail->{from}, $mail->{to},
			       $mail->{spam_status}, $mail->{spam_score}, $mail->{spam_score_required}, $mail->{spam_score_detail},
			       $mail->{size}, $mail->{delay}, $mail->{status}, $mail->{relay}, $mail->{info};
		}
        	elsif ( $brief ) {
                	$i = "%s,%s,%s,%s,From:%s,To:%s\n";
                	printf "$i",
                	        $mail->{deleted_time}, $mail->{id}, $mail->{status}, $mail->{spam_status}, $mail->{from}, $mail->{to};
	
        	}
	 	else {
                        $i = "%s,%s,%s,%s,From:%s,To:%s,Sent to:%s\n";
                	printf "$i",
                        	$mail->{deleted_time}, $mail->{id}, $mail->{status}, $mail->{spam_status}, $mail->{from},
                        	$mail->{to}, $mail->{relay},
		}
	}
	else {
		if ( $verbose ) {
                        $i = "%s,%s,%s,From:%s,To:%s,Size:%s,Delay:%s,Status:%s,Relay:%s,Info:%s\n";
                        printf "$i",
                               $mail->{first_seen}, $mail->{deleted_time}, $mail->{id}, $mail->{from}, $mail->{to},
                               $mail->{size}, $mail->{delay}, $mail->{status}, $mail->{relay}, $mail->{info};
                }
                elsif ( $brief ) {
                        $i = "%s,%s,%s,From:%s,To:%s\n";
                        printf "$i",
                                $mail->{deleted_time}, $mail->{id}, $mail->{status}, $mail->{from}, $mail->{to};

                }
                else {
                        $i = "%s,%s,%s,From:%s,To:%s,Sent to:%s\n";
                        printf "$i",
                                $mail->{deleted_time}, $mail->{id}, $mail->{status}, $mail->{from}, $mail->{to}, $mail->{relay},
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

	my $to = join( ", ", @{ $mail->{to} } );
	if ( $to eq '' ) { $to = '<>'; }

	print "!!!$#{$mail->{status}}!!!\n";
	my $col_mystatus = checkstatuscolor( $mail->{status}[$#{$mail->{status}}] );

	print color "$col_time" if $color; printf "%-12s", $mail->{deleted_time};
	unless( $brief ) { print color "$col_id" if $color; printf " %-12s", $mail->{id}; }

        if ( $verbose ) {
		print color "$col_from" if $color; printf " From:%s", $mail->{from};
		print color "$col_size" if $color; printf " Size:%s\n", $mail->{size}; 

		if ( defined( $mail->{mailscanner} ) ) {
			if ( $color ) {
				my $col_myspamstatus = checkstatuscolor( $mail->{spam_status} );
				print color "$col_myspamstatus";
			}
			printf "\tSpam stat:'%s' score:%s required:%s\n", 
				$mail->{spam_status}, $mail->{spam_score}, $mail->{spam_score_required};

			print color "$col_info" if $color;
			printf "\tchecks:%.120s\n", $mail->{spam_score_detail};
		}

        	for $i ( 0..$#{ $mail->{info} } ) {
			print color "$col_to"       if $color; printf "\tto:%s", $mail->{to}[$i];
			print color "$col_info"     if $color; printf " Delay:%s", $mail->{delay}[$i];

			$col_mystatus = checkstatuscolor( $mail->{status}[$i] );
			print color "$col_mystatus" if $color; printf " Status:%s", $mail->{status}[$i];

			print color "$col_info"     if $color;
			printf " Sent to:%s\n\tInfo:%s\n", $mail->{relay}[$i], $mail->{info}[$i];
        	}
	}
        else {
		print color "$col_mystatus" if $color; printf " Status:%s", $mail->{status}[$#{$mail->{status}}];
		print color "$col_from"     if $color; printf " From:%s", $mail->{from};
		print color "$col_to"       if $color; printf " To:%s", $to;
        }
        unless ( $brief || $verbose ) {
		print color "$col_info"    if $color;
		printf " Sent to:%s", $mail->{relay}[$#{$mail->{relay}}];
        }
	print "\n";
}


###
# Printing the result in chosen format.
sub printmailinfo {

	# Check if mail matches optional $address..
	$j = join( ", ", @{ $mail->{to} } );
	return  if ( $address ne 'all' && ( $mail->{from} !~ /$address/i && $j !~ /$address/i && $mail->{id} !~ /$address/ ) );

	# Filling the holes of incomplete records...
	if ( ! defined( $mail->{id} )           ) { $mail->{id}           =  '<!>'  }
	if ( ! defined( $mail->{first_seen} )   ) { $mail->{first_seen}   =  '<!>'  }
	if ( ! defined( $mail->{deleted_time} ) ) { $mail->{deleted_time} =  '<!>'  }
	if ( ! defined( $mail->{from} )         ) { $mail->{from}         =  '<!>'  }
	if ( ! defined( $mail->{to} )           ) { $mail->{to}           = ['<!>'] }
	if ( ! defined( $mail->{size} )         ) { $mail->{size}         =  '<!>'  }
	if ( ! defined( $mail->{delay} )        ) { $mail->{delay}        = ['<!>'] }
	if ( ! defined( $mail->{status} )       ) { $mail->{status}       = ['<!>'] }
	if ( ! defined( $mail->{relay} )        ) { $mail->{relay}        = ['<!>'] }
	if ( ! defined( $mail->{info} )         ) { $mail->{info}         = ['<!>'] }

	if ( defined( $mail->{mailscanner} ) ) {
		if ( ! defined( $mail->{spam_status} )       ) { $mail->{spam_status}         = '<!>' }
		if ( ! defined( $mail->{spam_score} )        ) { $mail->{spam_score}          = '<!>' }
		if ( ! defined( $mail->{spam_score_required})) { $mail->{spam_score_required} = '<!>' }
		if ( ! defined( $mail->{spam_score_detail} ) ) { $mail->{spam_score_detail}   = '<!>' }
	}

	PrintMailInfo_csv() if $csv;
	PrintMailInfo_visual() unless $csv;
}


###
# Parsing the postfix log line extracting all necessary info into the mailbox hash.
sub parsepostfix {

	#Check if mail id is a mail requeued from Mailscanner switching id to original mail-id..
	if ( defined( $mapper->{$id} ) ) { 
		$j = $id; # Saving the original id if we want to delete the entry below.
		$id = $mapper->{$id};
	 }

	# Find message or create new hash
	$mail = $msg->{$id} ||= { id => $id, time => $1, server => $2, to => [ ] };

	if ( $cmd eq 'qmgr' ) {
		if ( $line =~ /^removed$/ ) {
			$mail->{deleted_time} = $time;
			printmailinfo( $mail );
			delete $msg->{$id};
			delete $mapper->{$j}; # Deleting mapper id as well.
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
	#elsif ( $cmd eq 'virtual' || $cmd eq 'smtp' || $cmd eq 'error' ) {
	elsif ( $cmd =~ /(virtual|smtp|error|local)/) {
		push @{ $mail->{to}  }, $1 if $line =~/to=<([^>]+)>/;
		push @{ $mail->{delay}  }, $1 if $line =~ /delay=(\d+)/;
		push @{ $mail->{delay}  }, $1 if $line =~ /delay=(\d+\.\d+)/;
		push @{ $mail->{status} }, $1 if $line =~ /status=(\w+)/;
		push @{ $mail->{relay} }, $1 if $line =~ /relay=(.*?), /;

		# Adjust relay info to "thrash" if mail is bounced.
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
		delete $msg->{$id};
		delete $mapper->{$id}; # Deleting mapper id as well.
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
		$mailscanner = 1;
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

print color "$col_headline" if $color; 
print "Reading log files..\n_____________________\n\n";

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


# Process whatever is thrown at us via STDIN:
else {
	while ( <STDIN> ) {
		&ParseLine( $_ );
	}
}

print color "$col_headline" if $color;
print "_____________________\nDone. $lines lines parsed.\n" if ! $debug;
print color 'reset' if $color;
die("\n") if ! $debug;

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
