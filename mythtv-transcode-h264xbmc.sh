#!/bin/bash

# MythTV auto-transcode to mp4 (low res leave commerials, high res remove, low
# res remove).  This does not alter the original files or update mythtv
# databases (it can, but that hasn't proved helpful to me since I don't use
# mythfrontend to view them).
#
# The goal of this script is to convert the full mpg sized files to mp4
# so that XBMC or iOS devices can play them natively.  
#
# Since I don't alter or care about the source mpg files or alter the mythdb,
# you may want to manually purge the source files or have a job that
# comes through on a schedule to remove them.  Something similar to this would
# remove files older than 5 days.
# find /var/lib/mythtv/recordings -name \*.mpg -mtime +5 -exec rm -f "{}" \;

# Arguments
# $1 must be the directory/file to be transcoded.
# $2 is file extension
# $3 must be chanid
# $4 must be starttime
# $5 must be "LOW" for low res or "HIGH" for high-res or "LOWREMC" for low but remove commercials
#
# The full userjob command in mythtv-setup should look like this:
# /path/to/this-script/mythtv-transcode-h264xbmc.sh "%DIR%/%FILE%" "%DIR%/%TITLE% - # %PROGSTART%.mkv" "%CHANID%" "%STARTTIME%" "LOW|HIGH|LOWREMC"
# I have 3 setup in my MythTV setup that look like this:
# /etc/mythtv/mythtv-transcode-h264xbmc.sh "%DIR%/%FILE%" "mp4" "%CHANID%" "%STARTTIME%" "HIGH"
# /etc/mythtv/mythtv-transcode-h264xbmc.sh "%DIR%/%FILE%" "mp4" "%CHANID%" "%STARTTIME%" "LOWREMC"
# /etc/mythtv/mythtv-transcode-h264xbmc.sh "%DIR%/%FILE%" "mp4" "%CHANID%" "%STARTTIME%" "LOW"
#
# Logs for this are written to /var/log/mythtv/mythbackend.log, so check there
# if you have issues. This script was created and updated over 3 years and
# never meant for public consumption, so proceed with caution.
#
# Author: Brian Wilson <bubba@bubba.org>
#

# You need to install HandBrake CLI to transcode your shows!
# http://handbrake.fr/downloads2.php or
# Build HandBrake: http://r3dux.org/2010/05/how-to-build-a-working-version-of-handbrake-for-ubuntu-10-04/
HANDBRAKECLI="/usr/local/bin/HandBrakeCLI"

# Path to NFO file creater (see https://github.com/bdwilson/XBMCnfo)
# Final filename will be passed as the last argument to this script
TVNFO="/etc/mythtv/XBMCnfo.pl"
TVARGS="-forcetitle -tvshow -usefirst -deldup -overwrite -duration -altimg"

# optional addtional job to run after processing. Any addtl args can
# be added in the respective variable below.
# Final filename will be passed as the last argument to this script
ADDLJOB=""
ADDLARGS=""

# Variables for XBMC API calls (requires curl to be installed)
# XBMCSERVER should be set to IP:PORT. Unauthenticated web API calls
# need to be enabled on your XBMC server.  Leave this blank to not
# have this script tell XBMC to re-scan Show/Season directories.
# 
# XBMCBASEPATH should be base path as defined on your XBMC server. 
# In most cases this will be a remote SMB location with or without password.
# If you need help finding this path, you can run a command against 
# your XBMC database:
# mysql -u xbmc -pxbmc xbmc_video60 -e 'select strPath from path where strContent="tvshows"'
XBMCSERVER="192.168.1.211:8080"
XBMCBASEPATH="smb://user:pass@SERVER/media/TV"

# a temporary working directory (must be writable by mythtv user)
TEMPDIR="/tmp"

# MySQL database login information (for mythconverg database)
DATABASEUSER="mythtv"
DATABASEPASSWORD="mythtv"

# MythTV Install Prefix (make sure this matches with the directory where MythTV is installed)
INSTALLPREFIX="/usr/bin"

# Base dir where your TV shows will be stored (Mapped as a TV share in XBMC)
TVBASE="/media/TV"

# Who to trust if you get Season/Episode data from both MythTV and
# MythicalLibrarian.  Either MYTHTV or MYTHICAL
# Note, even if this is set to MYTHTV, if both MythicalLibrarian and
# Myth have the same episode title, then we will use MythicalLibarian
# data. This is because their season/episode numbering for some shows,
# but we only want to trust them if the episode titles from mythtv and
# ML match.. got it?
TRUST="MYTHTV"

# Download and install MythicalLibrarian - optional 
# works to map Episode Name + Episode description -> SXXEXX format. 
# I would leave this variable empty and rely on MythTV listing data if
# possible, the only issue is that Season Episode info might not be right :(
# If you do use ML, make sure you configure mythicalLibarian UserJob:
# /etc/mythicalLibrarian/JobSucessful BEFORE you run mythicalSetup
#
# #!/bin/bash
# echo SHOWFILENAME: $ShowFileName
#
# Then set SYMLINK=LINK in the mythicalLibrarian script itself after setup
MYTHICALTV="/home/mythtv/.mythicalLibrarian/mythicalSetup/mythicalLibrarian"

# don't change anything below here.
SCRIPT="mythtv-transcode-h264xbmc"
DIRNAME=`dirname "$1"`
EXTENSION=$2
BASENAME2=`echo "$1" | awk -F/ '{print $NF}'`
INFILE=$1
SQL="update-database.sql.$$"
DEBUG=0
FLAG=0

if [ "$5" = "LOW" ]; then 
	FLAG=1
elif [ "$5" = "LOWREMC" ]; then
	FLAG=2
fi

if [ "$DEBUG" -eq 1 ]; then
	TVBASE="/media/TV"
fi

echo "$SCRIPT: Running $0 $@"

# go to correct working dir
cd $TEMPDIR
# Use mythicalLibrian to get Season & Episode info.
if [ -x "$MYTHICALTV" ]; then
   OUT=`$MYTHICALTV "$1" > /tmp/mythical_$$`
   CONFIDENCE=`egrep '^CONFIDENCE:' /tmp/mythical_$$ | cut -c 12`

   MATCH=`grep SHOWFILENAME /tmp/mythical_$$`
   if [ ! -z "$MATCH" ] && [ "${CONFIDENCE}" -gt 0 ] && [ "${CONFIDENCE//[0-9]*}" = "" ]; then
                SEASONO=`echo "$MATCH" | sed 's/.*S\([0-9]\)\([0-9]\)E.*/\1/'`
                SEASONT=`echo "$MATCH" | sed 's/.*S\([0-9]\)\([0-9]\)E.*/\2/'`
                MYLSEASON="${SEASONO}${SEASONT}"
                TMP=`echo "$SEASONO" | grep "^[0-9]*$"`
                RET=$?
                TMP=`echo "$SEASONT" | grep "^[0-9]*$"`
                RET2=$?
		MYLTITLE=`echo "$MATCH" | sed 's/ S\([0-9]\)\([0-9]\)E.*//'`
		MYLTITLE=`echo "$MYLTITLE" | sed 's/SHOWFILENAME: //'`
		#MYLTEPISODE=`echo "$MATCH" | awk -F\( '{print \$2}' | awk -F\) '{print \$1}'`
		MYLTEPISODE=`grep 'EPISODE NUMBER' /tmp/mythical_$$ | awk -F "EPISODE:" '{print $2}' | awk -F " EPISODE" '{print $1}'`
                if [ "$RET" -eq 0 ] && [ "$RET2" -eq 0 ]; then
                        if [ "$SEASONO" -eq 0 ]; then
                                MYLSEASONDIR="Season $SEASONT"
                        else
                                MYLSEASONDIR="Season $MYLSEASON"
                        fi
                        MYLEPISODENUM=`echo "$MATCH" | sed 's/.*S\([0-9]*\)E\([0-9]*\).*/\2/'`
                        echo "$SCRIPT: FOUND MYL Season/Episode info: Show Name: $MYLTITLE Season: $MYLSEASON Episode: $MYLEPISODENUM Season Dir: $MYLSEASONDIR Confidence: $CONFIDENCE"
                else
                        echo "$SCRIPT: Unable to find legitimate season/episode: $MATCH"
                        MYLSEASON=""
                        MYLEPISODENUM=""
                fi
                MYLPLOT=`grep PLOT /tmp/mythical_$$ | awk -F": " '{print $2}'`
		#this is what was searched for, not what was returned..., only use what was searched for if confidence is low
                #MYLTEPISODE=`grep SEARCHING /tmp/mythical_$$ | awk -F "EPISODE: " '{print $2}'`
                echo "$SCRIPT: Listing info: Show Name: $MYLTITLE Plot: $MYLPLOT Episode: $MYLEPISODE MYLTEPISODE title: $MYLTEPISODE"
   else
        # if confidence is 0, then we take whatever we got from our listings
        # database.  I don't know why I'm setting vars below here because I'm
        # not using the data if confidence is 0 or less
        MYLPLOT=`grep PLOT /tmp/mythical_$$ | awk -F": " '{print $2}'`
        MYLTEPISODE=`grep SEARCHING /tmp/mythical_$$ | awk -F "EPISODE: " '{print $2}'`
	MTVTEPISODE=`echo "$MTVTEPISODE" |tr -d '!|\?*<":>+[],/'"'"`
	MTVTEPISODE=`echo "$MTVTEPISODE" |sed 's/\;/ /g'`
        echo "$SCRIPT: Confidence was $CONFIDENCE; Skipping MythicalLibrary"
	# using Lising info: Plot: $MYLPLOT Episode: $MYLTEPISODE"
        #SEASONDIR=""
   fi
fi

echo "select programid from recorded where chanid='$3' and starttime='$4';" > $SQL
PROGRAMID=`mysql --user=$DATABASEUSER --password=$DATABASEPASSWORD mythconverg < $SQL | grep -v programid`
if [ ! -z "$PROGRAMID" ]; then
        echo "select distinct originalairdate from program where programid='$PROGRAMID';" > $SQL
        AIRDATE=`mysql --user=$DATABASEUSER --password=$DATABASEPASSWORD mythconverg < $SQL | grep -v originalairdate`
        echo "select distinct title from program where programid='$PROGRAMID';" > $SQL
        MTVTITLE=`mysql --user=$DATABASEUSER --password=$DATABASEPASSWORD mythconverg < $SQL | grep -v title`
        echo "select distinct description from program where programid='$PROGRAMID';" > $SQL
        MTVPLOT=`mysql --user=$DATABASEUSER --password=$DATABASEPASSWORD mythconverg < $SQL | grep -v description`
        echo "select distinct syndicatedepisodenumber from program where programid='$PROGRAMID';" > $SQL
        MTVEPISODENUM=`mysql --user=$DATABASEUSER --password=$DATABASEPASSWORD mythconverg < $SQL | grep -v syndicatedepisodenumber`
        echo "select distinct subtitle from program where programid='$PROGRAMID';" > $SQL
        MTVTEPISODE=`mysql --user=$DATABASEUSER --password=$DATABASEPASSWORD mythconverg < $SQL | grep -v subtitle`
	MTVTEPISODE=`echo "$MTVTEPISODE" |tr -d '!|\?*<":>+[],/'"'"`
	MTVTEPISODE=`echo "$MTVTEPISODE" |sed 's/\;/ /g'`
	FOUNDMTV=0
	FOUNDMYL=0
	# process MythTV Episode/Season Data
	if [ ! -z "${MTVEPISODENUM}" ]; then
		if [ "${MTVEPISODENUM//[0-9]*}" = "" ] && [ ${MTVEPISODENUM} -lt 9999 ]; then
			# using MythTV data and EPISODENUM is a natural number less
			# than 9999 (hopefully there are no shows with > 99 seasons and
			# 99 episodes 
        		MTVSEASON=`echo $MTVEPISODENUM| sed -r 's/([0-9]+)[0-9][0-9]/\1/'`
        		MTVEPISODENUM=`echo $MTVEPISODENUM| sed -r 's/[0-9]+([0-9][0-9])/\1/'`
        		TMP=`echo "$MTVSEASON" | grep "^0*$"`
        		if [ -z "${TMP}" ] && [ ${MTVSEASON} -lt 10 ]; then
        			MTVSEASONDIR="Season $MTVSEASON"
               		 	MTVSEASON="0${MTVSEASON}"
			else
        			MTVSEASONDIR="Season $MTVSEASON"
        		fi
        		echo "$SCRIPT: Found MythTV Data...........: SEASON: $MTVSEASON EPISODE: $MTVEPISODENUM SEASONDIR: $MTVSEASONDIR"
			FOUNDMTV=1
		fi
	fi
	# process MythicalLibrarian Episode/Season Data
	if [ ! -z "${MYLEPISODENUM}" ] && [ ! -z "${MYLSEASON}" ]; then 
		if [ "${MYLEPISODENUM//[0-9]*}" = "" ] && [ "${MYLSEASON//[0-9]*}" = "" ] && [ "${MYLEPISODENUM}" -lt 99 ] && [ "${MYLSEASON}" -lt 99 ] ; then 
        		echo "$SCRIPT: Found MythicalLibrarian Data: SEASON: $MYLSEASON EPISODE: $MYLEPISODENUM SEASONDIR: $MYLSEASONDIR"
			FOUNDMYL=1
		fi
	fi
	# Decide which data to use... 
	if [ $FOUNDMYL -eq 0 ] && [ $FOUNDMTV -eq 0 ]; then 
		#if [ ! -z "$EPISODE" ]; then 
		#	EPISODENUM="$EPISODE"
		#fi
		#SEASON=""
        	echo "$SCRIPT: Not enough data to use: SEASON: $SEASON EPISODE: $EPISODENUM SEASONDIR: $SEASONDIR"
	fi
	AGREE=0
	if [ $FOUNDMYL -eq 1 ] && [ $FOUNDMTV -eq 1 ]; then
		# I'm not doing anythign with the agree stuff.. but it's here
		if [ "$MYLSEASON" == "$MTVSEASON" ] && [ "$MYLEPISODNUM" == "$MTVEPISODENUM" ]; then
			echo "$SCRIPT: Both MythTV and MythicalLibrarian agree on Season/Episode number."
			AGREE=1
		else 
			echo "$SCRIPT: Both MythTV and MythicalLibrarian differ on Season/Episode number."
		fi
		# If titles from MythTV and MythicalLibarian match, trust
		# MythicalLibrarian.  Data just seems to be better if they
		# match... :)
		if [ "$MTVTEPISODE" == "$MYLTEPISODE" ]; then
			echo "$SCRIPT: Episode titles match, trusting MythicalLibrarian"
			TRUST="MYTHICAL";
		fi

		echo "$SCRIPT: Found data for both MythTV and MythicalLibrarian. Using $TRUST"
		if [ "${TRUST}" = "MYTHTV" ]; then	
			echo "$SCRIPT: Using data from MythTV."
			FOUNDMYL=0
			FOUNDMTV=1
		else 
			echo "$SCRIPT: Using data from MythicalLibrarian."
			FOUNDMYL=1
			FOUNDMTV=0
		fi
	fi
	if [ $FOUNDMYL -eq 1 ]; then 
		SEASONDIR=$MYLSEASONDIR
		SEASON=$MYLSEASON
		EPISODENUM=$MYLEPISODENUM
		TEPISODE=$MYLTEPISODE
		PLOT=$MYLPLOT
		#TITLE=$MYLTITLE  Always use show name from MythTV...4/25/2013
		TITLE=$MTVTITLE
	else 
		SEASONDIR=$MTVSEASONDIR
		SEASON=$MTVSEASON
		EPISODENUM=$MTVEPISODENUM
		TEPISODE=$MTVTEPISODE
		PLOT=$MTVPLOT
		TITLE=$MTVTITLE
	fi

	if [ ! -z "$TEPISODE" ]; then 
		EPISODE="$TEPISODE"
	fi	
        echo "$SCRIPT: TITLE: $TITLE TEPISODE: $TEPISODE SEASONDIR: $SEASONDIR AIRDATE: $AIRDATE EPISODENUM: $EPISODENUM SEASON: $SEASON BASENAME: $BASENAME 4:$4"
fi

if [ ! -z "$TITLE" ]; then
	BASENAME=`echo "$TITLE" | sed 's/ /./g' | sed 's/&/and/g' | sed 's/\;/./g'`
	BASENAME=`echo "$BASENAME" |tr -d '!|\?*<":;>+[]/'"'"`
	if [ ! -z "$EPISODE" ] && [ -z "$SEASON" ]; then
		if [ -z "$EPISODENUM" ]; then
			echo "$SCRIPT: Setting EPISODENUM to OTA"
			EPISODENUM="OTA"
		fi
        	#BASENAME=`echo $BASENAME | awk -F" -" '{print $1}'`
        	BASENAME="$BASENAME-$EPISODE-$EPISODENUM.$EXTENSION"
	elif [ ! -z "$EPISODE" ] && [ ! -z "$SEASON" ] && [ ! -z "$EPISODENUM" ]; then
		BASENAME="$BASENAME-$EPISODE-S${SEASON}E${EPISODENUM}.$EXTENSION"
        elif [ ! -z "$EPISODE" ] && [ ! -z "$SEASON" ]; then
		BASENAME="$BASENAME-S${SEASON}E${EPISODE}.$EXTENSION"
	else
		#BASENAME="$BASENAME-$4.$EXTENSION"
		# change 12/25/2012
		BASENAME="$BASENAME-$BASENAME-OTA.$EXTENSION"
		#BASENAME="$BASENAME-$BASENAME-S00E00.$EXTENSION"
	fi
else 
	BASENAME="$3-$4.$EXTENSION"
fi

#### Insert any custom code here if you wish to remove data/skip conversion of particular 
# episodes/Seasons.  For instance, if I want to skip processing of all Arthur seasons
# less than season 11, then you'd do this.
if [ "$TITLE" = "Arthur" ] && [ "$SEASON" -lt 11 ]; then
        echo "$SCRIPT: Exiting out since this is $TITLE and season is < $SEASON"
        exit
fi
if [ "$TITLE" = "Martha Speaks" ] && [ "$SEASON" -eq 1 ] && [ "$EPISODENUM" -lt 21]; then
        echo "$SCRIPT: Exiting out since this is $TITLE and season is $SEASON and $EPISODENUM < 21"
        exit
fi
####

echo "$SCRIPT: Setting BASENAME to be $BASENAME"

# remove commercials 
if [ "$FLAG" -eq 0 ] || [ "$FLAG" -eq 2 ]; then 
	if [ "$DEBUG" -eq 0 ]; then
		echo "$SCRIPT: Removing commericals..."
		$INSTALLPREFIX/mythcommflag -c "$3" -s "$4" --gencutlist
		$INSTALLPREFIX/mythtranscode --chanid "$3" --starttime "$4" --mpeg2 --honorcutlist 
		#echo "DELETE FROM recordedseek WHERE chanid='$3' AND starttime='$4';" > $SQL
		#mysql --user=$DATABASEUSER --password=$DATABASEPASSWORD mythconverg < $SQL
		#echo "DELETE FROM recordedmarkup WHERE chanid='$3' AND starttime='$4';" > $SQL
		#mysql --user=$DATABASEUSER --password=$DATABASEPASSWORD mythconverg < $SQL
		#echo "UPDATE recorded SET basename='$BASENAME2.tmp' WHERE chanid='$3' AND starttime='$4';" > $SQL
		INFILE=$1.tmp
	fi
fi


if [ "$FLAG" -eq 0 ]; then
	if [ "$DEBUG" -eq 0 ]; then
		# 1.5GB/hr - https://trac.handbrake.fr/wiki/BuiltInPresets#atv
		${HANDBRAKECLI} -i "$INFILE" -o "$DIRNAME/$BASENAME" -e x264 -q 20.0 -a 1 -E faac -B 160 -6 dpl2 -R Auto -D 0.0 -X 960 --loose-anamorphic -m -r 29.97 -x cabac=0:ref=2:me=umh:b-pyramid=none:b-adapt=2:weightb=0:trellis=0:weightp=0:vbv-maxrate=9500:vbv-bufsize=9500
	else 
		touch "$DIRNAME/$BASENAME"
	fi
else	 
	if [ "$DEBUG" -eq 0 ]; then
		# 600MB/hr 
		${HANDBRAKECLI} -i "$INFILE" -o "$DIRNAME/$BASENAME" -q 5.0 -I -O -X 640 -Y 480 -a 1 -E faac -6 auto -R Auto -B 128 -r 29.97 -D 0.0 -m 
	else
		touch "$DIRNAME/$BASENAME"
	fi
fi


if [ ! -z "$TITLE" ]; then 
	# new 12/25/2012
	#echo "OLD_TITLE: $TITLE"
	##TITLE=`echo "$TITLE" | sed 's/ /./g' | sed 's/://g' | sed 's/?//g' | sed 's/&/and/g' | sed 's/\;/./g' | sed 's/\://g' | sed 's/!//g' | sed -e s/\'//g`
	#echo "NEW_TITLE: $TITLE"
	if [ ! -z "$SEASONDIR" ]; then 
		MYDIR="$TVBASE/$TITLE/$SEASONDIR"
	else 
		MYDIR="$TVBASE/$TITLE"
	fi
	if [ ! -d "$MYDIR" ]; then
		mkdir -p "$MYDIR"
		chmod 777 "$MYDIR"
		chmod 777 "$TVBASE/$TITLE"
	fi
	if [ ! -z "$PLOT" ]; then
		echo "$PLOT" > "$MYDIR/$BASENAME.plot"
	fi
	echo "$SCRIPT: Copying to $MYDIR/$BASENAME"
	mv -f "$DIRNAME/$BASENAME" "$MYDIR/$BASENAME"
	chmod 777 "$MYDIR/$BASENAME"
	TVNFORET=1
	if [ -x "${TVNFO}" ]; then
		echo "$SCRIPT: Running ${TVNFO}"
		${TVNFO} ${TVARGS} "$MYDIR/$BASENAME"
		TVNFORET=$?
		echo "$SCRIPT: Returned $TVNFORET"
	fi
	if [ -x "${ADDLJOB}" ] && [ "${TVNFORET}" -eq 1 ]; then
		echo "$SCRIPT: Running additional job ${ADDLJOB} ${ADDLARGS} $MYDIR/$BASENAME"
		${ADDLJOB} ${ADDLARGS} "$MYDIR/$BASENAME"
	fi 
	if [ ! -z "${XBMCSERVER}" ] && [ ! -z "${XBMCBASEPATH}" ] && [ ${TVNFORET} -eq 0 ]; then
		MEDIAPATH="$TITLE/$SEASONDIR"
		MEDIAPATH=`echo "$MEDIAPATH" | sed 's/ /\%20/g'`
		echo "$SCRIPT: Running XBMC.updatelibrary on ${XBMCSERVER} for ${XBMCBASEPATH}/${MEDIAPATH}"
		if [ ${DEBUG} -eq 0 ]; then
			curl "http://${XBMCSERVER}/xbmcCmds/xbmcHttp?command=ExecBuiltIn&parameter=XBMC.updatelibrary(video,${XBMCBASEPATH}/${MEDIAPATH})"
		fi
	fi
else 
	echo "$SCRIPT: Not moving file ($DIRNAME/$BASENAME) or running any scraper scripts"
fi
if [ -f "$DIRNAME/$BASENAME2.tmp" ]; then
	 rm -f "$DIRNAME/$BASENAME2.tmp" 
fi
rm $SQL
rm /tmp/mythical_$$
echo "$SCRIPT: Done with conversion process"
