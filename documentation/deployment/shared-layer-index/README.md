# Netgovern Shared Layer configuration - index/solr

The starting point is after having deployed in your infrastructure a Netgovern index image.  
*If the VM is deployed using Azure ARM templates, this script runs automatically after deployment, using the parameters gathered by Azure.*

### Download the following script to the same location in the index VMs that will create your index cluster

<a href="https://bitbucket.netmail.com/projects/PUB/repos/deployments/raw/scripts/solr_config.sh" target="_blank">solr_config.sh</a>


### Example of parameters used to run the configuration wizard 
The following shows how to configure a cluster of 3 index VMs.
The VMs have been configured to use the IP addresses 1.1.1.1, 1.1.1.2 and 1.1.1.3
First, make sure that the file has unix style eol:
```
sudo yum install dos2unix –y && dos2unix ./solr_config.sh
```
Then, in the first node:
```
./solr_config.sh -m
```
In the second node (1.1.1.2):
```
./solr_config.sh -z 1.1.1.1
```
In the third node (1.1.1.3):
```
./solr_config.sh -z 1.1.1.1 -f 
```
or if you need more shards or replicas, you can use the option -s and -r when finalizing the cluster (last node):
```
./solr_config.sh -z 1.1.1.1 -f -r 1 -s 12
```

The default options to configure the cluster can be changed.  The help section of the script shows information about them:
```
Configures Solr on default port 31000.  Optional zookeeper for the first node on default port 32000.
    [-m]                        Install a Master Node.  Zookeeper and Solr without finalizing it.
    [-q]                        Quick installation using a single node installation with default values shown below)
    [-z ZOOKEEPER_IP_ADDRESS]   Do not configure zookeeper and use an already existing zookeeper - uses default 32000 port to connect

    [-f]                        Finalizes cluster. To be used at the last node
    [-r REPLICAS]               Number of replicas to be used if the option -f is used - defaults to 0
    [-s SHARDS]                 Number of shards to be used if the option -f is used - cannot exceed 16, defaults to 8
    [-h]                        This message
```
