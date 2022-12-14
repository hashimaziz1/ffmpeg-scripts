#!/bin/bash
set -o errexit
set -o pipefail

watermark="D:\Users\Hashim\Documents\Projects\YouTube Channel 1\Meta\Watermark\Watermark.png"

err='\e[31m'
warn='\e[33m'
rc='\033[0m' # Reset colour

usage() {
	echo
	echo "Pass an image input, an audio input and an output name."
	echo "usage: `basename $0` frame.jpg audio.opus output.mp4"
	echo " -h --help     Print this help."
	echo " -f --final    Disable the ultrafast preset to produce a final file."
	exit
}

if [ $# -lt 2 ]; then usage
else
	preset="-preset ultrafast"
	length1="$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$2" | tr -d $'\r')"
	length2="$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 outro.mp4 | tr -d $'\r')"
	wmlength="$(echo $length1 - 5 | bc)"
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
	
	read -p "Enter fade duration in seconds: " -ei 2 fadeduration
	if ! [[ "$fadeduration" =~ ^[0-9]+$ ]] || [[ "$fadeduration" -eq 2 ]]; then 
		fadeduration=2 
		echo -e "${warn}Defaulting to $fadeduration seconds.${rc}"
	else echo "Using fade duration of $fadeduration."
	fi

	wmstream1="[3:v]lut=a=val*0.7,fade=in:st=15:d=3:alpha=1,fade=out:st=$wmlength:d=2:alpha=1[v3];"
 	wmstream2="[v3][tmp2]scale2ref=w=oh*mdar:h=ih*0.07[wm_scaled][video];"
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
		while [[ -z "$fadetime" ]]; do
		echo
		read -p "Enter custom start time in seconds: " fadetime
		echo "Using custom fade time of $fadetime seconds from first input.".
	done
  fi
	if [[ -z "$fadetime" ]]; then fadetime="$(echo "$length1" - "$fadeduration" | tr -d $'\r' | bc)" && 
		echo -e "${warn}Defaulting to adding fade -$fadeduration seconds from first input, at $fadetime seconds.${rc}" 
	fi
 	total="$(echo "$length1 + $length2 - $fadeduration" | tr -d $'\r' | bc)"
	ffmpeg -y -hide_banner \
	-loop 1 -t 2 -i "$1" -i "$2" -i "outro.mp4" -loop 1 -i "../Watermark/Watermark.png" \
	-movflags faststart \
	$preset \
	-filter_complex \
	"color=black:16x16:d=$total[base];
	[0:v]fade=in:st=0:d=2,scale=-2:'max(1080,ih)'::flags=lanczos,setpts=PTS-STARTPTS[v0];
	[2:v]fade=in:st=0:d=$fadeduration:alpha=1,setpts=PTS-STARTPTS+(($fadetime)/TB)[v2];
	$wmstream1
	[base][v0]scale2ref[base][v0];
	[base][v0]overlay[tmp];
	[tmp][v2]overlay,setsar=1[tmp2];
	$wmstream2
	[video][wm_scaled]overlay=$wmpos:shortest=1:format=rgb[outv];
	[1:a]afade=out:st=$fadetime:d=$fadeduration[1a];
	[1a][2:a]acrossfade=d=$fadeduration[outa]" \
	-map "[outv]" -map "[outa]" -c:v libx264 -crf 18 -c:a libopus -pix_fmt yuv420p "$3"
	unset fadetime
fi

# EXTRA STREAM FOR ARTIST IMAGE
# [4:v]fade=in:st=0.2:d=2:alpha=1,fade=out:st=45:d=3:alpha=1[v4];
# [v4][outv]scale2ref=w=oh*mdar:h=ih*0.3[wm_scaled][video];
# [video][wm_scaled]overlay=W-w-65:65:shortest=1:format=auto[final];" 