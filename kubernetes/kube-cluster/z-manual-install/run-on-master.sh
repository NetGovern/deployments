#!/bin/bash

#Master config

echo  "Becoming root"
sudo su -

echo "Setting up k8s master node"
kubeadm init --pod-network-cidr=10.244.0.0/16 >> cluster_initialized.txt

echo "Copying k8s access configurations over to the Ubuntu user"
mkdir /home/ubuntu/.kube
cp /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
chown -R ubuntu.ubuntu /home/ubuntu

echo "Becoming Ubuntu"
sudo su - ubuntu
echo "Setting up Flannel"
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/v0.9.1/Documentation/kube-flannel.yml >> pod_network_setup.txt
echo "Setting up WeaveNet"
kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n')"

echo "Waiting for Master to be Ready"
while [ ! -z "$(kubectl get nodes | grep master | grep NotReady)" ]; do
    sleep 3
done
echo "Node Status:"
echo "-----------"
kubectl get nodes -o wide


echo "Waiting for all pods to be Running"
while [ ! -z "$(kubectl -n kube-system get pods -o=wide | grep -v RESTARTS | grep -v Running)" ]; do
    sleep 3
done 
echo "Pod Status:"
echo "-----------"
kubectl get pods -o=wide --all-namespaces

echo "**************************************************"
echo "*** Please take note of your cluster join command:"
echo "**************************************************"
kubeadm token create --print-join-command
