#!/bin/bash

#Master config

echo "Setting up k8s master node"
kubeadm init --pod-network-cidr=10.244.0.0/16 >> cluster_initialized.txt

echo "Copying k8s access configurations over to the Ubuntu user"
mkdir /home/ubuntu/.kube
cp /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
chown -R ubuntu.ubuntu /home/ubuntu
