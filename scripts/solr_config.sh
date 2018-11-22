# Indexes location: Additional disks should be added before running this script and mounted to /var/netmail.  xfs should be used.
# This script configures zookeeper and solr

Usage() {
    echo "Solr/Zookeeper Deployment script"
    echo "$0
    Configures Solr on default port 31000.  Optional zookeeper for the first node on default port 32000.
    [-m]                        Install a Master Node.  Zookeeper and Solr without finalizing it.
    [-q]                        Quick installation using a single node installation with default values shown below)
    [-z ZOOKEEPER_IP_ADDRESS]   Do not configure zookeeper and use an already existing zookeeper - uses default 32000 port to connect

    [-f]                        Finalizes cluster. To be used at the last node
    [-r REPLICAS]               Number of replicas to be used if the option -f is used - defaults to 0
    [-s SHARDS]                 Number of shards to be used if the option -f is used - cannot exceed 16, defaults to 8
    [-h]                        This message
    
    Example of 3 nodes installation:
    in node1: $0 -m
    in node2: $0 -z <node1_ip_address>
    in node3: $0 -z <node1_ip_address> -f

    Example of 1 node only:
    $0 -q
    or
    $0 -f -r 0 -s 16
    "
}
function valid_ip()
{
    local  ip=$1
    stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
            && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

function firewall_service_check()
{
    #Checking Firewalld State and Status
    FWSTATE=`systemctl is-enabled firewalld`
    if [ "${FWSTATE}" != "enabled" ]; then
        sudo systemctl enable firewalld
    fi

    FWSTATUS=`systemctl is-active firewalld`
    if [ "${FWSTATUS}" != "active" ]; then
        sudo systemctl start firewalld
    fi
}

function configure_zookeeper()
{
    #First node installation.  Zookeeper gets installed at the first node.  
    #Adittional nodes only run solr_wizard.sh, pointing to the first node's ip address for zookeeper info.
    sudo /opt/ma/netmail/zookeeper/zookeeper_wizard.sh --quiet \
        --zk-port $ZOOKEEPER_PORT \
        --zk-start-script /opt/ma/netmail/sbin/zookeeper.sh \
        --zk-chroot /solr \
        --zk-bin-dir /opt/ma/netmail/zookeeper \
        --zk-data-dir /var/netmail/zookeeper \
        --zk-ensemble n \
        --zk-start-script /opt/ma/netmail/sbin/zookeeper.sh \
        --zk-conf /opt/ma/netmail/etc/zookeeper.conf \
        --zk-internal-conf ./zookeeper_internal.conf \
        --upload-config y \
        --solr-bin-dir /opt/ma/netmail/solr \
        --solr-config-dir /opt/ma/netmail/solr/conf \
        --platformreg y \
        --host $ZOOKEEPER_IP_ADDR

    sudo /opt/ma/netmail/sbin/zookeeper.sh start

    if [ $OPEN_PORTS -eq 1 ]; then
        echo "Opening Firewall ports"
        sudo firewall-cmd --add-port=$ZOOKEEPER_PORT/tcp --permanent
        sudo systemctl reload firewalld
    fi
}

function configure_solr()
{
    sudo /opt/ma/netmail/solr/solr_wizard.sh --quiet \
        --solr-start-script /opt/ma/netmail/sbin/solr.sh \
        --solr-conf /opt/ma/netmail/etc/solr.conf \
        --solr-java-heap-size ${HEAP}g \
        --solr-port 31000 \
        --solr-host $SOLR_IP_ADDR \
        --solr-bin-dir /opt/ma/netmail/solr \
        --solr-data-dir /var/netmail/solr \
        --solr-zk-nodes $ZOOKEEPER_HOST:$ZOOKEEPER_PORT/solr

    #Create solr launcher conf symlink
    sudo ln -s /opt/ma/netmail/etc/launcher.d-available/30-solr.conf /opt/ma/netmail/etc/launcher.d/30-solr.conf

    if [ $OPEN_PORTS -eq 1 ]; then
        echo "Opening Firewall ports"
        sudo firewall-cmd --add-port=$SOLR_PORT/tcp --permanent
        sudo systemctl reload firewalld
    fi
    #Start solr
    /opt/ma/netmail/sbin/solr.sh start

    if [ $SOLR_FINISH -eq 1 ]; then
        echo "Finishing Solr Cluster"
        sudo /opt/ma/netmail/solr/solr_wizard_col.sh --quiet \
            --solr-port $SOLR_PORT \
            --solr-host $SOLR_IP_ADDR \
            --solr-num-shard $SHARDS \
            --solr-num-replica $REPLICAS
    fi
}

#Default Values
ZOOKEEPER_IP_ADDR=`hostname -I | xargs`
SOLR_IP_ADDR=`hostname -I | xargs`
ZOOKEEPER=1
SOLR=1
SOLR_FINISH=0
OPEN_PORTS=1
DEFAULT_QUICK_INSTALL=0
SOLR_PORT=31000
ZOOKEEPER_PORT=32000
REPLICAS=0
SHARDS=8
DEBUG=0
MASTER_ONLY=0

MEM=`free | grep Mem | awk 'NF>1{print $2}'`
HALF=`echo "scale=3; $MEM / 2000000" | bc `
HEAP=`printf "%.0f" $HALF`


# Parse params
while getopts ":mqz:fr:s:dh" arg; do
    case "${arg}" in
        m)
            MASTER_ONLY=1
            ;;
        q)
            DEFAULT_QUICK_INSTALL=1
            SOLR_FINISH=1
            ;;
        z)
            ZOOKEEPER=0
            ZOOKEEPER_HOST=${OPTARG}
            ;;
        f)
            SOLR_FINISH=1
            ;;
        r)
            REPLICAS=${OPTARG}
            ;;
        s)
            SHARDS=${OPTARG}
            ;;
        d)
            DEBUG=1
            ;;
        h)
            Usage
            exit 0
            ;;
        *)
            Usage
            exit 0
            ;;
    esac
done

if [ $OPTIND -eq 1 ]; then
    Usage
    exit 0
fi

firewall_service_check

if [ ${ZOOKEEPER} -eq 0 ]; then
    valid_ip ${ZOOKEEPER_HOST}
    if [ $stat -ne 0 ]; then
        echo "Invalid Zookeeper IP: ${ZOOKEEPER_HOST}"
        Usage
        exit 2
    fi
fi

if [ ${ZOOKEEPER} -eq 1 ]; then 
    if [ $DEBUG -eq 0 ]; then
        configure_zookeeper
    fi
    ZOOKEEPER_HOST=${ZOOKEEPER_IP_ADDR}
fi

if [ ${SOLR} -eq 1 ]; then
    valid_ip $SOLR_IP_ADDR
    if [ $stat -ne 0 ]; then
        echo "Invalid Solr IP: ${SOLR_IP_ADDR}"
        Usage
        exit 2
    fi
    if [ $ZOOKEEPER_HOST ]; then
        valid_ip $ZOOKEEPER_HOST
        if [ $stat -ne 0 ]; then
            echo "Invalid Zookeeper Host IP: $ZOOKEEPER_HOST"
            Usage
            exit 2
        fi
    else
        echo "Missing Zookeeper Host IP address"
        Usage
        exit 2
    fi

    if [ $SOLR_FINISH -eq 1 ]; then
        IS_NUMBER=0
        if [ ! -z "${REPLICAS##*[!0-9]*}" ]; then
            ((IS_NUMBER++))
        fi
        if [ ! -z "${SHARDS##*[!0-9]*}" ]; then
            ((IS_NUMBER++))
        fi
        if [ -z $REPLICAS ] || [ -z $SHARDS ] || [ $IS_NUMBER -ne 2 ]; then
            echo "Missing or wrong REPLICAS,SHARD information"
            Usage
            exit 2
        fi
        if [ $REPLICAS -gt 3 ]; then
            echo "The number of replicas cannot be greater than 3"
            exit 2
        fi
        if [ $SHARDS -gt 16 ]; then
            echo "The number of shards cannot be greater than 16"
            exit 2
        fi
    fi
    if [ $DEBUG -eq 0 ]; then
        configure_solr
    fi
fi

#Restarting services
if [ $DEBUG -eq 0 ]; then
    sudo systemctl restart netmail
fi

if [ $DEBUG -eq 1 ]; then
    echo "
    MASTER_ONLY: $MASTER_ONLY
    ZOOKEEPER_IP_ADDR: $ZOOKEEPER_IP_ADDR
    ZOOKEEPER_HOST: $ZOOKEEPER_HOST
    SOLR_IP_ADDR: $SOLR_IP_ADDR
    ZOOKEEPER: $ZOOKEEPER
    SOLR: $SOLR
    SOLR_FINISH: $SOLR_FINISH
    OPEN_PORTS: $OPEN_PORTS
    DEFAULT_QUICK_INSTALL: $DEFAULT_QUICK_INSTALL
    SOLR_PORT: $SOLR_PORT
    ZOOKEEPER_PORT: $ZOOKEEPER_PORT
    REPLICAS: $REPLICAS
    SHARDS: $SHARDS
    "
fi