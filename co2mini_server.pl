#!/usr/bin/perl -w
# 

## Heavily based on http://docstore.mik.ua/orelly/perl/cookbook/ch17_14.htm

use strict;
use POSIX;
use IO::Socket;
use IO::Select;
use Socket;
use Fcntl;

$SIG{PIPE} = "IGNORE";

my $device = shift;
my $port = shift;

die "Need two arguments: device file and port" if !defined($device) or !defined($port);

# Listen to port.
my $server = IO::Socket::INET->new(LocalPort => $port,
                                   Listen    => 10 )
  or die "Can't make server socket: $@\n";
nonblock($server);

# Result of printf("0x%08X\n", HIDIOCSFEATURE(9)); in C
my $HIDIOCSFEATURE_9 = 0xC0094806;

# Key retrieved from /dev/random, guaranteed to be random ;-)
my $key = "\x86\x41\xc9\xa8\x7f\x41\x3c\xac";

my $deviceconn;
my $select;

sub mainloop {
    # begin with empty buffers
    my %outbuffer = ();

    $select = IO::Select->new($server);

    sysopen($deviceconn, $device, O_RDWR | O_APPEND | O_NONBLOCK) or return "Error opening " . $device;

    # Send a FEATURE Set_Report with our key
    ioctl($deviceconn, $HIDIOCSFEATURE_9, "\x00".$key) or return "Error establishing connection to " . $device;

    $select->add($deviceconn);

    # Main loop: check reads/accepts, check writes, check ready to process
    while (1) {
        my $client;
        my $rv;

        # check for new information on the connections we have

        # anything to read or accept?
        foreach $client ($select->can_read(1)) {

            if ($client == $server) {
                # accept a new connection

                $client = $server->accept();
                $select->add($client);
                nonblock($client);
            } elsif ($client == $deviceconn) {
                my $buf;
                my $readlength = sysread($deviceconn, $buf, 8);
                return "Could not read from device" if $readlength != 8;
            
                my @data = co2mini_decrypt($key, $buf);
                if($data[4] != 0xd or (($data[0] + $data[1] + $data[2]) & 0xff) != $data[3]) {
                    return "co2mini wrong data format received or checksum error";
                }

                my $msg = join("", map { chr } @data[0 .. 4]);

                foreach $client ($select->handles()) {
                    next if $client == $server;
                    next if $client == $deviceconn;
                    $outbuffer{$client} = ($outbuffer{$client} // "") . $msg;
                }
            }
        }

        # Buffers to flush?
        foreach $client ($select->can_write(0)) {
            # Skip this client if we have nothing to say
            next unless exists $outbuffer{$client};

            $rv = $client->send($outbuffer{$client}, 0);
            if ( ($rv // -1) == length $outbuffer{$client} ||
                $! == POSIX::EWOULDBLOCK) {
                substr($outbuffer{$client}, 0, $rv) = '';
                delete $outbuffer{$client} unless length $outbuffer{$client};
            } else {
                # Couldn't write all the data, and it wasn't because
                # it would have blocked.  Shutdown and move on.
                delete $outbuffer{$client};

                $select->remove($client);
                close($client);
                next;
            }
        }
    }
}


while(1) {
    my $errmsg = mainloop();
    warn $errmsg;
    
    # Cleanup, re-start the main loop
    my $client;
    foreach $client ($select->handles()) {
	next if $client == $server;
        close($client);
    }
    sleep 1;
}

# Input: string key, string data
# Output: array of integers result
sub
co2mini_decrypt {
  my @key = map { ord } split //, shift;
  my @data = map { ord } split //, shift;
  my @offset = (0x84,  0x47,  0x56,  0xD6,  0x07,  0x93,  0x93,  0x56);
  my @shuffle = (2, 4, 0, 7, 1, 6, 5, 3);
  
  my @phase1 = map { $data[$_] } @shuffle;
  
  my @phase2 = map { $phase1[$_] ^ $key[$_] } (0 .. 7);
  
  my @phase3 = map { ( ($phase2[$_] >> 3) | ($phase2[ ($_-1+8)%8 ] << 5) ) & 0xff; } (0 .. 7);
  
  my @result = map { (0x100 + $phase3[$_] - $offset[$_]) & 0xff; } (0 .. 7);
  
  return @result;
}


# nonblock($socket) puts socket into nonblocking mode
sub nonblock {
    my $socket = shift;
    my $flags;
    
    $flags = fcntl($socket, F_GETFL, 0)
            or die "Can't get flags for socket: $!\n";
    fcntl($socket, F_SETFL, $flags | O_NONBLOCK)
            or die "Can't make socket nonblocking: $!\n";
}