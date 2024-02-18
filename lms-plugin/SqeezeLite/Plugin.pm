package Plugins::SqueezeLite::Plugin;

use strict;

use base qw(Slim::Plugin::Base);

use Slim::Utils::Log;

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.squeezelite',
	'defaultLevel' => 'INFO',
	'description'  => 'PLUGIN_SQUEEZELITE',
});

sub initPlugin {
	my $class = shift;

	$class->SUPER::initPlugin(@_);
	Slim::Networking::Slimproto::addPlayerClass($class, 99, 'squeezeelite', { client => 'Plugins::SqueezeLite::Player', display => 'Slim::Display::NoDisplay' });
	main::INFOLOG && $log->is_info && $log->info("Added class 99 for SqueezeLite");
}

1;
