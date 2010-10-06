Name:		XXX
Version:	0
# Release:	0%{?dist}
Release:	0
Summary:	Dummy rpm used in rpmdb-brokenness.sh

Group:          Development/Tools
License:	BSD
Source0:	XXX.sh
BuildRoot:	%{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
Buildarch:      noarch


%description
Dummy rpm used in XXX.sh

%prep
%setup -c -T

%build
rm -rf $RPM_BUILD_ROOT
cp %{SOURCE0} .


%install
install -D -m 755 XXX.sh $RPM_BUILD_ROOT%{_bindir}/XXX.sh

%clean
rm -rf $RPM_BUILD_ROOT


%files
%defattr(-,root,root,-)
%{_bindir}/XXX.sh

%changelog
* Sun Jul 19 2009 Masatake YAMATO <yamato@redhat.com>
- Initial build
