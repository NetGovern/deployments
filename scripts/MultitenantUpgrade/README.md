# Multitenant upgrade script
  
It needs to run from the Remote Provider server.
It also needs the credentials for the Windows and Linux servers (Archive and index).

This script has 2 parts:  
* Discovery
* Upgrade

## Discovery
It generates a json file with a map of the nodes (Remote Provider, Index, Archive and Workers)

## Upgrade
It upgrades the nodes that meet the conditions (current version < target upgrade version).
It starts with Index, followed by the Remote Provider and Archive/Workers later.
