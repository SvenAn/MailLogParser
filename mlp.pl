#!/usr/bin/perl -w
###             mlp.pl                          ###
# MailLogParse by Sven Andreassen sven@tideli.com #
# a small utility to parse e-mail log files       #
# printing all necessary info about an e-mail     #
# in a simple, human readable format.             #
###                                             ###

my $version = 'v.006_1';


use strict;
use warnings;
use File::Spec;
use POSIX qw(setsid);
use IO::Select;
use Term::ANSIColor;
use Term::ReadKey;
local $Term::ANSIColor::AUTORESET = 1;
#use Compress::Zlib;


my $helptext = <<EOF;
###  MailLogParse $version by Sven Andreassen ###
##					     ##

Syntax:
mlp.pl [-vblncdxdah] <mail address>

        "v|verbose"   = Prints extra info about the mail on multiple lines.
        "b|brief"     = Prints only some info about the mail.
        "l|logfile:s" = Specify which logfile to read.
        "n|num:i"     = How many generation of files to read. Mlp.pl will also
			unzip .gz or .bz2 files. 
        "c|csv"       = Prints output in csv format. This option can be used
			along with the -v or -b options.
        "d|debug"     = Prints debug info.
        "xd|xdebug"   = Will provide extensive debug info about all processed
			lines.
        "a|ansicolor" = Gives output in wonderful colors.
        "tlsinfo"     = Prints tlsinfo.
        "h|help"      = Prints this help info and quits.
        "warnings"    = Prints warning messages as they apppear in the log file.
        "deferred"    = Prints failed delivery of an e-mail.

Example:
	Searching for someone@ (all domains) in the seven past generations 
	of /var/log/maillog and print verbose output about the findings:
		
		mlp.pl -v -l /var/log/maillog -n 7 someone@

All parameters can be set in /etc/mlp.conf or in .mlprc. Please see http://url
for further information.

EOF


# Default colors
my $col = {
    headline      => 'YELLOW',
    time          => 'WHITE',
    from          => 'WHITE',
    to            => 'WHITE',
    id            => 'BLUE',
    size          => 'BLUE',
    info          => 'BLUE',
    shortdelay    => 'BLUE',
    longdelay     => 'BOLD YELLOW',
    bounced       => 'RED',
    reject        => 'BOLD RED',
    sent          => 'GREEN',
    spam          => 'BOLD RED',
    notspam       => 'GREEN',
    quarantine    => 'BOLD RED',
    tls           => 'GREEN',
    tlstrust      => 'BOLD GREEN',
};


my ( $verbose, $brief, $file, $help, $csv, $debug, $xdebug, $color, $stdin, $tlsinfo,
    $date_change, $my_printed_date, $maillog_filename, $display_mailserver, $warnings,
    $PrintRestOfMessages, $display_deferred );


&ReadConfigFile(); # We want to read default config before processing command line options;


#We want to make sure Bold is not set unless explicitly specified.
while ( my ($key, $value) = each(%$col) ) {
    unless ( $value =~ /^BOLD/ ) { $col->{$key} = "RESET $value"; };
}


use Getopt::Long;
my $NumberOfFiles;
my $options = GetOptions ( 
        "v|verbose"   => \$verbose,
        "b|brief"     => \$brief,
        "l|logfile:s" => \$file,
        "n|num:i"     => \$NumberOfFiles,
        "c|csv"       => \$csv,
        "d|debug"     => \$debug,
        "xd|xdebug"   => \$xdebug,
        "a|ansicolor" => \$color,
        "tlsinfo"     => \$tlsinfo,
        "h|help"      => \$help,
        "warnings"    => \$warnings,
        "deferred"    => \$display_deferred
        
);
my $address = $ARGV[0] || 'all';

my ($volume,$path,$logfile);
($volume,$path,$logfile) = File::Spec->splitpath( $file ) if defined($file);

die "$helptext" if $help;


# Making sure all values have been handled properly: 
if ( ! defined($NumberOfFiles) ) { $NumberOfFiles = 1; };


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


# All sorts of variables
my ( $i, $j, $msg, $date, $time, $server, $cmd, $id, $line, $Mailscanner, $starttime, $readytoprint,
    $endtime, $postgreylist, $Postgrey, $tls, $to );
my $lines = 0;
my $entries = 0;
my @config;
my $delaywarn = 600; #seconds..
$my_printed_date = "none";


# Makes sure we tidy up when closing down..
sub shutdown_prog {
    print"\n";
    &printfooter();
    print color 'reset' if $color;
    exit(0);
}
$SIG{'INT'} = 'shutdown_prog';
$SIG{'TERM'} = 'shutdown_prog';
$SIG{'QUIT'} = 'shutdown_prog';



###
# Parsing configfiles.
sub parseconfig {
    foreach $line ( @config ) {
        chomp( $line );
        unless ( $line =~ /(^#|^$)/ ) {
            #print "Reading config line: $line.\n";
            SWITCH: {
                # Colors:
                $line =~ /^headline.*=.*'(.*)'/i   && do { $col->{headline}   = $1; last SWITCH; }; 
                $line =~ /^time.*=.*'(.*)'/i       && do { $col->{time}       = $1; last SWITCH; }; 
                $line =~ /^from.*=.*'(.*)'/i       && do { $col->{from}       = $1; last SWITCH; }; 
                $line =~ /^to.*=.*'(.*)'/i         && do { $col->{to}         = $1; last SWITCH; }; 
                $line =~ /^id.*=.*'(.*)'/i         && do { $col->{id}         = $1; last SWITCH; }; 
                $line =~ /^size.*=.*'(.*)'/i       && do { $col->{size}       = $1; last SWITCH; }; 
                $line =~ /^info.*=.*'(.*)'/i       && do { $col->{info}       = $1; last SWITCH; }; 
                $line =~ /^shortdelay.*=.*'(.*)'/i && do { $col->{shortdelay} = $1; last SWITCH; }; 
                $line =~ /^longdelay.*=.*'(.*)'/i  && do { $col->{longdelay}  = $1; last SWITCH; }; 
                $line =~ /^bounced.*=.*'(.*)'/i    && do { $col->{bounced}    = $1; last SWITCH; }; 
                $line =~ /^reject.*=.*'(.*)'/i     && do { $col->{reject}     = $1; last SWITCH; }; 
                $line =~ /^sent.*=.*'(.*)'/i       && do { $col->{sent}       = $1; last SWITCH; }; 
                $line =~ /^spam.*=.*'(.*)'/i       && do { $col->{spam}       = $1; last SWITCH; }; 
                $line =~ /^quarantine.*=.*'(.*)'/i && do { $col->{quarantine} = $1; last SWITCH; }; 
                $line =~ /^tls.*=.*'(.*)'/i        && do { $col->{tls}        = $1; last SWITCH; }; 
                $line =~ /^tlstrust.*=.*'(.*)'/i   && do { $col->{tlstrust}   = $1; last SWITCH; }; 

                # Default variables:
                $line =~ /^display_mode.*=.*brief/i                 && do { $brief = 1;                     last SWITCH; }; 
                $line =~ /^display_mode.*=.*verbose/i               && do { $verbose = 1; undef( $brief );  last SWITCH; }; 
                $line =~ /^logfile_name.*=\s*(\S+)/i                && do { $logfile = $1;                  last SWITCH; }; 
                $line =~ /^NumFilesToParse.*=\s*(\d+)/i             && do { $NumberOfFiles = $1;            last SWITCH; }; 
                $line =~ /^debug.*=\s*(true|on)/i                   && do { $debug = $1;                    last SWITCH; }; 
                $line =~ /^Xdebug.*=\s*(true|on)/i                  && do { $xdebug = $1;                   last SWITCH; }; 
                $line =~ /^color.*=\s*(true|on)/i                   && do { $color = $1;                    last SWITCH; }; 
                $line =~ /^Display_date_change.*=\s*(true|on)/i     && do { $date_change = $1;              last SWITCH; }; 
                $line =~ /^Display_maillog_filename.*=\s*(true|on)/i   && do {  $maillog_filename = $1;     last SWITCH; }; 
                $line =~ /^Display_mailserver.*=\s*(true|on)/i      && do { $display_mailserver = $1;       last SWITCH; }; 
                $line =~ /^Display_warnings.*=\s*(true|on)/i        && do { $warnings = $1;                 last SWITCH; }; 
                $line =~ /^PrintRestOfMessages\s*=\s*(true|on)/i    && do { $PrintRestOfMessages = $1;      last SWITCH; };
                $line =~ /^Display_deferred_mail.*=\s*(true|on)/i   && do { $display_deferred = $1;         last SWITCH; }; 
                $line =~ /^default_logpath\s*=\s*(\S+)/i            && do { 
                    $path = $1;
                    if ( $path !~ /\/$/ ) { $path .= "/"; }
                    last SWITCH;
                }; 
            } 
        }
    }
}


###
# Reading config in /etc/mlp.conf, /etc/mlp/mlp.conf, /usr/local/etc or ~/.mlprc
sub ReadConfigFile() {
    my $file;

    if ( -e "$ENV{HOME}/.mlprc" )          { $file = "$ENV{HOME}/.mlprc";       }
    elsif ( -e "/etc/mlp.conf" )           { $file = "/etc/mlp.conf";           }
    elsif ( -e "/etc/mlp/mlp.conf" )       { $file = "/etc/mlp/mlp.conf";       }
    elsif ( -e "/usr/local/etc/mlp.conf" ) { $file = "/usr/local/etc/mlp.conf"; }

    if ( defined( $file ) ) {
        open( CONF, $file ) || print "ERROR: Could not open $file!";
        @config = <CONF>;
        close( CONF );
        parseconfig();
    }
}


###
# Printing info in csv format.
sub PrintMailInfo_csv() {

    my $msgidto = join( ";", @{ $msg->{$id}->{to} } );
    if ( $msgidto eq '' ) { $msgidto = '<>'; }

    $msg->{$id}->{delay}  = join( ";", @{ $msg->{$id}->{delay}  } );
    $msg->{$id}->{relay}  = join( ";", @{ $msg->{$id}->{relay}  } );
    $msg->{$id}->{status} = join( ";", @{ $msg->{$id}->{status} } );
    $msg->{$id}->{info}   = join( ";", @{ $msg->{$id}->{info}   } );

    if ( defined( $msg->{$id}->{mailscanner} ) ) {
        if ( $verbose ) {
            $i = "%s,%s,%s,From:%s,To:%s,Spaminfo:%s,%s,%s,%s,Size:%s,Delay:%s,Status:%s,Relay:%s,Info:%s\n";
            printf "$i",
                   $msg->{$id}->{first_seen}, $msg->{$id}->{deleted_time}, $msg->{$id}->{id}, $msg->{$id}->{from}, $msgidto,
                   $msg->{$id}->{spam_status}, $msg->{$id}->{spam_score}, $msg->{$id}->{spam_score_required},
                   $msg->{$id}->{spam_score_detail}, $msg->{$id}->{size}, $msg->{$id}->{delay}, $msg->{$id}->{status},
                   $msg->{$id}->{relay}, $msg->{$id}->{info};
        }
        elsif ( $brief ) {
            $i = "%s,%s,%s,%s,From:%s,To:%s\n";
            printf "$i",
                   $msg->{$id}->{deleted_time}, $msg->{$id}->{id}, $msg->{$id}->{status}, $msg->{$id}->{spam_status},
                        $msg->{$id}->{from}, $msgidto;
        }
        else {
            $i = "%s,%s,%s,%s,From:%s,To:%s,Sent to:%s\n";
            printf "$i",
                   $msg->{$id}->{deleted_time}, $msg->{$id}->{id}, $msg->{$id}->{status}, $msg->{$id}->{spam_status},
                        $msg->{$id}->{from}, $msgidto, $msg->{$id}->{relay},
        }
    }
    else {
        if ( $verbose ) {
            $i = "%s,%s,%s,From:%s,To:%s,Size:%s,Delay:%s,Status:%s,Relay:%s,Info:%s\n";
            printf "$i",
                   $msg->{$id}->{first_seen}, $msg->{$id}->{deleted_time}, $msg->{$id}->{id}, $msg->{$id}->{from}, $msgidto,
                   $msg->{$id}->{size}, $msg->{$id}->{delay}, $msg->{$id}->{status}, $msg->{$id}->{relay}, $msg->{$id}->{info};
        }
        elsif ( $brief ) {
            $i = "%s,%s,%s,From:%s,To:%s\n";
            printf "$i",
                   $msg->{$id}->{deleted_time}, $msg->{$id}->{id}, $msg->{$id}->{status}, $msg->{$id}->{from}, $msgidto;

        }
        else {
            $i = "%s,%s,%s,From:%s,To:%s,Sent to:%s\n";
            printf "$i",
                   $msg->{$id}->{deleted_time}, $msg->{$id}->{id}, $msg->{$id}->{status}, $msg->{$id}->{from}, $msgidto,
                        $msg->{$id}->{relay},
        }
    }
}


sub checkstatuscolor {
    if ( defined( $_[0] ) ) {
        return $col->{bounced} if $_[0] =~ /bounced/;
        return $col->{sent}    if $_[0] =~ /sent/;
        return $col->{spam}    if $_[0] =~ /is spam/;
        return $col->{notspam} if $_[0] =~ /is not spam/;
        return $col->{reject}  if $_[0] =~ /reject/;
    }
    return 'MAGENTA';
}


sub checkpostgreytriple { 
    if ( defined ( $msg->{$id}->{from} ) && defined( $msg->{$id}->{to}[0] ) ) {
       $i = "$msg->{$id}->{from}-$msg->{$id}->{to}[0]";
    }
    if ( defined( $postgreylist->{$i}->{delay} ) ) {
        return $i;
    }
    else {
        return "not ok";
    }
}


sub disableregexp() {
    my $result = $_[0];
    $result =~ s/(\?|\+|\{|\}|\*|\(|\))/\\$1/g;
    $result =~ s/(\s)/_/g;
    return $result;
}


sub uniquerecipient {
    my $addr = &disableregexp( $_[0] );
    if ( defined ( $msg->{$id}->{to} ) ) {
        for $i ( 0 .. $#{ $msg->{$id}->{to} } ) {
            if ( &disableregexp( ${ $msg->{$id}->{to} }[$i] ) =~ /$addr/i ) { return "nope" }
        }
    }
    return "yes";
}


sub formattime {
    my ( $dayexpr, $hourexpr, $minexpr, $secexpr );
    $i = $_[0];

    if ( $i !~ /^[\d|\.]+$/ ) { return $i };

    my $days = int( $i / 86400 );
    $i = $i - ( $days * 86400 );

    my $hours = int( $i / 3600 );
    $i = $i - ( $hours * 3600 );

    my $mins = int( $i / 60 );

    my $secs = $i - ( $mins * 60 );

    if ( $days == 1 ) { $dayexpr = "day" }
    else { $dayexpr = "days" }

    if ( $hours == 1 ) { $hourexpr = "hour" }
    else { $hourexpr = "hours" }

    if ( $mins == 1 ) { $minexpr = "minute" }
    else { $minexpr = "minutes" }

    if ( $secs == 1 ) { $secexpr = "second" }
    else { $secexpr = "seconds" }

    if ( $days > 0 )     { return "$days $dayexpr, $hours $hourexpr, $mins $minexpr, $secs $secexpr" }
    elsif ( $hours > 0 ) { return "$hours $hourexpr, $mins $minexpr, $secs $secexpr" }
    elsif ( $mins  > 0 ) { return "$mins $minexpr, $secs $secexpr" }
    else { return "$secs $secexpr" }
}


sub formatnr {
    my $num = $_[0];

    if ( $num > 1000000 ) { $num = sprintf( "%.1f mill", $num / 1000000 ); }
    elsif ( $num > 1000 ) { $num = sprintf( "%.1fk", $num / 1000 ); }

    return "$num";
}


sub check_date_change {
    if ( $my_printed_date ne $date ) {
        print color "$col->{headline}" if $color;
        print "Parcing date: $date\n";
        $my_printed_date = $date;
    }
}


sub addcolor{
    $col->{mystatus} = checkstatuscolor( $msg->{$id}->{status}[$#{$msg->{$id}->{status}}] ) if $#{$msg->{$id}->{status}} > -1;

    #Time
    $msg->{$id}->{deleted_time} = colored( $msg->{$id}->{deleted_time}, $col->{time} );
    #From
    $msg->{$id}->{from}         = colored( $msg->{$id}->{from}, $col->{from} );
    #Server
    $msg->{$id}->{server}       = colored( $msg->{$id}->{server}, $col->{time} );
    #ID
    $msg->{$id}->{id}           = colored( $msg->{$id}->{id}, $col->{id} );

    # Adding color to all recipients:
    for $i ( 0..$#{ $msg->{$id}->{info} } ) {
        #mystatus
        $col->{mystatus} = checkstatuscolor( $msg->{$id}->{status}[$i] );
        $msg->{$id}->{status}[$i] = colored( $msg->{$id}->{status}[$i], $col->{mystatus} );
        # To
        $msg->{$id}->{to}[$i]     = colored( $msg->{$id}->{to}[$i], $col->{to} );
        # Delay
        if ( $msg->{$id}->{delay}[$i] =~ /(\d+|\d+\.\d+)/) { $j = $1 }
        else { $j = 0 };
        if ( $delaywarn < $j ) {
             $msg->{$id}->{delay}[$i] = colored($msg->{$id}->{delay}[$i], $col->{longdelay});
        }
        else {
             $msg->{$id}->{delay}[$i] = colored($msg->{$id}->{delay}[$i], $col->{shortdelay});
        }
        # Info
        $msg->{$id}->{info}[$i] = colored( $msg->{$id}->{info}[$i], $col->{info} ) if defined( $msg->{$id}->{info}[$i] );
    }
}


###
# Formatting the info, obviesly!
sub format_info {

    # Lets set the sender/recipient size based on terminal width:
    my ( $size, $neg_size );
    my @term = GetTerminalSize;
    my $terminalwidth = $term[0];
    if ( $brief ) {
        $size = ( $terminalwidth - 31 ) / 2 - 3;
    }
    else {
        $size = ( $terminalwidth / 2 - 40 );
    }
    $neg_size -= ($size);
    
    # Formatting length of the variables for easy printing:
    # Time
    $msg->{$id}->{deleted_time} = sprintf( "%-12s", $msg->{$id}->{deleted_time} );
    # From
    if ( length( $msg->{$id}->{from} ) < $size ) { 
        $msg->{$id}->{from} = sprintf( "From: %*s", $neg_size, $msg->{$id}->{from} );
    }
    else {
        $msg->{$id}->{from} = sprintf( "From: %.*s..", $size-2, $msg->{$id}->{from} );
    }
    # Mailserver
    #$msg->{$id}->{server}       = sprintf( "%s", $msg->{$id}->{server} );
    # ID
    $msg->{$id}->{id}           = sprintf( "%-12s", $msg->{$id}->{id} );

    # Format info on each recipient.
    for $i ( 0..$#{ $msg->{$id}->{info} } ) {

        #status
        $msg->{$id}->{status}[$i] = sprintf( "%-8s", $msg->{$id}->{status}[$i] );
        #To
        if ( length( $msg->{$id}->{to}[$i] ) < $size ) { 
            $msg->{$id}->{to}[$i] = sprintf( "To: %*s", $neg_size, $msg->{$id}->{to}[$i] );
        }
        else {
            $msg->{$id}->{to}[$i] = sprintf( "To: %.*s..", $size-2, $msg->{$id}->{to}[$i] );
        }
        #Delay
        #if ( $msg->{$id}->{delay}[$i] =~ /^\d+$/ ) {
        $msg->{$id}->{delay}[$i] = sprintf( "Delay: %s", formattime( $msg->{$id}->{delay}[$i] ) );
        #}
        if ( $msg->{$id}->{status}[$i] eq 'deferred' ) {
                $msg->{$id}->{info}[$i] = $msg->{$id}->{extinfo}[$i];
        }
        if ( defined( $msg->{$id}->{info}[$i] ) ) {
            if ( $msg->{$id}->{info}[$i] =~ /(.*;) http:\/\// ) { $msg->{$id}->{info}[$i] = $1 };
            if ( length( $msg->{$id}->{info}[$i] ) > $size ) { 
                $msg->{$id}->{info}[$i] = sprintf( "Info:%.*s..", ($terminalwidth - $size -12) , $msg->{$id}->{info}[$i] );
            }
            else {
                $msg->{$id}->{info}[$i] = sprintf( "Info:%.*s", $terminalwidth - 82, $msg->{$id}->{info}[$i] );
            }
        }
    }
}


sub Printmailinfo_visual {
    format_info();
    addcolor() if $color;

    if ( $brief ) {
        for $i ( 0..$#{ $msg->{$id}->{info} } ) {
            print "$msg->{$id}->{deleted_time} $msg->{$id}->{status}[$i] $msg->{$id}->{from} $msg->{$id}->{to}[$i]\n";
        }
    }
    elsif ($verbose)  {

    }
    else {
        print "$msg->{$id}->{deleted_time} $msg->{$id}->{from} $msg->{$id}->{server} $msg->{$id}->{id}\n";
        for $i ( 0..$#{ $msg->{$id}->{info} } ) {
            print "\t$msg->{$id}->{status}[$i]  $msg->{$id}->{to}[$i] $msg->{$id}->{info}[$i]\n";
        }
    }
}



sub Printmailinfo_visual_verbose {
    $col->{mystatus} = checkstatuscolor( $msg->{$id}->{status}[$#{$msg->{$id}->{status}}] ) if $#{$msg->{$id}->{status}} > -1;

    # Time
    print color "$col->{time}" if $color;
    printf "%-12s", $msg->{$id}->{deleted_time};

    # Mailserver
    if ( $display_mailserver ) {
        print color "$col->{time}" if $color;
        printf "  %s ", $msg->{$id}->{server};
    }

    # Id
    print color "$col->{id}" if $color;
    if ( "$id" eq "$msg->{$id}->{id}" ) { 
        printf " %-12s", $msg->{$id}->{id};
    }
    else {
        printf " %s %s", $msg->{$id}->{id}, $id;
    }

    # Client
    print color "$col->{id}" if $color;
    printf " client=%-12s", $msg->{$id}->{client};

    # Size
    print color "$col->{size}" if $color;
    printf " Size:%s", $msg->{$id}->{size}; 

    # Postgrey info
    unless ( checkpostgreytriple() eq "not ok" ) { 
        $j = formattime( $postgreylist->{$i}->{delay} );
        print " Postgrey delay: $j.";
    }

    print "\n";

    # Mailscanner
    if ( defined( $msg->{$id}->{mailscanner} ) && defined( $msg->{$id}->{scanned} ) ) {
        if ( $color ) {
            my $col->{myspamstatus} = checkstatuscolor( $msg->{$id}->{spam_status} );
            print color "$col->{myspamstatus}";
        }
        printf "\tSpam stat:'%s' score:%s required:%s\n", 
               $msg->{$id}->{spam_status}, $msg->{$id}->{spam_score}, $msg->{$id}->{spam_score_required};

        print color "$col->{info}" if $color;
        printf "\tchecks:%.120s\n", $msg->{$id}->{spam_score_detail};
    }
    elsif ( defined( $msg->{$id}->{mailscanner} ) && ! defined( $msg->{$id}->{scanned} ) ) {
        print color "$col->{info}" if $color;
        print "\tInfo: Mail is passed to mailscanner, but not checked.\n";
    }

    # From
    print color "$col->{from}" if $color; 
    printf "\tFrom: %s\n", $msg->{$id}->{from};

    printf "\tSubject: %s\n", $msg->{$id}->{subject} if defined( $msg->{$id}->{subject} );

    #Hack to remove extra recipient info only needed if mail is rejected og sent to quarantine:
    #shift( @{ $msg->{$id}->{to} } ) if $#{ $msg->{$id}->{to} } > $#{ $msg->{$id}->{status} };

    for $i ( 0..$#{ $msg->{$id}->{to} } ) {

        print color "$col->{to}"   if $color; 
        printf "\t  To: %s", $msg->{$id}->{to}[$i]; 

        if ( $msg->{$id}->{delay}[$i] =~ /^\d+$/ ) {
            if ( $delaywarn < $msg->{$id}->{delay}[$i] && $color ) { print color "$col->{longdelay}" }
            elsif ( $color ) { print color "$col->{shortdelay}" }; 
            printf " Delay:%s", formattime( $msg->{$id}->{delay}[$i] );
        }

        $col->{mystatus} = checkstatuscolor( $msg->{$id}->{status}[$i] );
        print color "$col->{mystatus}" if $color;
        printf " Status:%s", $msg->{$id}->{status}[$i];

        # Sent to
        print color "$col->{info}" if $color;
        printf " Sent to:%s", $msg->{$id}->{relay}[$i] if $msg->{$id}->{status}[$i] !~ /reject/;

        #Info
        if ( defined( $msg->{$id}->{dovecotinfo}[$i] ) ) {
            printf "\n\t  Info: %s\n", $msg->{$id}->{dovecotinfo}[$i];
        }
        else {
            if ( $msg->{$id}->{info}[$i] =~ /(.*;) http:\/\// ) { $msg->{$id}->{info}[$i] = $1 };
            printf "\n\t  Info:%s\n", $msg->{$id}->{info}[$i];
        }
        if ( defined( $msg->{$id}->{extinfo}[$i] ) ) {
            printf "\t  Info:%s\n", $msg->{$id}->{extinfo}[$i];
        }
        #printf "\n\t  Info:%s\n", $msg->{$id}->{dovecotinfo}[$i];# if defined( $msg->{$id}->{dovecotinfo}[$i]);
   
        if ( $tlsinfo ) {
            print "\tEncryption: ";
            if ( defined( $tls->{$msg->{$id}->{relay}[$i]}->{relay} ) ) {
                if ( $color ) {
                    if ( $tls->{$msg->{$id}->{relay}[$i]}->{type} =~ /Untrust/ ) { print color "$col->{tls}" }
                    else { print color "$col->{tlstrust}" }
                }
                printf "%s\n", $tls->{$msg->{$id}->{relay}[$i]}->{type};
            }
            else {
                print "none\n";
            }
        }
    }
    print "\n";
}

###
# Printing the result in chosen format.
sub printmailinfo {
    # Filling the holes of incomplete records...
    unless ( defined( $msg->{$id}->{from} ) ) { $msg->{$id}->{from} =  '<!>'  }
    unless ( defined( $msg->{$id}->{to} )   ) { $msg->{$id}->{to}   = ['<!>'] }
    unless ( defined( $msg->{$id}->{id} )   ) { $msg->{$id}->{id}   =  '<!>'  }

    # Check if mail matches optional $address and return if not..
    $j = join( ", ", @{ $msg->{$id}->{to} } );
    if ( $address eq 'all' || $msg->{$id}->{from} =~ /$address/i || $j =~ /$address/i || $msg->{$id}->{id} =~ /$address/ ) { 

        unless ( defined( $msg->{$id}->{client}       ) ) { $msg->{$id}->{client}       =  '<!>'  }
        unless ( defined( $msg->{$id}->{server}       ) ) { $msg->{$id}->{server}       =  '<!>'  }
        unless ( defined( $msg->{$id}->{first_seen}   ) ) { $msg->{$id}->{first_seen}   =  '<!>'  }
        unless ( defined( $msg->{$id}->{deleted_time} ) ) { $msg->{$id}->{deleted_time} =  '<!>'  }
        unless ( defined( $msg->{$id}->{size}   )       ) { $msg->{$id}->{size}         =  '<!>'  }
        unless ( defined( $msg->{$id}->{delay}  )       ) { $msg->{$id}->{delay}        = ['<!>'] }
        unless ( defined( $msg->{$id}->{status} )       ) { $msg->{$id}->{status}       = ['<!>'] }
        unless ( defined( $msg->{$id}->{relay}  )       ) { $msg->{$id}->{relay}        = ['<!>'] }
        unless ( defined( $msg->{$id}->{info}   )       ) { $msg->{$id}->{info}         = ['<!>'] }
        unless ( defined( $msg->{$id}->{client} )       ) { $msg->{$id}->{client}       =  '<!>'  }
        #unless ( defined( $msg->{$id}->{dovecotinfo} )  ) { $msg->{$id}->{dovecotinfo}  = ['<!>'] }

        if ( defined( $msg->{$id}->{mailscanner} ) ) {
            unless ( defined( $msg->{$id}->{spam_status} )       ) { $msg->{$id}->{spam_status}         = '<!>' }
            unless ( defined( $msg->{$id}->{spam_score} )        ) { $msg->{$id}->{spam_score}          = '<!>' }
            unless ( defined( $msg->{$id}->{spam_score_required})) { $msg->{$id}->{spam_score_required} = '<!>' }
            unless ( defined( $msg->{$id}->{spam_score_detail} ) ) { $msg->{$id}->{spam_score_detail}   = '<!>' }
        }

        if ( $csv ) {
            PrintMailInfo_csv();
        }
        elsif ( $brief ) {
            Printmailinfo_visual('brief');
        }
        elsif ( $verbose ) {
            Printmailinfo_visual_verbose();
        }
        else {
            Printmailinfo_visual('standard');
        }
        $entries++;
    }

    #After processing the mail we delete all traces of it...
    unless ( checkpostgreytriple() eq "not ok" ) { 
        if ( defined( $postgreylist->{$_[0]} ) ) { delete $postgreylist->{$_[0]} };
    }
    print "\tDeleting $id\n" if $debug;
    delete $msg->{ $msg->{$id}->{id1} } if defined $msg->{$id}->{id1};
    delete $msg->{$id};
}


###
# Parsing the postfix log line extracting all necessary info into the mailbox hash.
sub parsepostfix {
    # We want $time to contain both $date and $time:
    $time = "$date $time";

    # Find message or create new hash
    $msg->{$id} = $msg->{$id} ||= { id => $id, time => $date, server => $server, to => [ ] };

    if ( $cmd eq 'qmgr' ) {
        if ( $line =~ /^removed$/ ) {
            $msg->{$id}->{deleted_time} = $time;
	        print "\tDebug: Got remove info, printing mail.\n" if $xdebug;
            $readytoprint->{$id} = 1; 
        } 
        else {
            print "\tDebug: parsing $line\n" if $xdebug;
            $msg->{$id}->{from} = $1 if $line =~ /from=<([^>]+)>/;
            $msg->{$id}->{from} = $1 if $line =~ /from=(\<\>)/;
            $msg->{$id}->{size} = $1 if $line =~ /size=(\d+)/;
            $msg->{$id}->{first_seen} = $time;
	        print "\tDebug: Got from/size/first_seen info.\n" if $xdebug;
	        print "\tDebug: $msg->{$id}->{from}, $msg->{$id}->{size}, $msg->{$id}->{first_seen}\n" if $xdebug;
        }
    }
    elsif ( $cmd eq 'cleanup' ) {
        $msg->{$id}->{first_seen} = $time;
        #$msg->{$id}->{msgid} = $1 if $line =~ /^message-id=(<[^>]+>)/ ;
        $msg->{$id}->{msgid} = $1 if $line =~ /^message-id=<(.*)>/ ;
        $msg->{$id}->{from} = $1 if $line =~ /from=<([^>]+)>/;
        $msg->{$id}->{from} = $1 if $line =~ /from=(\<\>)/;
        push @{ $msg->{$id}->{to} }, $1 if $line =~/to=<([^>]+)>/;
	    print "\tDebug: Got first_seen,msgid,from,to info.\n" if $xdebug;
    }
    elsif ( $cmd eq 'smtpd'  && $line =~ /^(reject):/ ) {
        push @{ $msg->{$id}->{status} }, $1;
        push @{ $msg->{$id}->{to}     }, $1 if $line =~/to=<([^>]+)>/;
        push @{ $msg->{$id}->{info}   }, $1 if $line =~ /RCPT from .*\]: (\d{3} \d\.\d\.\d .*);/;
        push @{ $msg->{$id}->{delay} }, 0;
        push @{ $msg->{$id}->{relay} }, 'Never received message.';
        $msg->{$id}->{deleted_time} = $time;
        $msg->{$id}->{from} = $1 if $line =~ /from=<([^>]+)>/;
        $msg->{$id}->{client} = $1 if $line =~ /RCPT from (.*]): /;
        $msg->{$id}->{size} = 'unknown';
	    print "\tDebug: Got reject info, printing mail.\n" if $xdebug;
        printmailinfo( $msg->{$id} ); 
        #$readytoprint->{$id} = 1; 
    }
    elsif ( $cmd =~ /(virtual|smtp|error|local)/) {
        if ( $line =~ /orig_to=<([^>]+)>/ ) {
            push @{ $msg->{$id}->{to} }, $1 if uniquerecipient( $1 ) eq "yes";
        }
        elsif ( $line =~ /to=<([^>]+)>/ && uniquerecipient( $1 ) eq "yes" ) {
            push @{ $msg->{$id}->{to} }, $1;
        }

        push @{ $msg->{$id}->{delay}  }, $1 if $line =~ /delay=(\d+)/;
        push @{ $msg->{$id}->{delay}  }, $1 if $line =~ /delay=(\d+\.\d+)/;
        push @{ $msg->{$id}->{status} }, $1 if $line =~ /status=(\w+)/;

        if ( $line =~ /relay=(.*?), /i && $line !~ /status=deferred/ ) {
            push @{ $msg->{$id}->{relay}  }, $1 if $line =~ /relay=(.*?), /;
        }

        $msg->{$id}->{client} = $1 if $line =~ /client=.*\[(\d{1,3}.\d{1,3}\.\d{1,3}\.\d{1,3})\]/;

        # Adjust relay info to "thrash" if mail is bounced.
        if ( defined( $msg->{$id}->{status}[$#{$msg->{$id}->{status}}] ) ) {
            if ( $msg->{$id}->{status}[$#{$msg->{$id}->{status}}] =~ /bounced/ ) {
                $msg->{$id}->{relay}[$#{$msg->{$id}->{relay}}] = 'thrashcan';
            }
        }
        push @{ $msg->{$id}->{info} }, $1 if $line =~ /status=.*(\(.*\)$)/;

        push @{ $msg->{$id}->{extinfo} }, $1 if $line =~ /host .* said: (.*)/;

        if ( $line =~ /status=deferred/ ) {
            $msg->{$id}->{first_seen} = $time;
            $msg->{$id}->{deleted_time} = $time;
            printmailinfo( $msg->{$id} ); 
        }

	    print "\tDebug: Got client/delay/relay/status info.\n" if $xdebug;
    }
}


sub parsetls {
    if ( $line =~ /(Trusted TLS|Untrusted TLS) connection established to (.*\[\d{1,3}.\d{1,3}\.\d{1,3}\.\d{1,3}\]:\d+): (.*)/ ) {
        $tls->{$2}->{type} = $1;
        $tls->{$2}->{relay} = $2;
        $tls->{$2}->{details} = $3;
	print "\tDebug: Got tls info.\n" if $xdebug;
    }
}


###
# Parsing the mailscanner log line extracting all necessary info into the mailbox hash.
sub parsemailscanner {
    if ( $line =~ /Message ([0-9A-F]+)\.[0-9A-F]+/i ) {
        $id = $1;
        $msg->{$id} = $msg->{$id} ||= { id => $id, time => '<!>', server => '<!>', to => [ ] };
        $msg->{$id}->{mailscanner} = 'TRUE';
	    print "\tDebug: Got Mailscanner = TRUE\n" if $xdebug;
    }

    #if ( $line =~ /\((.*\@.*)\) to .* (is not spam|is spam|is too big|is whitelisted|is blacklisted)/ ) {
    if ( $line =~ /\((.*)\) to .* (is not spam|is spam|is too big|is whitelisted|is blacklisted)/ ) {
        $msg->{$id}->{scanned} = 'TRUE';
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
	    print "\tDebug: Got spam status+score.\n" if $xdebug;
    }
    elsif ( $line =~ /Spam Actions: message .* actions are store$/ ) {
        $msg->{$id}->{relay} = ['Quarantine'];
        $msg->{$id}->{delay} = ['-'];
        $msg->{$id}->{size} = 'unknown';
        $msg->{$id}->{status} = ["$msg->{$id}->{spam_status}"] if defined( $msg->{$id}->{spam_status} );
        $msg->{$id}->{info} = ['none'];
        $msg->{$id}->{deleted_time} = "$time";
        printmailinfo( $msg->{$id} );
        #$readytoprint->{$id} = 1; 
	    print "\tDebug: Got spam quarantine info.\n" if $xdebug;
    }
    elsif ( $line =~ /Requeue: ([0-9A-F]+)\.[0-9A-F]+ to ([0-9A-F]+)/ ) {
        $msg->{$2} = $msg->{$1};
        $msg->{$2}->{id1} = $1;
        delete $msg->{$1};
	    print "\tDebug: Got requeue info. $1($id) -> $2\n" if $debug;
    }
    elsif ( $line =~ /with subject (.*)/ ) {
         $msg->{$id}->{subject} = $1;
    }
}



###
# Parsing the postgrey log line extracting all necessary info into the mailbox hash.
sub parsepostgrey {
    if ( $line =~ /triplet found, delay=(\d+), client_name=(.*?), client_address=(.*?), sender=(.*?), recipient=(.*)$/ ) {
        #$i = "$3-$4-$5";
        $i = "$4-$5";
        $postgreylist->{$i}->{time}           = $time;
        $postgreylist->{$i}->{delay}          = $1;
        $postgreylist->{$i}->{client_address} = $3;
        $postgreylist->{$i}->{sender}         = $4;
        $postgreylist->{$i}->{recipient}      = $5;
        print "Got: $postgreylist->{$i}->{time}, $postgreylist->{$i}->{client_address}, $postgreylist->{$i}->{sender},
             $postgreylist->{$i}->{recipient}!\n" if $xdebug;
    }
}


###
# Parsing the dovecot log line extracting all necessary info into the mailbox hash.
sub parsedovecot {
    if ( $line =~ /msgid=<(.*)>: (.*)/ ) {
        for $i ( keys %$msg ) {
            if ( defined( $msg->{$i}->{msgid} ) && "$msg->{$i}->{msgid}" eq "$1" ) { 
                    push @{ $msg->{$i}->{dovecotinfo} }, $2;
            }
        }    
    }
}


sub ParseLine {
    $lines++;
    chomp( $_[0] );

    if (  $_[0] =~ /(warning:.*)/i && $warnings ) {
        print "$1\n";
    }

    # Check if line is in a known Postfix format:
    if ( $_[0] =~ /^(\w\w\w\s{1,2}\d{1,2}) (\d\d:\d\d:\d\d) (.*) postfix\/(\w+)\[\d+\]: ([0-9A-Z]+): (.*)/ ) {
        ( $date, $time, $server, $cmd, $id, $line ) = ( $1, $2, $3, $4, $5, $6 );
        print "\tDebug: Parsing (Postfix): <$_>\n" if $xdebug;
        check_date_change() if $date_change;
        parsepostfix( $_ );
    }

    # Check if line is in a known Mailscanner format:
    elsif ( $_[0] =~ /^(\w\w\w\s{1,2}\d{1,2} \d\d:\d\d:\d\d) (\w+) MailScanner\[\d+\]: (.*)/ ) {
        ( $time, $server, $line ) = ( $1, $2 ,$3 );
        $Mailscanner = 1;
        print "\tDebug: Parsing (Mailscanner): <$_>\n" if $xdebug;
        parsemailscanner( $_ );
    }

    # Check if line is in a known Postgrey format:
    elsif ( $_[0] =~ /^(\w\w\w\s{1,2}\d{1,2} \d\d:\d\d:\d\d) (\w+) postgrey\[\d+\]: (.*)/ ) {
        ( $time, $server, $line ) = ( $1, $2 ,$3 );
        $Postgrey = 1;
        print "\tDebug: Parsing (Postgrey): <$_>\n" if $xdebug;
        parsepostgrey( $_ );
    }

    # Check if line is in a known TLS format:
    elsif ( $_[0] =~ /^(\w\w\w\s{1,2}\d{1,2} \d\d:\d\d:\d\d) .* postfix\/\w+\[\d+\]: (\w+ TLS connection established .*)/ ) {
        ( $time, $line ) = ( $1, $2 );
        print "\tDebug: Parsing (TLS): <$_>\n" if $xdebug;
        parsetls( $_ );
    }

    # Check if line is in a known Dovecot format:
    elsif ( $_[0] =~ /^(\w\w\w\s{1,2}\d{1,2} \d\d:\d\d:\d\d) .* dovecot: (.*)/ ) {
        ( $time, $line ) = ( $1, $2 );
        print "\tDebug: Parsing (dovecot): <$_>\n" if $xdebug;
        parsedovecot( $_ );
    }

    else {
        print "\tDebug: No known format: <$_>\n" if $xdebug;
    }

    # This little loop checks if there are any mail that has been marked as 'ready to print', and that mlp has
    # parsed 10 additional lines to make sure that all info about the spesific mail has been caught. 
    for $i ( keys %$readytoprint ) {
        $readytoprint->{$i}++;
        if ( $readytoprint->{$i} == 10 ) {
            $id = $i;
            printmailinfo( $msg->{$i} );
            delete $readytoprint->{$i};
        }
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
        print "$line" if $debug;
        ParseLine( $line );
    }
    $gz->gzclose() ;
}


###
# Prints the footer:
sub printfooter {
    my $entryname = 'entries';

    unless ( $csv ) {
        $endtime = formattime( time - $starttime );
        $lines = formatnr( $lines );
        if ( $entries == 0 ) { $entries = 'No' }
        elsif ( $entries == 1 ) { $entryname = 'entry' }
        else { $entries = formatnr( $entries ) };

        print color "$col->{headline}" if $color;
        print "_________________________________________________\n";
        print "Done. $lines lines parsed in $endtime. $entries $entryname found.\n\n" if ! $debug;
        print color 'reset' if $color;
    }
}


####################################################################################
# Ok, Let's start the show!

unless ( $csv ) {
    $starttime = time;

    print color "$col->{headline}" if $color; 
    print "Reading log files..\n_____________________\n\n";
}


# Process whatever is thrown at us via STDIN if $stdin-flag is set:
$stdin = IO::Select->new();
$stdin->add(\*STDIN);

if ($stdin->can_read(.5)) {
    print "Reading from <stdin>.\n" if ( $debug || $maillog_filename );
    while ( <STDIN> ) {
        &ParseLine( $_ );
        undef( $logfile );
    }
}


# If you want me to search logfiles:
elsif ( defined( $logfile ) ) {
    for $i ( 1 .. $NumberOfFiles-1 ) {	
        $i = $NumberOfFiles - $i;  # We want to parse oldest logs first.
        print "Reading $path$logfile.$i\n" if ( $debug || $maillog_filename );

        if    ( -e "$path$logfile.$i.gz" ) { print ".gz\n"  if $debug; readgzfile( "$path$logfile.$i.gz"  ); }
        elsif ( -e "$path$logfile.$i.bz" ) { print ".bz2\n" if $debug; readbzfile( "$path$logfile.$i.bz2" ); }
        elsif ( -e "$path$logfile.$i" )    { print "\n"     if $debug; readfile(   "$path$logfile.$i"     ); }
        else { print "Warning!  File not found: $path$logfile.$i(or .gz or .bz2)!\n"; }
    }

    print "Reading $path$logfile\n" if ( $debug || $maillog_filename );
    if ( -e "$path$logfile" ) { 
        &readfile( "$path$logfile" );
    }
    else {
        print "Warning!  File not found: $path$logfile!\n";
    }
}


# time to print any mail that still waits in queue to be handled:
for $i ( keys %$readytoprint ) {
    $id = $i;
    printmailinfo( $msg->{$i} );
    delete $readytoprint->{$i};
}


# Time to print footer info:
printfooter();


exit if ! $PrintRestOfMessages;


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
    #if ( $address eq 'all' ||  $j =~ /$address/i ) {
        print "$j\n";
    #}
}
print "Done.\n";
