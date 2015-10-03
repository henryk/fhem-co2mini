
package main;

use strict;
use warnings;

sub
co2mini_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "co2mini_Define";
  $hash->{NOTIFYDEV} = "global";
  $hash->{NotifyFn} = "co2mini_Notify";
  $hash->{UndefFn}  = "co2mini_Undefine";
  $hash->{AttrFn}   = "co2mini_Attr";
  $hash->{AttrList} = "disable:1 ".
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

  if( $init_done ) {
    co2mini_Disconnect($hash);
    co2mini_Connect($hash);
  } elsif( $hash->{STATE} ne "???" ) {
    $hash->{STATE} = "Initialized";
  }

  return undef;
}

sub
co2mini_Notify($$)
{
  my ($hash,$dev) = @_;

  return if($dev->{NAME} ne "global");
  return if(!grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));

  co2mini_Connect($hash);
}

sub
co2mini_Connect($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return undef if( AttrVal($name, "disable", 0 ) == 1 );

  # FIXME Implement

}

sub
co2mini_Disconnect($)
{
  my ($hash) = @_;
  my $name   = $hash->{NAME};

  # FIXME Implement

  $hash->{STATE} = "disconnected";
  Log3 $name, 3, "$name: disconnected";
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
  <b>Readings</b> FIXME

  <a name="co2mini_Attr"></a>
  <b>Attributes</b>
  <ul>
    <li>disable<br>
      1 -> disconnect</li>
  </ul>
</ul>

=end html
=cut
