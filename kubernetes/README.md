Introduction
------------

Kubernetes is a container orchestration system, it manages containers, it is open source and actively developed.

There are many commercially supported distributions (IBM Cloud Private, Kontena Pharos, Kublr, SuSe CaaS) following the steps below will get you going if you want to do it on your own. 

Kubeadm automates the installation and configuration of Kubernetes components such as the API server, Controller Manager, and Kube DNS. It does not, however, create users or handle the installation of software or its dependencies and its configuration. For these preliminary tasks we will use Ansible.


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

This guide will walk you through installing a Kubernetes cluster composed of one Master node and two Worker nodes.

The master node (a node in Kubernetes refers to a server) is responsible for managing the state of the cluster. It runs Etcd, which stores cluster data among components that schedule workloads to worker nodes.

Shared storage is required for true portability, and the simplest way is to provision space on the Master node and use an NFS export, that you will mount from each worker node.

Worker nodes are the servers where your workloads (i.e., containerized applications and services) will run. A worker will continue to run your workload once they're assigned to it, even if the master goes down once scheduling is complete. A cluster's capacity can be increased by adding workers.


Prerequisites
-------------

- An SSH key pair on your local machine.
- Three servers running Ubuntu 18.04 where the root user can login using that ssh key, sudo without password, and there is no swap enabled.
	- One Master with 4GBB RAM and 4CPU and 500GB storage
	- Two  workers with as much RAM and CPU as you can give them, as they will do the work, and 200GB storage
- Ansible installed on your local machine.


Setting Up the Workspace Directory and Ansible Inventory File
-------------------------------------------------------------

Create a directory on your local machine that will serve as your workspace. Ansible will be configured locally so that it can communicate with and execute commands on your remote servers. Once that's done, Create a hosts file containing the IP addresses of your servers and the groups that each server belongs to.


	$ mkdir ~/kube-cluster
	$ cd ~/kube-cluster
	$ vi ~/kube-cluster/hosts

	[masters]
	master ansible_host=master_ip ansible_user=root
	
	[workers]
	worker1 ansible_host=worker_1_ip ansible_user=root
	worker2 ansible_host=worker_2_ip ansible_user=root
	
	[all:vars]
	ansible_python_interpreter=/usr/bin/python3

Now that you have the server inventory with groups, install the operating system level dependencies and create configuration settings.


Creating a Non-Root User on All Remote Servers
----------------------------------------------

Add the following playbook to create a non-root user with sudo privileges on all of the servers.

https://bitbucket.netmail.com/projects/PUB/repos/deployments/raw/kubernetes/kube-cluster/1-%20initial.yml?at=refs%2Fheads%2Fmaster

	$ vi ~/kube-cluster/initial.yml

	- hosts: all
	  become: yes
	  tasks:
		- name: create the 'ubuntu' user
		  user: name=ubuntu append=yes state=present createhome=yes shell=/bin/bash

		- name: allow 'ubuntu' to have passwordless sudo
		  lineinfile:
			dest: /etc/sudoers
			line: 'ubuntu ALL=(ALL) NOPASSWD: ALL'
			validate: 'visudo -cf %s'

		- name: set up authorized keys for the ubuntu user
		  authorized_key: user=ubuntu key="{{item}}"
		  with_file:
			- ~/.ssh/id_rsa.pub

Once done, now we run the playbook to actually do the work; this will  create a ubuntu user on all the hosts in the inventory  file, accessible with your key, and with sudo privileges.

	$ ansible-playbook -i hosts ~/kube-cluster/initial.yml

With that done, the groundwork is laid to begin deploying Kubernetes.


Installing Kubernetes Dependencies
----------------------------------
The bare minimum packages required by Kubernetes on Ubuntu 18.04LTS are Docker (a container engine), kubeadm (a command line tool to install and configure k8s), kubelet (a minion installed on every node) and kubectl (a command line interface into Kubernetes' API server).

Let's create the playbook that will deploy these to all the nodes.

https://bitbucket.netmail.com/projects/PUB/repos/deployments/raw/kubernetes/kube-cluster/2-%20kube-dependencies.yml?at=refs%2Fheads%2Fmaster
    
	$ vi ~/kube-cluster/kube-dependencies.yml

	- hosts: all
	  become: yes
	  tasks:
	   - name: install Docker
		 apt:
		   name: docker.io
		   state: present
		   update_cache: true

	   - name: install APT Transport HTTPS
		 apt:
		   name: apt-transport-https
		   state: present

	   - name: add Kubernetes apt-key
		 apt_key:
		   url: https://packages.cloud.google.com/apt/doc/apt-key.gpg
		   state: present

	   - name: add Kubernetes' APT repository
		 apt_repository:
		  repo: deb http://apt.kubernetes.io/ kubernetes-xenial main
		  state: present
		  filename: 'kubernetes'

	   - name: install kubelet
		 apt:
		   name: kubelet=1.11.7-00
		   state: present
		   update_cache: true

	   - name: install kubeadm
		 apt:
		   name: kubeadm=1.11.7-00
		   state: present

	- hosts: master
	  become: yes
	  tasks:
	   - name: install kubectl
		 apt:
		   name: kubectl=1.11.7-00
		   state: present
		   force: yes

Now run the playbook to push out all the components to the appropriate hosts.

	$ ansible-playbook -i hosts ~/kube-cluster/kube-dependencies.yml

The output should look like this:
	
![](https://bitbucket.netmail.com/projects/PUB/repos/deployments/raw/kubernetes/kube-cluster/screenshots/dep-success.jpg?at=refs%2Fheads%2Fmaster)

Docker, kubeadm, and kubelet are now installed on all the servers. Kubectl is only installed on the master node since you will run kubectl commands from there (or from your workstation)

Now, let's set up the master node and initialize the cluster.


Setting Up the Master Node
--------------------------

Create an Ansible playbook named master.yml on your local machine:

https://bitbucket.netmail.com/projects/PUB/repos/deployments/raw/kubernetes/kube-cluster/3-%20master.yml?at=refs%2Fheads%2Fmaster

	$ vi ~/kube-cluster/master.yml

	- hosts: master
	  become: yes
	  tasks:
	    - name: initialize the cluster
	      shell: kubeadm init --pod-network-cidr=10.244.0.0/16 >> cluster_initialized.txt
	      args:
	        chdir: $HOME
	        creates: cluster_initialized.txt

	    - name: create .kube directory
	      become: yes
	      become_user: ubuntu
	      file:
	        path: $HOME/.kube
	        state: directory
	        mode: 0755

	    - name: copy admin.conf to user's kube config
	      copy:
	        src: /etc/kubernetes/admin.conf
	        dest: $HOME/.kube/config
	        remote_src: yes
	        owner: ubuntu

	    - name: install Pod network
	      become: yes
	      become_user: ubuntu
	      shell: kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/v0.9.1/Documentation/kube-flannel.yml >> pod_network_setup.txt
	      args:
	        chdir: $HOME
	        creates: pod_network_setup.txt

Now run the playbook to create the cluster.

	$ ansible-playbook -i hosts ~/kube-cluster/master.yml

This is where we actually get things going. Kubeadm init creates the cluster, and set the inter node network all the pods will live on.  This happens to be the default network space for flannel, and we're just opportunistically informing the master node that that's what we'll be using. We then create the .kube directory in ubuntu's home folder and copy /etc/kubernetes/admin.conf into it. This is the directory you copy from machine to machine to cheat and run kubectl locally.

Once kubectl is configured with that file, the  last task runs kubectl apply to install Flannel and enable inter pod networking.

Let's now confirm everything works by connecting to the master and running kubectl.

	$ ssh ubuntu@master_ip
	$ kubectl get nodes

This should return a list of nodes, one node, one master node, in a ready state.

Master nodes are cool, but, you can't actually run pods on the master, that's not allowed.

At this point, you can install kubectl on your client machine as well, so that you no longer need to run kubectl commands only on the master.  To do this copy ubuntu's .kube directory into your own home folder on your client machine, and you can directly control your shiny new k8s single master cluster.

Setting Up the Worker Nodes
---------------------------

Enough mocking this single master cluster, let's add some workers. This involves executing a single command on each, that includes the cluster information, such as the IP address and port of the master's API Server and a secure token -- not just  anyone can join.

https://bitbucket.netmail.com/projects/PUB/repos/deployments/raw/kubernetes/kube-cluster/4-%20workers.yml?at=refs%2Fheads%2Fmaster


	$ vi ~/kube-cluster/workers.yml


	- hosts: master
	  become: yes
	  gather_facts: false
	  tasks:
	    - name: get join command
	      shell: kubeadm token create --print-join-command
	      register: join_command_raw

	    - name: set join command
	      set_fact:
	        join_command: "{{ join_command_raw.stdout_lines[0] }}"


	- hosts: workers
	  become: yes
	  tasks:
	    - name: join cluster
	      shell: "{{ hostvars['master'].join_command }} >> node_joined.txt"
	      args:
	        chdir: $HOME
	        creates: node_joined.txt

Here we, accessing the master, run a kubeadm command to get the proper info to join, and pass it along to the next playbook task to be executed on each worker and join.

Now let's run that playbook and join those workers.

	$ ansible-playbook -i hosts ~/kube-cluster/workers.yml

Once done, let's get back to the master and make sure we have some worker nodes.

	$ ssh ubuntu@master_ip
	$ kubectl get nodes

Here you should see one Master and two Workers, in a happy ready state.

Let's now make sure that we can spin up pods and containers and deployments oh my!

So while you're still  on the master, let's create the most basic of deployments.

	$ kubectl run nginx --image=nginx --port 80

This will run a one node nginx deployment on your cluster.  While deployments describe running states, they do not provide access. For that, you need to create a service that will expose the app publicly. It will do so through a NodePort, a scheme that will make the pod accessible through an arbitrary port opened on each node of the cluster.

	$ kubectl expose deploy nginx --port 80 --target-port 80 --type NodePort

Now you can verify the available services, and their port.

	$ kubectl get services

Pay close attention to the exposed port, as that is the way to interact with your deployment;  it is usually in the form of a high port (usually 3xxxx). The container networking fabric takes care of routing requests form any host:port to the right pod, you can then browser to http://master_ip:3xxxx and you'll be whisked away and connected to the right service.

Now let's clean up.

	$ kubectl delete service nginx
	$ kubectl delete deployment nginx


Setting up Helm
---------------

Package managers are a very familiar concept, they're used to facilitate software deployment.  The days of building software are long gone, now we yum install or apt-get install.  In K8s, this facility is provided by a tool called Helm.  While yum installs rpms and apt-get installs deb files, helm installs helm charts.

Install helm on your client node. Once installed, helm init will install tiller (the server-side portion of helm) onto your k8s cluster.

With our kubectl connected to our cluster as a pre requisite (from the master section  where we copied the .kube directory), we can install helm.

Getting helm varies by distribution, but in most cases you can use snap to install it.

	$ sudo snap install helm --classic

Now, since we do RBAC, let's enable the tiller account for use with helm:

https://bitbucket.netmail.com/projects/PUB/repos/deployments/raw/kubernetes/kube-cluster/c-%20rbac-config.yaml?at=refs%2Fheads%2Fmaster

	$ vi rbac-config.yaml

	apiVersion: v1
	kind: ServiceAccount
	metadata:
	  name: tiller
	  namespace: kube-system
	---
	apiVersion: rbac.authorization.k8s.io/v1
	kind: ClusterRoleBinding
	metadata:
	  name: tiller
	roleRef:
	  apiGroup: rbac.authorization.k8s.io
	  kind: ClusterRole
	  name: cluster-admin
	subjects:
	  - kind: ServiceAccount
	    name: tiller
	    namespace: kube-system

And then apply it:

	$ kubectl create -f rbac-config.yaml

And then get helm using it:

	$ helm init --service-account tiller

Confirming helm is correctly installed, you can search for charts.

	$ helm search

This should list available things to install.

Setting up K8s Dashboard
------------------------

Running kubernetes implies comfort with the command line, but sometimes visuals help. The K8s dashboard is now easily installable:

	$ kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v1.10.1/src/deploy/recommended/kubernetes-dashboard.yaml

Which will, after a few minutes, and when ready and listable in:

	$ kubectl -n kube-system get all

Then it will return connection information for connecting to the dashboard.

The dashboard is a protected resource, and is usually only manageable locally using kube-proxy.  If you want to change that, you can edit the dashboard's yaml file and change the Type from ClusterIP to NodePort.

	$ kubectl -n kube-system edit service kubernetes-dashboard

You will then need to get the port it listens on like so:

	$ kubectl -n kube-system get services kubernetes-dashboard

And then you can connect to it at https://masterIP:port

You'll need a user, and a token, that you can get as such:

https://bitbucket.netmail.com/projects/PUB/repos/deployments/raw/kubernetes/kube-cluster/a-%20dashboard-adminuser.yaml?at=refs%2Fheads%2Fmaster

	$ vi dashboard-adminuser.yaml

	apiVersion: v1
	kind: ServiceAccount
	metadata:
	  name: admin-user
	  namespace: kube-system

	$ kubectl apply -f dashboard-adminuser.yaml

	$ vi dashboard-rolebinding.yaml

	apiVersion: rbac.authorization.k8s.io/v1
	kind: ClusterRoleBinding
	metadata:
	  name: admin-user
	roleRef:
	  apiGroup: rbac.authorization.k8s.io
	  kind: ClusterRole
	  name: cluster-admin
	subjects:
	- kind: ServiceAccount
	  name: admin-user
	  namespace: kube-system

	$ kubectl apply -f dashboard-rolebinding.yaml

	$ kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep admin-user | awk '{print $1}')

Setting up HAProxy (on, or off the system)
------------------

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


Setting up NetGovern services
-----------------------------

Installing the AI service is as straight forward as other helm charts once you add NetGovern's helm repo as such:

    $ helm repo add netgovern http://charts.netgovern.ai

Verify that it it correct:

    $ helm search netgovern

Before we install the chart, let's create the namespace it requires:

	$ vi namespace.yaml

	{
	  "kind": "Namespace",
	  "apiVersion": "v1",
	  "metadata": {
	    "name": "monitoring",
	    "labels": {
	      "name": "monitoring"
	    }
	  }
	}


	$ kubectl create -f namespace.yaml

And then proceed to install the chart (postgres persistence requires shared storage, which is beyond the scope of this document, so we will skip over that):

    $ helm install --set postgresql.persistence.enabled=false netgovern/netgovernai

Once running, and the system has been given time to settle, we can  verify the installation like so:

    $ helm list

And:

    $ kubectl get all

Or examining the dashboard to ensure everything is ok.

Tweaks
------

- fix access to node/stats for metrics server
