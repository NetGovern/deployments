#Pre-requisites:

* X number of nodes (listed in hosts file) with ubuntu 18.04LTS installed (and barely configured)
	* I used named entries from my ssh config in the host file, but, you can use IPs
* swap disabled on all machines
* id_rsa.pub present in your home dir
* kubeadm installed locally on your machine
* ansible installed locally on your machine
* run each playbook as such:
	* ansible-playbook -i hosts [path to playbook]
