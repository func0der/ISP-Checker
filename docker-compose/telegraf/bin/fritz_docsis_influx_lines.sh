#!/bin/bash
#
# fritz_docsis_influx_lines.sh
#
# read DOCSIS informations from Fritzbox Cable Routers
# and write these infos in a format that can be
# written into an influx database
#
# example: fritz_docsis_influx_lines.sh | influx write -b <bucket>

# ---------------------------------------------
# please define your settings for your fritzbox
# ---------------------------------------------
fritzbox=${FRITZ_DOCSIS_INFLUX_HOST:-192.168.178.1}
user=${FRITZ_DOCSIS_INFLUX_USERNAME:-admin}
pass=${FRITZ_DOCSIS_INFLUX_PASSWORD:-password}

#
# nothing to be changed from here
#

# --------------------
# cache Login with SID
# --------------------
sidfile=/dev/shm/$fritzbox.sid
[ ! -f $sidfile ] && echo "0000000000000000" > $sidfile
sid=$(cat $sidfile)

# --------------------
# check Login with SID
# --------------------
result=$(curl -s "http://$fritzbox/login_sid.lua?sid=$sid" | grep -c "0000000000000000")
if [ $result -gt 0 -o "$sid" = "0000000000000000" ]; then
  challenge=$(curl -s http://$fritzbox/login_sid.lua | grep -o "<Challenge>.*</Challenge>" | sed 's,</*Challenge>,,g')
  hash=$(echo -n "$challenge-$pass" | sed -e 's,.,&\n,g' | tr '\n' '\0' | md5sum | grep -o "[0-9a-z]\{32\}")
  curl -s "http://$fritzbox/login_sid.lua" -d "response=$challenge-$hash" -d 'username='${user} | grep -o "<SID>[a-z0-9]\{16\}" | cut -d'>' -f 2 > $sidfile
fi
sid=$(cat $sidfile)

# --------------------------------
# read DOCSIS-Infos (page=docInfo)
# --------------------------------
docsis=$(curl -s "http://$fritzbox/data.lua" -d "xhr=1&sid=$sid&lang=de&page=docInfo&xhrId=all&no_sidrenew")

# check docsis version 3.0 or 3.1
docsis_version=docsis30
if [ "_"$(echo ${docsis} | jq -r ".data.channelUs.${docsis_version}[0].powerLevel") = "_null" ]; then
    docsis_version=docsis31
fi

# AVM may change the modulation entry from 'type' to 'modulation' in later OS version
if [ "_"$(echo ${docsis} | jq -r ".data.channelUs.${docsis_version}[0].type") = "_null" ]; then
  qam="modulation"
else
  qam="type"
fi

# get nr. of up-/downstream channels
channelUs=$(echo ${docsis} | jq ".data.channelUs.${docsis_version}[].powerLevel" | wc -l)
channelDs=$(echo ${docsis} | jq ".data.channelDs.${docsis_version}[].powerLevel" | wc -l)

#{"powerLevel":"40.0","modulation":"64QAM","multiplex":"ATDMA","channelID":2,"frequency":"41.800"}
# read upstream channels
for (( c=0; c<$channelUs; c++ )); do
  channelID[$c]=$(echo ${docsis}  | jq -r ".data.channelUs.${docsis_version}[$c].channelID")
  modulation[$c]=$(echo ${docsis} | jq -r ".data.channelUs.${docsis_version}[$c].$qam" | sed 's/[^0-9.]//g')
  powerLevel[$c]=$(echo ${docsis} | jq -r ".data.channelUs.${docsis_version}[$c].powerLevel")
  frequency[$c]=$(echo ${docsis}  | jq -r ".data.channelUs.${docsis_version}[$c].frequency")
  multiplex[$c]=$(echo ${docsis}  | jq -r ".data.channelUs.${docsis_version}[$c].multiplex")

  echo "docsis,mode=up,channel=${channelID[$c]} Modulation=${modulation[$c]}"
  echo "docsis,mode=up,channel=${channelID[$c]} PowerLevel=${powerLevel[$c]}"
  echo "docsis,mode=up,channel=${channelID[$c]} Frequency=${frequency[$c]}"
done

#{"powerLevel":"-0.2","nonCorrErrors":0,"modulation":"256QAM","corrErrors":16,"latency":0.32,"mse":"-38.6","channelID":5,"frequency":"186.000"}
# read downstream channels
for (( c=0; c<$channelDs; c++ )); do
  channelID[$c]=$(echo ${docsis}  | jq -r ".data.channelDs.${docsis_version}[$c].channelID")
  modulation[$c]=$(echo ${docsis} | jq -r ".data.channelDs.${docsis_version}[$c].$qam" | sed 's/[^0-9.]//g')
  powerLevel[$c]=$(echo ${docsis} | jq -r ".data.channelDs.${docsis_version}[$c].powerLevel")
  frequency[$c]=$(echo ${docsis}  | jq -r ".data.channelDs.${docsis_version}[$c].frequency")
  latency[$c]=$(echo ${docsis}    | jq -r ".data.channelDs.${docsis_version}[$c].latency")
  corrErrors[$c]=$(echo ${docsis} | jq -r ".data.channelDs.${docsis_version}[$c].corrErrors")
  nonCorrErrors[$c]=$(echo ${docsis} | jq -r ".data.channelDs.${docsis_version}[$c].nonCorrErrors")
  mse[$c]=$(echo ${docsis}        | jq -r ".data.channelDs.${docsis_version}[$c].mse")

  echo "docsis,mode=down,channel=${channelID[$c]} Modulation=${modulation[$c]}"
  echo "docsis,mode=down,channel=${channelID[$c]} PowerLevel=${powerLevel[$c]}"
  echo "docsis,mode=down,channel=${channelID[$c]} Frequency=${frequency[$c]}"
  echo "docsis,mode=down,channel=${channelID[$c]} Latency=${latency[$c]}"
  echo "docsis,mode=down,channel=${channelID[$c]} correctedErrors=${corrErrors[$c]}"
  echo "docsis,mode=down,channel=${channelID[$c]} Errors=${nonCorrErrors[$c]}"
  echo "docsis,mode=down,channel=${channelID[$c]} MSE=${mse[$c]}"
done