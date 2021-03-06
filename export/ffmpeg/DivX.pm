#
# $Date$
# $Revision$
# $Author$
#
#  export::ffmpeg::DivX
#  Maintained by Gavin Hurlbut <gjhurlbu@gmail.com>
#

package export::ffmpeg::DivX;
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

    sub new {
        my $class = shift;
        my $self  = {
                     'cli'      => qr/\bdivx\b/i,
                     'name'     => 'Export to DivX',
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

    # Initialize and check for ffmpeg
        $self->init_ffmpeg();

    # Can we even encode divx?
        if (!$self->can_encode('mpeg4')) {
            push @{$self->{'errors'}}, "Your ffmpeg installation doesn't support encoding to mpeg4.";
        }
        if (!$self->can_encode('mp3') && !$self->can_encode('libmp3lame')) {
            push @{$self->{'errors'}}, "Your ffmpeg installation doesn't support encoding to mp3 audio.";
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
    # Default bitrates and resolution
        $self->{'defaults'}{'a_bitrate'} = 128;
        $self->{'defaults'}{'v_bitrate'} = 960;
        $self->{'defaults'}{'width'}     = 624;
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
    # Query the resolution
        $self->query_resolution();
    }

    sub export {
        my $self    = shift;
        my $episode = shift;
    # Make sure we have the framerate
        $self->{'out_fps'} = $episode->{'finfo'}{'fps'};
    # Dual pass?
        if ($self->{'multipass'}) {
        # Add the temporary file to the list
            push @tmpfiles, "/tmp/divx.$$.log";
        # Back up the path and use /dev/null for the first pass
            my $path_bak = $self->{'path'};
            $self->{'path'} = '/dev/null';
        # First pass
            print "First pass...\n";
            $self->{'ffmpeg_xtra'} = ' -vcodec mpeg4'
                                   . $self->param('bit_rate', $self->{'v_bitrate'})
                                   . $self->param('rc_max_rate', (2 * $self->{'v_bitrate'}))
                                   . $self->param('bit_rate_tolerance', 32)
                                   . ' -bufsize 65535'
                                   . ' -lumi_mask 0.05 -dark_mask 0.02 -scplx_mask 0.5'
                                   . ' -flags mv4'
                                   . ' -flags part'
                                   . ' -vtag divx'
                                   . " -pass 1 -passlogfile '/tmp/divx.$$.log'"
                                   . ' -f avi';
            $self->SUPER::export($episode, '');
        # Restore the path
            $self->{'path'} = $path_bak;
        # Second pass
            print "Final pass...\n";
            $self->{'ffmpeg_xtra'} = ' -vcodec mpeg4'
                                   . $self->param('bit_rate', $self->{'v_bitrate'})
                                   . $self->param('rc_max_rate', (2 * $self->{'v_bitrate'}))
                                   . $self->param('bit_rate_tolerance', 32)
                                   . ' -bufsize 65535'
                                   . ' -lumi_mask 0.05 -dark_mask 0.02 -scplx_mask 0.5'
                                   . ' -flags mv4'
                                   . ' -flags part'
                                   . ' -vtag divx'
                                   . ' -acodec '
                                   .($self->can_encode('libmp3lame') ? 'libmp3lame' : 'mp3')
                                   .' '.$self->param('ab', $self->{'a_bitrate'})
                                   . " -pass 2 -passlogfile '/tmp/divx.$$.log'"
                                   . ' -f avi';
        }
    # Single Pass
        else {
            $self->{'ffmpeg_xtra'} = ' -vcodec mpeg4'
                                   . $self->param('bit_rate', $self->{'v_bitrate'})
                                   . ($self->{'vbr'}
                                       ? " -qmin $self->{'quantisation'}"
                                        . ' -qmax 31'
                                        . $self->param('rc_max_rate', (2 * $self->{'v_bitrate'}))
                                        . $self->param('bit_rate_tolerance', 32)
                                        . ' -bufsize 65535'
                                       : '')
                                   . ' -lumi_mask 0.05 -dark_mask 0.02 -scplx_mask 0.5'
                                   . ' -flags mv4'
                                   . ' -flags part'
                                   . ' -vtag divx'
                                   . ' -acodec '
                                   .($self->can_encode('libmp3lame') ? 'libmp3lame' : 'mp3')
                                   .' '.$self->param('ab', $self->{'a_bitrate'})
                                   . ' -f avi';
        }
    # Execute the (final pass) encode
        $self->SUPER::export($episode, '.avi');
    }

1;  #return true

# vim:ts=4:sw=4:ai:et:si:sts=4
