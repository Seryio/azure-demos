#!/bin/bash

source ./config.sh
echo "" > $INVENTORY_FILE

echo "-- LIST WORKERS"
for WORKER_NAME in $(az resource list --tag "role=worker" --query "[?type=='Microsoft.Compute/virtualMachines']".name  -o tsv); do
	WORKER_EXTERNAL_IP=$(az vm show -g $RESOURCE_GROUP -n $WORKER_NAME -d --query publicIps -o tsv)
	WORKER_INTERNAL_IP=$(az vm show -g $RESOURCE_GROUP -n $WORKER_NAME -d --query privateIps -o tsv)
	echo "WORKER_NODE $WORKER_NAME $WORKER_INTERNAL_IP $WORKER_EXTERNAL_IP " >> $INVENTORY_FILE
done


echo "-- LIST MASTERS"
for MASTER_NAME in $(az resource list --tag "role=master" --query "[?type=='Microsoft.Compute/virtualMachines']".name  -o tsv); do
	MASTER_EXTERNAL_IP=$(az vm show -g $RESOURCE_GROUP -n $MASTER_NAME -d --query publicIps -o tsv)
	MASTER_INTERNAL_IP=$(az vm show -g $RESOURCE_GROUP -n $MASTER_NAME -d --query privateIps -o tsv)
	echo "MASTER_NODE $MASTER_NAME $MASTER_INTERNAL_IP $MASTER_EXTERNAL_IP " >> $INVENTORY_FILE
done

echo "-- LIST NETWORKS"
for CIDR in $(az network vnet subnet list --vnet-name vnet1 --resource-group $RESOURCE_GROUP --query "[].addressPrefix" -o tsv); do
	echo "CIDR $CIDR" >> $INVENTORY_FILE
done

echo "-- FLAG PRIMARY MASTER PUBLIC IP"
MASTER_PUBLIC_IP=$(az network public-ip list --query "[?tags.role=='master'].ipAddress" -o tsv)

LINE_PRIMARY_MASTER=$(grep $MASTER_PUBLIC_IP $INVENTORY_FILE)
NEW_LINE_PRIMARY_MASTER=$LINE_PRIMARY_MASTER" PRIMARY_MASTER"

sed -i "s/$LINE_PRIMARY_MASTER/$NEW_LINE_PRIMARY_MASTER/" $INVENTORY_FILE
