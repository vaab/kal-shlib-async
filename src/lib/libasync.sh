
tmp=${tmp:-/tmp}
export POOL_LABEL=${POOL_LABEL:-$$}


_dprefix() {
    echo "async_run.pool-${POOL_LABEL}"
}

_dforget() {
    local def
    def=$1
    rm "$def/"{out,err,errlvl,pid} &&
    rmdir "$def"
}

_dread() {
    local def target
    def=$1
    target=$2
    [ -e "$def"/"$target" ] && cat "$def"/"$target"
}

##
## Returns on stdout a string that represent a deferred. This string
## identifies the running process and will be used to wait or get output
## from it.
##
## Example:
##     deferred COMMAND...
deferred() {
    local varname
    prefix=$(_dprefix)
    mkprocdir=$(mktemp -d --tmpdir="$tmp" "$prefix.XXXXXXXX")
    ( "$@" > "$mkprocdir/out" 2> "$mkprocdir/err";
     echo "$?" > "$mkprocdir/errlvl") &
    echo "$!" > "$mkprocdir/pid"
    echo "$mkprocdir"
}

#async_kill
#async_read
#async_wait

##     dlist [-r|-u|-a]
##
dlist() {
    local opt
    prefix=$(_dprefix)
    opt="${1:--a}"
    case "$opt" in
        "-a") 
        for d in "$tmp/$prefix".*; do
            [ -e "$d" ] && echo "$d"
        done
        ;;
        "-r"|"-u") 
        for d in "$tmp/$prefix".*; do
            if [ -e "$d/errlvl" ]; then
                [ "$opt" == "-r" ] && echo "$d"
            else
                [ "$opt" == "-u" ] && echo "$d"
            fi
        done
        ;;
    esac

}


##     dwait [-t TIMEOUT] [$def1 [$def2...]]
##
## Example:
##     dwait [-t TIMEOUT] [$def1 [$def2...]]
dwait() {
    local def
    timeout=
    if [ "$1" == "-t" ]; then
        shift
        timeout="$1"
        start=$(date +%s.%N)
        shift
    fi
    if [ "$#" == 0 ]; then
        defs=$(dlist -u)
    else
        defs="$@"
    fi
    while [ "$defs" ]; do
        new_defs=""
        for d in $defs; do
            dresolved "$d"
            errlvl="$?"
            case $errlvl in
                0)
                    :
                    ;;
                1)
                    new_defs="$d $new_defs"
                    ;;
                *)
                    return 1
                    ;;
            esac
        done
        defs="$new_defs"
        if [ "$timeout" ]; then
            now=$(date +%s.%N)
            is_timeout=$(echo "($now - $start) > $timeout" | bc -l)
            [ "$is_timeout" == "1" ] && return 1
        fi
        sleep 0.1
    done
    return 0
}

##     dresolved [DEF1 [DEF2...]]
##
## Example:
##     dresolved $def1    ## is "$def1" resolved ?
##     dresolved          ## are all defs resolved ?
dresolved() {
    if [ "$#" == 0 ]; then
        if [ -z "$(dlist -u)" ]; then
            return 0
        else
            return 1
        fi
    fi
    for d in "$@"; do
        if ! [ -d "$d" ]; then
            echo "Error: invalid deferred '$d'." >&2
            return 2
        fi
        [ -e "$d/errlvl" ] || return 1
    done
    return 0
}

dforeground() {
    local def
    keep=
    if [ "$1" == "-k" ]; then
        shift
        keep=y
    fi
    def="$1"
    if ! dwait "$def"; then
        echo "Error: failed to attach to '$def'." >&2
        return 1
    fi
    _dread "$def" out
    _dread "$def" err >&2
    errlvl=$(_dread "$def" errlvl)
    if [ -z "$keep" ]; then
        _dforget "$def"
    fi
    return "$errlvl"
}

dkill() {
    local defs
    if [ "$#" == 0 ]; then
        defs=$(dlist -u)
    else
        defs="$@"
    fi
    for d in $defs; do
        ## process could have been killed in the meantime
        ## so avoid displaying any error.
        kill "$(_dread $d pid)" >/dev/null 2>&1
    done
}


##
## Remove tracking file for all finished process
##
##
##     dclean [-r|-u|-a] [-k|-w] [DEF1 [DEF2...]]
dclean() {
    local defs
    if [ "$#" == 0 ]; then
        defs=$(dlist -r)
    else
        defs="$@"
    fi
    for d in $defs; do
        _dforget "$d"
    done
}
