#!/usr/bin/perl -w
use strict;
use warnings "all";
use Getopt::Long;
use Mail::IMAPClient;
use Data::Dumper;
use Mail::SpamAssassin;
use DBI;

###############################################################################
# THE BEERWARE LICENSE:
# <david [arobase] mercereau [.] info> wrote the first version of this file.
# The docker version is based on this file was wrote by Gaetan Janssens.
# As long as you retain 
# this notice you can do whatever you want with this stuff. If we meet some day, 
# and you think this stuff is worth it, you can buy a beer to David in return.
###############################################################################

# Version and date
my $version = '0.4'; my $dateVersion = '8 Avril 2025';

my $params = {
    'version'       => $version,
    'dateversion'   => $dateVersion,
    'programme'     => 'imapspamscan',
    'learnprogramme'     => 'imapspamlearn',
    'help'          => 0,
    'verbose'       => 1,
    'debug'         => 1,
    'imapsrv'       => '',
    'imapuser'      => '',
    'imappassword'  => '',
    'imappasswordfile'  => 0,
    'imapssl'       => 0,
    'imapinbox'     => 'INBOX',
    'imapjunk'      => 'INBOX.spam',
    'imapspam'      => 'INBOX.spam',
    'db'            => '/tmp/imapspamscan.db',
    'dbrotate'      => 7,
    'daemon'        => 0,
    'force'        => 0,
    'daemonsleep'   => 30
};

# Read options
GetOptions(
    'help!'         => \$params->{help},
    'version!'      => \$params->{help},
    'verbose!'      => \$params->{verbose},
    'debug!'        => \$params->{debug},
    'imapsrv:s'     => \$params->{imapsrv},
    'imapuser:s'    => \$params->{imapuser},
    'imappassword:s' => \$params->{imappassword},
    'imappasswordfile:s' => \$params->{imappasswordfile},
    'imapssl!'      => \$params->{imapssl},
    'imapinbox:s'   => \$params->{imapinbox},
    'imapjunk:s'    => \$params->{imapjunk},
    'imapspam:s'    => \$params->{imapspam},
    'db:s'          => \$params->{db},
    'dbrotate:s'    => \$params->{dbrotate},
    'daemon!'       => \$params->{daemon},
    'force!'       => \$params->{force},
    'daemonsleep:s' => \$params->{daemonsleep}
);

if ($params->{help} > 0) {
    print <<TEXTHELP;
-----------------------------------------------------------
THE BEERWARE LICENSE:
<david [arobase] mercereau [.] info> wrote this file. As long as you retain 
this notice you can do whatever you want with this stuff. If we meet some day, 
and you think this stuff is worth it, you can buy me a beer in return. David
-----------------------------------------------------------
Programme : $params->{programme}.pl V$params->{version} - ($params->{dateversion})
    Scan imap folder for spam detection
Perl version : $]

Usage : $params->{programme}.pl [Option ...]

  Option :
    -verbose                     : Print verbose messages
    -debug                       : Print debugging messages
    -force                       : Force evaluation of all messages (clean db)
    -imapsrv=                    : IMAP server (localhost)
    -imapuser=                   : IMAP user (env user)
    -imappassword=               : IMAP password (empty)
    -imappasswordfile=           : IMAP password in file (empty)
    -imapssl                     : IMAP ssl (false)
    -imapinbox=                  : IMAP inbox folder (INBOX)
    -imapjunk=                   : IMAP folder to put spam in (Junk)
    -imapspam=                   : IMAP spam folder for Learning (SpamToLearn)
    -db=                         : SPAM (/tmp/imapspamscan.db)
    -dbrotate=                   : Number of day to DB clean (7)
    -daemon                      : Daemon mode
    -daemonsleep=                : Number of seconds to wait (30)
    -help                        : This page
    -version                     : This page

TEXTHELP
    exit();
}

# callback signal handler for signals.
$SIG{INT} = $SIG{TERM} = $SIG{HUP} = \&signalHandler;
$SIG{PIPE} = 'ignore';

local $| = 1; # disabling buffering (autoflush)

logEntry(7, "Start"); 

my $dieNow = 0; # used for "infinte loop" construct - allows daemon mode to gracefully exit

my $IMAPClientPassword;

if ($params->{imappasswordfile}) {
    open my $passwdfile, '<', $params->{imappasswordfile} or die $!; 
    my $firstLinePasswdfile = <$passwdfile>; 
    close $passwdfile;
    $firstLinePasswdfile =~ s/\n//gs;
    $IMAPClientPassword = $firstLinePasswdfile;   
} else {
    $IMAPClientPassword = $params->{imappassword};
}

# Connection IMAP
my $client = Mail::IMAPClient->new(Server => $params->{imapsrv},
                                User    => $params->{imapuser},
                                Password => $IMAPClientPassword,
                                Ssl                => $params->{imapssl}
                                ) or die("\nConnection IMAP error : $@\n");

if ( $client->IsAuthenticated() ) {
    logEntry(7, "IsAuthenticated"); 
#     # Liste des dossiers
# my @folders = $client->folders or die "Impossible de lister les dossiers : $@";

# foreach my $folder (@folders) {
#     print "📂 $folder\n";
# }
    logEntry(7, "Connection in base ".$params->{db}); 
    my $db = DBI->connect("dbi:SQLite:".$params->{db}, "", "", {RaiseError => 1, AutoCommit => 1});
    $db->do("CREATE TABLE IF NOT EXISTS ".$params->{programme}." (messageid VARCHAR UNIQUE, date DATETIME, spam BOOL)");
    $db->do("CREATE TABLE IF NOT EXISTS ".$params->{learnprogramme}." (messageid VARCHAR UNIQUE, date DATETIME, spam BOOL)");
    if ($params->{force}) {
        $db->do("DELETE FROM ".$params->{programme});
    }
    $db->do("DELETE FROM ".$params->{programme}." WHERE date < datetime('now','-".$params->{dbrotate}." day')");
    # "infinite" loop where some useful process happens
    until ($dieNow) {
        # Select spam folder and learn spam
        logEntry(7, "lets learn from spam folder : ".$params->{imapspam}); 
        $client->select($params->{imapspam});
        for my $msg ( reverse $client->messages ) {  
            my @flags   = $client->flags( $msg ) ;  
            # Check unread
            my $req1 = $db->selectall_arrayref("SELECT messageid FROM ".$params->{learnprogramme}." WHERE messageid = '".$client->get_header($msg, "Message-Id")."' ");
            my $dbNb = scalar(@$req1);
            if ($dbNb == 0) {
                logEntry(7, "message #".$client->get_header($msg, "Message-Id")." is not in DB");
                logEntry(7, "title = ".$client->get_header($msg, "Subject"));
                # No unread message when ->message_string
                $client->Peek(1);
                my $msg_string = $client->message_string($msg) 
                    or die "\nCould not message_string: $@\n";

                my $spamtest = Mail::SpamAssassin->new();
                my $mail = $spamtest->parse($msg_string);
                my $status = $spamtest->check($mail);
                $status->learn('spam');
                $status->finish();
                $mail->finish();
                $spamtest->finish();

                $db->do("INSERT INTO ".$params->{learnprogramme}." VALUES ('".$client->get_header($msg, "Message-Id")."', datetime('now'), '1')");
            } 
        }
        logEntry(7, "learning done"); 
        logEntry(7, "lets check for unread spam on Inbox folder : ".$params->{imapinbox}); 
        $client->select($params->{imapinbox});
        for my $msg ( reverse $client->messages ) {  
            my @flags   = $client->flags( $msg ) ;  
            # Check unread
            if ((! scalar(grep(/Seen/ , @flags))) && (! scalar(grep(/Deleted/ , @flags)))) {                 
                my $req1 = $db->selectall_arrayref("SELECT messageid FROM ".$params->{programme}." WHERE messageid = '".$client->get_header($msg, "Message-Id")."' ");
                my $dbNb = scalar(@$req1);
                if ($dbNb == 0) {
                    # No unread message when ->message_string
                    $client->Peek(1);
                    my $string = $client->message_string($msg) 
                        or die "\nCould not message_string: $@\n";
                    my $spamtest = Mail::SpamAssassin->new();
                    my $mail = $spamtest->parse($string);
                    my $status = $spamtest->check($mail);

                    # Obtenir le score global attribué
                    my $score = $status->get_hits;

                    # Obtenir le seuil de déclenchement (par défaut 5.0)
                    my $threshold = $status->get_required_score;

                    # Obtenir la liste des règles qui ont matché
                    my @rules_hit = split(/\s+/, $status->get_names_of_tests_hit);

                    # Afficher
                    print "Return-Path       : " . $client->get_header($msg, "Return-Path") . "\n";
                    print "Score       : $score\n";
                    print "Seuil       : $threshold\n";
                    print "SPAM ?      : " . ($status->is_spam ? "OUI" : "NON") . "\n";
                    print "Règles      : " . join(", ", @rules_hit) . "\n";

                    if ($status->is_spam()) {
                        # Is SPAM
                        logEntry(7, "Spam detect : ".$client->get_header($msg, "Message-Id")); 
                        $db->do("INSERT INTO ".$params->{programme}." VALUES ('".$client->get_header($msg, "Message-Id")."', datetime('now'), '1')");
                        logEntry(5, "Move message in ".$params->{imapjunk}." for ".$client->get_header($msg, "Message-Id")); 
                        my $newUid = $client->move($params->{imapjunk}, $msg) 
                            or die "\nCould not move message : $@\n";
                    } else {
                        # No SPAM
                        logEntry(7, "No spam detect : ".$client->get_header($msg, "Message-Id")); 
                        $db->do("INSERT INTO ".$params->{programme}." VALUES ('".$client->get_header($msg, "Message-Id")."', datetime('now'), '0')");
                    }
                    $status->finish();
                    $mail->finish();
                    $spamtest->finish();
                } 
            }
        }
        $client->close or die("\nError close folder ".$params->{imapinbox}." : $@");
        if ($params->{daemon}) {
            logEntry(7, "sleep ".$params->{daemonsleep}); 
            sleep($params->{daemonsleep});
        } else {
            logEntry(7, "No daemon mode : exit"); 
            $dieNow = 1;
        }
    }
};




sub logEntry {
    # 7 debug, 6 info, 5 notice, 4 warning, 3 error, 2 critical, 1 alert, 0 emergency
    # 7 debug          5 verbose
    my ($logLevel, $logText) = @_;
    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime(time);
    my $dateTime = sprintf "%4d-%02d-%02d %02d:%02d:%02d", $year + 1900, $mon + 1, $mday, $hour, $min, $sec;
    if (($params->{debug} != 0) && ($logLevel <= 7)) {
        print  "[".$dateTime."] [".$params->{programme}."] ".$logText."\n";
    } elsif (($params->{verbose} != 0) && ($logLevel <= 5)) {
        print  "[".$dateTime."] [".$params->{programme}."] ".$logText."\n";
    } 
}
 
# catch signals and end the program if one is caught.
sub signalHandler {
    logEntry(7, "signalHandler !"); 
    $dieNow = 1;    # this will cause the "infinite loop" to exit
}
 
# do this stuff when exit() is called.
END {
    if ($params->{help} == 0) {
        logEntry(7, "The end"); 
        $client->logout();
    }
}


