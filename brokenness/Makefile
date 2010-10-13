XXX-0-0.noarch.rpm: XXX.spec XXX
	mkdir -p build/{SPECS,RPMS,BUILD,SRPMS,SOURCES}
	cp -f XXX build/SOURCES
	cp -f $< build/SPECS
	rpmbuild --define "_topdir `pwd`/build" -bb $<
	cp build/RPMS/noarch/XXX-0-0.noarch.rpm .

clean:
	/bin/rm -rf build
	rm -f XXX-0-0.noarch.rpm
