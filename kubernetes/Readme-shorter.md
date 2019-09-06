Introduction
------------

Kubernetes is a container orchestration system, it manages containers, it is open source and actively developed.

There are many commercially supported distributions (IBM Cloud Private, Kontena Pharos, Kublr, SuSe CaaS) following the steps below will get you going if you want to do it on your own. 

Kubeadm automates the installation and configuration of Kubernetes components such as the API server, Controller Manager, and Kube DNS. It does not, however, create users or handle the installation of software or its dependencies and its configuration. In this instance, the provided OVF has all the pre-requisites installed.


Kubernetes concepts
-------------------

Clusters are made of nodes; one Master node (many in a currently experimental High availability mode) and one or more Worker nodes.

Pods run "the stuff"; they are the atomic unit and are composed of one or more containers. These containers share resources such as file volumes and network interfaces in common. Pods are the basic unit in Kubernetes. All containers in a pod are guaranteed to run on the same node.

Each pod has its own IP address. Pods on one node should be able to access pods on another node using the pod's IP. Containers on a single node can communicate easily through a local interface. Communication between pods is more complicated. It requires a separate networking component to route traffic from a pod on one node to a pod on another.

This functionality is provided by pod network plugins. For this cluster, we will use Flannel, a stable and performant option.

The API server acts as the inbound vector for all management commands.  DNS is provided by CoreDNS and by default piggybacks onto the host DNS.

Kubbernetes is declarative, that  is to say, a configuration  file, a yaml file, describes a desired state.  Once you deploy such an item, the Kubernetes system will ensure that it maintains the described state for that deployment.

A deployment is a type of Kubernetes object that ensures there's always a specified number of pods running based on a defined template, that upgrades are dealt with in a specific way, etc... 

Services are another type of Kubernetes object. They are responsible for exposing deployments to clients and load balancing requests to multiple pods.

Goals
-----

This guide will walk you through configuring a Kubernetes cluster composed of one Master node and one worker node.

The master node (a node in Kubernetes refers to a server) is responsible for managing the state of the cluster. It runs Etcd, which stores cluster data among components that schedule workloads to worker nodes.

Shared storage is required for true portability, and the simplest way is to provision space on the Master node and use an NFS export, that you will mount from each worker node.

Worker nodes are the servers where your workloads (i.e., containerized applications and services) will run. A worker will continue to run your workload once they're assigned to it, even if the master goes down once scheduling is complete. A cluster's capacity can be increased by adding workers.


Prerequisites
-------------

- An SSH key pair on your local machine.
- Two instances of the k8s VM.
	- One Master with 4GBB RAM and 4CPU and 500GB storage
	- One worker with as much RAM and CPU as you can give it, as it will do the work, and 200GB storage

Creating a Non-Root User on All Remote Servers
----------------------------------------------
There is a ubuntu user pre-installed on that VM, please ensure your ssh key is in its authorized_keys file.

With that done, the groundwork is laid to begin deploying Kubernetes.


Setting Up the Master Node
--------------------------
SSH over to the master and run this one command as ubuntu:

	wget https://bitbucket.netmail.com/projects/PUB/repos/deployments/raw/kubernetes/kube-cluster/z-manual-install/run-on-master.sh?at=refs%2Fheads%2Fmaster -O run-on-master.sh && chmod +x run-on-master.sh && ./run-on-master.sh'

Master nodes are cool, but, you can't actually run pods on the master, that's not allowed.

At this point, you can install kubectl on your client machine as well, so that you no longer need to run kubectl commands only on the master.  To do this copy ubuntu's .kube directory into your own home folder on your client machine, and you can directly control your shiny new k8s single master cluster.

Setting Up the Worker Node
---------------------------

Enough mocking this single master cluster, let's add a worker. This involves executing a single command on each, that includes the cluster information, such as the IP address and port of the master's API Server and a secure token -- not just  anyone can join.

To join, simply run, as the root user on the worker node, the kubeadm command we got from the previous step (just an example below):

	kubeadm join 1.2.3.4:6443 --token YOURTOKENHERE --discovery-token-ca-cert-hash sha256:LOTSOFNUMBERSHERE


Setting up Helm & Dashboard
---------------------------

Package managers are a very familiar concept, they're used to facilitate software deployment.  The days of building software are long gone, now we yum install or apt-get install.  In K8s, this facility is provided by a tool called Helm.  While yum installs rpms and apt-get installs deb files, helm installs helm charts.

Install helm on your client node. Once installed, helm init will install tiller (the server-side portion of helm) onto your k8s cluster.

With our kubectl connected to our cluster as a pre requisite (from the master section  where we copied the .kube directory), we can install helm.

	wget https://bitbucket.netmail.com/projects/PUB/repos/deployments/raw/kubernetes/kube-cluster/z-manual-install/helm-and-dashboard.sh?at=refs%2Fheads%2Fmaster -O helm-and-dashboard.sh && chmod +x helm-and-dashboard.sh && ./helm-and-dashboard.sh


Setting up NetGovern services
-----------------------------

Installing the AI service is as simple as running just a few commands.

As the Ubuntu user, run:

	wget https://bitbucket.netmail.com/projects/PUB/repos/deployments/raw/kubernetes/kube-cluster/z-manual-install/install-netgovernai.sh?at=refs%2Fheads%2Fmaster -O install-netgovernai.sh && chmod +x install-netgovernai.sh && ./install-netgovernai.sh

The swagger UI is accessible through https://WORKERNODEIP:32160/swagger-ui.html


Optionally Setting up HAProxy (on, or off the system)
-----------------------------------------------------

Kubernetes' networking fabric makes sure that every port on every pod is available on every node.  But, it does not go make your resources easy to access for people who don't want to remember cryptic port numbers.

For that, we will deploy a reverse-proxy called HAProxy on the master

	# apt-get -y install haproxy

And configure it by adding (samples below) our k8s pod configurations:

	# vi /etc/haproxy/haproxy.cfg

	frontend  http-in
    bind *:80

	#Define ACLs
	acl host_beta       hdr(host) -I beta.netgovern.ai
	acl host_dashboard  hdr(host) -I dashboard.netgovern.ai


	#Define redirections
	use_backend example if host_beta
	use_backend dashboard if host_dashboard

	#Define backends
	backend example        
		server nginx 10.200.0.171:30587 maxconn 1024
	backend dashboard
	    server dashboard 10.200.0.171:32181 ssl maxconn 1024

All you have to do is point a wildcard DNS to the master IP, and HAProxy will route the connection, based on host header, to the defined service.

In our case, we are assigning *.netgovern.ai to our HAProxy installation.  This is done in DNS and is outside the scope of this document.

