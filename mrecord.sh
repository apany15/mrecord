#!/bin/bash

CONFIGFILE="./mrecord.cfg"
TRUE=1
FALSE=0
SUCCESS=0
FAIL=1

counter=0

function fn_dump_config() {
    echo "=============CONFIGURATION USED==================="
    cat ${CONFIGFILE}
    echo "=================================================="
}

function ctrl_c() {
    echo "** TERMINATING"
    exit 0
}

function fn_listen_stream_output() {
    local stream_num=$1
    local input_file_descriptor=$2
    local stream_title_old_var=$3
    local stream_title_old=
    local stream_title_new=
    while read -r -u ${input_file_descriptor} line
    do
        echo ">>${stream_num}>> $line"
        stream_title_new=$(echo $line | sed -n "s|[[:space:]]*ICY Info: StreamTitle='\(.*\)';|\1|p")
        if [[ -n ${stream_title_new} ]]
        then
            [[ -z ${stream_title_old} ]] && stream_title_old=${stream_title_new}
            if [[ ${stream_title_new} != ${stream_title_old} ]]
            then
                echo ">>${stream_num}>> [${stream_title_new}][${stream_title_old}]"
                echo ">>${stream_num}>> Next track found"
                eval $stream_title_old_var='${stream_title_old}'
                break
            fi
        fi
    done
}

function remove_old_files() {
    find "$RECDIR" -name '*.mp3' ! -name "tempREC_*.mp3" -type f -printf '%Ts\t%p\n' \
        | sort -nr \
        | cut -f2 \
        | tail -n +$(( MAXCOMPS + 1 )) \
        | ( while read f; do echo "Removing old file [$f]"; rm -f "$f"; done )
}

function fn_record_stream() {
    local stream_URL=$1
    local stream_num=$2
    local time_start=0
    local time_end=0
    local comp_len=0
    local is_first_comp=${TRUE}
    tempFileName="tempREC_${stream_num}.mp3"
    echo ">>${stream_num}>> Start recording: ${stream_URL}"
    echo ">>${stream_num}>> Temp file name: ${tempFileName}"
    rm -f "$RECDIR/$tempFileName"
    while :
    do
        exec {input_file_descriptor}< <(mplayer "${stream_URL}" -dumpstream -dumpfile "$RECDIR/$tempFileName" -vc dummy -vo null 2>&1)
        mpid=$!
        echo ">>${stream_num}>> mplayer PID: [$mpid]; file descriptor: [${input_file_descriptor}]"
        time_start=$(date +%s)
        fn_listen_stream_output ${stream_num} ${input_file_descriptor} "stream_title_old_var_${stream_num}"
        time_end=$(date +%s)
        kill $mpid
        exec {input_file_descriptor}>&-
        comp_len=$((time_end-time_start))
        echo ">>${stream_num}>> Len of comp: [${comp_len}] sec"
        if [[ ${is_first_comp} -ne ${TRUE} ]]
            then
            if [[ ${comp_len} -ge $MINCOMPLEN ]] 
            then
                mv "$RECDIR/$tempFileName" "$RECDIR/$(eval echo "\$$(echo stream_title_old_var_$stream_num)").mp3"
                echo ">>${stream_num}>> $(eval echo "\$$(echo stream_title_old_var_$stream_num)").mp3 created"
            else
                echo ">>${stream_num}>> Len of comp < [$MINCOMPLEN]"
                rm -f "$RECDIR/$tempFileName"
            fi
        else
            echo ">>${stream_num}>> Remove first comp as incomplete"
            rm -f "$RECDIR/$tempFileName"
        fi
        is_first_comp=${FALSE}
        remove_old_files
    done
}

[[ -n $1 ]] && CONFIGFILE=$1

. "$CONFIGFILE"

fn_dump_config

trap ctrl_c INT


while read -r streamURL
do
    [[ -z ${streamURL} ]] && continue
    fn_record_stream "$streamURL" ${counter} &
    counter=$(( counter + 1 ))
done <<< "$(sed "s|[[:space:]]*#.*||" "$STREAMSFILE")"


while :; do sleep 1; done;

