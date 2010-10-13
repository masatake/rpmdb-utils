Name:		XXX
Version:	0
# Release:	0%{?dist}
Release:	0
Summary:	Dummy rpm used in rpmdb-brokenness.sh

Group:          Development/Tools
License:	BSD
Source0:	XXX
BuildRoot:	%{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
Buildarch:      noarch

%define __os_install_post true

%description
Dummy rpm used in Dummy rpm used in rpmdb-brokenness.sh

%prep
%setup -c -T

%build
rm -rf $RPM_BUILD_ROOT
cp %{SOURCE0} .


%install
install -D -m 755 XXX $RPM_BUILD_ROOT%{_sysconfdir}/XXX

%clean
rm -rf $RPM_BUILD_ROOT


%files
%defattr(-,root,root,-)
%{_sysconfdir}/XXX

%changelog
* Sun Jul 19 2009 Masatake YAMATO <yamato@redhat.com>
- Initial build
