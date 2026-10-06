#!/bin/bash

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_DIR="$BASE_DIR/state"
LOG_FILE="$BASE_DIR/watchdog.log"
CONFIG_FILE="$BASE_DIR/services.conf"
METRICS_FILE="$STATE_DIR/metrics.db"

source "$CONFIG_FILE"
source "$METRICS_FILE"


timestamp() {

   date "+%Y-%m-%d %H:%M:%S"

}

log() {

     echo "[$(timestamp)] $1" | tee -a "$LOG_FILE"
}

is_critical() {
    for cs in "${CRITICAL_SERVICES[@]}"; do
         [ "$cs" = "$1" ] && return 0
    done
    return 1

}


save_metrics() {

    cat > "$METRICS_FILE" << EOF
TOTAL_CHECKS=$TOTAL_CHECKS
TOTAL_RESTARTS=$TOTAL_RESTARTS
TOTAL_FAILURES=$TOTAL_FAILURES
EOF


}

show_report() {

	echo "========================================"
	echo "    SERVICE WATCHDOG REPORT"
	echo "========================================"
	echo

	echo "Total Checks   : $TOTAL_CHECKS"
	echo "Total Restarts : $TOTAL_RESTARTS"
	echo "Total Failures: $TOTAL_FAILURES"
	echo


	printf "%-12s %-10s\n" "SERVICE" "STATUS"

	for SERVICE in "${SERVICES[@]}"; do

		if systemctl is-active --quiet "$SERVICE"; then
		    printf "%-12s %-10s\n" "$SERVICE" "RUNNING"
		else
		    printf "%-12s %-10s\n" "$SERVICE" "DOWN"

		fi
	done

}

show_status() {
	
    printf "%-12s %-10s\n" "SERVICE" "STATUS"

    for SERVICE in "${SERVICES[@]}"; do
	    if systemctl is-active --quiet "$SERVICE"; then
		    printf "%-12s %-10s\n" "$SERVICE" "RUNNING"
	    else
		    printf "%-12s %-10s\n" "$SERVICE" "DOWN"
	    fi
    

    done


}


monitor_services() {

TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
for SERVICE in "${SERVICES[@]}"; do

    # Check if service exists
    if ! systemctl list-unit-files | grep -q "^${SERVICE}.service" ; then
        log "WARNING: $SERVICE does not exist, skipping"
        continue
    fi

    # Check service status
    if systemctl is-active --quiet "$SERVICE"; then
        continue
    fi

   COUNT_FILE="$STATE_DIR/${SERVICE}.count"
   COUNT=0

   [ -f "$COUNT_FILE" ] && COUNT=$(cat "$COUNT_FILE")

   COUNT=$((COUNT + 1))
   echo "$COUNT" > "$COUNT_FILE"

   log "ALERT: $SERVICE is down (restart attempt $COUNT)"

   systemctl restart "$SERVICE"

   sleep 2

    if systemctl is-active --quiet "$SERVICE"; then
	    TOTAL_RESTARTS=$((TOTAL_RESTARTS + 1))
	    log "SUCCESS: $SERVICE restarted successfully."
    else
	    TOTAL_FAILURES=$((TOTAL_FAILURES + 1))
	    log "FAILURE: $SERVICE failed to restart."
    fi

    if [ "$COUNT" -ge "$MAX_RESTARTS" ]; then
        if is_critical "$SERVICE"; then
            log "CRITICAL ALERT: $SERVICE unstable but NOT disabling (critical service)"
        else
            log "CRITICAL: $SERVICE exceeded restart limit, disabling service"
            systemctl disable --now "$SERVICE"
            rm -f "$COUNT_FILE"
        fi
    fi

done

save_metrics
log "Watchdog run completed."

}

case "$1" in

    status)
        show_status
        ;;

    report)
	show_report
	;;

    *)
        monitor_services
        ;;

esac
