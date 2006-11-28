#
# RPM spec file for nuvexport
#

Name:       nuvexport
Version:    0.4
Release:    0.20061117.svn
License:    GPL
Summary:    mythtv nuv video file conversion script
URL:        http://forevermore.net/nuvexport/
Group:      Applications/Multimedia
Source:     %{name}-%{version}-%{release}.tar.bz2
BuildRoot:  %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)

# This is a perl script -- no arch needed
BuildArch:  noarch

# Standard nuvexport modules:
Requires:  perl >= 5.6
Requires:  perl-DateManip
Requires:  perl-DBD-MySQL
Requires:  perl-DBI
Requires:  perl-MythTV >= 0.21
Requires:  transcode   >= 0.6.12
Requires:  ffmpeg      >= 0.4.9
Requires:  mjpegtools  >= 1.6.2
Requires:  mplayer

Requires:  /usr/bin/id3tag

# Provides some of its own perl modules -- rpm complains if this isn't included
Provides:  perl(nuvexport::shared_utils)

%description
nuvexport is a perl script wrapper to several encoders, which is capable of
letting users choose shows from their MythTV database and convert them to one
of several different formats, including SVCD/DVD mpeg and XviD avi.

%prep
%setup

%build

%install
[  %{buildroot} != "/" ] && rm -rf %{buildroot}
%{makeinstall}

%clean
[  %{buildroot} != "/" ] && rm -rf %{buildroot}
rm -f $RPM_BUILD_DIR/file.list.%{name}

%files
%defattr(-, root, root)
%{_bindir}/*
%{_datadir}/nuvexport/
%config %{_sysconfdir}/*
%doc COPYING

%changelog
* Tue Dec 7  2004 Chris Petersen <rpm@forevermore.net>
- Built first spec
