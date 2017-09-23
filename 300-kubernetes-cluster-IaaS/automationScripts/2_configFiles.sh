#!/bin/bash

source ./config.sh

echo "-- Generating workers config files"  
PRIMARY_MASTER_EXTERNAL_IP=$(grep PRIMARY_MASTER $INVENTORY_FILE | cut -d" " -f4)
  
while read WORKER_NAME; do	
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server=https://${PRIMARY_MASTER_EXTERNAL_IP}:6443 \
    --kubeconfig=${WORKER_NAME}.kubeconfig

  kubectl config set-credentials system:node:${WORKER_NAME} \
    --client-certificate=${WORKER_NAME}.pem \
    --client-key=${WORKER_NAME}-key.pem \
    --embed-certs=true \
    --kubeconfig=${WORKER_NAME}.kubeconfig

  kubectl config set-context default --cluster=kubernetes-the-hard-way \
    --user=system:node:${WORKER_NAME} \
    --kubeconfig=${WORKER_NAME}.kubeconfig

  kubectl config use-context default --kubeconfig=${WORKER_NAME}.kubeconfig

done <<< "$(cat $INVENTORY_FILE | grep WORKER_NODE | cut -d" " -f2)"

echo "-- Generating kube-proxy config files" 
kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=ca.pem \
  --embed-certs=true \
  --server=https://${PRIMARY_MASTER_EXTERNAL_IP}:6443 \
  --kubeconfig=kube-proxy.kubeconfig
kubectl config set-credentials kube-proxy \
  --client-certificate=kube-proxy.pem \
  --client-key=kube-proxy-key.pem \
  --embed-certs=true \
  --kubeconfig=kube-proxy.kubeconfig
kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=kube-proxy \
  --kubeconfig=kube-proxy.kubeconfig
kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig


echo "-- Distributing config files to workers" 
while read WORKER_DATA; do	
	WORKER_NAME=$(echo $WORKER_DATA        |  cut -d" " -f2)
	WORKER_EXTERNAL_IP=$(echo $WORKER_DATA |  cut -d" " -f4)
	scp -o StrictHostKeyChecking=no ${WORKER_NAME}.kubeconfig kube-proxy.kubeconfig $WORKER_EXTERNAL_IP:~/
done <<< "$(cat $INVENTORY_FILE | grep WORKER_NODE)"
