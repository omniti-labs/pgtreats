use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

eval {
    require Net::Pcap;
};
if (! $@) {
    if (&Net::Pcap::lib_version() eq 'libpcap version unknown (pre 0.8)') {
        warn <<VERSION_TOO_LOW;
Your version of libpcap is too low.

You need to install a higher version of
libpcap, and possibly recompile Net::Pcap
so it picks up the new, and necessary features.

If you're using Debian, the magic incantation is

  apt-get install libpcap0.8-dev

I give up. Sorry.
VERSION_TOO_LOW
        exit 1;
    };
};

WriteMakefile(
    'NAME'    => 'Sniffer::Postgres',
    'VERSION_FROM'  => 'lib/Sniffer/Postgres.pm', # finds $VERSION
    'EXE_FILES'    => ['bin/pgsniff'],
    'PREREQ_PM'    => { 'Class::Accessor' => 0,
                        'Class::Data::Inheritable' => 0,
                        'NetPacket::TCP'  => 0,
                        'Net::Pcap'       => 0.09,
			'Exporter::Lite'  => 0,
                        'Sniffer::HTTP'   => 0.19,
                      }, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM => 'lib/Sniffer/Postgres.pm', # retrieve abstract from module
       AUTHOR     => 'Theo Schlossnagle <jesus@omniti.com>') : ()),
);

1;
