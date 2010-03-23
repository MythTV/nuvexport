#
# $Date$
# $Revision$
# $Author$
#
#  export::transcode::DVCD
#  Maintained by Gavin Hurlbut <gjhurlbu@gmail.com>
#

package export::transcode::DVCD;
    use base 'export::transcode';

# Load the myth and nuv utilities, and make sure we're connected to the database
    use nuv_export::shared_utils;
    use nuv_export::cli;
    use nuv_export::ui;
    use mythtv::recordings;

# Load the following extra parameters from the commandline

    sub new {
        my $class = shift;
        my $self  = {
                     'cli'      => qr/\bdvcd\b/i,
                     'name'     => 'Export to DVCD (VCD with 48kHz audio for making DVDs)',
                     'enabled'  => 1,
                     'errors'   => [],
                     'defaults' => {},
                    };
        bless($self, $class);

    # Initialize the default parameters
        $self->load_defaults();

    # Initialize and check for transcode
        $self->init_transcode();

    # Make sure that we have an mplexer
        find_program('mplex')
            or push @{$self->{'errors'}}, 'You need mplex to export a dvcd.';

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
    }

    sub export {
        my $self    = shift;
        my $episode = shift;
    # Force to 4:3 aspect ratio
        $self->{'out_aspect'} = 1.3333;
        $self->{'aspect_stretched'} = 1;
    # PAL or NTSC?
        my $standard = ($episode->{'finfo'}{'fps'} =~ /^2(?:5|4\.9)/) ? 'PAL' : 'NTSC';
        $self->{'width'} = 352;
        $self->{'height'} = ($standard eq 'PAL') ? '288' : '240';
        $self->{'out_fps'} = ($standard eq 'PAL') ? 25 : 29.97;
        my $ntsc = ($standard eq 'PAL') ? '' : '-N';
    # Build the transcode string
        $self->{'transcode_xtra'} = " -y mpeg2enc,mp2enc"
                                   .' -F 1 -E 48000 -b 224';
    # Add the temporary files that will need to be deleted
        push @tmpfiles, $self->get_outfile($episode, ".$$.m1v"), $self->get_outfile($episode, ".$$.mpa");
    # Execute the parent method
        $self->SUPER::export($episode, ".$$");
    # Multiplex the streams
        my $command = "$NICE mplex -f 1 -C"
                      .' -o '.shell_escape($self->get_outfile($episode, '.mpg'))
                      .' '.shell_escape($self->get_outfile($episode, ".$$.m1v"))
                      .' '.shell_escape($self->get_outfile($episode, ".$$.mpa"));
        system($command);
    }

1;  #return true

# vim:ts=4:sw=4:ai:et:si:sts=4
