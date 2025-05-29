#!/usr/bin/env bash

# Default namespace
NS="default"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --namespace|-n)
      NS="$2"
      shift 2
      ;;
    *)
      echo "Usage: $0 [--namespace|-n NAMESPACE]"
      exit 1
      ;;
  esac
done

# Define colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo "Namespace: $NS"

# Get all services in the namespace
services=$(kubectl get services -n $NS -o jsonpath='{.items[*].metadata.name}')

# Count services for tree display
service_count=$(echo "$services" | wc -w)
current_service=0

for service in $services; do
  current_service=$((current_service + 1))
  
  # Determine if this is the last service (for tree formatting)
  if [ $current_service -eq $service_count ]; then
    service_prefix="└── "
    pod_base_prefix="    "
  else
    service_prefix="├── "
    pod_base_prefix="│   "
  fi
  
  echo "${service_prefix}Service: $service"
  
  # Get selector for this service
  selector=$(kubectl get service $service -n $NS -o jsonpath='{.spec.selector}' | jq -r 'to_entries | map("\(.key)=\(.value)") | join(",")' 2>/dev/null)
  
  if [ -z "$selector" ] || [ "$selector" == "null" ]; then
    echo "${pod_base_prefix}└── No selector found for service"
    continue
  fi
  
  # Get pods matching the service selector
  pods=$(kubectl get pods -n $NS -l $selector -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
  
  if [ -z "$pods" ]; then
    echo "${pod_base_prefix}└── No pods found for service"
    continue
  fi
  
  # Count pods for tree display
  pod_array=($pods)
  pod_count=${#pod_array[@]}
  current_pod=0
  
  for pod in $pods; do
    current_pod=$((current_pod + 1))
    
    # Determine if this is the last pod (for tree formatting)
    if [ $current_pod -eq $pod_count ]; then
      pod_prefix="${pod_base_prefix}└── "
      container_base_prefix="${pod_base_prefix}    "
    else
      pod_prefix="${pod_base_prefix}├── "
      container_base_prefix="${pod_base_prefix}│   "
    fi
    
    echo "${pod_prefix}Pod: $pod"
    
    # Get container statuses
    container_data=$(kubectl get pod $pod -n $NS -o json | jq -c '.status.containerStatuses[]')
    
    # Count containers for tree display
    container_count=$(echo "$container_data" | wc -l)
    current_container=0
    
    # Process each container's data
    echo "$container_data" | while read -r container; do
      current_container=$((current_container + 1))
      
      # Extract container information
      name=$(echo "$container" | jq -r '.name')
      restarts=$(echo "$container" | jq -r '.restartCount')
      terminated=$(echo "$container" | jq -r '.lastState.terminated')
      
      # Determine if this is the last container (for tree formatting)
      if [ $current_container -eq $container_count ]; then
        container_prefix="${container_base_prefix}└── "
      else
        container_prefix="${container_base_prefix}├── "
      fi
      
      # Format the container status message
      if [ "$terminated" != "null" ]; then
        crash_time=$(echo "$terminated" | jq -r '.finishedAt')
        reason=$(echo "$terminated" | jq -r '.reason')
        exit_code=$(echo "$terminated" | jq -r '.exitCode')
        # Print in red for crashed containers
        echo -e "${container_prefix}${RED}Container: $name (restarts: $restarts, crash: $crash_time, reason: $reason, exit: $exit_code)${NC}"
      else
        # Print in green for healthy containers
        echo -e "${container_prefix}${GREEN}Container: $name (restarts: $restarts, no crashes)${NC}"
      fi
    done
  done
done