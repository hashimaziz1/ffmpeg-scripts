#!/bin/bash
set -o errexit
set -o pipefail

watermark="D:\Users\Hashim\Documents\Projects\YouTube Channel 1\Meta\Watermark\Watermark.png"

err='\e[31m'
warn='\e[33m'
rc='\033[0m' # Reset colour

usage() {
	echo
	echo "Pass two source files and an output name. To crop, add optional start and end times for each source."
	echo "usage: `basename $0` source1.mp4 source2.mkv Final.mp4 [start_time1] [end_time1] [start_time2] [end_time2]"
	echo " -h --help     Print this help."
	echo " -f --final    Disable the ultrafast preset to produce a final file."
	exit
}

if [ $# -lt 2 ]; then usage
else
	preset="-preset ultrafast"
	options=$(getopt -l "final,help" -o "fh" -a -- "$@")
	eval set -- "$options"
	while true
	do
		case $1 in
		-f|--final) 
	    preset=""
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

	if [ ! -z "$4" ]; then
		starttime1="$4" 
		start_opt1="-ss $4" 
		else 
		starttime1=0
		start_opt1=""
		fi 
		if [ ! -z "$5" ]; then
		endtime1="$5" 
		end_opt1="-to $5" 
		else 
		endtime1="$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$1" | tr -d $'\r')"
		end_opt1=""
		fi
		if [ ! -z "$6" ]; then
		starttime2="$6" 
		start_opt2="-ss $6" 
		else 
		starttime2=0
		start_opt2=""
		fi 
		if [ ! -z "$7" ]; then
		endtime2="$7" 
		end_opt2="-to $7" 
		else 
		endtime2="$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$1" | tr -d $'\r')"
		end_opt2=""
	fi

	read -p "Enter first fade duration in seconds: " -ei 2 fadeduration1
	if ! [[ "$fadeduration1" =~ ^[0-9]+$ ]] || [[ "$fadeduration1" -eq 2 ]]; then 
		fadeduration1=2 
		echo -e "${warn}Defaulting first fade to duration of $fadeduration1 seconds.${rc}"
	else echo "Setting first fade duration to $fadeduration1."
	fi
	read -p "Enter second fade duration in seconds: " -ei 2 fadeduration2
	if ! [[ "$fadeduration2" =~ ^[0-9]+$ ]] || [[ "$fadeduration2" -eq 2 ]]; then 
		fadeduration2=2 
		echo -e "${warn}Defaulting second fade to duration of $fadeduration2 seconds.${rc}"
	else echo "Setting second fade duration to $fadeduration2."
	fi

  # Preserve colour and prevent colour shifts by conforming rest of metadata to detected colorspace.
  # height=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=nw=1:nk=1 "$1" | tr -d $'\r')
	colour_space=$(ffprobe -v error -select_streams v:0 -show_entries stream=color_space -of default=nw=1:nk=1 "$1" | tr -d $'\r')
	if [[ $colour_space == "smpte170m" ]]; then # If input has BT601 (NTSC) colorspace or is standard definition
	colour_metadata="-colorspace smpte170m -color_trc smpte170m -color_primaries smpte170m" # set all metadata to BT601 (NTSC)
  # If input has BT601 (PAL/SECAM) or unknown colorspace, or is standard definition
	elif [[ ($colour_space == "bt470bg") ]]; then
	colour_metadata="-colorspace bt470bg -color_trc gamma28 -color_primaries bt470bg" # set all metadata to more common PAL/SECAM
  elif [[ $colour_space == "bt709" ]]; then # If input has BT709 colorspace or is high definition
  colour_metadata="-colorspace bt709 -color_trc bt709 -color_primaries bt709" # set all metadata to BT.709
	elif [[ $colour_space = "unknown" ]]; then
	echo -e "${err}Colorspace cannot be determined: setting metadata to safe default of BT601 (NTSC). Watch out for colour shifts and set manually if needed.${rc}" # BT601 is the most common for my (SD) video sources - change to BT701 if working with mostly HD sources.
	colour_metadata="-colorspace smpte170m -color_trc smpte170m -color_primaries smpte170m" 
  else echo "${err}Weird colorspace $color_space detected, leaving colour metadata untouched.${rc}"
	fi	

	length1="$(echo $endtime1 - $starttime1 | bc)"
	length2="$(echo $endtime2 - $starttime2 | bc)"
	length3="$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 outro.mp4 | tr -d $'\r')"
	wmlength="$(echo \($length1 + $length2\) - 5 | bc)"
	wmstream1="[3:v]lut=a=val*0.7,fade=in:st=15:d=3:alpha=1,fade=out:st=$wmlength:d=3:alpha=1[v3];"
 	wmstream2="[v3][video]scale2ref=w=oh*mdar:h=ih*0.07[wm_scaled][video];"
	read -e -n1 -p "Select watermark position:
1) Bottom left
2) Top left
3) Top right
4) No watermark
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
		while [[ -z "$fadetime1" ]]; do
		echo
		read -p "Enter custom start time for first input, in seconds: " fadetime1
		echo "Using custom fade time of -$fadeduration1 seconds from first input at $fadetime1 seconds".
	done
  fi
	if [[ -z "$fadetime1" ]]; then fadetime1="$(echo "$length1" - "$fadeduration1" | tr -d $'\r' | bc)"	
		echo "${warn}Defaulting to adding fade -$fadeduration1 seconds from first input at $fadetime1 seconds.${nc}" 
	fi	
	read -p "Start fade at custom time in second input? [y/N] " -n1 -r
	if [[ $REPLY =~ ^[Yy]$ ]]; then
		while [[ -z "$fadetime2" ]]; do
		echo
		read -p "Enter custom start time for second input, in seconds: " fadetime2
		echo "Using custom fade time of -$fadeduration2 seconds from second input at $fadetime2 seconds".
	done
  fi
	if [[ -z "$fadetime2" ]]; then fadetime2="$(echo "$length1 + $length2 - $fadeduration1 - $fadeduration2" | tr -d $'\r' | bc)"
		echo "${warn}Defaulting to adding fade -$fadeduration2 seconds from second input at $fadetime2 seconds.${nc}" 
	fi
 	total="$(echo "$length1 + $length2 + $length3 - $fadeduration1 - $fadeduration2" | tr -d $'\r' | bc)"
	ffmpeg -y -hide_banner \
	$start_opt1 $end_opt1 -i "$1" $start_opt2 $end_opt2 -i "$2" -i "outro.mp4" -loop 1 -i "../Watermark/Watermark.png" \
	-movflags faststart \
	$preset \
	-filter_complex \
	"color=black:16x16:d=$total[base];
	[0:v]scale=-2:'max(1080,ih)',setpts=PTS-STARTPTS[v0]; 
	[1:v]scale=-2:'max(1080,ih)',fade=in:st=0:d=$fadeduration1:alpha=1,setpts=PTS-STARTPTS+(($fadetime1)/TB)[v1]; 
	[2:v]fade=in:st=0:d=$fadeduration2:alpha=1,setpts=PTS-STARTPTS+(($fadetime2)/TB)[v2]; 
	[base][v0]scale2ref[base][v0];
	[base][v0]overlay[tmp]; 
	[tmp][v1]overlay[tmp2]; 
	[tmp2][v2]overlay,setsar=1[video]; 
	$wmstream1 
	$wmstream2
	[video][wm_scaled]overlay=$wmpos:shortest=1:format=rgb[outv];
	[0:a][1:a]acrossfade=d=$fadeduration1[aud];
	[aud][2:a]acrossfade=d=$fadeduration2[outa]" \
	-map "[outv]" -map "[outa]" -c:v libx264 -crf 17 -c:a libopus -shortest \
	-pix_fmt yuv420p $colour_metadata "$3"
	unset fadetime1
	unset fadetime2
fi

# afade=out:st=$fadetime1:d=$fadeduration1
# afade=out:st=0:d=$fadeduration2
# [0a][1a][2:a]concat=n=3:v=0:a=1[outa]
