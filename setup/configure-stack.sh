#!/bin/bash

set -o errexit -o pipefail -o noclobber -o nounset

# Script default values

ELASTICSEARCH_HOST=elasticsearch
ELASTICSEARCH_PORT=9200
FLEET_HOST=fleet-server
FLEET_PORT=8220
KIBANA_HOST=kibana
KIBANA_PORT=5601
USERNAME=elastic
PASSWORD=
INSECURE=0
VERBOSE=0

KBN_HEADERS=(
  -H "kbn-xsrf: kibana"
  -H 'Content-Type: application/json'
)

# Create the script usage menu
usage() {
  cat <<EOF | sed -e 's/^  //'
  usage: ./configure-stack [-v] [-h|--help] [-e HOST|--elasticsearch=HOST] [-f HOST|--fleet HOST] [-k HOST|--kibana=HOST]

  actions:
    all                 performs all the following steps
    enable-detection    Enables the detection engine in Kibana


  flags:
    -e|--elasticsearch    specify the host to connect for Elasticsearch (default: elasticsearch)
    --elasticsearch-port  specify the port to connect to Elasticsearch (default: 9200)
    -f|--fleet            specify the host to connect for Fleet (default: fleet-server)
    --fleet-port          specify the port to connect to Fleet server (default: 8220)
    -k|--kibana           specify the host to connect for Kibana (default: kibana)
    --kibana-port         specify the port to connect to Kibana (default: 5601)
    --insecure            use HTTP instead of HTTPS for all communication
    -u|--username         specify the username for authenticating to all services (default: elastic)
    -p|--password         specify the password for authenticating to all services
    -h|--help             show this message
    -v|--verbose          enable verbose output    
EOF
}



urlencode () {
  jq -rn --arg x "$1" '$x|@uri'
}

main () {

    OPTIONS=e:k:u:p:vh
    LONGOPTS=elasticsearch:,kibana:,insecure,username:,password:,verbose,help


    ! PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTS --name "$0" -- "$@")
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        # e.g. return value is 1
        #  then getopt has complained about wrong arguments to stdout
        usage
        exit 2
    fi
    eval set -- "$PARSED"

    # now enjoy the options in order and nicely split until we see --
    while true; do
        case "$1" in

            -e|--elasticsearch)
                ELASTICSEARCH_HOST="$2"
                shift 2
                ;;
            --elasticsearch-port)
                ELASTICSEARCH_PORT="$2"
                shift 2
                ;;
            -f|--fleet)
                FLEET_HOST="$2"
                shift 2
                ;;
            --fleet-port)
                FLEET_PORT="$2"
                shift 2
                ;;
            -k|--kibana)
                KIBANA_HOST="$2"
                shift 2
                ;;
            --kibana-port)
                KIBANA_PORT="$2"
                shift 2
                ;;
            --insecure)
                INSECURE=1
                shift
                ;;
            -u|--username)
                USERNAME="$2"
                shift 2
                ;;
            -p|--password)
                PASSWORD="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=1
                shift
                ;;
            -h|--help)
                usage
                exit 1
                ;;
            --)
                shift
                break
                ;;
            *)
                echo "Programming error"
                exit 3
                ;;
        esac
    done

    if [ ${VERBOSE} -eq 1 ]; then
      exec 3<>/dev/stderr
    else
      exec 3<>/dev/null
    fi

    SCHEME="https"
    if [ ${INSECURE} -eq 1 ]; then
      SCHEME="http"
    fi

    AUTH=""
    if [ ! -z "${PASSWORD}" ]; then
      AUTH="$(urlencode "${USERNAME}"):$(urlencode "${PASSWORD}")@"
    fi

    ES_URL="${SCHEME}://${AUTH}${ELASTICSEARCH_HOST}:${ELASTICSEARCH_PORT}"
    FLEET_URL="${SCHEME}://${AUTH}${FLEET_HOST}:${FLEET_PORT}"
    KBN_URL="${SCHEME}://${AUTH}${KIBANA_HOST}:${KIBANA_PORT}"
    ACTION="${1:-all}"

    if [ ${VERBOSE} -eq 1 ]; then
      printf "Action: %s\nConfig: \nelasticsearch url: %s\nfleet url: %s\nkibana url: %s\n" "${ACTION}" "${ES_URL}" "${FLEET_URL}" "${KBN_URL}"
      exec 3<>/dev/stderr
    fi

    case "${ACTION}" in
      all)
        do_all
        ;;
      *)
        echo "Invalid action '${1}'"
        usage
        exit 1
        ;;
    esac

}

enable-detection() {
  MAXTRIES=15
  i=${MAXTRIES}

  while [ $i -gt 0 ]; do
    STATUS=$(curl -w '%{response_code}' "${KBN_URL}" --silent -o /dev/null 2>&3)
    echo
    echo "Attempting to enable the Detection Engine and Prebuilt-Detection Rules"

    if [ "${STATUS}" == "302" ]; then
      echo
      echo "Kibana is up. Proceeding"
      echo
      output=$(curl --silent "${KBN_HEADERS[@]}" -XPOST "${KBN_URL}/api/detection_engine/index" 2>&3)
      [[ $output =~ '"acknowledged":true' ]] || (
        echo
        echo "Detection Engine setup failed :-("
        exit 1
      )

      echo "Detection engine enabled. Installing prepackaged rules."
      curl --silent "${KBN_HEADERS[@]}" -XPUT "${KBN_URL}/api/detection_engine/rules/prepackaged" 1>&3 2>&3

      echo
      echo "Prebuilt Detections Enabled!"
      break
    else
      echo
      echo "Kibana still loading. Trying again in 40 seconds"
    fi

    sleep 40
    i=$((i - 1))
  done

  [ $i -eq 0 ] && echo "Exceeded MAXTRIES (${MAXTRIES}) to setup detection engine." && exit 1
}

setup-fleet () {
  curl --silent "${KBN_HEADERS[@]}" -XPOST "${KBN_URL}/api/fleet/setup" | jq
}

create-fleet-user () {
  printf '{"forceRecreate": "true"}' | curl --silent "${KBN_HEADERS[@]}" -XPOST "${KBN_URL}/api/fleet/agents/setup" -d @- | jq
  MAXTRIES=15
  i=${MAXTRIES}

  while [ $i -gt 0 ]; do
    [ "$(curl --silent "${KBN_HEADERS[@]}" -XGET "${KBN_URL}/api/fleet/agents/setup" | jq -c 'select(.isReady==true)' | wc -l)" -gt 0 ] && break

    sleep 5
    i=$((i - 1))
  done

  [ $i -eq 0 ] && echo "Exceeded MAXTRIES (${MAXTRIES}) waiting to create fleet user." && exit 2
}


configure-fleet() {
  printf '{"kibana_urls": ["%s"]}' "${SCHEME}://${KBN_HOST}:${KBN_PORT}" | curl --silent "${KBN_HEADERS[@]}"  -XPUT "${KBN_URL}/api/fleet/settings" -d @- | jq
  printf '{"fleet_server_hosts": ["%s"]}' "${SCHEME}://${FLEET_HOST}:${FLEET_PORT}"| curl --silent "${KBN_HEADERS[@]}"  -XPUT "${KBN_URL}/api/fleet/settings" -d @- | jq

  OUTPUT_ID="$(curl --silent "${KBN_HEADERS[@]}"  -XGET "${KBN_URL}/api/fleet/outputs" | jq --raw-output '.items[] | select(.name == "default") | .id')"
  printf '{"hosts": ["%s"]}' "${ELASTICSEARCH_URL}" | curl --silent "${KBN_HEADERS[@]}"  -XPUT "${KBN_URL}/api/fleet/outputs/${OUTPUT_ID}" -d @- | jq

}

do_all () {
  echo "############  Enable detection engine in Kibana and enable rules"
  enable-detection
  echo "############  Setup Fleet"
  setup-fleet
  echo "############  Create Fleet User"
  create-fleet-user
  echo "############  Configure Fleet"
  configure-fleet

  exit 0
}

main "$@"