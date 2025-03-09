#!/usr/bin/env sh
CURRENTDIR="/etc"
OUTPUTDIR="/tmp"
get_files_list() {
    local list_of_files_str=""
    for file in "$1"/*; do
	    if [ -f $file ] && [ -r $file ]; then
		 list_of_files_str="$list_of_files_str $file"
	    elif [ -d $file ] && [ -r $file ]; then
		get_files_list $file
            fi
    done
    echo $list_of_files_str
}

create_baseline(){
	file_list=$(get_files_list $CURRENTDIR)
	output_file_name=$1
	output_path="$OUTPUTDIR/$output_file_name"
	sha256sum $file_list > "$output_path" 
}

LOGFILE="/var/log/integrity_report.log"

generate_report_summary(){
	DELETION_COUNT=$(grep -c "DELETED" "$LOGFILE")
	INSERTION_COUNT=$(grep -c "INSERTED" "$LOGFILE")
	MODIFICATION_COUNT=$(grep -c "MODIFIED" "$LOGFILE")
	report_summary="Report Summary:"
    	report_summary="$report_summary \nNumber of deletions: $DELETION_COUNT"
    	report_summary="$report_summary \nNumber of insertions: $INSERTION_COUNT"
    	report_summary="$report_summary \nNumber of modifications: $MODIFICATION_COUNT"
	echo "$report_summary"
}

check_hash_integrity(){
	temp_filename="temp_etc_hashes.txt"
	create_baseline "$temp_filename"
	[ -f "$LOGFILE" ] && > "$LOGFILE"
	if ! [ -f "$OUTPUTDIR/etc_hashes.txt" ]; then
    		echo "Error: Baseline file diesn't exist! run --baseline first"
    		exit 1
	fi
	line_number_temp=0
    	line_number_baseline=0
        
        exec 3< "$OUTPUTDIR/$temp_filename"  
        exec 4< "$OUTPUTDIR/etc_hashes.txt"   
	
    	IFS= read -r temp_line <&3
    	IFS= read -r baseline_line <&4

    	while [ -n "$temp_line" ] || [ -n "$baseline_line" ]; do
        	set -- $temp_line
        	temp_hash="$1"
        	shift
        	temp_file="$*"

        	set -- $baseline_line
        	baseline_hash="$1"
        	shift
        	baseline_filename="$*"

        	
        	if [ "$temp_file" = "$baseline_filename" ] && [ "$temp_hash" != "$baseline_hash" ]; then
           	 echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') MODIFIED: $temp_file" >> "$LOGFILE"
            	IFS= read -r temp_line <&3
            	IFS= read -r baseline_line <&4
           	 line_number_temp=$((line_number_temp + 1))
            	line_number_baseline=$((line_number_baseline + 1))

        	
        	elif [ "$temp_file" != "$baseline_filename" ]; then
            		if grep -q "$baseline_filename" "$OUTPUTDIR/$temp_filename"; then
                	echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') INSERTED: $temp_file" >> "$LOGFILE"
                	IFS= read -r temp_line <&3
                	line_number_temp=$((line_number_temp + 1))
            		else
                	echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') DELETED: $baseline_filename" >> "$LOGFILE"
                	IFS= read -r baseline_line <&4
                	line_number_baseline=$((line_number_baseline + 1))
            	fi
        	else
            	
            	IFS= read -r temp_line <&3
            	IFS= read -r baseline_line <&4
            	line_number_temp=$((line_number_temp + 1))
            	line_number_baseline=$((line_number_baseline + 1))
        	fi
    	done
	
   	exec 3<&-  
    	exec 4<&-  
	if [ -s "$LOGFILE" ]; then
		echo "integrity compromised! log created at /var/log : integrity_report.log"
	fi
}

display_report(){
	if [ ! -f "$LOGFILE" ]; then
        	echo "No log file found so no modification to files detected. Run --check after changes have been made to generate a log."
        	exit 1
    	fi
	cat $LOGFILE
	printf "%s\n" "$(generate_report_summary)" 
	printf "%s\n" "$(generate_report_summary)" >"/tmp/$(date '+%Y-%m-%d %H:%M:%S')_report.txt" 
	echo "Report created in /tmp: $(date '+%Y-%m-%d %H:%M:%S')_report.txt" 
}

display_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --baseline       Create a baseline of file hashes."
    echo "  --check          Check file integrity against the baseline."
    echo "  --report         Display the integrity report."
    echo "  --help           Show this help message."
    echo
    echo "Please ensure that the --baseline option is provided before --check."
}

main(){
     baseline_created=false
     if [ $# -eq 0 ]; then
        echo "Error: No flags provided! Need at least one valid flag."
        display_usage
        exit 1
     fi
     if [ $# -gt 3 ]; then
        echo "Error: Too many flags provided! A maximum of 3 valid flags is allowed."
        display_usage
        exit 1
     fi
     for arg in "$@"; do
        case "$arg" in
            --baseline|--check|--report|--help) ;;
            *) 
                echo "Error: Invalid flag: $arg"
                display_usage
                exit 1
                ;;
        esac
     done
     while [ $# -gt 0 ]; do
       case "$1" in
        --baseline)
            create_baseline "etc_hashes.txt"
	    baseline_created=true
            ;;
        --check)
	    if [ "$baseline_created" = false ] && echo "$@" | grep -qw -- "--baseline"; then
                    echo "Error: The --baseline option must be provided before --check."
                    exit 1
            fi
            check_hash_integrity
	    ;;
        --report)
            display_report
            ;;
        --help)
            display_usage
            exit 0
            ;;
       esac
       shift  
     done
}

main "$@"
