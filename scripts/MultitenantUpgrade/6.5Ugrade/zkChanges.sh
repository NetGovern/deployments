#!/usr/bin/bash

COLLECTION=ma
# Zk default config files
ZK_CONF=/opt/ma/netmail/etc/zookeeper.conf
ZK_INTERCONF_DEFAULT=/opt/ma/netmail/etc/zookeeper_internal.conf
SOLR_CONF=/opt/ma/netmail/etc/solr.conf
SOLR_SCHEMA=/opt/ma/netmail/solr/conf/schema.xml
SOLR_CONFIG=/opt/ma/netmail/solr/conf/solrconfig.xml

# Wizard output
STDOUT="/tmp/solr_wizard.stdout"
STDERR="/tmp/solr_wizard.stderr"

LogError() {
    echo "*** ERROR *** $1"
    echo "See for details: $STDOUT and $STDERR"
}

LogInfo() {
    echo "*** $1"
}


# check that zookeeper is installed on the node
# if zookeeper is not installed then do not try to upload the schema
if [[ ! -e $ZK_CONF ]];then
    LogInfo "Zookeeper is not installed on this node, there is nothing to do.";
    exit 0
fi

# Check that Zk conf is readable
[[ -r "$ZK_CONF" ]] \
    || ( echo "*** Cannot read Zk conf ($ZK_CONF) - use ZK_CONF to override default"; exit 1)

# Source Zk config and check values
. "$ZK_CONF"

# check that zk internal conf is readable
[[ -r $ZK_INTERCONF_DEFAULT ]] || ( echo "*** Cannot read Zk internal conf ($ZK_INTERCONF_DEFAULT)"; exit 1)
# source zk internal config
. $ZK_INTERCONF_DEFAULT

# use localhost as zookeeper host
ZK_HOST=localhost
# retrieve zookeeper port from config file
ZK_PORT=$clientPort


# check if solr config is readable
# Check that Zk conf is readable
[[ -r "$SOLR_CONF" ]] \
    || ( echo "*** Cannot read Solr conf ($SOLR_CONF)"; exit 1)

# source solr config
. $SOLR_CONF

# check that zookeeper is running
ZK_RUN=`netstat -an | grep $ZK_PORT`
#( echo "de" | nc -w 1 localhost $ZK_PORT >>"$STDOUT" 2>>"$STDERR" && ZK_RUN=1 ) || (ZK_RUN="0" )
#echo "lalalal=>$ZK_RUN" 

if [[ $ZK_RUN == "" ]];then
    LogInfo "Zookeeper is not running, will not update the schema.";
    exit 1
fi


OLD_CONFIG=/tmp/schema.$$

# download existing config from zookeeper
$ZK_DATA_DIR/bin/netmail_zkcli.sh -zkhost $ZK_HOST:$ZK_PORT/solr -cmd get /configs/$COLLECTION/schema.xml > $OLD_CONFIG
#retrieve version of old schema and assign 0 if no version was set
OLD_SCHEMA_VERSION=`grep netmailSchemaVersion $OLD_CONFIG | awk '{match($0,/(.*)=(.*)\-\->/,a); print a[2]}'`

if [[ $OLD_SCHEMA_VERSION == "" ]];then
    OLD_SCHEMA_VERSION=0
fi

rm -f $OLD_CONFIG

#retrieve version for new schema
NEW_SCHEMA_VERSION=`grep netmailSchemaVersion $SOLR_SCHEMA | awk '{match($0,/(.*)=(.*)\-\->/,a); print a[2]}'`

#compare schema versions
# only reload zookeeper config if they are different

if [[ $OLD_SCHEMA_VERSION == $NEW_SCHEMA_VERSION ]];then
    LogInfo "No changes detected in the schema will not upload the schema to Zookeeper"
    exit 0
fi

if [ $NEW_SCHEMA_VERSION \> $OLD_SCHEMA_VERSION ];then
    LogInfo "Detected new schema version ($NEW_SCHEMA_VERSION) will upload it to Zookeeper"
    #load new config to zookeeper
    $ZK_DATA_DIR/bin/netmail_zkcli.sh -zkhost $ZK_HOST:$ZK_PORT/solr -cmd putfile /configs/$COLLECTION/schema.xml $SOLR_SCHEMA
    $ZK_DATA_DIR/bin/netmail_zkcli.sh -zkhost $ZK_HOST:$ZK_PORT/solr -cmd putfile /configs/$COLLECTION/solrconfig.xml $SOLR_CONFIG    
fi

exit 0
