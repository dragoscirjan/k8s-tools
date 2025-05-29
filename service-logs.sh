#!/bin/bash

set -e

SERVICES=()
NAMESPACE=""
FOLLOW=false
COLOR=false
GREP_PATTERN=""

usage() {
  echo "Usage: $0 --service <SERVICE_NAME> [--service <SERVICE_NAME_2>...] --namespace <NAMESPACE> [--follow] [--color] [--grep <pattern>]"
  echo "       or: $0 -s <SERVICE_NAME> [-s <SERVICE_NAME_2>...] -n <NAMESPACE> [-f] [-c] [-g <pattern>]"
  exit 1
}

# === Parse arguments ===
while [[ $# -gt 0 ]]; do
  case "$1" in
    --service|-s)
      shift
      [[ $# -eq 0 || "$1" == -* ]] && usage
      SERVICES+=("$1")
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
[[ ${#SERVICES[@]} -eq 0 || -z "$NAMESPACE" ]] && usage

# === Build combined label selector ===
COMBINED_SELECTOR=""

for SERVICE in "${SERVICES[@]}"; do
  # Get label selector from service
  SERVICE_SELECTOR=$(kubectl get svc "$SERVICE" -n "$NAMESPACE" -o json \
    | jq -r '.spec.selector | to_entries | map("\(.key)=\(.value)") | join(",")')
  
  if [[ -z "$SERVICE_SELECTOR" ]]; then
    echo "Error: Service '$SERVICE' has no selector or doesn't exist."
    exit 1
  fi
  
  echo "[INFO] Service '$SERVICE' uses selector: $SERVICE_SELECTOR"
  
  # Add to combined selector
  if [[ -z "$COMBINED_SELECTOR" ]]; then
    COMBINED_SELECTOR="$SERVICE_SELECTOR"
  else
    # This will only work if the selectors are app=name style selectors
    # For more complex cases, we'd need to build a more sophisticated query
    COMBINED_SELECTOR="$COMBINED_SELECTOR,$SERVICE_SELECTOR"
  fi
done

echo "[INFO] Combined services: ${SERVICES[*]}"
echo "[INFO] Using combined selector for pods..."

# Get all pod names matching our services
POD_NAMES=()
for SERVICE in "${SERVICES[@]}"; do
  # Get selector for this service
  SELECTOR=$(kubectl get svc "$SERVICE" -n "$NAMESPACE" -o json | jq -r '.spec.selector | to_entries | map("\(.key)=\(.value)") | join(",")')
  
  # Get pod names using this selector
  PODS=$(kubectl get pods -n "$NAMESPACE" -l "$SELECTOR" -o name)
  
  if [[ -n "$PODS" ]]; then
    # Add each pod to our array
    while IFS= read -r pod; do
      POD_NAMES+=("$pod")
    done <<< "$PODS"
  fi
done

if [[ ${#POD_NAMES[@]} -eq 0 ]]; then
  echo "Error: No pods found for the specified services."
  exit 1
fi

echo "[INFO] Found ${#POD_NAMES[@]} pods across all services"

# === Use stern if color is requested ===
if $COLOR; then
  if ! command -v stern &>/dev/null; then
    echo "[ERROR] --color was requested but 'stern' is not installed."
    echo "        Install it with: brew install stern  OR  go install github.com/stern/stern@latest"
    exit 1
  fi

  echo "[INFO] Launching stern for colored log tailing..."
  
  # Build pod regex pattern for stern by:
  # 1. Remove 'pod/' prefix from pod names
  # 2. Create a proper regex with pipe separators between pod names
  POD_NAMES_CLEAN=()
  for pod in "${POD_NAMES[@]}"; do
    # Extract just the pod name without the 'pod/' prefix
    pod_name="${pod#pod/}"
    POD_NAMES_CLEAN+=("$pod_name")
  done
  
  # Join pod names with | for regex OR operator
  POD_REGEX=$(IFS="|"; echo "${POD_NAMES_CLEAN[*]}")
  
  echo "[DEBUG] Pod regex pattern: $POD_REGEX"
  
  CMD="stern -n \"$NAMESPACE\" \"$POD_REGEX\""
  $FOLLOW || CMD+=" --tail=100"
  [[ -n "$GREP_PATTERN" ]] && CMD+=" --include '$GREP_PATTERN'"
  
  echo "[DEBUG] Running: $CMD"
  eval $CMD
  exit 0
fi

# === Use kubectl logs ===
LOG_CMD="kubectl logs -n \"$NAMESPACE\" --all-containers=true --prefix"
$FOLLOW && LOG_CMD+=" --follow"

# Fetch pod logs and apply grep if set
echo "[INFO] Fetching logs from all pods..."

if $FOLLOW; then
  # For follow mode, we need to run kubectl in parallel and merge the output
  for pod in "${POD_NAMES[@]}"; do
    bash -c "$LOG_CMD $pod" &
  done | { [[ -n "$GREP_PATTERN" ]] && grep "$GREP_PATTERN" || cat; }
else
  # For non-follow mode, we can run sequentially
  for pod in "${POD_NAMES[@]}"; do
    bash -c "$LOG_CMD $pod" | { [[ -n "$GREP_PATTERN" ]] && grep "$GREP_PATTERN" || cat; }
  done
fi
