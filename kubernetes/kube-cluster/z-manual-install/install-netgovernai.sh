#!/bin/bash

echo "Getting packages"
wget -O /$HOME/k8s.tgz https://bitbucket.netmail.com/projects/PUB/repos/deployments/raw/kubernetes/k8s.tgz?at=refs%2Fheads%2Fmaster

echo "Extracting packages"
tar xzvf $HOME/k8s.tgz && find ./k8s-files | grep \.\_ | xargs -n1 -I{} rm {}

echo "Deploying"
kubectl create configmap aidbconfig --from-file=./k8s-files/scripts/
if [ $? -ne 0 ]; then
    kubectl create configmap aidbconfig --from-file=./k8s-files/scripts/ -o yaml --dry-run | kubectl replace -f -
fi

kubectl apply -f ./k8s-files/yaml/monitoring/namespaces.yaml
kubectl apply -f ./k8s-files/yaml/monitoring/metrics-server/
kubectl apply -f ./k8s-files/yaml/monitoring/prometheus/
kubectl apply -f ./k8s-files/yaml/monitoring/custom-metrics-api/
kubectl apply -f ./k8s-files/yaml/nlp/ 
kubectl apply -f ./k8s-files/yaml/azure/

Echo "Results"

kubectl get all --all-namespaces
