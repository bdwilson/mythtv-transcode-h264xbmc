MythTV auto-transcode to h264 for XBMC/Plex
=======

Shell script-based MythTV User Job to transcode recordings to mp4, retrieve
metatata, and update XBMC. This does not alter the MythTV content at all.

Requirements
------------
[MythTV](http://www.mythtv.org)<br>
[XBCMnfo](https://github.com/bdwilson/XBMCnfo)<br>
[HandbrakeCLI](http://handbrake.fr/downloads2.php)<br>
[mythicalLibrarian](http://wiki.xbmc.org/?title=MythicalLibrarian#Installation)<br>

MythTV Configuration
--------------------
Install and configure MythTV. Configure User Jobs in MythTV:

<pre>
$1 must be the directory/file to be transcoded.
$2 is file extension
$3 must be chanid
$4 must be starttime
$5 must be "LOW" for low res or "HIGH" for high-res or "LOWREMC" for low but remove commercials
</pre>

The full userjob command in mythtv-setup should look like this:
<pre>
/path/to/this-script/mythtv-transcode-h264xbmc.sh "%DIR%/%FILE%" "%DIR%/%TITLE% - # %PROGSTART%.mkv" "%CHANID%" "%STARTTIME%" "LOW|HIGH|LOWREMC"
</pre>
I have 3 setup in my MythTV setup that look like this:
<pre>
/etc/mythtv/mythtv-transcode-h264xbmc.sh "%DIR%/%FILE%" "mp4" "%CHANID%" "%STARTTIME%" "HIGH"
/etc/mythtv/mythtv-transcode-h264xbmc.sh "%DIR%/%FILE%" "mp4" "%CHANID%" "%STARTTIME%" "LOWREMC"
/etc/mythtv/mythtv-transcode-h264xbmc.sh "%DIR%/%FILE%" "mp4" "%CHANID%" "%STARTTIME%" "LOW"
</pre>

Pre-MythicalLibrarian Install
-----------------------------
<pre> # mkdir -p /etc/mythicalLibrarian </pre>

Create /etc/mythicalLibrarian/JobSucessful and add the following contents to it:

<pre>
#!/bin/bash
echo SHOWFILENAME: $ShowFileName
</pre>

Install MythcialLibrarian
-------------------------
Follow the instructions above prior to installation.  When prompted, or after install, make sure that the SYMLINK option is set to LINK inside the mythicalLibrarian script itself.

<pre>SYMLINK=LINK</pre>

Installing mythtv-transcode-h264xbmc
------------------------------------
Edit this script and modify variables in order to match the installations, passwords, etc of your other software pieces.

If you have problems...
-----------------------

Check the log file first.  The following should show you *most* of the output
when this script is run from a MythTV userjob. 
<pre>
grep mythtv-transcode-h264xbmc /var/log/mythtv/mythbackend.log
</pre>

You can also try enabling DEBUG mode and running things from the commandline.
You will need the proper variables to pass to the script (you can get this from
mythbackend.log)

Bugs/Contact Info
-----------------
Bug me on Twitter at [@brianwilson](http://twitter.com/brianwilson) or email me [here](http://cronological.com/comment.php?ref=bubba).


