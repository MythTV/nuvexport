#
# $Date$
# $Revision$
# $Author$
#
#  export::mencoder::H264
#  Copied from transcode.pm
#  and modified by Ryan Dearing <mythtv@mythtv.us>
#

package export::mencoder::H264AAC;
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
                     'cli'      => qr/\bh264-aac\b/i,
                     'name'     => 'Export to H.264/AAC (using mencoder)',
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

    # Do we have libfaac support in mplayer?
        if (!$self->have_codec('x264')) {
            push @{$self->{'errors'}}, "Your mencoder installation doesn't support encoding using libx264.";
        }
        if (!$self->have_codec('faac')) {
            push @{$self->{'errors'}}, "Your mencoder installation doesn't support encoding using libfaac.";
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
    # Video Bitrate
        $self->{'v_bitrate'} = query_text('Video bitrate?',
                                          'int',
                                          $self->val('v_bitrate'));                                          
        
    # Query the resolution
        $self->query_resolution();
    }

    sub export {
        my $self    = shift;
        my $episode = shift;
    # Build the mencoder string
        my $params = " -vf scale=$self->{'width'}:$self->{'height'}";
        # Add the temporary file to the list
            push @tmpfiles, "/tmp/h264.$$.log";
        # Back up the path and use /dev/null for the first pass
            my $path_bak = $self->{'path'};
            $self->{'path'} = '/dev/null';
        # First pass
            print "First pass...\n";
            $self->{'mencoder_xtra'} = "  $params"
                                       ." -passlogfile /tmp/h264.$$.log"
                                       ." -oac copy"
                                       ." -ovc x264 -x264encopts pass=1:bitrate=$self->{'v_bitrate'}:turbo=2:me=umh:me_range=24:dct_decimate:nointerlaced:no8x8dct:nofast_pskip:trellis=0:partitions=p8x8,b8x8,i4x4:mixed_refs:keyint=300:keyint_min=30:frameref=3:bframes=3:b_adapt:b_pyramid=none:weight_b:subq=7:chroma_me:nocabac:deblock:nossim:nopsnr:level_idc=31:threads=auto";
            $self->SUPER::export($episode, '', 1);
        # Restore the path
            $self->{'path'} = $path_bak;
        # Second pass
            print "Final pass...\n";
            $self->{'mencoder_xtra'} = " $params"
                                       ." -oac faac -faacopts mpeg=4:br=$self->{'a_bitrate'}:object=2  " 
                                       ." -passlogfile /tmp/h264.$$.log"
                                       ." -ovc x264 -x264encopts pass=2:bitrate=$self->{'v_bitrate'}:me=umh:me_range=24:dct_decimate:nointerlaced:no8x8dct:nofast_pskip:trellis=0:partitions=p8x8,b8x8,i4x4:mixed_refs:keyint=300:keyint_min=30:frameref=3:bframes=3:b_adapt:b_pyramid=none:weight_b:subq=7:chroma_me:nocabac:deblock:nossim:nopsnr:level_idc=31:threads=auto";        
        $self->SUPER::export($episode, '.avi');
    }

1;  #return true

# vim:ts=4:sw=4:ai:et:si:sts=4
