  # Since we're not getting into 'python', log telemetry now
  # first set up the JSON to post
  jsonPayloadEvent=$(cat <<EOF
{
  "iKey": "${AI_INSTRUMENTATION_KEY}",
  "name": "${0}",
  "time": "${STARTTIME}",
  "data": {
    "baseType": "EventData",
    "baseData": {
      "ver": 2,
      "name": "${0} post test",
      "properties": {
        "vm": "$(hostname)",
        "os": "linux",
        "distro": "${DISTRO}",
        "logString": "${LOGSTRING}",
        "checks": "\"{\"python\":\"$PY\",\"pycount\":\"$PYCOUNT\",\"PyVersion\":\"$PYVERSION\",\"WAAOwner\":\"$OWNER\",\"IMDSReturn\":\"$IMDSHTTPRC\",\"WireReturn\":\"$WIREHTTPRC\",\"WireExtn\":\"$WIREEXTPORT\",\"DiskSpace\":\"$FSFULLPCENT\"}\"",
        "findings": "\"{\"python\":\"Inconsistent python environment, other checks may have been aborted\"}\""
      }
    }
  }
}
EOF
)
  # ^^^ not happy with that really, the 'checks' ends up as a big string, instead of sub objects, but maybe AI has to be that way
          #"checks": {\"distro\":\"${DISTRO}\",\"IMDSReturn\":\"${IMDSHTTPRC}\",\"WireReturn\":\"${WIREHTTPRC}\",\"WireExtn\":\"${WIREEXTPORT}\",\"DiskSpace\":\"${FSFULLPCENT}\"}
  ## now get to posting the JSON
  CURLARGS="-i "
  # intentionally clearing the var, to save the old version for posterity
  CURLARGS=""
  if [[ $DEBUG ]]; then
    # not sure if there's anything more 'debuggy' to do here, maybe be verbose about why we're here
    true
  else
    CURLARGS="$CURLARGS --show-error --silent "
  fi
  echo "ARGS=:$CURLARGS"
  loggy "not posting to AI because telemetry is in question, and script is still in dev"
  #curl $CURLARGS -X POST "${AI_ENDPOINT}" -H "Content-Type: application/json" -d "${jsonPayloadEvent}"
  #echo "----"
  #echo $jsonPayloadEvent
  #echo "----"