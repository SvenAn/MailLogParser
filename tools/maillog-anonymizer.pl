#!/usr/bin/perl -w
###             anonymize.pl                    ###
# MailLogParse by Sven Andreassen sven@tideli.com #
# a small utility to parse e-mail log files       #
# printing all necessary info about an e-mail     #
# in a simple, human readable format.             #
###                                             ###

my $version = 'v.001';


use strict;
use warnings;
use IO::Select;


my $anonymous_address   = 'someone@somewhere.com';
my $anonymous_hostname  = 'somewhere.com';
my $anonymous_ipaddress = '0.0.0.0';


my $helptext = <<EOF;
###  MailLogParse anonymizer $version by Sven Andreassen ###
##                                                        ##

Syntax:
  anonymize [-dhfao] [filename]

        "d|debug"   = Prints extra info about the mail on multiple lines.
        "h|help"    = Prints this help info.
        "f|file"    = file to anonymize, (Default is STDIN).
        "a|address" = Mail address to use as anonymous address.
                      Defaults to 'someone\@somewhere.com'.
        "o|output"  = File to use as output file.
EOF


my ( $i, $debug, $help, $output, $stdin, $filename );


use Getopt::Long;
my $options = GetOptions (
        "d|debug"   => \$debug,
        "h|help"    => \$help,
        "f|file:s"  => \$filename,
        "a|address" => \$anonymous_address
);
$filename = $ARGV[0] if defined( $ARGV[0] );


die "$helptext" if $help;


sub anonymize {
    $i = $_[0];

    $i =~ s/\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/$anonymous_ipaddress/g;
    $i =~ s/<.*?\@.*?\.\w+?>/<$anonymous_address>/g;
    $i =~ s/from .*(\[$anonymous_ipaddress\])/from $anonymous_hostname$1/g;
    $i =~ s/from ($anonymous_ipaddress) \(.*?\) to .*? is/from $1 \($anonymous_hostname\) to $anonymous_hostname is/g;
    $i =~ s/([client|relay])=.*(\[$anonymous_ipaddress\])/$1=$anonymous_hostname$2/g;
    $i =~ s/helo=<.*?>/helo=<$anonymous_hostname>/g;
    $i =~ s/name=.*? /name=$anonymous_hostname/g;

    return $i;
}


# Process whatever is thrown at us via STDIN if $stdin-flag is set:
$stdin = IO::Select->new();
$stdin->add(\*STDIN);

if ($stdin->can_read(.5)) {
    print "Reading from <stdin>.\n" if ( $debug );
    while ( <STDIN> ) {
        $output = anonymize( $_ );
        print "$output";
    }
}


# Open filename if present:




# END
