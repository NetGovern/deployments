#!/bin/bash

echo "Installing k8s Dashboard"
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v1.10.1/src/deploy/recommended/kubernetes-dashboard.yaml

echo "Patching k8s dashboard service to NodePort"
kubectl -n kube-system patch svc kubernetes-dashboard -p '{"spec":{"type":"NodePort"}}'

kubectl apply -f https://raw.githubusercontent.com/NetGovern/deployments/master/kubernetes/kube-cluster/a-%20dashboard-adminuser.yaml
kubectl apply -f https://raw.githubusercontent.com/NetGovern/deployments/master/kubernetes/kube-cluster/b-%20rbac-auth.yaml
kubectl apply -f https://raw.githubusercontent.com/NetGovern/deployments/master/kubernetes/kube-cluster/c-%20rbac-config.yaml

echo "Get Dashboard port and Secret"
echo "Port: $(kubectl -n kube-system get services kubernetes-dashboard | awk '{print $5}')"
echo "Token: $(kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep admin-user | awk '{print $1}'))"

