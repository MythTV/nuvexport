# vim:ts=4:sw=4:ai:et:si:sts=4
#
# ffmpeg-based MP4 (iPod) video module for nuvexport.
#
# Many thanks to cartman in #ffmpeg, and for the instructions at
# http://rob.opendot.cl/index.php?active=3&subactive=1
# http://videotranscoding.wikispaces.com/EncodeForIPodorPSP
#

package export::ffmpeg::MP4;
    use base 'export::ffmpeg';

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
    add_arg('mp4_fps=s',        'Framerate to use:  auto, 25, 23.97, 29.97.');
    add_arg('ipod!',            'Produce ipod-compatible output.');

    sub new {
        my $class = shift;
        my $self  = {
                     'cli'      => qr/\b(?:mp4|ipod)\b/i,
                     'name'     => 'Export to MP4 (iPod)',
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

    # Initialize and check for ffmpeg
        $self->init_ffmpeg();

    # Can we even encode mp4?
        if (!$self->can_encode_format('mp4')) {
            push @{$self->{'errors'}}, "Your ffmpeg installation doesn't support encoding to mp4 file formats.";
        }
        if (!$self->can_encode('aac') && !$self->can_encode('libfaac')) {
            push @{$self->{'errors'}}, "Your ffmpeg installation doesn't support encoding to aac audio.";
        }
        if (!$self->can_encode('mpeg4')) {
            push @{$self->{'errors'}}, "Your ffmpeg installation doesn't support encoding to mpeg4 video.";
        }
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
    # Default settings
        $self->{'defaults'}{'v_bitrate'}  = 384;
        $self->{'defaults'}{'a_bitrate'}  = 64;
        $self->{'defaults'}{'width'}      = 320;
    # Verify commandline options
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
    # Video options
        if (!$is_cli) {
        # iPod compatibility mode?
            $self->{'ipod'} = query_text('Enable iPod compatibility?',
                                         'yesno',
                                         $self->val('ipod'));
        # Video bitrate options
            $self->{'vbr'} = query_text('Variable bitrate video?',
                                        'yesno',
                                        $self->val('vbr'));
            if ($self->{'vbr'}) {
                $self->{'multipass'} = query_text('Multi-pass (slower, but better quality)?',
                                                  'yesno',
                                                  $self->val('multipass'));
                if (!$self->{'multipass'}) {
                    while (1) {
                        my $quantisation = query_text('VBR quality/quantisation (1-31)?',
                                                      'float',
                                                      $self->val('quantisation'));
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
            } else {
                $self->{'multipass'} = 0;
            }
        # Ask the user what video bitrate he/she wants
            $self->{'v_bitrate'} = query_text('Video bitrate?',
                                              'int',
                                              $self->val('v_bitrate'));
        }
    # Loop, in case we need to verify ipod compatibility
        while (1) {
        # Query the resolution
            $self->query_resolution();
        # Warn about ipod resolution
            if ($self->val('ipod') && ($self->{'height'} > 480 || $self->{'width'} > 640)) {
                my $note = "WARNING:  Video larger than 640x480 will not play on an iPod.\n";
                die $note if ($is_cli);
                print $note;
                next;
            }
        # Done looping
            last;
        }
    }

    sub export {
        my $self    = shift;
        my $episode = shift;
    # Make sure this is set to anamorphic mode
        $self->{'aspect_stretched'} = 1;
    # Framerate
        my $standard = ($episode->{'finfo'}{'fps'} =~ /^2(?:5|4\.9)/) ? 'PAL' : 'NTSC';

        if (!defined $self->val('mp4_fps')) {
            $self->{'mp4_fps'} = "auto";
        }
            
        if ($standard eq 'PAL') {
            $self->{'out_fps'} = 25;
        }
        elsif ($self->val('mp4_fps') =~ /^23/) {
            $self->{'out_fps'} = 23.97;
        }
        elsif ($self->val('mp4_fps') =~ /^29/) {
            $self->{'out_fps'} = 29.97;
        }
        else {
            $self->{'out_fps'} = ($self->{'width'} > 320 || $self->{'height'} > 288) ? 29.97 : 23.97;
        }
    # Embed the title
        $safe_title = $episode->{'title'};
        if ($episode->{'subtitle'} ne 'Untitled') {
            $safe_title .= ' - '.$episode->{'subtitle'};
        }
        my $safe_title = shell_escape($safe_title);
        my $codec = 'mpeg4';

    # Build the common ffmpeg string
        my $ffmpeg_xtra  =
             ' -vcodec '.$codec
            .$self->param('bit_rate', $self->{'v_bitrate'})
            ;
    # Options required for the codecs separately
        $ffmpeg_xtra .= ' -flags +mv4+loop+aic'
                       .' -trellis 1'
                       .' -mbd 1'
                       .' -cmp 2 -subcmp 2'
                       ;
    # Some shared options
        if ($self->{'multipass'} || $self->{'vbr'}) {
            $ffmpeg_xtra .= $self->param('qcompress', 0.6)
                           .$self->param('qmax',      51)
                           .$self->param('max_qdiff', 4)
                           ;
        }
    # Dual pass?
        if ($self->{'multipass'}) {
        # Add all possible temporary files to the list
            push @tmpfiles, 'ffmpeg2pass-0.log';
        # Build the ffmpeg string
            print "First pass...\n";
            $self->{'ffmpeg_xtra'} = ' -pass 1'
                                    .$ffmpeg_xtra
                                    .' -f mp4';
            $self->SUPER::export($episode, '', 1);
        # Second Pass
            print "Final pass...\n";
            $ffmpeg_xtra = ' -pass 2 '
                          .$ffmpeg_xtra;
        }
    # Single Pass
        else {
            if ($self->{'vbr'}) {
                $ffmpeg_xtra .= ' -qmin '.$self->{'quantisation'};
            }
        }
    # Audio codec name changes between ffmpeg versions
        my $acodec = $self->can_encode('libfaac') ? 'libfaac' : 'aac';
    # Don't forget the audio, etc.
        $self->{'ffmpeg_xtra'} = $ffmpeg_xtra
                                ." -acodec $acodec -ar 48000 -async 1"
                                ." -strict experimental" if ($acodec eq "aac")
                                .$self->param('ab', $self->{'a_bitrate'});
    # Execute the (final pass) encode
        $self->SUPER::export($episode, '.mp4');
    }

1;  #return true

