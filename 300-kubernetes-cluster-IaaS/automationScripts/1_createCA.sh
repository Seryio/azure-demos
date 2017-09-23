#!/bin/bash

source ./config.sh

rm *pem *csr *json *yaml *kubeconfig 2> /dev/null

echo "-- CA config"
#Create the CA configuration file:
cat > ca-config.json <<EOF
{
  "signing": {
    "default": {
      "expiry": "8760h"
    },
    "profiles": {
      "kubernetes": {
        "usages": ["signing", "key encipherment", "server auth", "client auth"],
        "expiry": "8760h"
      }
    }
  }
}
EOF

echo "-- CA CSR"
#Create the CA certificate signing request:
cat > ca-csr.json <<EOF
{
  "CN": "Kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "ESP",
      "L": "MADRID",
      "O": "Kubernetes",
      "OU": "CA",
      "ST": "MADRID"
    }
  ]
}
EOF

echo "-- CA priv/pub keys and cert"
#Generate the CA certificate and private key:
cfssl gencert -initca ca-csr.json 2> /dev/null | cfssljson -bare ca

echo "-- Admin CSR"
#Create the admin client certificate signing request:
cat > admin-csr.json <<EOF
{
  "CN": "admin",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "system:masters",
      "OU": "Kubernetes The Hard Way",
      "ST": "Oregon"
    }
  ]
}
EOF

echo "-- Admin priv/pub keys and cert"
#Generate the admin client certificate and private key:
cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  admin-csr.json 2> /dev/null | cfssljson -bare admin

echo "-- Workers priv/pub keys and cert"  
#Generate a certificate and private key for each Kubernetes worker node:
for instance in k8sworker1 k8sworker2 k8sworker3; do
	cat > ${instance}-csr.json <<EOF
	{
	  "CN": "system:node:${instance}",
	  "key": {
		"algo": "rsa",
		"size": 2048
	  },
	  "names": [
		{
		  "C": "US",
		  "L": "Portland",
		  "O": "system:nodes",
		  "OU": "Kubernetes The Hard Way",
		  "ST": "Oregon"
		}
	  ]
	}
EOF

	EXTERNAL_IP=$(az vm show -g $resGroup -n $instance -d --query "publicIps" -o tsv)
	INTERNAL_IP=$(az vm show -g $resGroup -n $instance -d --query "privateIps" -o tsv)

	cfssl gencert \
	  -ca=ca.pem \
	  -ca-key=ca-key.pem \
	  -config=ca-config.json \
	  -hostname=${instance},${EXTERNAL_IP},${INTERNAL_IP} \
	  -profile=kubernetes \
	 ${instance}-csr.json 2> /dev/null | cfssljson -bare ${instance}
	 
done

echo "-- Kube-proxy priv/pub keys and cert"
#Generate the kube-proxy client certificate and private key:
cat > kube-proxy-csr.json <<EOF
{
  "CN": "system:kube-proxy",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "system:node-proxier",
      "OU": "Kubernetes The Hard Way",
      "ST": "Oregon"
    }
  ]
}
EOF

cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  kube-proxy-csr.json 2> /dev/null | cfssljson -bare kube-proxy

echo "-- Kube API priv/pub keys and cert"
#Generate the kube API certificate and private key:
cat > kubernetes-csr.json <<EOF
{
  "CN": "kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "Kubernetes",
      "OU": "Kubernetes The Hard Way",
      "ST": "Oregon"
    }
  ]
}
EOF

for masterName in $(az resource list --tag "role=master" --query "[?type=='Microsoft.Compute/virtualMachines']".name  -o tsv); do
	THIS_IP=$(az vm show -g $resGroup -n $masterName -d --query privateIps -o tsv)
	VM_IP_LIST="$VM_IP_LIST$THIS_IP,"
done

MASTER_PUBLIC_IP=$(az network public-ip list --query "[?tags.role=='master'].ipAddress" -o tsv)
VM_IP_LIST="$VM_IP_LIST$MASTER_PUBLIC_IP"

cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -hostname=${VM_IP_LIST},127.0.0.1,kubernetes.default \
  -profile=kubernetes \
  kubernetes-csr.json 2> /dev/null | cfssljson -bare kubernetes

echo "-- Copying files to destination"

for workerName in $(az resource list --tag "role=worker" --query "[?type=='Microsoft.Compute/virtualMachines']".name  -o tsv); do
	workerExternalIP=$(az vm show -g $resGroup -n $workerName -d --query publicIps -o tsv)
	scp -o StrictHostKeyChecking=no ca.pem ${workerName}-key.pem ${workerName}.pem $workerExternalIP:~/
done

for masterName in $(az resource list --tag "role=master" --query "[?type=='Microsoft.Compute/virtualMachines']".name  -o tsv); do
	masterExternalIP=$(az vm show -g $resGroup -n $masterName -d --query publicIps -o tsv)
	scp -o StrictHostKeyChecking=no ca.pem ca-key.pem kubernetes-key.pem kubernetes.pem $masterExternalIP:~/
done
 