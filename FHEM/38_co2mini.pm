
package main;

use strict;
use warnings;

use Fcntl;
use Errno;

# Key retrieved from /dev/random, guaranteed to be random ;-)
my $key = "u/R\xf9R\x7fv\xa5";

sub
co2mini_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "co2mini_Define";
  $hash->{ReadFn}   = "co2mini_Read";
  $hash->{NOTIFYDEV} = "global";
  $hash->{NotifyFn} = "co2mini_Notify";
  $hash->{UndefFn}  = "co2mini_Undefine";
  $hash->{AttrFn}   = "co2mini_Attr";
  $hash->{AttrList} = "disable:0,1 showraw:0,1 ".
                      $readingFnAttributes;
}

#####################################

sub
co2mini_Define($$)
{
  my ($hash, $def) = @_;

  my @a = split("[ \t][ \t]*", $def);

  return "Usage: define <name> co2mini [device]"  if(@a < 2);

  my $name = $a[0];

  $hash->{DEVICE} = $a[2] // "/dev/co2mini0";

  $hash->{NAME} = $name;

  my $result = undef;

  if( $init_done ) {
    co2mini_Disconnect($hash);
    $result = co2mini_Connect($hash);
  } elsif( $hash->{STATE} ne "???" ) {
    $hash->{STATE} = "Initialized";
  }

  return $result;
}

sub
co2mini_Notify($$)
{
  my ($hash,$dev) = @_;
  my $name = $hash->{NAME};

  return if($dev->{NAME} ne "global");
  return if(!grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));

  my $msg = co2mini_Connect($hash);
  if(defined($msg)) {
    Log3 $name, 1, "co2mini error while opening device: $msg, disabling device";
    CommandAttr(undef, "$name disable 1");
  }
}

sub
co2mini_Connect($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return undef if( AttrVal($name, "disable", 0 ) == 1 );

  sysopen($hash->{HANDLE}, $hash->{DEVICE}, O_RDWR | O_APPEND | O_NONBLOCK) or return "Error opening " . $hash->{DEVICE};

  # Result of printf("0x%08X\n", HIDIOCSFEATURE(9)); in C
  my $HIDIOCSFEATURE_9 = 0xC0094806;

  # Send a FEATURE Set_Report with our key
  ioctl($hash->{HANDLE}, $HIDIOCSFEATURE_9, "\x00".$key) or return "Error establishing connection to " . $hash->{DEVICE};

  $hash->{FD} = fileno($hash->{HANDLE});
  $selectlist{"$name"} = $hash;

  $hash->{STATE} = "connecting";

  return undef;
}

sub
co2mini_Disconnect($)
{
  my ($hash) = @_;
  my $name   = $hash->{NAME};

  if($hash->{HANDLE}) {
    delete $selectlist{"$name"};
    delete $hash->{FD};

    close($hash->{HANDLE});
    delete $hash->{HANDLE};
  }

  $hash->{STATE} = "disconnected";
  Log3 $name, 3, "$name: disconnected";
}


# Input: string key, string data
# Output: array of integers result
sub
co2mini_decrypt($$)
{
  my ($key_, $data_) = @_;
  my @key = map { ord } split //, $key_;
  my @data = map { ord } split //, $data_;
  my @cstate = (0x48,  0x74,  0x65,  0x6D,  0x70,  0x39,  0x39,  0x65);
  my @shuffle = (2, 4, 0, 7, 1, 6, 5, 3);
  
  my @phase1 = (0..7);
  for my $i (0 .. $#phase1) { $phase1[ $shuffle[$i] ] = $data[$i]; }
  
  my @phase2 = (0..7);
  for my $i (0 .. 7) { $phase2[$i] = $phase1[$i] ^ $key[$i]; }
  
  my @phase3 = (0..7);
  for my $i (0 .. 7) { $phase3[$i] = ( ($phase2[$i] >> 3) | ($phase2[ ($i-1+8)%8 ] << 5) ) & 0xff; }
  
  my @ctmp = (0 .. 7);
  for my $i (0 .. 7) { $ctmp[$i] = ( ($cstate[$i] >> 4) | ($cstate[$i]<<4) ) & 0xff; }
  
  my @out = (0 .. 7);
  for my $i (0 .. 7) { $out[$i] = (0x100 + $phase3[$i] - $ctmp[$i]) & 0xff; }
  
  return @out;
}

sub
co2mini_Read($)
{
  my ($hash) = @_;
  my $name   = $hash->{NAME};
  my ($buf, $readlength);

  my $showraw = AttrVal($name, "showraw", 0);

  readingsBeginUpdate($hash);
  while ( defined($readlength = sysread($hash->{HANDLE}, $buf, 8)) and $readlength == 8 ) {
    my @data = co2mini_decrypt($key, $buf);
    Log3 $name, 5, "co2mini data received " . join(" ", @data);
    
    if($data[4] != 0xd or (($data[0] + $data[1] + $data[2]) & 0xff) != $data[3]) {
      Log3 $name, 3, "co2mini wrong data format received or checksum error";
      next;
    }

    my ($item, $val_hi, $val_lo, $rest) = @data;
    my $value = $val_hi << 8 | $val_lo;
    
    if($item == 0x50) {
      readingsBulkUpdate($hash, "co2", $value);
    } elsif($item == 0x42) {
      readingsBulkUpdate($hash, "temperature", $value/16.0 - 273.15);
    } elsif($item == 0x44) {
      readingsBulkUpdate($hash, "humidity", $value/100.0);
    }
    if($showraw) {
      readingsBulkUpdate($hash, sprintf("raw_%02X", $item), $value);
    }
    
    $hash->{STATE} = "connected";
  }

  my $dodisable = 0;
 
  if(!defined($readlength)) {
    if($!{EAGAIN} or $!{EWOULDBLOCK}) {
      # This is expected, ignore it
    } else {
      Log3 $name, 1, "co2mini device error or disconnected: $!, disabling device";
      $dodisable = 1;
    }
  } elsif($readlength != 8) {
    Log3 $name, 3, "co2mini incomplete data received, shouldn't happen, ignored";
  }

  readingsEndUpdate($hash, 1);

  if($dodisable) {
    co2mini_Disconnect($hash);
    CommandAttr(undef, "$name disable 1");
  }
}

sub
co2mini_Undefine($$)
{
  my ($hash, $arg) = @_;

  co2mini_Disconnect($hash);

  return undef;
}

sub
co2mini_Attr($$$)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;

  if( $attrName eq "disable" ) {
    my $hash = $defs{$name};
    if( $cmd eq "set" && $attrVal ne "0" ) {
      co2mini_Disconnect($hash);
    } else {
      $attr{$name}{$attrName} = 0;
      co2mini_Disconnect($hash);
      co2mini_Connect($hash);
    }
  }

  return;
}

1;

=pod
=begin html

<a name="co2mini"></a>
<h3>co2mini</h3>
<ul>
  Module for measuring temperature and air CO2 concentration with a co2mini like device. 
  These are available under a variety of different branding, but all register as a USB HID device
  with a vendor and product ID of 04d9:a052.
  For photos and further documentation on the reverse engineering process see
  <a href="https://hackaday.io/project/5301-reverse-engineering-a-low-cost-usb-co-monitor">Reverse-Engineering a low-cost USB CO₂ monitor</a>.

  Notes:
  <ul>
    <li>FHEM has to have permissions to open the device. To configure this with udev, put a file named <tt>90-co2mini.rules</tt>
        into <tt>/etc/udev/rules.d</tt> with this content:
<pre>ACTION=="remove", GOTO="co2mini_end"

SUBSYSTEMS=="usb", KERNEL=="hidraw*", ATTRS{idVendor}=="04d9", ATTRS{idProduct}=="a052", GROUP="plugdev", MODE="0660", SYMLINK+="co2mini%n", GOTO="co2mini_end"

LABEL="co2mini_end"
</pre> where <tt>plugdev</tt> would be a group that your FHEM process is in.</li>
  </ul><br>

  <a name="co2mini_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; co2mini [device]</code><br>
    <br>

    Defines a co2mini device. Optionally a device node may be specified, otherwise this defaults to <tt>/dev/co2mini0</tt>.<br><br>

    Examples:
    <ul>
      <code>define co2 co2mini</code><br>
    </ul>
  </ul><br>

  <a name="co2mini_Readings"></a>
  <b>Readings</b>
  <dl><dt>co2</dt><dd>CO2 measurement from the device, in ppm</dd>
    <dt>temperature</dt><dd>temperature measurement from the device, in °C</dd>
    <dt>humidity</dt><dd>humidity measurement from the device, in % (may not be available on your device)</dd>
  </dl>

  <a name="co2mini_Attr"></a>
  <b>Attributes</b>
  <ul>
    <li>disable<br>
      1 -> disconnect</li>
    <li>showraw<br>
      1 -> show raw data as received from the device in readings of the form raw_XX</li>
  </ul>
</ul>

=end html
=cut
