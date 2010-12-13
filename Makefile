#
# Makefile for installing nuvexport
#

BINS	          = nuvexport nuvinfo

CONF              = nuvexportrc

EXPORT_MODULES	  = export/generic.pm         \
		    export/ffmpeg.pm          \
		    export/mencoder.pm        \
		    export/NUV_SQL.pm         \
		    export/ffmpeg/XviD.pm     \
		    export/ffmpeg/DivX.pm     \
		    export/ffmpeg/MP3.pm      \
		    export/ffmpeg/ASF.pm      \
		    export/ffmpeg/DVD.pm      \
		    export/ffmpeg/PSP.pm      \
		    export/ffmpeg/MP4.pm      \
		    export/ffmpeg/H264.pm     \
		    export/mencoder/XviD.pm   \
		    export/mencoder/H264MP3.pm \
                    export/mencoder/H264AAC.pm 
MODULE_SUBDIRS    = ffmpeg    \
		    mencoder
MYTHTV_MODULES	  = mythtv/nuvinfo.pm \
		    mythtv/recordings.pm
NUVEXPORT_MODULES = nuv_export/help.pm         \
		    nuv_export/shared_utils.pm \
		    nuv_export/task.pm         \
		    nuv_export/cli.pm          \
		    nuv_export/ui.pm
MODULES		  = ${EXPORT_MODULES} ${MYTHTV_MODULES} ${NUVEXPORT_MODULES}

NUVEXPORT_LINKS   = divx dvcd dvd mp3 nuvsql svcd vcd asf xvid

OWNER	=

INSTALL	= /usr/bin/install

prefix=/usr/local
bindir=${prefix}/bin
datadir=${prefix}/share
sysconfdir=/etc

MODDIR=${datadir}/nuvexport

default:
	@echo "Use \"make install\" to install the new version and \"make uninstall\" to remove this version"

install:
	# First the binaries
	@for i in ${BINS} ; do \
	   ${INSTALL} -Dv ${OWNER} -m 0755 $$i ${bindir}/$$i; \
	done
	# Then the config file(s)
	@for i in ${CONF} ; do \
	   if [ -e "${sysconfdir}"/"$$i" ]; then \
	      ${INSTALL} -Dv ${OWNER} -m 0755 $$i ${sysconfdir}/$$i.dist; \
	   else \
	      ${INSTALL} -Dv ${OWNER} -m 0755 $$i ${sysconfdir}/$$i; \
	   fi \
	done
	# Install the mode symlinks
	@for i in ${NUVEXPORT_LINKS} ; do \
	   ln -fs nuvexport ${bindir}/nuvexport-$$i; \
	done
	# Install the modules
	@for i in ${MODULES} ; do \
	   ${INSTALL} -Dv ${OWNER} -m 0755 $$i ${MODDIR}/$$i; \
	done

uninstall:
	# First the binaries
	@for i in ${BINS} ; do \
	    rm -f ${bindir}/$$i; \
	done
	# Remove the mode symlinks
	@for i in ${NUVEXPORT_LINKS} ; do \
	    rm -f ${bindir}/nuvexport-$$i; \
	done
	# Remove the modules
	@for i in ${MODULES} ; do \
	    rm -f ${MODDIR}/$$i; \
	done

