#!/bin/bash

set -e

SERVICE=""
NAMESPACE=""
FOLLOW=false
COLOR=false
GREP_PATTERN=""

usage() {
  echo "Usage: $0 --service <SERVICE_NAME> --namespace <NAMESPACE> [--follow] [--color] [--grep <pattern>]"
  echo "       or: $0 -s <SERVICE_NAME> -n <NAMESPACE> [-f] [-c] [-g <pattern>]"
  exit 1
}

# === Parse arguments ===
while [[ $# -gt 0 ]]; do
  case "$1" in
    --service|-s)
      shift
      [[ $# -eq 0 || "$1" == -* ]] && usage
      SERVICE="$1"
      shift
      ;;
    --namespace|-n)
      shift
      [[ $# -eq 0 || "$1" == -* ]] && usage
      NAMESPACE="$1"
      shift
      ;;
    --follow|-f)
      FOLLOW=true
      shift
      ;;
    --color|-c)
      COLOR=true
      shift
      ;;
    --grep|-g)
      shift
      [[ $# -eq 0 || "$1" == -* ]] && usage
      GREP_PATTERN="$1"
      shift
      ;;
    *)
      echo "Unknown option: $1"
      usage
      ;;
  esac
done

# === Validate required values ===
[[ -z "$SERVICE" || -z "$NAMESPACE" ]] && usage

# === Get label selector from service ===
SERVICE_SELECTOR=$(kubectl get svc "$SERVICE" -n "$NAMESPACE" -o json \
  | jq -r '.spec.selector | to_entries | map("\(.key)=\(.value)") | join(",")')

if [[ -z "$SERVICE_SELECTOR" ]]; then
  echo "Error: Service has no selector or doesn't exist."
  exit 1
fi

echo "[INFO] Using selector: $SERVICE_SELECTOR"

# === Use stern if color is requested ===
if $COLOR; then
  if ! command -v stern &>/dev/null; then
    echo "[ERROR] --color was requested but 'stern' is not installed."
    echo "        Install it with: brew install stern  OR  go install github.com/stern/stern@latest"
    exit 1
  fi

  echo "[INFO] Launching stern for colored log tailing..."
  CMD="stern -n \"$NAMESPACE\" -l \"$SERVICE_SELECTOR\""
  $FOLLOW || CMD+=" --tail=100"
  [[ -n "$GREP_PATTERN" ]] && CMD+=" --include '$GREP_PATTERN'"
  eval $CMD
  exit 0
fi

# === Use kubectl logs ===
LOG_CMD="kubectl logs -n \"$NAMESPACE\" --all-containers=true --prefix"
$FOLLOW && LOG_CMD+=" --follow"

# Fetch pod logs and apply grep if set
eval kubectl get pods -n "$NAMESPACE" -l "$SERVICE_SELECTOR" -o name \
  | xargs -r -I {} bash -c "$LOG_CMD {}" \
  | { [[ -n "$GREP_PATTERN" ]] && grep "$GREP_PATTERN" || cat; }
