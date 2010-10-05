#!/bin/bash
#
# Copyright (C) 2010 Red Hat, Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is fur-
# nished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FIT-
# NESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE 
# AUTHOR BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
# ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#
# Except as contained in this notice, the name of the author shall not be
# used in advertising or otherwise to promote the sale, use or other dealings
# in this Software without prior written authorization from the author.
#
function print_usage
{
    echo "Usage: "
    echo "$0 [--help|-h]"
    echo "$0 [--debug] [--dbpath=DBPATH] [--expected-rpms=#] [--dummy-rpm=RPM]"

    exit $1
}

function report_status
{
    local status=$1


    if ! [ "$status" = 0 ]; then
	echo "(abnormal exit)"
	return 1
    else
	echo "(normal exit)"
    fi
}



DBPATH=/var/lib/rpm

# 300
EXPECTED_RPMS=

DUMMY_RPM=
DEBUG=no

function parse_arguments
{
    while [ $# -gt 0 ]; do
	case "$1" in
	    --help|-h)
		print_usage 0 1>&2
		;;
	    --dbpath=*)
		DBPATH=${1/--dbpath=}
		if ! [ -d $DBPATH ]; then
		    echo "No such directory: $DBPATH" 1>&2
		    exit 1
		fi
		;;
	    --expected-rpms=*)
		EXPECTED_RPMS=${1/--expected-rpms=}
		;;
	    --dummy-rpm=*)
		DUMMY_RPM=${1/--dummy-rpm=}
		if ! [ -f $DUMMY_RPM ]; then
		    echo "No such file: $DUMMY_RPM" 1>&2
		    exit 1
		fi
		;;
	    --debug)
		DEBUG=yes
		;;
	    --*)
		echo "No such option: $1" 1>&2 
		print_usage 1 1>&2
		;;
	    *)
		break
		;;
	esac
	shift
    done

    if [ $# -gt 0 ]; then
	print_usage 1 1>&2
    fi
}

function check_qa_on_original
{
    local db=$1
    local tmp=$2
    local name=${3:-$FUNCNAME}
    local status

    printf "running rpm -qa --dbpath $db..."
    rpm -qa --dbpath $db > $tmp/stdout 2>$tmp/stderr
    status=$?
    printf "$status"

    echo $status > $tmp/status
    report_status $status

    printf "the number of rpms..."
    local lines=$(wc -l < $tmp/stdout)
    printf $lines

    if [ -n "$EXPECTED_RPMS" ]; then
	if [ "$EXPECTED_RPMS" -gt "$lines" ]; then
	    echo "(too few)"
	    return 0
	else
	    echo "(enough)"
	    return 0
	fi
    else
	echo "(use as default)"
	EXPECTED_RPMS=$lines
	return 0
    fi
}

function check_qa_on_copied
{
    check_qa_on_original $1 $2 $FUNCNAME
    return $?
}

function check_qa_on_copied_other_than_db00X
{
    check_qa_on_original $1 $2 $FUNCNAME
    return $?
}

function check_qa_on_copied_Packages_only
{
    check_qa_on_original $1 $2 $FUNCNAME
    return $?
}

function check_fcntl_lock_target
{
    local db=$1
    local lockfile

    lockfile=$db/__db.000
    printf "fcntl locking file..."
    if [ -f $lockfile ]; then
	echo $lockfile
	return 0
    fi
	
    lockfile="$(dirname $(dirname $db))/lock/rpm/transactions"
    if [ -f $lockfile ]; then
	echo $lockfile
	return 0
    fi

    echo "unknown"
    return 0
}

function check_region_files
{
    local db=$1
    local rfile

    printf "region files..."
    for rfile in $db/__db.00[1-3]; do
	if [ -f $rfile ]; then
	    printf " $(basename $rfile)"
	else
	    printf "no region file"
	    break
	fi
    done
    echo
}

function check_install_on_copied
{
    local db=$1
    local tmp=$2
    local pkg=$3
    local name=$(rpm -qp --queryformat "%{name}\n" "$pkg")

    printf "running rpm -ivh --justdb --dbpath $db $pkg..."
    rpm -i --justdb --dbpath $db $pkg > $tmp/stdout-i 2>  $tmp/stderr-i
    status=$?
    printf "$status"
    echo $status > $tmp/status
    report_status $status

    printf "checking rpm -qa --dbpath $db..."
    if (rpm -qa --dbpath $db 2>/dev/null | grep "^$name") > /dev/null 2>&1; then
	echo found \"$name\"
    else
	echo not found \"$name\"
    fi
    return 0
}

function check_install_on_copied_other_than_db00X
{
    check_install_on_copied $1 $2 $3 $4
    return $?
}

function check_install_on_copied_Packages_only
{
    check_install_on_copied $1 $2 $3 $4
    return $?
}

function check_rebuilddb_on_copied
{
    local db=$1
    local tmp=$2
    local pkg=$3

    printf "running rpm --rebuilddb --dbpath $db..."
    rpm --rebuilddb --dbpath $db > $tmp/stdout-rebuilddb 2> $tmp/stderr-rebuilddb
    status=$?
    printf "$status"
    echo $status > $tmp/status-rebuilddb
    report_status $status

    if ! [ $status = 0 ]; then
	return $status
    fi

    if ! check_qa_on_original $db $tmp $FUNCNAME; then
	return $?
    fi

    if [ -n "$pkg" ];then 
	if ! check_install_on_copied $db $tmp $pkg; then
	    return $?
	fi
    fi
    return 0
}

function check_rebuilddb_on_copied_other_than_db00X
{
    check_rebuilddb_on_copied $1 $2 $3
    return $?
}


function main
{
    local surgery=$(mktemp -d)
    if [ "$DEBUG" != "yes" ]; then
	trap "chmod -R u+w $surgery; /bin/rm -rf $surgery" 0    
    fi
    
    local func

    
    parse_arguments "$@"

    func=fcntl_lock_target
    if ! check_${func} $DBPATH; then
	return $?
    fi

    func=region_files
    if ! check_${func} $DBPATH; then
	return $?
    fi

    func=qa_on_original
    mkdir ${surgery}/$func
    if ! check_$func $DBPATH ${surgery}/$func; then
	return $?
    fi

    printf "conducting installation check..."
    if [ -n "$DUMMY_RPM" ]; then
	echo "with $DUMMY_RPM"
    else
	echo "disabled"
    fi


    func=qa_on_copied
    mkdir -p ${surgery}/$func/db
    cp -r $DBPATH/* ${surgery}/$func/db
    if ! check_$func ${surgery}/$func/db ${surgery}/$func; then
	return $?
    fi
    
    if [ -n "$DUMMY_RPM" ]; then
	func=install_on_copied
	mkdir -p ${surgery}/$func/db
	cp -r $DBPATH/* ${surgery}/$func/db
	if ! check_$func ${surgery}/$func/db ${surgery}/$func $DUMMY_RPM; then
	    return $?
	fi
    fi

    func=rebuilddb_on_copied
    mkdir -p ${surgery}/$func/db
    cp -r $DBPATH/* ${surgery}/$func/db
    if ! check_$func ${surgery}/$func/db ${surgery}/$func $DUMMY_RPM; then
	return $?
    fi

    func=qa_on_copied_other_than_db00X
    mkdir -p ${surgery}/$func/db
    cp -r $DBPATH/* ${surgery}/$func/db
    rm -f ${surgery}/$func/db/__db00*
    if ! check_$func ${surgery}/$func/db ${surgery}/$func; then
	return $?
    fi
    
    if [ -n "$DUMMY_RPM" ]; then
	func=install_on_copied_other_than_db00X
	mkdir -p ${surgery}/$func/db
	cp -r $DBPATH/* ${surgery}/$func/db
	rm -f ${surgery}/$func/db/__db00*
	if ! check_$func ${surgery}/$func/db ${surgery}/$func $DUMMY_RPM; then
	    return $?
	fi
    fi

    func=rebuilddb_on_copied_other_than_db00X
    mkdir -p ${surgery}/$func/db
    cp -r $DBPATH/* ${surgery}/$func/db
    rm -f ${surgery}/$func/db/__db00*
    if ! check_$func ${surgery}/$func/db ${surgery}/$func $DUMMY_RPM; then
	return $?
    fi
    
    func=qa_on_copied_Packages_only
    mkdir -p ${surgery}/$func/db
    cp -r $DBPATH/Packages ${surgery}/$func/db
    if ! check_$func ${surgery}/$func/db ${surgery}/$func; then
	return $?
    fi

    if [ -n "$DUMMY_RPM" ]; then
	func=install_on_copied_Packages_only
	mkdir -p ${surgery}/$func/db
	cp -r $DBPATH/Packages ${surgery}/$func/db
	if ! check_$func ${surgery}/$func/db ${surgery}/$func $DUMMY_RPM; then
	    return $?
	fi
    fi

    # DUMP LEVEL
}

main "$@"


