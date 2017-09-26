#!/bin/bash

source ./config.sh

echo "-- Generating workers config files"  
PRIMARY_MASTER_EXTERNAL_IP=$(grep PRIMARY_MASTER $INVENTORY_FILE | cut -d" " -f4)

while read WORKER_NAME; do	
  kubectl config set-cluster kubernetes-the-hard-way \
    --server=http://${PRIMARY_MASTER_EXTERNAL_IP}:6443 \
    --kubeconfig=$DATA_FOLDER${WORKER_NAME}.kubeconfig

  kubectl config set-credentials system:node:${WORKER_NAME} \
    --kubeconfig=$DATA_FOLDER${WORKER_NAME}.kubeconfig
  
  kubectl config set-context default --cluster=kubernetes-the-hard-way \
    --user=system:node:${WORKER_NAME} \
    --kubeconfig=$DATA_FOLDER${WORKER_NAME}.kubeconfig

  kubectl config use-context default --kubeconfig=$DATA_FOLDER${WORKER_NAME}.kubeconfig

done <<< "$(cat $INVENTORY_FILE | grep WORKER_NODE | cut -d" " -f2)"

echo "-- Generating kube-proxy config files" 
kubectl config set-cluster kubernetes-the-hard-way \
   --server=http://${PRIMARY_MASTER_EXTERNAL_IP}:6443 \
   --kubeconfig=$DATA_FOLDER"kube-proxy.kubeconfig"

kubectl config set-credentials kube-proxy \
  --kubeconfig=$DATA_FOLDER"kube-proxy.kubeconfig"

kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=kube-proxy \
  --kubeconfig=$DATA_FOLDER"kube-proxy.kubeconfig"
kubectl config use-context default --kubeconfig=$DATA_FOLDER"kube-proxy.kubeconfig"


echo "-- Distributing config files to workers" 
while read WORKER_DATA; do	
	WORKER_NAME=$(echo $WORKER_DATA        |  cut -d" " -f2)
	WORKER_EXTERNAL_IP=$(echo $WORKER_DATA |  cut -d" " -f4)
	scp -o StrictHostKeyChecking=no $DATA_FOLDER${WORKER_NAME}.kubeconfig $DATA_FOLDER"kube-proxy.kubeconfig" $WORKER_EXTERNAL_IP:~/
done <<< "$(cat $INVENTORY_FILE | grep WORKER_NODE)"
