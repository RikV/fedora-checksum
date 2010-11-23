#!/usr/bin/perl
#
# Author:	Riccardo Valzorio - fc-devel@cilea.it
#
# Version 0.3 - 12/11/2010

# loadin' modules
#use DBI; # removed DB connection
use LWP;
use Config::Simple;
use Switch;

# ----------------------- #
# Configuration File      #
# File: config 		  #
# ----------------------- #
my $Config = {};

# Add your configuration file
Config::Simple->import_from("config.cfg",$Config);

### first run ...
$session = getPIDs();
if ($session) {
	print "\n...getting session: $session\n\n";
	do {
		$session = getPIDs_by_token($session);
		print "\n...resuming session: $session\n\n";
	}
	while ($session);
}

#### Functions:
#
#
#

#### auth header, parameter: URL
sub auth {
	my ($url) = @_;
	my $browser = LWP::UserAgent->new;
        # Auth Header
	$browser->credentials(
               $Config->{"Fedora.Host"},
               $Config->{"Fedora.Realm"},
               $Config->{"Fedora.Username"} => $Config->{"Fedora.Password"}
        );
        my $response = $browser->get($url);
        die "Can't get $url -- ", $response->status_line , $response->header('WWW-Authenticate') unless $response->is_success;
	return $response;
}
###### Datastreams
sub getDatastreams {
	my $ppid = $_[0];
	my $response = auth($Config->{"Fedora.Protocol"}.'://'.$Config->{"Fedora.Host"}."/".$Config->{"Fedora.Context"}."/objects/".$ppid."/datastreams/?format=xml");
	my @ds = ($response->content =~ /\<datastream dsid\=\"(\S+)\"/g);
        foreach (@ds) {
		#### checksum here!!!!!!
		print "PID: $ppid - DS: $_ ";
		my $response = auth($Config->{"Fedora.Protocol"}.'://'.$Config->{"Fedora.Host"}."/".$Config->{"Fedora.Context"}."/objects/".$ppid."/datastreams/$_?format=xml&validateChecksum=true");
		$check = checkDs($response->content);
		switch($check) {
			case 0 {
				print "\t...Checksum error!\n";
				print "\n\n\n############################################\n";
				print "# CHECKSUM FAILED - PID: $ppid - DSID: $_\n";  
				print "############################################\n\n\n";
				alert($ppid,$_);
				break;
			}
			case 1 {
				print "... OK!\n";
				break;
			}
			case 2 {
				print "... WARN! ";
				print "... Checksum not defined in config!\n";
				break;
			}
		}
       	}
}

#### PID, 
sub getPIDs {
	my $response = auth($Config->{"Fedora.Protocol"}.'://'.$Config->{"Fedora.Host"}."/".$Config->{"Fedora.Context"}."/objects?pid=true&terms=&query=&maxResults=".$Config->{"Items.Page"}."&resultFormat=xml");
	my $xml = $response->content;
	($Config->{"Items.Random"}) ? fetchRandomObjects($xml) : fetchObjects($xml);
	if ($response->content =~ /\<token\>(\S+)\</) {
		return $1;
        }
	else {
		return 0;
	}
}
# PID WITH token
sub getPIDs_by_token {
	my $session = $_[0];
	if ($session =~ /\S+/) {
		my $response = auth($Config->{"Fedora.Protocol"}.'://'.$Config->{"Fedora.Host"}."/".$Config->{"Fedora.Context"}."/objects?sessionToken=$session&resultFormat=xml");
		my $xml = $response->content;
		($Config->{"Items.Random"}) ? fetchRandomObjects($xml) : fetchObjects($xml);
		if ($response->content =~ /\<token\>(\S+)\</) {
                        my $token = $1;
			return $token;
                }
		else {
			print "Session not found ... exiting.\n";
			return 0;
		}
	}
	else {return 0;}
}
#### get all PIDs from page
sub fetchRandomObjects {
	my $response = $_[0];
	my @ids = split('\n',$response);
	my @pid;
        foreach (@ids) {
                if ($_ =~ /\s+\<pid\>(\S+)\<\/pid\>/) { 
				push(@pid,$1);	
                }
        }
	#build random array
	my %random= ();
	#array to hash
	my $j = 0;
	foreach (@pid) {
		$random{$j} = $pid[$j];
		++$j;
	}	
	#iterating through %#pids
	for (my $i=0; $i<int(($#pid+1)*($Config->{"Items.Number"}/100)); ++$i) {
		#getting random item from all pids
		my $random_index = int(rand(scalar keys(%random)));
		my $item = $random{$random_index};
		#removing from random array
		delete $random{$random_index};
		getDatastreams($pid[$random_index]);
	}
}
#### get random PIDs from page
sub fetchObjects {
        my $response = $_[0];
        my @ids = split('\n',$response);
        foreach (@ids) {
                if ($_ =~ /\s+\<pid\>(\S+)\<\/pid\>/) {
                        getDatastreams($1);
                }
        }
}
sub checkDs {
### API-M
	my $xml = $_[0];
	
	if ($xml =~ /.*sChecksumType\>DISABLED\<.*/) {
		return 2;
        }
        else {
        	$xml =~ /.*sChecksumValid\>(\w+)\<.*/;
        	if ($1 eq "true") {
			return 1;
        	}
        	else {
			return 0;
        	}
        }
}
####### Alert
sub alert {
	$mta = $Config->{'Others.MTA'};
	my ($pid,$t)=@_;
	open(MAIL,"|$Config->{'Others.MTA'} -s 'PRESERVATION ERROR' $Config->{'Others.Email'}");
	print MAIL scalar(localtime()),"\n\n\tObject PID $pid\n\tDatastream Type $t\n\n\n";
	close MAIL;
	return 1;
}
