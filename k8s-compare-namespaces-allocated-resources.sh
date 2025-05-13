clear
ns1=$1
ns2=$1
for service in $(kubectl get service -n $ns1 | tail -n +2 | awk '{ print $1 }'); do
    # get label selector
    selector=$(kubectl get svc $service -n $ns1 -o jsonpath='{.spec.selector.app}')
    # find the deployment
    deployment=$(kubectl get deploy -l app=$selector -n $ns1 | tail -n +2 | awk '{ print $1 }')
    
    echo
    echo "=== $service ==="
    echo 

    if [ -z "$deployment" ]; then
        echo "No deployment found for service $service in namespace $ns1"
        continue
    fi

    diff --color <(kubectl get deploy $deployment -n $ns1 \
        -o jsonpath='{.spec.template.spec.containers[*].resources}' | jq .) <(kubectl get deploy $deployment -n $ns2 \
        -o jsonpath='{.spec.template.spec.containers[*].resources}' | jq .)
done
