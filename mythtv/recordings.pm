#
# $Date$
# $Revision$
# $Author$
#
#   mythtv::recordings
#
#   Load the available recordings/shows, and perform any
#

package mythtv::recordings;

    use DBI;
    use nuv_export::shared_utils;
    use nuv_export::cli;
    use mythtv::db;
    use mythtv::nuvinfo;
    use Date::Manip;

    BEGIN {
        use Exporter;
        our @ISA = qw/ Exporter /;

        our @EXPORT = qw/ &load_finfo &load_recordings $video_dir %Shows /;

    # These are available for export, but for the most part should only be needed here
        our @EXPORT_OK = qw/ &generate_showtime $num_shows /;
    }

# Variables we intend to export
    our ($video_dir, %Shows, $num_shows);

# Autoflush buffers
    $|++;

# Make sure we have the db filehandle
    die "Not connected to the database.\n" unless ($dbh);

# Load the following extra parameters from the commandline
    add_arg('date:s', 'Date format used for human-readable dates.');

#
#   Load all known recordings
#
    sub load_recordings {
    # Let the user know what's going on
        clear();
        print "Loading MythTV recording info.\n";

    # Query variables we'll use below
        my ($q, $sh, @files, $file, $count);

    # Find the directory where the recordings are located
        $q = 'SELECT data FROM settings WHERE value="RecordFilePrefix" AND hostname=?';
        $sh = $dbh->prepare($q);
            $sh->execute($hostname) or die "Could not execute ($q):  $!\n\n";
        ($video_dir) = $sh->fetchrow_array();
        die "This host not configured for myth.\n(No RecordFilePrefix defined for $hostname in the settings table.)\n\n" unless ($video_dir);
        die "Recordings directory $video_dir doesn't exist!\n\n" unless (-d $video_dir);
        $video_dir =~ s/\/+$//;

    # Try a basename file search
        my $rows;
        $sh = $dbh->prepare('SELECT *, basename FROM recorded');
        $rows = $sh->execute();
        if (defined $rows) {
            while ($file = $sh->fetchrow_hashref()) {
                next unless ($file->{'basename'} && -e "$video_dir/".$file->{'basename'});
                push @files, $file;
            }
        }
        $sh->finish;

    # Nothing?!
        die "No valid recordings found!\n\n" unless (@files);

    # Prepare a query to look up GOP info used to determine mpeg recording length
        $q = 'SELECT MAX(mark) FROM recordedseek WHERE chanid=? AND starttime=?';
        $sh  = $dbh->prepare($q);
        die "nuvexport $VERSION requires MythTV 0.20\n" unless ($sh);

    # Prepare a query to pull out cutlist information
        my $c_q  = 'SELECT type, mark FROM recordedmarkup WHERE chanid=? AND starttime=? AND type IN (0,1) ORDER BY mark';
        my $c_sh = $dbh->prepare($c_q);

        $num_shows = $count = 0;
        foreach $file (@files) {
            $count++;
        # Print the progress indicator
            print "\r", sprintf('%.0f', 100 * ($num_shows / @files)), '% ';
        # Info hash
            my %info = %{$file};
        # Import the commercial flag list
            ### FIXME:  how do I do this?
        # Import the cutlist
            $info{'cutlist'} = '';
            my $cutlist_frames = 0;
            my $last_mark      = 0;
            $c_sh->execute($info{'chanid'}, $info{'starttime'})
                or die "Could not execute ($c_q):  $!\n\n";
            while (my ($type, $mark) = $c_sh->fetchrow_array) {
                if ($type == 1) {
                    $info{'cutlist'} .= " $mark";
                    $last_mark        = $mark;
                }
                elsif ($type == 0) {
                    $info{'cutlist'} .= "-$mark";
                    $cutlist_frames  += $mark - $last_mark;
                }
            }
            if ($type && $type == 1) {
                $info{'cutlist'} .= '-'.$self->{'last_frame'};
                $cutlist_frames  += $self->{'last_frame'} - $last_mark;
            }
        # Skip shows without cutlists?
            next if (arg('require_cutlist') && !$info{'cutlist'});
        # Pull out GOP info for mpeg files
            $sh->execute($info{'chanid'}, $info{'starttime'})
                or die "Could not execute ($q):  $!\n\n";
            ($info{'last_frame'}) = $sh->fetchrow_array();
        # Cleanup
            $info{'starttime_sep'} = $info{'starttime'};
            $info{'starttime_sep'} =~ s/\D+/-/sg;
            $info{'starttime'}     =~ tr/0-9//cd;
            $info{'endtime'}       =~ tr/0-9//cd;
        # Defaults
            $info{'title'}       = 'Untitled'       unless ($info{'title'} =~ /\S/);
            $info{'subtitle'}    = 'Untitled'       unless ($info{'subtitle'} =~ /\S/);
            $info{'description'} = 'No Description' unless ($info{'description'} =~ /\S/);
        #$description =~ s/(?:''|``)/"/sg;
            push @{$Shows{$info{'title'}}}, {'filename'       => "$video_dir/".$info{'basename'},
                                             'channel'        => $info{'chanid'},
                                             'start_time'     => $info{'starttime'},
                                             'end_time'       => $info{'endtime'},
                                             'start_time_sep' => $info{'starttime_sep'},
                                             'show_name'      => $info{'title'},
                                             'title'          => $info{'subtitle'},
                                             'description'    => $info{'description'},
                                             'transcoder'     => ($info{'transcoder'}    or 'autodetect'),
                                             'hostname'       => ($info{'hostname'}      or ''),
                                             'cutlist'        => ($info{'cutlist'}       or ''),
                                             'last_frame'     => ($info{'last_frame'}    or 0),
                                             'cutlist_frames' => ($cutlist_frames        or 0),
                                             'showtime'       => generate_showtime(split(/-/, $info{'starttime_sep'})),
                                            # This field is too slow to populate here, so it will be populated in ui.pm on-demand
                                             'finfo'          => undef
                                            };
        # Counter
            $num_shows++;
        }
        $c_sh->finish();
        $sh->finish();
        print "\n";

    # No shows found?
        unless ($num_shows) {
            die "Found $count files, but no matching database entries.\n"
                .(arg('require_cutlist') ? "Perhaps you should try disabling require_cutlist?\n" : '')
                ."\n";
        }

    # We now have a hash of show names, containing an array of episodes
    # We should probably do some sorting by timestamp (and also count how many shows there are)
        foreach my $show (sort keys %Shows) {
            @{$Shows{$show}} = sort {$a->{'start_time'} <=> $b->{'start_time'} || $a->{'channel'} <=> $b->{'channel'}} @{$Shows{$show}};
        }
    }

    sub load_finfo {
        my $episode = shift;
        return if ($episode->{'finfo'});
        %{$episode->{'finfo'}} = nuv_info($episode->{'filename'});
    # Aspect override?
        if ($exporter->val('force_aspect')) {
            $episode->{'finfo'}{'aspect'}   = aspect_str($exporter->val('force_aspect'));
            $episode->{'finfo'}{'aspect_f'} = aspect_float($exporter->val('force_aspect'));
        }
    }

#
#   Returns a nicely-formatted timestamp from a specified time
#
    sub generate_showtime {
        my $showtime = '';
    # Get the requested date
        my ($year, $month, $day, $hour, $minute, $second) = @_;
        $month = int($month);
        $day   = int($day);
    # Special datetime format?
        if ($showtime = arg('date')) {
            $showtime = UnixDate(ParseDate("$year-$month-$day $hour:$minute:$second"), $showtime);
        }
    # Default to the standard
        else {
        # Get the current time, so we know whether or not to display certain fields (eg. year)
            my ($this_second, $this_minute, $this_hour, $ignore, $this_month, $this_year) = localtime;
            $this_year += 1900;
            $this_month++;
        # Default the meridian to AM
            my $meridian = 'AM';
        # Generate the showtime string
            $showtime .= "$month/$day";
            $showtime .= "/$year" unless ($year == $this_year);
            if ($hour == 0) {
                $hour = 12;
            }
            elsif ($hour > 12) {
                $hour -= 12;
                $meridian = 'PM';
            }
            $showtime .= ", $hour:$minute $meridian";
        }
    # Return
        return $showtime;
    }

# vim:ts=4:sw=4:ai:et:si:sts=4
