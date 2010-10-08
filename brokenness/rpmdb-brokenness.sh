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
# Author: Masatake YAMATO <yamato@redhat.com>
#
DBPATH=${DBPATH:-/var/lib/rpm}
EXPECTED_RPMS=${EXPECTED_RPMS:-100}
DUMMY_RPM=
DEBUG=${DEBUG:-no}
REPORT_LEVEL=${REPORT_LEVEL:-line}
IGNORE_ERROR=


CHECKERS="
          rpm_running
          fcntl_lock_target_db000
          fcntl_lock_target_transactions
          region_file_1
          region_file_2
          region_file_3
          rpm_qa_on_original
          expected_rpms_on_original
          install_on_copied
          verify_installation_on_copied
"


function print_usage
{
    echo "Usage: "
    echo "	$0 [--help|-h]"
    echo "	$0 [--debug] [--ignore-error] \\"
    echo "	   [[--report-level=line|quiet|verbose]|--verbose|--quiet] \\"
    echo "	   [--dbpath=DBPATH] [--expected-rpms=#] [--dummy-rpm=RPM] \\"
    echo "         [--dont-check=A,B..]"
    echo "	$0 [--debug] [--decode=...]"
    echo ""
    echo "Default value:"
    echo "	DBPATH: $DPBATH"
    echo "	EXPECTED_RPMS: $EXPECTED_RPMS"
    echo "	REPORT_LEVEL: $REPORT_LEVEL"
    echo ""
    echo "Exit status:"
    echo "	0: No brokenness detected in any checkers"
    echo "	1: Error occurred in script execution"
    echo "	2...N: Brokenness detected in the (N-2)th checker, zero indexed" 
    echo ""
    echo "Checkers:"
    for c in $CHECKERS; do
	describe $c
    done
    echo ""
    echo "Output of line reporter:"
    for c in . _ B e s c t; do
	printf "	$c => %s\n" "$(decode_result $c)"
    done
    echo ""
    exit $1
}

# 
# Utilities
#
function verbose_p
{
    test $REPORT_LEVEL = verbose
    return $?
}

function quiet_p
{
    test $REPORT_LEVEL = quiet
    return $?
}

function line_p
{
    test $REPORT_LEVEL = line
    return $?
}

function member_p
{
    local elt=$1
    shift
    for x in "$@"; do
	if [ "$x" = "$elt" ]; then
	    return 0
	fi
    done
    
    return 1
}

function index_of
{
    local found
    local index=0
    local elt=$1
    shift

    for x in "$@"; do
	if [ "$x" = "$elt" ]; then
	    echo $index
	    return 0
	fi
	index=$(( $index + 1 ))
    done
    
    return 1
}

function dprintf
{
    verbose_p && printf "$@"
}

function family_for
{
    local checker=$1

    echo "$(eval echo \$${checker}__family)"
    return 0
}

#
# Describe
#
function describe
{
    local checker=$1
    local family=$(family_for $checker)
    
    printf "	%s/%s:\n		%s\n" "${family}" "${checker}" "$(eval echo \$${checker}__desc)"
}

#
# Decode
#
function decode
{
    local result="$1"
    local r
    local c
    local checkers="${CHECKERS}"
    local status=0


    for c in $checkers; do
	r=${result:0:1}
	result=${result:1}

	if [ -z "$c" ]; then
	    {
		echo "The argument for decode is too short: $result"
		return 1
	    } 2>&1
	fi

	if ! decode_1 $c $r; then
	    status=1
	fi
    done
    
    return $status
    
}

function decode_result
{
    local result=$1
    local msg
    local status=0

    case $result in
	.)
	    msg="good"
	    # TODO This should be "no corruption found"
	    ;;
	_)
	    msg="not checked"
	    ;;
	e)
	    msg="error"
	    ;;
	c)
	    msg="error in checker function"
	    ;;
	s)
	    msg="error in setup function"
	    ;;
	t)
	    msg="error in teardown function"
	    ;;
	B)
	    msg="broken"
	    ;;
	*)
	    status=1
	    msg="unknown"
	    ;;
	
    esac

    echo $msg
    return $status
}

function decode_1
{
    local checker=$1
    local result=$2
    local status=0
    local family
    local msg

    family=$(family_for $checker)
    msg=$(decode_result $result)
    status=$?

    printf "%s/%s...%s\n" "$family" "$checker" "$msg"

    return $status
}


#
# Check
#
# ----------------------------------------------------------------------
# argument:
# 1: DB
# 2: TMPDIR
# 3: DUMMY PKG or -
# 4: EXPECTED_RPMS
# 
# ----------------------------------------------------------------------
# return value:
# 0: found no brokenness 
# 1: error occurred
# 2: found brokenness
# 3: not checked
#
function check
{
    local func
    local checker
    local status
    local family


    checker=$1
    shift


    family=$(family_for $checker)
    dprintf "* %s/%s  %s\n" "$family" "$checker" "$*"
    if verbose_p; then
	echo -n "  "
	echo $(eval echo \$${checker}__desc)
    fi
    
    func=${checker}__setup
    dprintf "	Setup..."
    if type $func > /dev/null 2>&1  &&  ! $func "$@"; then
	eval ${c}__result=s
	dprintf "error\n"
	return 1
    fi
    dprintf "ok\n"

    func=${checker}__check
    dprintf "	Check..."
    $func "$@"
    status=$?
    case $status in
	0)
	    eval ${c}__result=.
	    dprintf "good\n" 
	    ;;
	1)
	    eval ${c}__result=c
	    dprintf "error\n" 
	    ;;
	2)
	    eval ${c}__result=B
	    dprintf "broken\n" 
	    ;;
	3)
	    eval ${c}__result=_
	    dprintf "not checked\n"
	    ;;
    esac

    
    dprintf "	Teardown..."
    func=${checker}__teardown
    if type $func > /dev/null 2>&1  && ! $func "$@"; then
	eval ${c}__result=t
	dprintf "error\n"
	return 1
    fi
    dprintf "ok\n"


    return $status
}

#
# Main
# 
function parse_arguments
{
    for c in $CHECKERS; do
	local d="$(eval echo \$${c}__desc)"
	test -z "$d" && eval ${c}__desc="\"NO DOCUMENT\""
    done

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
	    --decode=*)
	       local result=${1/--decode=}
	       decode "$result"
	       exit $?
	       ;;
	    --debug)
		DEBUG=yes
		REPORT_LEVEL=verbose
		set -x
		;;
	    --dummy-rpm=*)
		DUMMY_RPM=${1/--dummy-rpm=}
		# TODO
		if ! [ -f $DUMMY_RPM ]; then
		    echo "No such file: $DUMMY_RPM" 1>&2
		    exit 1
		fi
		;;
	    --expected-rpms=*)
		EXPECTED_RPMS=${1/--expected-rpms=}
		# TODO: Check value
		;;
	    --ignore-error)
	       IGNORE_ERROR=yes
	       ;;
	    --quiet)
	       REPORT_LEVEL=quiet
	       ;;
            --report-level=*)
	       REPORT_LEVEL=${1/--report-level=}
	       if ! member_p $REPORT_LEVEL quiet line verbose; then
		   {
		       echo "No such report level: $REPORT_LEVEL"
		       print_usage 1 
		   } 1>&2
	       fi
	       ;;
	    --verbose)
	       REPORT_LEVEL=verbose
	       ;;
	    --*)
	       {
		   echo "No such option: $1" 
		   print_usage 1 
	       } 1>&2
		;;
	    *)
		break
		;;
	esac
	shift
    done

    if [ $# -gt 0 ]; then
	{
	    echo "Unexpected argument(s): $@"
	    print_usage 1
	} 1>&2
    fi
}

function report_line
{
    local checker=$1
    local result=$2

    if ( [ "$result" = s ] \
      || [ "$result" = c ] \
      || [ "$result" = t ] ); then
	result=e
    fi
    printf "%s" "$result"
    return 0
}

function report_verbose
{
    decode_1 $1 $2

    return $?
}

function main
{
    local surgery
    local found_error=
    local found_brokenness=

    parse_arguments "$@"

    surgery=$(mktemp -d "/tmp/rpmdb_brokenness.XXXXX")

    if [ "$DEBUG" != "yes" ]; then
	trap "chmod -R u+w $surgery; /bin/rm -rf $surgery" 0    
    else
	printf "surgery: %s\n" "$surgery"
    fi

    local checkers="$CHECKERS"
    
    for c in $checkers; do
	eval ${c}__result=_
    done

    for c in $checkers; do
	local family

	family=$(family_for $c)
	if [ -z "$family" ]; then
	    family="$c"
	fi
	mkdir -p "${surgery}/${family}"
	mkdir -p "${surgery}/${c}"

	check $c $DBPATH "$surgery" ${DUMMY_RPM:--} "${EXPECTED_RPMS}"
	case $? in
	    0)
		:
		;;
	    1)
		found_error=$c
		;;
	    2)
		if [ -z "$found_brokenness" ]; then
		    found_brokenness=$c
		fi
		;;
	esac
	
	if [ -n "$found_error" ]; then
	    if [ -z "$IGNORE_ERROR" ]; then
		break
	    fi

	fi
    done

    case $REPORT_LEVEL in
	quiet)
	    :
	    ;;
	line)
	    for c in $checkers; do
		report_$REPORT_LEVEL $c $(eval 'echo $'${c}__result)
	    done
	    if [ -n "$found_error" ]; then
		echo -n ": $found_error<error>"
	    fi
	    if [ -n "$found_brokenness" ]; then
		echo -n ": $found_brokenness<broken>"
	    fi
	    echo
	    ;;
	verbose)
	    for c in $checkers; do
		report_$REPORT_LEVEL $c $(eval 'echo $'${c}__result)
	    done
	    ;;
    esac

    if [ -n "$found_error" ]; then
	return 1
    fi

    if [ -n "found_brokenness" ]; then
	local index=$(index_of "$found_brokenness" $checkers)
	return $(( $index + 2 ))
    fi

    return 0
}


#
# Checkers
#
function __file_existence__desc
{
    local obj=$1
    printf "Checking whether %s exists or not" $obj
}

function __file_existence__check 
{
    local file=$1
    if [ -e $file ]; then
	return 2
    fi
    return 0
}

rpm_running__desc="Checking whether another rpm process is running or not"
function rpm_running__check
{
    if pidof rpm > /dev/null 2>&1; then
	return 1
    fi
    return 0
}

fcntl_lock_target_db000__desc=$(__file_existence__desc __db.000)
function fcntl_lock_target_db000__check
{
    local db=$1

    __file_existence__check "$db/__db.000"
    return $?
}

fcntl_lock_target_transactions__desc=$(__file_existence__desc /var/lock/rpm/transactions)
function fcntl_lock_target_transactions__check
{
    local db=$1

    __file_existence__check "$(dirname $(dirname $db))/lock/rpm/transactions"
    return $?
    
}

function __region_file__check
{
    local db=$1
    local n=$2
    __file_existence__check "$db/__db.00$n"
    return $?
}

region_file_1__desc=$(__file_existence__desc __db.001)
function region_file_1__check
{
    __region_file__check $1 1
    return $?
}
region_file_2__desc=$(__file_existence__desc __db.002)
function region_file_2__check
{
    __region_file__check $1 2
    return $?
}
region_file_3__desc=$(__file_existence__desc __db.003)
function region_file_3__check
{
    __region_file__check $1 3
    return $?
}

function __rpm_qa__check
{
    local db=$1
    local tmp=$2
    local dummy_pkg=$3
    local expected_rpms=$4
    local func=$5


    if ! rpm -qa --dbpath $db > $tmp/${func}_stdout 2>$tmp/${func}_stderr; then
	return 2
    fi

    return 0
}

rpm_qa_on_original__desc="Checking exit status of 'rpm -qa' on the original rpmdb"
function rpm_qa_on_original__check
{
    __rpm_qa__check "$@" qa_on_original
    return $?
}

function __expected_rpms__check
{
    local db=$1
    local tmp=$2
    local dummy_pkg=$3
    local expected_rpms=$4
    local func=$5
    local lines

    if ! [ -r "$tmp/${func}_stdout" ]; then
	return 1
    fi
    
    lines=$(wc -l < "$tmp/${func}_stdout")
    if [ "$lines" -gt $expected_rpms ]; then
	return 0
    else
	return 2
    fi

}

expected_rpms_on_original__desc="Checking the lines of output of 'rpm -qa' on the original rpmdb"
function expected_rpms_on_original__check
{
    __expected_rpms__check "$@" qa_on_original
    return $?
}


function __copy_db__setup
{
    local db=$1
    local tmp=$2
    local dummy_pkg=$3
    local expected_rpms=$4
    local func=$5    

    
    if [ "$dummy_pkg" = "-" ]; then
	return 0
    fi
    
    mkdir -p "$tmp/$func/db"
    cp --archive $db/* "$tmp/$func/db"
    return $?
}

function __install__check
{
    local db=$1
    local tmp=$2
    local dummy_pkg=$3
    local expected_rpms=$4
    local func=$5    

    if [ "$dummy_pkg" = "-" ]; then
	return 3
    fi

    db="$tmp/$func/db"
    if rpm -i --justdb --dbpath $db $dummy_pkg > $tmp/${func}/stdout 2> $tmp/${func}/stderr; then
	return 0
    else
	return 2
    fi
}

function __verify_installation__check
{
    local db=$1
    local tmp=$2
    local dummy_pkg=$3
    local expected_rpms=$4
    local func=$5    
    local name


    if [ "$dummy_pkg" = "-" ]; then
	return 3
    else
	name=$(rpm -qp --queryformat "%{name}\n" "$dummy_pkg")
    fi

    db="$tmp/$func/db"
    if (rpm -qa --dbpath $db 2>/dev/null | grep "^${name}") > /dev/null 2>&1; then
	return 0
    else
	return 2
    fi
}

install_on_copied__desc="Checking the exit status of 'rpm -i --justdb' on the copied rpmdb"
function install_on_copied__setup
{
    __copy_db__setup "$@" install_on_copied
    return $?
}

function install_on_copied__check
{
    __install__check "$@" install_on_copied
    return $?
}

verify_installation_on_copied__desc="Checking the dummy package is really installed to the copied rpmdb"
function verify_installation_on_copied__check
{
    __verify_installation__check "$@" install_on_copied
    return $?
}

#
#
#
main "$@"


