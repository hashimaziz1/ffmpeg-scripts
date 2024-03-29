#!/bin/bash
set -o errexit
set -o pipefail

watermark="D:\Users\Hashim\Documents\Projects\YouTube Channel 1\Meta\Watermark\Watermark.png"

err='\e[31m'
warn='\e[33m'
rc='\033[0m' # Reset colour

usage() {
	echo
	echo "Pass a source file and an output name. To crop, add optional start and end times."
	echo "usage: `basename $0` source.mp4 Final.mp4 [start_time] [end_time]"
	echo " -h --help     Print this help."
	echo " -f --final    Disable the ultrafast preset to produce a final file."
	echo " -b            Enable brightness compensation."
	exit
}

if [ $# -lt 2 ]; then usage
else
	preset="-preset ultrafast"
	options=$(getopt -l "final,help,brightness" -o "fhb" -a -- "$@")
	eval set -- "$options"
	while true
	do
		case $1 in
		-f|--final) 
	    preset=""
	    ;;
	  -b|--brightness)
	  	adj_bright=",curves=0.4/0.5" # Use the curves filter to lighten the output
	  	;;
		-h|--help) 
	    usage
			shift
	    ;;
		--)
	    shift
	    break
	    ;;
		\?) 
			echo "$OPTARG is not a valid option."
			usage
			shift
			break
			;;    
		esac
		shift
	done

	if [ ! -z "$3" ]; then
		starttime="$3" 
		start_opt="-ss $3" 
		else 
		starttime=0
		start_opt=""
		fi 
		if [ ! -z "$4" ]; then
		endtime="$4" 
		end_opt="-to $4" 
		else 
		endtime="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$1" | tr -d $'\r')"
		end_opt=""
	fi
	
	read -p "Enter fade duration in seconds: " -ei 2 fadeduration
	if ! [[ "$fadeduration" =~ ^[0-9]+$ ]] || [[ "$fadeduration" -eq 2 ]]; then 
		fadeduration=2 
		echo -e "${warn}Defaulting to $fadeduration seconds.${rc}"
	else echo "Using fade duration of $fadeduration."
	fi

  # Preserve colour and prevent colour shifts by explicitly setting colour metadata
  height=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=nw=1:nk=1 "$1" | tr -d $'\r')
	colour_space=$(ffprobe -v error -select_streams v:0 -show_entries stream=color_space -of default=nw=1:nk=1 "$1" | tr -d $'\r')
	if [[ $colour_space = "unknown" ]]; then
		echo -e "${err}Colorspace is unknown: setting metadata to safe default of BT601 (NTSC). Watch out for colour shifts and set manually if needed.${rc}" # BT601 is the most common for my (SD) video sources - change to BT701 if working with mostly HD sources.
		colour_metadata="-colorspace smpte170m -color_trc smpte170m -color_primaries smpte170m"
		elif [[ $height -lt "720" && $colour_space == "bt470bg" ]]; then # If input is standard definition and has BT.601 (PAL/SECAM) colorspace
		colour_metadata="-colorspace bt470bg -color_trc gamma28 -color_primaries bt470bg" # set all colour metadata to BT.601 (PAL/SECAM)
		elif [[ $height -lt "720" ]]; then # If input is standard definition and has any other colorspace
		colour_metadata="-colorspace smpte170m -color_trc smpte170m -color_primaries smpte170m" # set all colour metadata to BT.601 (NTSC)
		elif [[ $height -ge "720" ]]; then # If input is high definition
		colour_metadata="-colorspace bt709 -color_trc bt709 -color_primaries bt709" # set all colour metadata to BT.709
		else echo "${err}Weird colorspace $color_space detected, leaving colour metadata untouched.${rc}"
	fi

	length1="$(echo $endtime - $starttime | bc)"
	length2="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 outro.mp4 | tr -d $'\r')"
	wmlength="$(echo $length1 - 5 | bc)"	
	wmstream1="[2:v]lut=a=val*0.7,fade=in:st=15:d=3:alpha=1,fade=out:st=$wmlength:d=3:alpha=1[v2];"
 	wmstream2="[v2][tmp2]scale2ref=w=oh*mdar:h=ih*0.07[wm_scaled][video];"
	read -e -n1 -p "Select watermark position:
1) Bottom left
2) Top left
3) Top right
4) Bottom right
" ans
	case $ans in
  1)  echo "Defaulting to bottom-left position."
      wmpos="80:H-h-50"
			;;
  2)  echo
			echo "Positioning watermark at top-left."
			wmpos="80:50"
		  ;;
  3)  echo
			echo "Positioning watermark at top-right."
			wmpos="W-w-80:50"
			;;
	4)  echo
			echo "Positioning watermark at bottom-right."
			wmpos="W-w-80:H-h-50"
			;;
  *)  echo -e "${warn}No option selected, defaulting to bottom-left position.${rc}"
			wmpos="80:H-h-50"
      ;;
	esac
	read -p "Start fade at custom time in first input? [y/N] " -n1 -r
	if [[ $REPLY =~ ^[Yy]$ ]]; then
		while [[ -z "$fadetime" ]]; do
		echo
		read -p "Enter custom start time in seconds: " fadetime
		echo "Using custom fade time of $fadetime seconds from first input."
	done
  fi
	if [[ -z "$fadetime" ]]; then fadetime="$(echo "$length1" - "$fadeduration" | tr -d $'\r' | bc)" &&
		echo -e "${warn}Defaulting to adding fade -$fadeduration seconds from first input, at $fadetime seconds.${rc}" 
	fi
 	total="$(echo "$length1 + $length2 - $fadeduration" | tr -d $'\r' | bc)"
	ffmpeg -y -hide_banner \
	$start_opt $end_opt -i "$1" -i "outro.mp4" -loop 1 -i "$watermark" \
	-movflags +faststart+write_colr \
	$preset \
	-filter_complex \
 	"color=black:16x16:d=$total[base];
	[0:v]scale=-2:'max(1080,ih)':flags=lanczos$adj_bright,setpts=PTS-STARTPTS[v0];
	[1:v]scale=-2:'max(1080,ih)':flags=lanczos,fade=in:st=0:d=$fadeduration:alpha=1,setpts=PTS-STARTPTS+(($fadetime)/TB)[v1];
	$wmstream1
	[base][v0]scale2ref[base][v0];
	[base][v0]overlay[tmp];
	[tmp][v1]overlay,setsar=1[tmp2];
	$wmstream2
	[video][wm_scaled]overlay=$wmpos:shortest=1:format=rgb[outv];
	[0:a]afade=out:st=$fadetime:d=$fadeduration[0a];
	[0a][1:a]concat=n=2:v=0:a=1[outa]" \
	-map "[outv]" -map "[outa]" -c:v libx264 -crf 13 -c:a libopus \
	-pix_fmt yuv420p $colour_metadata "$2" 
	unset fadetime
fi

# in_color_matrix=auto:out_color_matrix=bt470
# loudnorm=I=-12:dual_mono=true:TP=-1.5:LRA=11:print_format=summary


