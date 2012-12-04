#!/bin/bash
#Licensed under GPL 2
#Copyright 2009 Andrew Williams and Chris Cherrett
#set -x
## User configurable VARIABLES
#RGLIBRARIAN="Christopher Cherrett"  #Used for rosegarden xml
RGLIBRARIAN="Christopher Cherrett"  #Used for rosegarden xml
RGEMAIL="ccherrett@openoctave.org" #Used for the rosegarden xml
## Path to rosegarden config file
RGCONF="${HOME}/.kde/share/apps/rosegarden/autoload.rg" #Personal config file. NOTE: We will NOT overwrite this file
#RGCONF="/usr/share/apps/rosegarden/autoload.rg" #System wide default config
XSLTCONF="${HOME}/bin/rgd2midnam.xsl" #Path to xslt file used to convert rdg files to midnam
# array of mountpoints that will be used to map midi and audio devices to drive for optimization
#MOUNTPOINTS[0]="/mnt/sdb"
#MOUNTPOINTS[1]="/mnt/sdc"
#MOUNTPOINTS[0]="/home/chris/Drive1"
#MOUNTPOINTS[1]="/home/chris/Drive2"
#MOUNTPOINTS[2]="/home/chris/Drive3"
MOUNTPOINTS[0]="/home/chris/Drive3_SSD"
MOUNTPOINTS[1]="/home/chris/Drive4_SSD"

###############################################################################################################
###    END User Editing. If you edit below this line you are helping to extend this script :)                ##
###############################################################################################################

usage() {
	cat << EOF
usage: 	$0 -s <infile> -d <outfile> -c <channelnum> [-m <mode>] [-f] [-l <Your Name>] [-e <emailaddress>]

Converts Channels and Banks automatically

OPTIONS:
	-s Source lscp file or folder containing files to be parsed
	-d Destination parsed file or folder containing parsed files if -s = folder 
	-S With this you can pass a group of folders containing your lscp files [This is a comma separated list]
	-c This is the channel to start numbering
	-f Finalize mode, Creates a final lscp with all ports and banks, this should only be turned on if this is your final run
	-e Used for the email address in header of rosegarden xml files
	-l User for the librarian name in header of rosegarden xml files
	-m Instrument Load mode, 0 for ON_DEMAND, 1 for ON_DEMAND_HOLD, 2 for PERSISTENT. Default == 1
	-o Overwrite, This will overwrite previous runs without prompting
	-h Displays this help screen and exits

EOF
}

channelnum=
infile=
outfile=
FINAL_RUN=
DIRARRAY=
OVERWRITE=
MAP_DIRS=
MODE="ON_DEMAND_HOLD"

while getopts "hfoc:s:d:l:e:S:m:p:" OPTS
do
	case $OPTS in
		h)
			usage
			exit 0
			;;
		s)
			infile=$OPTARG;;
		S)
			DIRARRAY=$OPTARG;;
		d)
			outfile=$OPTARG;;
		c)
			channelnum=$OPTARG;;
		f)
			FINAL_RUN="true";;
		l)
			RGLIBRARIAN=$OPTARG;;
		o)
			OVERWRITE="true";;
		e)
			RGEMAIL=$OPTARG;;
		m)
			case $OPTARG in
				0)
					MODE="ON_DEMAND";;
				1)
					MODE="ON_DEMAND_HOLD";;
				2)
					MODE="PERSISTENT";;
			esac
			;;
		p)
			echo $OPTARG | read -a MOUNTPOINTS
			;;
		?)
			usage
			exit 1
			;;
	esac
done

#Make sure MODE is availabe to awk ENVIRON array
export MODE

if [[ -z $infile && -z $DIRARRAY ]]; then
	usage
	exit 1
fi

[[ -z $channelnum ]] && channelnum=0
[[ -z $outfile ]] && outfile=$(basename ${infile}).converted

if [[ $infile = $outfile ]]; then
	echo "Can not copy same file"
	exit 1
fi
#MAPINDEX=0
declare -a MIDIDEVICE
declare -a AUDIODEVICE
declare -a DRIVECOUNT

index=0
ec=${#MOUNTPOINTS[@]}
echo "Mount Array Size: $ec - Contents: ${MOUNTPOINTS[@]}"
while [[ "$index" -lt "$ec" ]]
do
	DRIVECOUNT[$index]=0
	MIDIDEVICE[$index]=0
	#echo "Drive Count: ${DRIVECOUNT[$index]}"
	index=$(($index + 1))
done

studioheader='RESET
SET VOLUME 0.83'
#
studiofooter=''
#
#midiheader='CREATE MIDI_INPUT_DEVICE ALSA
midiheader='CREATE MIDI_INPUT_DEVICE JACK NAME=%s
SET MIDI_INPUT_DEVICE_PARAMETER %d PORTS=%d'

##MIDI Port template
# device number, channel number, name
midiport1="SET MIDI_INPUT_PORT_PARAMETER %d %d NAME='%s'"
midiport2="SET MIDI_INPUT_PORT_PARAMETER %d %d JACK_BINDINGS=NONE"
#midiport2="SET MIDI_INPUT_PORT_PARAMETER %d %d ALSA_SEQ_BINDINGS=NONE"
#

chanheader="CREATE AUDIO_OUTPUT_DEVICE JACK ACTIVE=true CHANNELS=%d SAMPLERATE=44100 NAME='LinuxSampler%d'"

#Audio device channels
# device number, channel number, name
rchan1="SET AUDIO_OUTPUT_CHANNEL_PARAMETER %d %d NAME='1_%s'"
rchan2="SET AUDIO_OUTPUT_CHANNEL_PARAMETER %d %d JACK_BINDINGS=NONE"

lchan1="SET AUDIO_OUTPUT_CHANNEL_PARAMETER %d %d NAME='2_%s'"
lchan2="SET AUDIO_OUTPUT_CHANNEL_PARAMETER %d %d JACK_BINDINGS=NONE"
#
channeltmpl='ADD CHANNEL
SET CHANNEL MIDI_INPUT_DEVICE {chanindex} {mdevicenum}
SET CHANNEL MIDI_INPUT_PORT {chanindex} {chan}
SET CHANNEL MIDI_INPUT_CHANNEL {chanindex} 0
LOAD ENGINE GIG {chanindex}
SET CHANNEL VOLUME {chanindex} 1.0
SET CHANNEL MIDI_INSTRUMENT_MAP {chanindex} {mapindex}
SET CHANNEL AUDIO_OUTPUT_DEVICE {chanindex} {adevicenum}
SET CHANNEL AUDIO_OUTPUT_CHANNEL {chanindex} 0 {left}
SET CHANNEL AUDIO_OUTPUT_CHANNEL {chanindex} 1 {right}'
#LOAD INSTRUMENT NON_MODAL %s 0 0'

MIDIPORTSFILE=mconvert.ports
CHANNELFILE=mconvert.chan
CHANNELDEFFILE=mconvert.def
chanindex=0

#{{{
preamble='<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE rosegarden-data>
<rosegarden-data>
  <studio thrufilter="0" recordfilter="0">
    <device id="0" name="%s" type="midi">
      <librarian name="%s" email="%s"/>'

postamble='
    </device>
  </studio>
</rosegarden-data>'
bankstart='<bank name="%s" msb="0" lsb="%d">'
programid='<program id="%d" name="%s"/>'
bankend='</bank>'

devicestart_rgstudio='
    <device id="%d" name="%s" type="midi">
      <librarian name="%s" email="%s"/>'

deviceend_rgstudio='
</device>
'
rgd_studio_out="${HOME}/.mconvert/rgstudio.banks"

mnpreamble='<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE MIDINameDocument PUBLIC "-//MIDI Manufacturers Association//DTD MIDINameDocument 1.0//EN" "http://www.midi.org/dtds/MIDINameDocument10.dtd">
<MIDINameDocument>
  <Author>%s</Author>
  <MasterDeviceNames>
    <Manufacturer>Rosegarden</Manufacturer>
    <Model>%s</Model>'
mnpostamble='
  </MasterDeviceNames>
</MIDINameDocument>'
#}}}


function processFile() #{{{
{
	local in=$1
	local out=$2
	if [[ -f $out && -z ${OVERWRITE} ]]; then
		echo -n "The output file $out exists, Overwrite[y/n]?:  "
		read ANS
		case $ANS in
			y|Y)
			rm -fr $out;;
			*)
			return 1;;
		esac
		echo
	elif [[  -f $out && ${OVERWRITE} == true ]]; then
		echo "Removing old output file/path: ${out}"
		rm -rf ${out}
	fi

	banknumber=-1
	echo -n "Processing $in, Bank: "
	local bankname="blank" lastbankname=""
	local rgdout="/tmp/$$.convert"
	printf "$preamble\n" $(basename ${out%.*}) "${RGLIBRARIAN}" "${RGEMAIL}"| perl -p -e's/&(?!\w+?;)/&amp;/g' > $rgdout
	#echo "After First basename"
## Chris added this to deal with the extra variable(deviceid) in the preamble
	printf "$devicestart_rgstudio\n" "${channelnum}" $(basename ${out%.*}) "${RGLIBRARIAN}" "${RGEMAIL}"| perl -p -e's/&(?!\w+?;)/&amp;/g' >> $rgd_studio_out
	#echo "After Second basename"
	
	programnum=0
	
	local lsbname programname lsbnum=-1 firstfile channelname fullchannelname
	local count=0
	firstfile=$(head -3 $in|tail -1 |cut -d' ' -f8)
	while read -r line
	do
		lastbankname="$bankname"

		if [[ $(echo $line|cut -d' ' -f1) != "ADD" ]]; then
			#echo "Third basename: $(echo "$line"|cut -d' ' -f8|cut -d. -f1)"
			bankname=$(basename $(echo "$line"|cut -d' ' -f8|cut -d. -f1))
			lsbname=$(echo $bankname|sed -e 's/\\x20/_/g')
			programname=$(echo "$line"|cut -d' ' -f12-|tr -d '\015'| perl -p -w -e "s/\\\x20/_/g; s/^'//; s/\'$//; s/\\\'//g; s/ /_/g; s/\\\\//g; s/\\\"//g;") 
			#programnum=$(echo "$line"|cut -d' ' -f6)
		else
			bankname="skip"
			channelname=$(echo $line|cut -d' ' -f3-|sed -e 's/ //g' -e 's/PERF/P/' -e "s/'//g"|tr -d '\015')
			fullchannelname=$(echo $line|cut -d' ' -f3-|sed -e 's/ /_/g' -e "s/'//g"|tr -d '\015')
			#channelname=${channelname:0:16}
			#programnum=0
		fi

		if [[ $(echo $line |awk -F' ' '{print $1}') = "MAP" && "$bankname" = "$lastbankname" ]]; then
			printf "\t\t\t$programid\n" ${programnum} "${programname}" |perl -p -e's/&(?!\w+?;)/&amp;/g'>> $rgdout
			printf "\t\t\t$programid\n" ${programnum} "${programname}" |perl -p -e's/&(?!\w+?;)/&amp;/g'>> $rgd_studio_out

			echo "$line" |tr -d '\015' | sed -e "s/AL[[:space:]][[:digit:]]\{1,\}[[:space:]][[:digit:]]\{1,\}[[:space:]][[:digit:]]\{1,\}[[:space:]]/AL $channelnum $banknumber $programnum /" | awk '{$11=ENVIRON["MODE"]}1' >> $out
			echo "$line" |tr -d '\015' | sed -e "s/AL[[:space:]][[:digit:]]\{1,\}[[:space:]][[:digit:]]\{1,\}[[:space:]][[:digit:]]\{1,\}[[:space:]]/AL $channelnum $banknumber $programnum /" | awk '{$11=ENVIRON["MODE"]}1' >> LS_Master/LS_Master.lscp
			echo "$line" |tr -d '\015' | sed -e "s/AL[[:space:]][[:digit:]]\{1,\}[[:space:]][[:digit:]]\{1,\}[[:space:]][[:digit:]]\{1,\}[[:space:]]/AL $channelnum $banknumber $programnum /" | awk '{$11=ENVIRON["MODE"]}1' >> ${HOME}/.mconvert/studio-prep.lscp
			
			lsbnum=$(($lsbnum + 1))
			programnum=$(($programnum + 1))
		elif [[ $(echo $line |awk -F' ' '{print $1}') = "MAP" && "$bankname" != "$lastbankname"  ]]; then
			banknumber=`expr $banknumber + 1`
			lsbnum=0
			programnum=0
			
			[[ $banknumber != 0 ]] && printf "\t\t${bankend}\n" >> $rgdout
			printf "\t\t$bankstart\n" "${lsbname}" ${banknumber} | perl -p -e's/&(?!\w+?;)/&amp;/g' >> $rgdout
			printf "\t\t\t$programid\n" ${programnum} "${programname}" | perl -p -e's/&(?!\w+?;)/&amp;/g' >> $rgdout
			
			[[ $banknumber != 0 ]] && printf "\t\t${bankend}\n" >> $rgd_studio_out
			printf "\t\t$bankstart\n" "${lsbname}" ${banknumber} | perl -p -e's/&(?!\w+?;)/&amp;/g' >> $rgd_studio_out
			printf "\t\t\t$programid\n" ${programnum} "${programname}" | perl -p -e's/&(?!\w+?;)/&amp;/g' >> $rgd_studio_out
			
			echo -n "$banknumber "
			echo "$line" |tr -d '\015' | sed -e "s/AL[[:space:]][[:digit:]]\{1,\}[[:space:]][[:digit:]]\{1,\}[[:space:]][[:digit:]]\{1,\}[[:space:]]/AL $channelnum $banknumber $programnum /" | awk '{$11=ENVIRON["MODE"]}1' >> $out
			echo "$line" |tr -d '\015' | sed -e "s/AL[[:space:]][[:digit:]]\{1,\}[[:space:]][[:digit:]]\{1,\}[[:space:]][[:digit:]]\{1,\}[[:space:]]/AL $channelnum $banknumber $programnum /" | awk '{$11=ENVIRON["MODE"]}1' >> LS_Master/LS_Master.lscp
			echo "$line" |tr -d '\015' | sed -e "s/AL[[:space:]][[:digit:]]\{1,\}[[:space:]][[:digit:]]\{1,\}[[:space:]][[:digit:]]\{1,\}[[:space:]]/AL $channelnum $banknumber $programnum /" | awk '{$11=ENVIRON["MODE"]}1' >> ${HOME}/.mconvert/studio-prep.lscp
			
			lsbnum=$(($lsbnum + 1))
			programnum=$(($programnum + 1))
		else ## Everything else that is not a MAP line
			echo "$line" |tr -d '\015' >>$out
			echo "$line" |tr -d '\015' >>LS_Master/LS_Master.lscp
			echo "$line" |tr -d '\015' >> ${HOME}/.mconvert/studio-prep.lscp
		fi
		count=$(($count + 1))
	done < $in

	printf "\t\t${bankend}\n" >> $rgdout
	printf "${postamble}\n" >> $rgdout
	
	printf "\t\t${bankend}\n" >> $rgd_studio_out
	printf "\t${deviceend_rgstudio}\n" >> $rgd_studio_out
	
	echo
	echo "Total Banks: $(($banknumber + 1))"
	midnamfile=${out%%.*}

	echo '<?xml version="1.0" encoding="UTF-8"?>' > "${midnamfile}.midnam"
	echo '<!DOCTYPE MIDINameDocument PUBLIC "-//MIDI Manufacturers Association//DTD MIDINameDocument 1.0//EN" "http://www.midi.org/dtds/MIDINameDocument10.dtd">' >> "${midnamfile}.midnam"
	echo >> "${midnamfile}.midnam"
	cat ${rgdout} | xsltproc --param filename \"$(basename ${midnamfile})\" ${XSLTCONF} - | xmllint --format --encode UTF-8 --dtdvalid http://www.midi.org/dtds/MIDINameDocument10.dtd - | sed '1d' >> "${midnamfile}.midnam"
	echo "END Generating ${midnamfile}.midnam"
	cat ${rgdout} | gzip -9 -c > ${out%%.*}.rgd
	rm -f ${rgdout}
	
	#mapindex=$(grep $fullchannelname ${HOME}/.mconvert/studio-prep.lscp|tail -n1|cut -d' ' -f4)
	appendTemplate "$channelnum" "$channelname" "$firstfile" "$fullchannelname" "$chanindex"
	chanindex=$(($chanindex + 1))
} ##}}}

appendTemplate() #{{{
{
	local mapindex=$1 channel cname=$2 fname=$3 fullcname=$4 gigindex=$5 audiodev mididev
	index=0
	ec=${#MOUNTPOINTS[@]}
	while [[ "$index" -lt "$ec" ]]
	do
		if echo $fname | grep -q ${MOUNTPOINTS[$index]} ; then
			channel=${DRIVECOUNT[$index]}
			midichannel=${MIDIDEVICE[$index]}
			MIDIDEVICE[$index]=$((${MIDIDEVICE[$index]} + 1))
			DRIVECOUNT[$index]=$(($channel + 1))
			# commented to make the mono setup work
			#if [[ "$channel" != "0" ]];then
			#	channel=${DRIVECOUNT[$index]}
			#fi
			mididev=$index
			audiodev=$index
			break;
		fi
		index=$(($index + 1))
	done
	
	#fbase=$(basename $fullcname)
	#mapindex=$(grep ${MOUNTPOINTS[$index]} ${HOME}/.mconvert/studio-prep.lscp | grep $fbase | tail -n1 | cut -d' ' -f4)
	echo "MAPINDEX: $mapindex"
	echo "[Channel: $channel] [Channel Name: $cname] [Filename: $fname]"
	
	if [[ -f ${HOME}/.mconvert/${MIDIPORTSFILE} && $channel -eq 0 && -z ${OVERWRITE} ]]; then
		echo "This looks like a fresh run and template files already exists."
		echo "Please remove ${MIDIPORTSFILE} from ${HOME}/.mconvert then press ENTER to continue"
		read
	elif [[ -f ${HOME}/.mconvert/${MIDIPORTSFILE} && $channel -eq 0 && "${OVERWRITE}" = "true" ]]; then
		rm -f ${HOME}/.mconvert/${MIDIPORTSFILE}
	fi

	echo "mididev: $mididev channel: $midichannel cname: $cname"
	printf "${midiport1}\n" $mididev $midichannel "$cname" >> ${HOME}/.mconvert/${MIDIPORTSFILE}_$mididev
	printf "${midiport2}\n" $mididev $midichannel >> ${HOME}/.mconvert/${MIDIPORTSFILE}_$mididev
	
	#leftchan=$channel
	echo -n "Port: $audiodev -- Left Channel: $channel"
	#[[ $channel -ne 0 ]] && leftchan=$(($(tail -n1 ${HOME}/.mconvert/${CHANNELFILE}|awk '{print $4}') + 1))
	printf "${rchan1}\n" $audiodev $channel "${fullcname}" >> ${HOME}/.mconvert/${CHANNELFILE}_$audiodev
	printf "${rchan2}\n" $audiodev $channel >> ${HOME}/.mconvert/${CHANNELFILE}_$audiodev
	
	rightchannel=$(($channel + 1))
	DRIVECOUNT[$audiodev]=$rightchannel

	## I commented the following lines to eliminate the stereo setup and go to mono
	#echo " -- Right Channel: $rightchannel"
	#printf "${lchan1}\n" $audiodev $rightchannel "${fullcname}" >> ${HOME}/.mconvert/${CHANNELFILE}_$audiodev
	#printf "${lchan2}\n" $audiodev $rightchannel  >> ${HOME}/.mconvert/${CHANNELFILE}_$audiodev

	#Ctmpl=$(echo "$channeltmpl"|sed -e "s/{chan}/${midichannel}/g" -e "s/{adevicenum}/${audiodev}/g" -e "s/{mapindex}/${gigindex}/g" -e "s/{chanindex}/${gigindex}/g")
	#echo -e "${Ctmpl}\n"| sed -e "s/{left}/${channel}/g" -e "s/{right}/${rightchannel}/g" -e "s/{mdevicenum}/${mididev}/g">> ${HOME}/.mconvert/${CHANNELDEFFILE}
	
	Ctmpl=$(echo "$channeltmpl"|sed -e "s/{chan}/${midichannel}/g" -e "s/{adevicenum}/${audiodev}/g" -e "s/{mapindex}/${gigindex}/g" -e "s/{chanindex}/${gigindex}/g")
	echo -e "${Ctmpl}\n"| sed -e "s/{left}/${channel}/g" -e "s/{right}/${channel}/g" -e "s/{mdevicenum}/${mididev}/g">> ${HOME}/.mconvert/${CHANNELDEFFILE}

} ##}}}

finalize_LS_Studio() #{{{
{
	#totalmaps=$(($(tail -n1 ${HOME}/.mconvert/${MIDIPORTSFILE}|awk '{print $4}') + 1))
	studio="${HOME}/.mconvert/LS_Studio_Final.lscp"
	local devcount mididevcount
	echo -e "${studioheader}\n" > $studio
	index=0
	ec=${#MOUNTPOINTS[@]}
	midiportname="LSJPort"
	while [[ "$index" -lt "$ec" ]]
	do
		midiportnametmp=$midiportname$index
		echo "Device count ${DRIVECOUNT[@]}"
		devcount=${DRIVECOUNT[$index]}
		mididevcount=${MIDIDEVICE[$index]}
		echo "Devount for channel: $index == $devcount"
		printf "${midiheader}\n" $midiportnametmp $index $mididevcount >> $studio
		#printf "${midiheader}\n" $index $mididevcount >> $studio
		cat ${HOME}/.mconvert/${MIDIPORTSFILE}_$index >> $studio

		echo -e "\n\n" >> $studio
		#commented out to fix the over count of audio channels for mono
		#devcount=$(($devcount + 1))
		printf "${chanheader}\n" $devcount $index >> $studio
		cat ${HOME}/.mconvert/${CHANNELFILE}_$index >> $studio
		echo -e "\n\n" >> $studio
		
		index=$(($index + 1))
	done

	echo -e "\n\n" >> $studio
	cat ${HOME}/.mconvert/studio-prep.lscp >> $studio
	#index=0
	#while [[ "$index" -lt "$ec" ]]
	#do
		echo -e "\n\n" >> $studio
		cat ${HOME}/.mconvert/${CHANNELDEFFILE} >> $studio
		#index=$(($index + 1))
	#done
	
} #}}}

finalize_RG_Studio() #{{{
{
	rgstudio="${HOME}/.mconvert/RG_Studio_Final.rgd"
	if [[ -f ${RGCONF} ]]; then
		zcat ${RGCONF}|sed -n '/^<?xml/,/^<studio/p' >${rgstudio}
		cat ${rgd_studio_out} >> ${rgstudio}
		zcat ${RGCONF}|sed -n '/^<\/studio/,/^<\/rosegarden-data>/p' >>${rgstudio}
	fi
	cat "${rgstudio}" |gzip -9 > "${rgstudio%.*}.rg"
} #}}}


finalize_MIDNAM()  #{{{
{
	local FPATH=$1
	shopt -s extglob
	FPATH=${FPATH##+([[:space:]])} fpath=${FPATH%%+([[:space:]])}
	shopt -u extglob
	echo "Inside finalize_MIDNAM [Path = $FPATH]"
	if test -d ${FPATH} && test -d ${FPATH}/MIDNAM_MAPS ; then
		pushd ${FPATH}/MIDNAM_MAPS >/dev/null
		#echo "Inside $PWD"
		#ls
		#echo "End CONTENTS"
		local mytmp="/tmp/$$.master.midnam"
		local myfile=$(basename "$1")
		echo "" > $mytmp
		local mydirm="${PWD}"			
		echo "-> Generating master midnam for: ${myfile} [ ${HOME}/.mconvert/${myfile}.midnam ]"
		echo -e -n "Processing: [ " 
		shopt -s nullglob
		for mn in *.midnam; do 
			echo -n "$mn "
			cat "$mn" | sed -n -e '/<Model>/,/<\/MasterDeviceNames>/p' "${mn}" | sed 1d - |sed '$d' >> "${mytmp}"
		done
		shopt -u nullglob
		echo "]"
		popd >/dev/null
		printf "${mnpreamble}" "${RGLIBRARIAN}" "$myfile" >${HOME}/.mconvert/"${myfile}".midnam
		cat $mytmp >>${HOME}/.mconvert/"${myfile}".midnam
		printf "${mnpostamble}" >>${HOME}/.mconvert/"${myfile}".midnam
		rm -f $mytmp
	fi
} #}}}

runParser() #{{{
{
	if [[ -d $infile ]]; then
		if [[ $channelnum -eq 0 && -d ${HOME}/.mconvert ]]; then
			mv ${HOME}/.mconvert ${HOME}/mconvert.`date +%Y%m%d`.$$
		fi
		mkdir -p ${HOME}/.mconvert
		
		if [[ $channelnum  -eq 0 && $OVERWRITE == true ]];then
			rm -rf "${infile}"/{RG_MAPS,MIDNAM_MAPS,LS_Single,LS_Master}
		fi
		mkdir -p ${infile}/{RG_MAPS,MIDNAM_MAPS,LS_Single,LS_Master}
		pushd "$infile" >/dev/null
		MAP_DIR="${MAP_DIR} $PWD"
		pushd "${outfile}" >/dev/null
		fpath=${PWD}
		popd >/dev/null
		for f in `ls *.lscp`
		do
			processFile "$f" "${fpath}"/`basename "$f"`
			channelnum=$(($channelnum + 1))
		done
	else
		processFile "$infile" "$outfile"
		channelnum=$(($channelnum + 1))
	fi
	mv "$outfile"/*.rgd RG_MAPS
	mv "$outfile"/*.midnam MIDNAM_MAPS
} #}}}

cleanup()
{
	rm -rf ${HOME}/.mconvert/{mconvert.chan*,mconvert.ports*,studio-prep.lscp,mconvert.def*,rgstudio.banks*,RG_Studio_Final.rgd}
}

## Do the heavy lifting
if [[ -z $DIRARRAY ]]; then
	runParser
else
	declare -a DIRS
	DIRS=($(echo "$DIRARRAY" | tr ',' ' '))
	for p in ${DIRS[@]}
	do
		infile="$p"
		[[ -d "$infile" ]] && runParser
	done
fi

if [[ "${FINAL_RUN}" = "true" ]]; then
	echo "Finalize detected"
	echo -e "-> Finalizing linuxsampler mappings\n\t ${HOME}/.mconvert/LS_Studio_Final.lscp ]"
	finalize_LS_Studio
	echo -e "-> Finalizing rosegarden studio file\n\t [ ${HOME}/.mconvert/RG_Studio_Final.rg ]"
	finalize_RG_Studio
	echo "-> Finalizing midnam file[s]"
	declare -a OPTDIRS
	OPTDIRS=($(echo $MAP_DIR))
	for p in ${OPTDIRS[@]}
	do
		finalize_MIDNAM "${p}"
	done
	cleanup
fi
echo "Next Channel increment is: $channelnum"
