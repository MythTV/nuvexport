#
# $Date$
# $Revision$
# $Author$
#
#  export::mencoder::XviD
#  Copied from transcode.pm
#  and modified by Ryan Dearing <mythtv@mythtv.us>
#

package export::mencoder::XviD;
    use base 'export::mencoder';

# Load the myth and nuv utilities, and make sure we're connected to the database
    use nuv_export::shared_utils;
    use nuv_export::cli;
    use nuv_export::ui;
    use mythtv::recordings;

# Load the following extra parameters from the commandline
    add_arg('quantisation|q=i', 'Quantisation');
    add_arg('a_bitrate|a=i',    'Audio bitrate');
    add_arg('v_bitrate|v=i',    'Video bitrate');
    add_arg('multipass!',       'Enable two-pass encoding.');

    sub new {
        my $class = shift;
        my $self  = {
                     'cli'      => qr/\bxvid\b/i,
                     'name'     => 'Export to XviD (using mencoder)',
                     'enabled'  => 1,
                     'errors'   => [],
                     'defaults' => {},
                    };
        bless($self, $class);

    # Initialize the default parameters
        $self->load_defaults();

    # Verify any commandline or config file options
        die "Audio bitrate must be > 0\n" unless (!defined $self->val('a_bitrate') || $self->{'a_bitrate'} > 0);
        die "Video bitrate must be > 0\n" unless (!defined $self->val('v_bitrate') || $self->{'v_bitrate'} > 0);
        die "Width must be > 0\n"         unless (!defined $self->val('width')     || $self->{'width'} =~ /^\s*\D/  || $self->{'width'}  > 0);
        die "Height must be > 0\n"        unless (!defined $self->val('height')    || $self->{'height'} =~ /^\s*\D/ || $self->{'height'} > 0);

    # VBR, multipass, etc.
        if ($self->val('multipass')) {
            $self->{'vbr'} = 1;
        }
        elsif ($self->val('quantisation')) {
            die "Quantisation must be a number between 1 and 31 (lower means better quality).\n" if ($self->{'quantisation'} < 1 || $self->{'quantisation'} > 31);
            $self->{'vbr'} = 1;
        }

    # Initialize and check for mencoder
        $self->init_mencoder();

    # Any errors?  disable this function
        $self->{'enabled'} = 0 if ($self->{'errors'} && @{$self->{'errors'}} > 0);
    # Return
        return $self;
    }

# Load default settings
    sub load_defaults {
        my $self = shift;
    # Load the parent module's settings
        $self->SUPER::load_defaults();
    # Not really anything to add
    }

# Gather settings from the user
    sub gather_settings {
        my $self = shift;
    # Load the parent module's settings
        $self->SUPER::gather_settings();
    # Audio Bitrate
        $self->{'a_bitrate'} = query_text('Audio bitrate?',
                                          'int',
                                          $self->val('a_bitrate'));
    # VBR options
        if (!$is_cli) {
            $self->{'vbr'} = query_text('Variable bitrate video?',
                                        'yesno',
                                        $self->val('vbr'));
            if ($self->{'vbr'}) {
                $self->{'multipass'} = query_text('Multi-pass (slower, but better quality)?',
                                                  'yesno',
                                                  $self->val('multipass'));
                if (!$self->{'multipass'}) {
                    while (1) {
                        my $quantisation = query_text('VBR quality/quantisation (1-31)?', 'float', $self->val('quantisation'));
                        if ($quantisation < 1) {
                            print "Too low; please choose a number between 1 and 31.\n";
                        }
                        elsif ($quantisation > 31) {
                            print "Too high; please choose a number between 1 and 31\n";
                        }
                        else {
                            $self->{'quantisation'} = $quantisation;
                            last;
                        }
                    }
                }
            }
        # Ask the user what audio and video bitrates he/she wants
            if ($self->{'multipass'} || !$self->{'vbr'}) {
                $self->{'v_bitrate'} = query_text('Video bitrate?',
                                                  'int',
                                                  $self->val('v_bitrate'));
            }
        }
    # Query the resolution
        $self->query_resolution();
    }

    sub export {
        my $self    = shift;
        my $episode = shift;
    # Build the mencoder string
        my $params = " -ovc xvid -vf scale=$self->{'width'}:$self->{'height'}"
        #." -N 0x55" # make *sure* we're exporting mp3 audio

        #." -oac mp3lame -lameopts vbr=3:br=$self->{'a_bitrate'}"
                    ;
       # unless ($episode->{'finfo'}{'fps'} =~ /^2(?:5|4\.9)/) {
       #    $params .= " -J modfps=buffers=7 --export_fps 23.976";
       # }
    # Dual pass?
        if ($self->{'multipass'}) {
        # Add the temporary file to the list
            push @tmpfiles, "/tmp/xvid.$$.log";
        # Back up the path and use /dev/null for the first pass
            my $path_bak = $self->{'path'};
            $self->{'path'} = '/dev/null';
        # First pass
            print "First pass...\n";
            $self->{'mencoder_xtra'} = "  $params"
                                       ." -passlogfile /tmp/xvid.$$.log"
                                       ." -oac copy"
                                       ." -xvidencopts bitrate=$self->{'v_bitrate'}:pass=1:quant_type=mpeg:threads=2:keyframe_boost=10:kfthreshold=1:kfreduction=20 ";
            $self->SUPER::export($episode, '', 1);
        # Restore the path
            $self->{'path'} = $path_bak;
        # Second pass
            print "Final pass...\n";
            $self->{'mencoder_xtra'} = " $params"
                                       ." -oac mp3lame -lameopts vbr=3:br=$self->{'a_bitrate'}"
                                       ." -passlogfile /tmp/xvid.$$.log"
                                       ." -xvidencopts bitrate=$self->{'v_bitrate'}:pass=2:quant_type=mpeg:threads=2:keyframe_boost=10:kfthreshold=1:kfreduction=20 ";
        }
    # Single pass
        else {
            $self->{'mencoder_xtra'} = " $params"
                                       ." -oac mp3lame -lameopts vbr=3:br=$self->{'a_bitrate'}";
            if ($self->{'quantisation'}) {
                $self->{'mencoder_xtra'} .= " -xvidencopts fixed_quant=".$self->{'quantisation'};
            }
            else {
                $self->{'mencoder_xtra'} .= " -xvidencopts bitrate=$self->{'v_bitrate'} ";
            }
        }
    # Execute the (final pass) encode
        $self->SUPER::export($episode, '.avi');
    }

1;  #return true

# vim:ts=4:sw=4:ai:et:si:sts=4
