XXX-0-0.noarch.rpm: XXX.spec XXX
	mkdir -p build/{SPECS,RPMS,BUILD,SRPMS,SOURCES}
	cp -f XXX build/SOURCES
	cp -f $< build/SPECS
	rpmbuild --define "_topdir `pwd`/build" -bb $<
	cp build/RPMS/noarch/XXX-0-0.noarch.rpm .

clean:
	/bin/rm -rf build
	rm -f XXX-0-0.noarch.rpm

DISTS=XXX.spec XXX rpmdb-brokenness.sh Makefile
dist: 
	v="`bash ./rpmdb-brokenness.sh --version`";			\
	mkdir -p rpmdb-brokenness-$$v;					\
	cp $(DISTS) rpmdb-brokenness-$$v;				\
	tar cvfj rpmdb-brokenness-$$v.tar.bz2 rpmdb-brokenness-$$v;
