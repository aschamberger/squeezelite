# based on
# https://github.com/sle118/squeezelite-esp32/tree/master-v4.3/plugin --> adding player plugin + config handling
# https://github.com/Logitech/slimserver/blob/public/8.4/Slim/Player/Boom.pm --> audp: line in handling
# https://github.com/Logitech/slimserver/blob/public/8.4/Slim/Player/Squeezebox2.pm --> setd: line in level config

package Plugins::SqueezeLite::Player;

use strict;
use base qw(Slim::Player::SqueezePlay);

use Digest::MD5 qw(md5);
use List::Util qw(min);

use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $prefs = preferences('server');
my $log   = logger('plugin.squeezelite');

sub new {
	my $class = shift;
    
	my $client = $class->SUPER::new(@_);
    
	return $client;
}

our $defaultPrefs = {
	'lineInAlwaysOn'       => 0,
	'lineInLevel'          => 50,
};

$prefs->setValidate({ 'validator' => 'intlimit', 'low' => 0, 'high' => 100 }, 'lineInLevel');
$prefs->setChange(\&setLineInLevel, 'lineInLevel');

# Boom enables line in when setting is enabled
# $prefs->setChange(sub {
	# my ($name, $enabled, $client) = @_;
	
	# if ($enabled) { $client->setLineIn(1); }
	
	# # turn off if line is not playing
	# elsif (!Slim::Music::Info::isLineIn(Slim::Player::Playlist::url($client))) {
		# $client->setLineIn(0);
	# }
	
# }, 'lineInAlwaysOn');

my $handlersAdded;

sub model { 'squeezelite' }
sub modelName { 'SqueezeLite' }

sub hasLineIn { 1 }

sub init {
	my $client = shift;

	if (!$handlersAdded) {

		# Add a handler for line-in/out status changes
		Slim::Networking::Slimproto::addHandler( LIOS => \&lineInOutStatus );

		# Create a new event for sending LIOS updates
		Slim::Control::Request::addDispatch(
			['lios', '_state'],
			[1, 0, 0, undef],
		   );

		Slim::Control::Request::addDispatch(
			['lios', 'linein', '_state'],
			[1, 0, 0, undef],
		   );

		Slim::Control::Request::addDispatch(
			['lios', 'lineout', '_state'],
			[1, 0, 0, undef],
		   );

		$handlersAdded = 1;

	}

	$client->SUPER::init(@_);

	main::INFOLOG && $log->is_info && $log->info("SqueezeLite player connected: " . $client->id);
}

sub initPrefs {
	my $client = shift;

	$prefs->client($client)->init($defaultPrefs);

	$client->SUPER::initPrefs;
}

sub play {
	my ($client, $params) = @_;

	# If the url to play is a source: value, that means the Line In
	# are being used. The LineIn plugin handles setting the audp
	# value for those. If the user then goes and pressed play on a
	# standard file:// or http:// URL, we need to set the value back to 0,
	# IE: input from the network.
	my $url = $params->{'url'};

	if ($url) {
		if (Slim::Music::Info::isLineIn($url)) {
			# The LineIn plugin will handle this, so just return
			return 1;
		}
		else {
			main::INFOLOG && logger('player.source')->info("Setting LineIn to 0 for [$url]");
			$client->setLineIn(0);
		}
	}
	return $client->SUPER::play($params);
}

sub pause {
	my $client = shift;

	$client->SUPER::pause(@_);
	if (Slim::Music::Info::isLineIn(Slim::Player::Playlist::url($client))) {
		$client->setLineIn(0);
	}
}

sub stop {
	my $client = shift;

	$client->SUPER::stop(@_);
	if (Slim::Music::Info::isLineIn(Slim::Player::Playlist::url($client))) {
		$client->setLineIn(0);
	}
}

sub resume {
	my $client = shift;

	$client->SUPER::resume(@_);
	if (Slim::Music::Info::isLineIn(Slim::Player::Playlist::url($client))) {
		$client->setLineIn(Slim::Player::Playlist::url($client));
	}
}

sub power {
	my $client = shift;
	my $on = $_[0];
	my $currOn = $prefs->client( $client)->get( 'power') || 0;

	my $result = $client->SUPER::power($on);

	# Start playing line in on power on, if line in was selected before
	if( defined( $on) && (!defined(Slim::Buttons::Common::mode($client)) || ($currOn != $on))) {
		if( $on == 1) {
			if (Slim::Music::Info::isLineIn(Slim::Player::Playlist::url($client))) {
				$client->execute(["play"]);
			}
		}
	}

	return $result;
}

sub reconnect {
	my $client = shift;	
	$client->SUPER::reconnect(@_);
    
    $client->getLineInLevel();
}

# process settings from player
sub playerSettingsFrame {
	my $client   = shift;
	my $data_ref = shift;

	my $value;
	my $id = unpack('C', $$data_ref);

	# SETD command for lineInLevel
	if ($id == 0xfe) {
		$level = (unpack('CC', $$data_ref))[1];
		if ($level >= 0 && $value <= 100) {
			$prefs->client($client)->set('lineInLevel', $value);

            main::INFOLOG && logger('player.source')->info("Setting line in level to $level");
		}
	}

	$client->SUPER::playerSettingsFrame($client, $data_ref);
}

sub getLineInLevel {
	my $client = shift;
	
	main::INFOLOG && logger('player.source')->info("Getting line in level");
	
	# request level from client
    my $data = pack('C', 0xfe || 0);
    $client->sendFrame('setd', \$data);
}

sub setLineInLevel {
	my $level = $_[1];
	my $client = $_[2];
	
	main::INFOLOG && logger('player.source')->info("Setting line in level to $level");
	
	# send level to client
    my $data = pack('CC', 0xfe, $level);
    $client->sendFrame('setd', \$data);
}

sub setLineIn {
	my $client = shift;
	my $input  = shift;

	my $log    = logger('player.source');

	# convert a source: url to a number, otherwise, just use the number
	if (Slim::Music::Info::isLineIn($input)) {
	
		main::INFOLOG && $log->info("Got source: url: [$input]");

		if ($INC{'Slim/Plugin/LineIn/Plugin.pm'}) {

			$input = Slim::Plugin::LineIn::Plugin::valueForSourceName($input);

			# make sure volume is set, without changing temp setting
			$client->volume( abs($prefs->client($client)->get("volume")), defined($client->tempVolume()));
		}
	}

	# turn off linein if nothing's plugged in
	if (!$client->lineInConnected()) {
		$input = 0;
	}

	# override the input value if the alwaysOn option is set
	elsif ($prefs->client($client)->get('lineInAlwaysOn')) {
		$input = 1;
	}

	main::INFOLOG && $log->info("Switching to line in $input");

	$prefs->client($client)->set('lineIn', $input);
	$client->sendFrame('audp', \pack('C', $input));
}

sub lineInConnected {
	my $state = Slim::Networking::Slimproto::voltage(shift) || return 0;
	return $state & 0x01 || 0;
}

sub lineOutConnected {
	my $state = Slim::Networking::Slimproto::voltage(shift) || return 0;
	return $state & 0x02 || 0;
}

sub lineInOutStatus {
	my ( $client, $data_ref ) = @_;

	my $state = unpack 'n', $$data_ref;

	my $oldState = {
		in  => $client->lineInConnected(),
		out => $client->lineOutConnected(),
	};

	Slim::Networking::Slimproto::voltage( $client, $state );

	Slim::Control::Request::notifyFromArray( $client, [ 'lios', $state ] );

	if ($oldState->{in} != $client->lineInConnected()) {
		Slim::Control::Request::notifyFromArray( $client, [ 'lios', 'linein', $client->lineInConnected() ] );
		if ( Slim::Utils::PluginManager->isEnabled('Slim::Plugin::LineIn::Plugin')) {
			Slim::Plugin::LineIn::Plugin::lineInItem($client, 1);
		}
	}

	if ($oldState->{out} != $client->lineOutConnected()) {
		Slim::Control::Request::notifyFromArray( $client, [ 'lios', 'lineout', $client->lineOutConnected() ] );
	}
}

1;
