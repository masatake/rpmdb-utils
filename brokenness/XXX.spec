Name:		XXX
Version:	0
Release:	0%{?dist}
Summary:	Dummy rpm used in rpmdb-brokenness.sh

Group:          Development/Tools
License:	BSD
Source0:	rpmdb-brokenness.sh
BuildRoot:	%{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
Buildarch:      noarch


%description
Dummy rpm used in rpmdb-brokenness.sh

%prep
%setup -c -T

%build
rm -rf $RPM_BUILD_ROOT
cp %{SOURCE0} .


%install
install -D -m 755 rpmdb-brokenness.sh $RPM_BUILD_ROOT%{_bindir}/rpmdb-brokenness.sh

%clean
rm -rf $RPM_BUILD_ROOT


%files
%defattr(-,root,root,-)
%{_bindir}/rpmdb-brokenness.sh

%changelog
* Sun Jul 19 2009 Masatake YAMATO <yamato@redhat.com>
- Initial build
