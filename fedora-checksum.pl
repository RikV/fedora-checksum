#!/usr/bin/perl

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

do {
	$session = getPIDs_by_token($session);
	print "\n...resuming session: $session\n\n";
}
while ($session);

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
                print "\tGetting Datastream (PID: $ppid): $_\n";
		#### checksum here!!!!!!
		print "\t\tChecking MD5 ...";
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
				print "\t... OK!\n";
				break;
			}
			case 2 {
				print "\t... Checksum not defined in config!\n";
				break;
			}
		}
       	}
}

#### PID, 
sub getPIDs {
	my $response = auth($Config->{"Fedora.Protocol"}.'://'.$Config->{"Fedora.Host"}."/".$Config->{"Fedora.Context"}."/search?pid=true&terms=&query=&maxResults=".$Config->{"Items.Page"}."&xml=true");
	if ($response->content =~ /\<token\>(\S+)\</) {
		$xml = $response->content;
		fetchObjects($xml);
		return $1;
        }
}
# PID WITH token
sub getPIDs_by_token {
	my $session = $_[0];
	if ($session =~ /\S+/) {
		my $response = auth($Config->{"Fedora.Protocol"}.'://'.$Config->{"Fedora.Host"}."/".$Config->{"Fedora.Context"}."/search?sessionToken=$session&xml=true");
		fetchObjects($response->content);
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
sub fetchObjects {
	my $response = $_[0];
	my @ids = split('\n',$response);
	my @pid;
        foreach (@ids) {
                if ($_ =~ /\s+\<pid\>(\S+)\<\/pid\>/) { 
                        #print "Getting PID: $1\n";
			#print "...getting datastreams...\n";
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
	my ($pid,$t)=@_;
	open(MAIL,"|/usr/bin/mail -s 'PRESERVATION ERROR' $Config->{'Others.Email'}");
	print MAIL scalar(localtime()),"\n\n\tObject PID $pid\n\tDatastream Type $t\n\n\n";
	close MAIL;
	return 1;
}
