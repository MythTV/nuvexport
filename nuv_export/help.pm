#!/usr/bin/perl -w
#
# help
#
# @url       $URL: svn+ssh://xris@svn.mythtv.org/var/lib/svn/trunk/mythextras/nuvexport/nuv_export/help.pm $
# @date      $Date$
# @version   $Revision$
# @author    $Author$
#

    if (arg('mode')) {
        my $exporter = query_exporters($export_prog);
        print "No help for $export_prog/", arg('mode'), "\n\n";
    }

    if (arg('help') eq 'debug') {
        print "Please read https://svn.forevermore.net/nuvexport/wiki/debug\n";
    }

    else {
        print "Help section still needs to be updated.\n"
             ."   For now, please read /etc/nuvexportrc or the nuvexport wiki at\n"
             ."   http://mythtv.org/wiki/index.php/Nuvexport\n\n";
    }

    exit;

# vim:ts=4:sw=4:ai:et:si:sts=4
