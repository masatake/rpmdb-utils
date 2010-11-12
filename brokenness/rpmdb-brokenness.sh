#!/bin/bash

VERSION=0.1.3
#
# Copyright (C) 2010 Red Hat, Inc.
# Copyright (C) 2010 Masatake YAMATO
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
EXPECTED_THE_NUMBER_OF_RPMS=${EXPECTED_THE_NUMBER_OF_RPMS:-100}
DUMMY_RPM=
DEBUG=
REPORT_LEVEL=${REPORT_LEVEL:-line}
IGNORE_ERROR=
TIMEOUT=60

DISABLED_CHECKERS=""
CHECKERS="
          has_pidof
          rpm_running
          up2date_running
          yum_running
          fcntl_lock_target_rpmlock
          fcntl_lock_target_db000
          fcntl_lock_target_transactions
          region_file_1
          region_file_2
          region_file_3
          timeout_rpm_qa
          rpm_qa_on_original
          expected_the_number_of_rpms_on_original
          install_on_copied
          verify_installation_on_copied
          rebuilddb_on_copied
          rpm_qa_on_rebuilt
          expected_the_number_of_rpms_on_rebuilt
          install_on_rebuilt
          verify_installation_on_rebuilt
          rpm_qa_on_copied_other_than_db00X
          expected_the_number_of_rpms_on_copied_other_than_db00X
          install_on_copied_other_than_db00X
          verify_installation_on_copied_other_than_db00X
          rebuilddb_on_copied_other_than_db00X
          rpm_qa_on_rebuilt_the_copied_from_the_original_other_than_db00X
          expected_the_number_of_rpms_on_rebuilt_the_copied_from_the_original_other_than_db00X
          install_on_rebuilt_the_copied_from_the_original_other_than_db00X
          verify_installation_on_rebuilt_the_copied_from_the_original_other_than_db00X
          packages
          rpm_qa_on_copied_only_Packages
          expected_the_number_of_rpms_on_copied_only_Packages
          install_on_copied_only_Packages
          verify_installation_on_copied_only_Packages
"


function print_usage_1
{
    echo "See '$0 --help'"
    exit $1
}

function print_usage
{
    echo "Usage: "
    echo "	$0 [--help|-h]"
    echo "	$0 [--debug=TMPDIR] [--ignore-error] \\"
    echo "	   [[--report-level=line|quiet|verbose]|--verbose|--quiet] \\"
    echo "	   [--dbpath=DBPATH] [-N=#|--expected-the-number-of-rpms=#] [--dummy-rpm=RPM] \\"
    echo "	   [--timeout=TIMEOUT(sec)] [--dont-check=C1,C2,@W1,@W2,...]"
    echo "	$0 --decode=..."
    echo "	$0 --version"
    echo ""
    echo "Default value:"
    echo "	DBPATH: $DPBATH"
    echo "	EXPECTED_THE_NUMBER_OF_RPMS: $EXPECTED_THE_NUMBER_OF_RPMS"
    echo "	REPORT_LEVEL: $REPORT_LEVEL"
    echo "	TIMEOUT: $TIMEOUT"
    echo ""
    echo "Exit status:"
    echo "	0: No corruption detected in any checkers"
    echo "	1: Error occurred in script execution"
    echo "	2...N: Corruption detected in the (N-2)th checker, zero indexed" 
    echo ""
    echo "Checkers (CHECKER[@WORKSPACE]:)"
    for c in $CHECKERS; do
	describe $c
    done
    echo ""
    echo "Output of line reporter:"
    for c in . _ ! e s c t; do
	printf "	$c => %s\n" "$(decode_result $c)"
    done
    echo ""
    exit $1
}


#
#-----------------------------------------------------------------------
# 
# Utilities
#
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

function member
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

function number_p
{
    local v=$1
    shift

    [[ $v =~ ^[0-9]+$ ]]
    return $?
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

function checker_for
{
    local funcname="$1"
    local checker

    case "$funcname" in
	*__setup)
	    checker="${funcname/__setup}"
	    ;;
	*__check)
	    checker="${funcname/__check}"
	    ;;   
	*__teardwon)
	    checker="${funcname/__teardown}"
	    ;;      
    esac
    if [ -n "${checker}" ]; then
	echo "$checker"
	return 0
    else
	echo UNKNOWN_CHECKER
	return 1
    fi
}

function workspace_for
{
    local checker=$1
    local workspace_ref="${checker}__workspace"

    echo "${!workspace_ref}"
    return 0
}

function all_workspaces
{
   for c in $CHECKERS ; do
       workspace_for $c
   done | uniq | sort
}

function describe
{
    local checker=$1
    local workspace=$(workspace_for $checker)
    
    printf "	%s%s:\n		%s\n" "${checker}" "${workspace}" "$(eval echo \$${checker}__desc)"
}

function falias
{
    local name=$1
    local value=$2

    eval "function $name {
             $value \"\$@\"
             return \$?
    }"
}

function alive_p
{
    command kill -s 0 $1 >/dev/null 2>&1 
    return $?
}

function assassinate
{
    local target_pid=$1
    local sig=$2
    
    # The target pid is a child of this bash process.
    # If the child is killed, bash reports it to stderr.
    # To suppress the report message, stderr for this bash
    # process must be closed or connected to /dev/null.
    #
    # close stderr
    exec 3>&2- 2>/dev/null
    command kill -s $sig $target_pid >/dev/null 2>&1    
    while alive_p $target_pid; do
	sleep 1
    done
    # open stderr again
    exec 2>&3-

}
#
# with_timeout TIMEOUT SIGNAL CMD...
#
# return 0 if CMD exits in TIMEOUT.
# return 1 if CMD doesn't stop in TIMEOUT.
#
# e.g. 
# with_timeout 10 KILL rpm -qa
#
# with_timeout 10 KILL sleep 5 => 0
# with_timeout 10 KILL sleep 5 => 1
#
function with_timeout
{
    local timeout=$1
    local sig=$2
    shift 2

    local target_pid
    local count=0

    
    "$@" &
    target_pid=$!
    
    while [[ "$count" -lt "$timeout" ]]; do
	if ! alive_p $target_pid; then
	    # wait $target_pid
	    return 0
	fi

	sleep 1
	count=$(( $count + 1 ))

	if ! alive_p $target_pid; then
	    # wait $target_pid
	    return 0
	fi
    done
 
    assassinate "$target_pid" "$sig"
    
    return 1
}

#
#-----------------------------------------------------------------------
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
	    } 1>&2
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
	    msg="no corruption found"
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
	!)
	    msg="corrupted"
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
    local workspace
    local msg

    workspace=$(workspace_for $checker)
    msg=$(decode_result $result)
    status=$?

    printf "%s%s...%s\n" "$checker" "${workspace}" "$msg"

    return $status
}

#
#-----------------------------------------------------------------------
#
# Check --- check function calls a checker.
#
# ----------------------------------------------------------------------
# 
# * A protocol between check() and a checker.
# 
# + arguments passed to checker:
# 1: CHECKER
# 2: DB
# 3: TMPDIR
# 4: DUMMY PKG or -
# 5: EXPECTED_THE_NUMBER_OF_RPMS
# 6: TIMEOUT
# 
# + value returned from the checker to check():
# 0: found no corruption 
# 1: error occurred
# 2: found corruption
# 3: not checked
# 4: critical error occurred
#
# + temporary directories prepared to a checker:
# tmpdir:
# $TMPDIR/$CHECKER
# $TMPDIR/$WORKSPACE
#
# + name convention
# $CHECKER__desc --- Human readable description for $CHECKER.
# $CHECKER__setup --- optional.
# $CHECKER__check
# $CHECKER__teardown --- optional.
# $CHECKER__workspace --- Name of workspace used in $CHECKER. optional.
#
function check
{
    local func
    local status


    local checker=$1
    local tmpdir=$3
    local workspace

    workspace=$(workspace_for $checker)


    dprintf "* %s %s\n" "${workspace}" "$*"
    dprintf "  %s\n" "$(eval echo \$${checker}__desc)"

    [ -n "${workspace}" ] && mkdir -p "${tmpdir}/${workspace}"

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
	    dprintf "no corruption found\n" 
	    ;;
	1)
	    eval ${c}__result=c
	    dprintf "error\n" 
	    ;;
	2)
	    eval ${c}__result=!
	    dprintf "corrupted\n" 
	    ;;
	3)
	    eval ${c}__result=_
	    dprintf "not checked\n"
	    ;;
	4)
	    eval ${c}__result=!
	    dprintf "corrupted\n" 
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
#-----------------------------------------------------------------------
#
# Main
# 
#

function parse_arguments
{
    local original_opt


    for c in $CHECKERS; do
	local d="$(eval echo \$${c}__desc)"
	test -z "$d" && eval ${c}__desc="\"NO DOCUMENT\""
    done

    while [ $# -gt 0 ]; do
	case "$1" in
	    --help|-h)
		print_usage 0 1>&2
		;;
	    --dbpath=*|--dbpath)
                if [ $1 = "--dbpath" ]; then
		    shift
		    DBPATH=$1
		else
		    DBPATH=${1/--dbpath=}
		fi

		if [ -z "$DBPATH" ]; then
		    echo "No dbpath given to --dbpath" 1>&2
		    exit 1
		fi

		if ! [ -d "$DBPATH" ]; then
		    echo "No such directory: $DBPATH" 1>&2
		    exit 1
		fi

		if ! [ "${DBPATH:0:1}" = "/" ]; then
		    echo "Don't use relative path for dbpath" 1>&2
		    exit 1
		fi
		;;
	    --decode=*|--decode)
	        local decode_p
                if [ "$1" = "--decode" ]; then
		    shift
		    decode_p=$1
		else
		    decode_p=${1/--decode=}
		fi
	        
		if [ -z "$decode_p" ]; then
		    echo "No decode string given to --decode" 1>&2
		    exit 1
		fi
		
	        decode "$decode_p"
	        exit $?
	        ;;

	    --debug=*|--debug)
	        local tmpdir
		
		if [ "$1" = "--debug" ]; then
		    shift
		    tmpdir=$1
		else
		    tmpdir=${1/--debug=}
		fi

	        if [ -z "$tmpdir" ]; then
		    echo "No directory given to --debug" 1>&2
		    exit 1
		fi
		if ! [ -d "$tmpdir" ]; then
		    echo "No such directory: $tmpdir" 1>&2
		    exit 1
		fi
		if ! [ -w "$tmpdir" ]; then
		    echo "Not writable: $tmpdir" 1>&2
		    exit 1
		fi
		
		DEBUG="${tmpdir}"
		REPORT_LEVEL=verbose
		;;
	    --dummy-rpm=*|--dummy-rpm)
	        if [ "$1" = "--dummy-rpm" ]; then
		    shift
		    DUMMY_RPM=$1
		else
		    DUMMY_RPM=${1/--dummy-rpm=}
		fi

	        if [ -z "$DUMMY_RPM" ]; then
		    echo "No dummy rpm given to --dummy-rpm" 1>&2
		    exit 1
		fi

		case $DUMMY_RPM in
		    http://*|file:///*|ftp://*)
			;;
		    *)
			if ! [ -f "$DUMMY_RPM" ]; then
			    echo "No such file: $DUMMY_RPM" 1>&2
			    exit 1
			fi
			;;
		esac
		;;
	     --dont-check=*|--dont-check)
	        if [ "$1" = "--dont-check" ]; then
		    shift
	            DISABLED_CHECKERS=$1
		else
		    DISABLED_CHECKERS=${1/--dont-check=}
		fi
		
		if [ -z "${DISABLED_CHECKERS}" ]; then
		    echo "No checkers given to --dont-check" 1>&2
		    exit 1
		fi

		DISABLED_CHECKERS=$(echo "${DISABLED_CHECKERS}" | tr "," " ")
		local all_workspaces=$(all_workspaces)

		for c in $DISABLED_CHECKERS; do
		    if [ ${c:0:1} = "@" ]; then
			if ! member $c $all_workspaces; then
			    echo "Unknown workspace: $c" 1>&2
			    exit 1
			fi
			dprintf "%s is disabled\n" $c
		    else
			if ! member $c $CHECKERS; then
			    echo "Unknown checker: $c" 1>&2
			    exit 1
			fi
			dprintf "%s is disabled\n" $c
		    fi
		done
                ;;
	    --expected-the-number-of-rpms=*|-N=*|--expected-the-number-of-rpms|-N)
	        original_opt=$1

	        if [ "$1" = "-N" ]; then
		    shift
		    EXPECTED_THE_NUMBER_OF_RPMS=$1
		elif [ "$1" = "--expected-the-number-of-rpms" ]; then
		    shift
		    EXPECTED_THE_NUMBER_OF_RPMS=$1
		elif [[ "$1" == -N=* ]]; then
		    EXPECTED_THE_NUMBER_OF_RPMS=${1/-N=}
		else
		    EXPECTED_THE_NUMBER_OF_RPMS=${1/--expected-the-number-of-rpms=}
		fi

		if [ -z $EXPECTED_THE_NUMBER_OF_RPMS ]; then
		    echo "No number given: $original_opt" 1>&2
		    exit 1
		fi
		
		if ! number_p "$EXPECTED_THE_NUMBER_OF_RPMS"; then
		    echo "No number given: $original_opt" 1>&2
		    exit 1
		fi
		
		;;
	    --ignore-error)
	        IGNORE_ERROR=yes
	        ;;
	    --quiet)
	        REPORT_LEVEL=quiet
	        ;;
            --report-level=*|--report-level)
	         if [ "$1" = "--report-level" ]; then
		     shift
		     REPORT_LEVEL=$1
		 else
	             REPORT_LEVEL=${1/--report-level=}
		 fi

		 if [ -z "$REPORT_LEVEL" ]; then
		     echo "No report level given to --report-level" 1>&2
		     exit 1
		 fi

		 if ! member $REPORT_LEVEL quiet line verbose; then
		     {
			 echo "No such report level: $REPORT_LEVEL"
			 print_usage_1 1 
		     } 1>&2
		 fi
		 ;;
            --timeout=*|--timeout)
                 original_opt=$1

	         if [ "$1" = "--timeout" ]; then
		     shift
		     TIMEOUT=$1
		 else
		     TIMEOUT=${1/--timeout=}
		 fi

		 if ! number_p "$TIMEOUT"; then
		    echo "No number given: $original_opt" 1>&2
		    exit 1
                 fi
		 ;;
	    --verbose)
	         REPORT_LEVEL=verbose
	         ;;
	    --version)
	         echo $VERSION
		 exit 0
		 ;;
	    --*)
	         {
		     echo "No such option: $1" 
		     print_usage_1 1 
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
	    print_usage_1 1
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
    local found_corruption=

    parse_arguments "$@"

    if [ -z "$DEBUG" ]; then
	surgery=$(mktemp -d "/tmp/rpmdb_corruption.XXXXX")
	trap "chmod -R u+w $surgery; /bin/rm -rf $surgery" 0    
    else
	surgery=$DEBUG
    fi

    for c in $CHECKERS; do
	eval ${c}__result=_
    done

    for c in $CHECKERS; do
	local w=$(workspace_for $c)
	local r
	if ! ( member $w $DISABLED_CHECKERS || member $c $DISABLED_CHECKERS ); then
	    check $c $DBPATH "$surgery" ${DUMMY_RPM:--} "${EXPECTED_THE_NUMBER_OF_RPMS}" "${TIMEOUT}"
	    r=$?
	    case $r in
		0)
		    :
		    ;;
		1)
		    found_error=$c
		    ;;
		2|4)
		    if [ -z "$found_corruption" ]; then
			found_corruption=$c
		    fi
		    if [ $r = 4 ]; then
			DISABLED_CHECKERS=$CHECKERS
		    fi
		    ;;
	    esac

	    if [ -n "$found_error" ]; then
		if [ -z "$IGNORE_ERROR" ]; then
		    break
		fi
	    fi
	fi
	case $REPORT_LEVEL in
	    line)
		report_$REPORT_LEVEL $c $(eval 'echo $'${c}__result)
		;;
	esac
    done

    case $REPORT_LEVEL in
	quiet)
	    :
	    ;;
	line)
	    if [ -n "$found_error" ]; then
		echo -n ": $found_error<error>"
	    fi
	    if [ -n "$found_corruption" ]; then
		echo -n ": $found_corruption<corruption>"
	    fi
	    echo
	    ;;
	verbose)
	    for c in $CHECKERS; do
		report_$REPORT_LEVEL $c $(eval 'echo $'${c}__result)
	    done
	    ;;
    esac

    if [ -n "$found_error" ]; then
	return 1
    fi

    if [ -n "found_corruption" ]; then
	local index=$(index_of "$found_corruption" $CHECKERS)
	return $(( $index + 2 ))
    fi

    return 0
}

#
#-----------------------------------------------------------------------
#
# Common Checkers
#
#
function __file_existence__desc
{
    local obj=$1
    printf "Checking whether %s exists or not" $obj
}

function __file_existence__check 
{
    local file=$1
    if [ -e "$file" ]; then
	return 2
    fi
    return 0
}

function __region_file__check
{
    local db=$1
    local n=$2
    __file_existence__check "$db/__db.00$n"
    return $?
}

function __rpm_qa__check
{
    local workspace=$1
    local db=$2
    local tmpdir=$3


    if ! [ -d $db ]; then
	return 1
    fi

    if ! rpm -qa --dbpath $db > $tmpdir/${workspace}/rpm_qa_stdout 2>$tmpdir/${workspace}/rpm_qa_stderr; then
	return 2
    fi

    return 0
}

function __expected_the_number_of_rpms__check
{
    local workspace=$1
    local tmpdir=$2
    local expected_the_number_of_rpms=$3
    local lines

    if ! [ -r "$tmpdir/${workspace}/rpm_qa_stdout" ]; then
	return 1
    fi
    
    lines=$(wc -l < "$tmpdir/${workspace}/rpm_qa_stdout")
    echo "$lines" > "$tmpdir/${workspace}/lines"
    if [ "$lines" -gt "${expected_the_number_of_rpms}" ]; then
	return 0
    else
	return 2
    fi

}

function __copy_db__setup
{
    local original_db=$1
    local copied_db=$2
    local dummy_pkg=$3


    if [ "$dummy_pkg" = "-" ]; then
	return 0
    fi
    
    mkdir -p "$copied_db" && cp --archive ${original_db}/* "$copied_db"
    return $?
}

function __install__check
{
    local workspace=$1
    local db=$2
    local tmpdir=$3
    local dummy_pkg=$4

    if [ "$dummy_pkg" = "-" ]; then
	return 3
    fi

    if rpm -ivh --justdb --dbpath $db $dummy_pkg > $tmpdir/${workspace}/rpm_i_justdb 2>&1; then
	return 0
    else
	return 2
    fi
}

function __verify_installation__check
{
    local workspace=$1
    local db=$2
    local dummy_pkg=$3
    local name

    
    if [ "$dummy_pkg" = "-" ]; then
	return 3
    fi

    if ! [  -d $db ];then
	# programming error
	return 1
    fi
    
    name=$(rpm -qp --queryformat "%{name}\n" "$dummy_pkg")
    if [ -z "${name}" ]; then
	# ??? 2
	return 1
    fi


    if (rpm -qa --dbpath $db 2>/dev/null | tee $tmpdir/${workspace}/rpm_qa_stdout | grep "^${name}") > /dev/null 2>&1; then
	return 0
    else
	return 2
    fi
}

function __rebuilddb__check
{
    local workspace=$1
    local db=$2
    local tmpdir=$3
    
    if rpm --rebuilddb --dbpath $db \
	> "${tmpdir}"/${workspace}/rpm_rebuildb_stdout      \
	2> "${tmpdir}"/${workspace}/rpm_rebuildb_stderr; then
	return 0
    else
	return 2
    fi
}

function __external_rpmdb_accessor__check
{
    local db=$1
    local program=$2

    if [ "$db" = /var/lib/rpm ]; then
	return 3
    fi

    if pidof "${program}" > /dev/null 2>&1; then
	return 1
    fi
    return 0
}

#
#-----------------------------------------------------------------------
#
# Checkers
#
#
has_pidof__desc="Checking whether pidof command is available or not"
function has_pidof__check
{
    if which pidof > /dev/null 2>&1; then
	return 0
    else
	return 1
    fi
}

rpm_running__desc="Checking whether another rpm process is running or not"
rpm_running__workspace="@external_rpmdb_accessor"
function rpm_running__check
{
    local db=$2
    __external_rpmdb_accessor__check $db rpm
    return $?
}

up2date_running__desc="Checking whether another up2date process is running or not"
up2date_running__workspace="@external_rpmdb_accessor"
function up2date_running__check
{
    local db=$2
    __external_rpmdb_accessor__check $db up2date
    return $?
}

yum_running__desc="Checking whether another yum process is running or not"
yum_running__workspace="@external_rpmdb_accessor"
function yum_running__check
{
    local db=$2
    __external_rpmdb_accessor__check $db yum
    return $?
}




fcntl_lock_target_rpmlock__desc=$(__file_existence__desc .rpm.lock)
function fcntl_lock_target_rpmlock__check
{
    local db=$2

    __file_existence__check "$db/.rpm.lock"
    return $?
}

fcntl_lock_target_db000__desc=$(__file_existence__desc __db.000)
function fcntl_lock_target_db000__check
{
    local db=$2

    __file_existence__check "$db/__db.000"
    return $?
}

fcntl_lock_target_transactions__desc=$(__file_existence__desc /var/lock/rpm/transactions)
function fcntl_lock_target_transactions__check
{
    local db=$2

    __file_existence__check "$(dirname $(dirname $db))/lock/rpm/transactions"
    return $?
    
}

region_file_1__desc=$(__file_existence__desc __db.001)
function region_file_1__check
{
    __region_file__check $2 1
    return $?
}
region_file_2__desc=$(__file_existence__desc __db.002)
function region_file_2__check
{
    __region_file__check $2 2
    return $?
}
region_file_3__desc=$(__file_existence__desc __db.003)
function region_file_3__check
{
    __region_file__check $2 3
    return $?
}

timeout_rpm_qa__desc="Checking rpm -qa exits in given time limit"
function timeout_rpm_qa__check
{
    local timeout=$6

    if ! with_timeout $timeout KILL rpm -qa > /dev/null 2>&1; then
	return 4
    else
	return 0
    fi
}

rpm_qa_on_original__desc="Checking exit status of 'rpm -qa' on the original rpmdb"
rpm_qa_on_original__workspace="@qa_on_original"
function rpm_qa_on_original__check
{
    __rpm_qa__check $(workspace_for "$1") $2 $3
    return $?
}

expected_the_number_of_rpms_on_original__desc="Checking the lines of output of 'rpm -qa' on the original rpmdb"
expected_the_number_of_rpms_on_original__workspace="@qa_on_original"
function expected_the_number_of_rpms_on_original__check
{
    __expected_the_number_of_rpms__check $(workspace_for "$1") $3 $5
    return $?
}

install_on_copied__desc="Checking the exit status of 'rpm -i --justdb' on the copied rpmdb"
install_on_copied__workspace="@install_on_copied"
function install_on_copied__setup
{
    local workspace=$(workspace_for "$1")
    local tmpdir=$3
    local dummy_pkg=$4


    __copy_db__setup $2 "${tmpdir}/${workspace}/db" ${dummy_pkg}

    return $?
}

function install_on_copied__check
{
    local workspace=$(workspace_for "$1")
    local tmpdir=$3
    local dummy_pkg=$4

    __install__check "${workspace}" "${tmpdir}"/${workspace}/db  "${tmpdir}" $dummy_pkg
    return $?
}

verify_installation_on_copied__desc="Checking the dummy package is really installed to the copied rpmdb"
verify_installation_on_copied__workspace="@install_on_copied"
function verify_installation_on_copied__check
{
    local workspace=$(workspace_for "$1")
    local tmpdir=$3
    local db="$tmpdir/${workspace}/db"
    local dummy_pkg=$4

    __verify_installation__check "${workspace}" "$db" "$dummy_pkg"
    return $?
}

rebuilddb_on_copied__desc="Checking exit status of 'rpm --rebuilddb' on the copied rpmdb"
rebuilddb_on_copied__workspace="@rebuilddb_on_copied"
function rebuilddb_on_copied__setup
{
    local workspace=$(workspace_for "$1")
    local tmpdir=$3

    __copy_db__setup $2 "${tmpdir}/${workspace}/db" X

    return $?
}

function rebuilddb_on_copied__check
{
    local workspace=$(workspace_for "$1")
    local tmpdir=$3

    __rebuilddb__check "${workspace}" "${tmpdir}"/${workspace}/db "${tmpdir}"

    return $?
}

rpm_qa_on_rebuilt__desc="Checking exit status of 'rpm -qa' on the rebuilt rpmdb"
rpm_qa_on_rebuilt__workspace="@rebuilddb_on_copied"
function rpm_qa_on_rebuilt__check
{
    local workspace=$(workspace_for "$1")
    local tmpdir=$3


    __rpm_qa__check "${workspace}" "${tmpdir}/${workspace}/db" "${tmpdir}"
    return $?
}

expected_the_number_of_rpms_on_rebuilt__desc="Checking the lines of output of 'rpm -qa' on the rebuilt rpmdb"
expected_the_number_of_rpms_on_rebuilt__workspace="@rebuilddb_on_copied"
falias expected_the_number_of_rpms_on_rebuilt__check expected_the_number_of_rpms_on_original__check

install_on_rebuilt__desc="Checking the exit status of 'rpm -i --justdb' on the rebuilt rpmdb"
install_on_rebuilt__workspace="@rebuilddb_on_copied"
falias install_on_rebuilt__check install_on_copied__check

verify_installation_on_rebuilt__desc="Checking the dummy package is really installed to the rebuilt rpmdb"
verify_installation_on_rebuilt__workspace="@rebuilddb_on_copied"
falias verify_installation_on_rebuilt__check verify_installation_on_copied__check


rpm_qa_on_copied_other_than_db00X__desc="Checking exit status of 'rpm -qa' on the rpmdb copied from the original other than __db00X files"
rpm_qa_on_copied_other_than_db00X__workspace="@qa_on_copied_other_than_db00X"
function rpm_qa_on_copied_other_than_db00X__setup
{
    local workspace=$(workspace_for "$1")
    local tmpdir=$3
    
    if __copy_db__setup $2 "${tmpdir}"/${workspace}/db X; then
	rm -f "${tmpdir}"/${workspace}/db/__db.00*
	return 0
    fi
    return $?
}
falias rpm_qa_on_copied_other_than_db00X__check rpm_qa_on_rebuilt__check


expected_the_number_of_rpms_on_copied_other_than_db00X__desc="Checking the lines of output of 'rpm -qa' on the rpmdb copied from the original other than __db00X files"
expected_the_number_of_rpms_on_copied_other_than_db00X__workspace="@qa_on_copied_other_than_db00X"
falias expected_the_number_of_rpms_on_copied_other_than_db00X__check expected_the_number_of_rpms_on_original__check

install_on_copied_other_than_db00X__desc="Checking the exit status of 'rpm -i --justdb' on the on the rpmdb copied from the original other than __db00X files"
install_on_copied_other_than_db00X__workspace="@qa_on_copied_other_than_db00X"
falias install_on_copied_other_than_db00X__check install_on_copied__check

verify_installation_on_copied_other_than_db00X__desc="Checking the dummy package is really installed to the rpmdb copied from the original other than __db00X files"
verify_installation_on_copied_other_than_db00X__workspace="@qa_on_copied_other_than_db00X"
falias verify_installation_on_copied_other_than_db00X__check verify_installation_on_copied__check




rebuilddb_on_copied_other_than_db00X__desc="Checking exit status of 'rpm --rebuilddb' on the rpmdb copied from the original other than __db00X files"
rebuilddb_on_copied_other_than_db00X__workspace="@rebuilddb_on_copied_other_than_db00X"
falias rebuilddb_on_copied_other_than_db00X__setup rpm_qa_on_copied_other_than_db00X__setup
falias rebuilddb_on_copied_other_than_db00X__check rebuilddb_on_copied__check

rpm_qa_on_rebuilt_the_copied_from_the_original_other_than_db00X__desc="Checking exit status of 'rpm -qa' on the rebuilt rpmdb"
rpm_qa_on_rebuilt_the_copied_from_the_original_other_than_db00X__workspace="@rebuilddb_on_copied_other_than_db00X"
falias rpm_qa_on_rebuilt_the_copied_from_the_original_other_than_db00X__check rpm_qa_on_rebuilt__check

expected_the_number_of_rpms_on_rebuilt_the_copied_from_the_original_other_than_db00X__desc="Checking the lines of output of 'rpm -qa' on the rpmdb rebuilt from copied from the original other than __db00X files"
expected_the_number_of_rpms_on_rebuilt_the_copied_from_the_original_other_than_db00X__workspace="@rebuilddb_on_copied_other_than_db00X"
falias expected_the_number_of_rpms_on_rebuilt_the_copied_from_the_original_other_than_db00X__check expected_the_number_of_rpms_on_original__check

install_on_rebuilt_the_copied_from_the_original_other_than_db00X__desc="Checking the exit status of 'rpm -i --justdb' on the rpmdb rebuilt from copied from the original other than __db00X files"
install_on_rebuilt_the_copied_from_the_original_other_than_db00X__workspace="@rebuilddb_on_copied_other_than_db00X"
falias install_on_rebuilt_the_copied_from_the_original_other_than_db00X__check install_on_copied__check

verify_installation_on_rebuilt_the_copied_from_the_original_other_than_db00X__desc="Checking the dummy package is really installed to the rpmdb rebuilt from the original other than __db00X files"
verify_installation_on_rebuilt_the_copied_from_the_original_other_than_db00X__workspace="@rebuilddb_on_copied_other_than_db00X"
falias verify_installation_on_rebuilt_the_copied_from_the_original_other_than_db00X__check verify_installation_on_copied__check



packages__desc=$(__file_existence__desc Packages)
function packages__check
{
    local db=$2

    if [ -e $db/Packages ]; then
	return 0
    else
	return 2
    fi
}

rpm_qa_on_copied_only_Packages__desc="Checking exit status of 'rpm -qa' on the rpmdb derived from the original Packages file"
rpm_qa_on_copied_only_Packages__workspace="@qa_on_rpmdb_derived_from_Packages"
function rpm_qa_on_copied_only_Packages__setup
{
    local workspace=$(workspace_for "$1")
    local db=$2
    local tmpdir=$3
    
    mkdir -p "${tmpdir}/${workspace}/db" && cp --archive $db/Packages "${tmpdir}/${workspace}/db"
    return $?
}
falias rpm_qa_on_copied_only_Packages__check rpm_qa_on_rebuilt__check


expected_the_number_of_rpms_on_copied_only_Packages__desc="Checking the lines of output of 'rpm -qa' on the rpmdb derived from the original Packages file"
expected_the_number_of_rpms_on_copied_only_Packages__workspace="@qa_on_rpmdb_derived_from_Packages"
falias expected_the_number_of_rpms_on_copied_only_Packages__check expected_the_number_of_rpms_on_original__check

install_on_copied_only_Packages__desc="Checking the exit status of 'rpm -i --justdb' on the on the rpmdb derived from the original Packages file"
install_on_copied_only_Packages__workspace="@qa_on_rpmdb_derived_from_Packages"
falias install_on_copied_only_Packages__check install_on_copied__check

verify_installation_on_copied_only_Packages__desc="Checking the dummy package is really installed to the rpmdb derived from the original Packages file"
verify_installation_on_copied_only_Packages__workspace="@qa_on_rpmdb_derived_from_Packages"
falias verify_installation_on_copied_only_Packages__check verify_installation_on_copied__check

#
#-----------------------------------------------------------------------
main "$@"

# Local Variables: 
# page-delimiter: "^#"
# End: 
