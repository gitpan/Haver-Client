#!/usr/bin/perl
use Module::Build;
my $build = Module::Build->new(
	module_name   => 'Haver::Client',
	dist_name     => 'haver-client',
	dist_version  => '0.043',
	dist_author   => 'Bryan Donlan <bdonlan@bd-home-comp.no-ip.org>',
	dist_abstract => 'Client libraries for the Haver chat system.',
	license => 'gpl',
	requires => {
		'perl'           => '5.6.1',
		POE              => 0.26,
		Haver            => 0.043,
		'Digest::SHA1'   => 2.01,
		'Data::Dumper'   => 2.121,

	},
	create_makefile_pl => 'passthrough',
	script_files => [ glob ('bin/*') ],
);

$build->create_build_script;
