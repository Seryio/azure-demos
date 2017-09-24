#!/bin/bash

source ./config.sh

rm *pem *csr *json *yaml *kubeconfig 2> /dev/null

echo "-- CA config"
#Create the CA configuration file:
cat > $DATA_FOLDER"ca-config.json" <<EOF
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
cat > $DATA_FOLDER"ca-csr.json" <<EOF
{
  "CN": "Kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "ES",
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
cfssl gencert -initca $DATA_FOLDER"ca-csr.json" 2> /dev/null | cfssljson -bare ca

echo "-- Admin CSR"
#Create the admin client certificate signing request:
cat > $DATA_FOLDER"admin-csr.json" <<EOF
{
  "CN": "admin",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "ES",
      "L": "Madrid",
      "O": "system:masters",
      "OU": "Kubernetes The Hard Way",
      "ST": "Madrid"
    }
  ]
}
EOF

echo "-- Admin priv/pub keys and cert"
#Generate the admin client certificate and private key:
cfssl gencert \
  -ca=$DATA_FOLDER"ca.pem" \
  -ca-key=$DATA_FOLDER"ca-key.pem" \
  -config=$DATA_FOLDER"ca-config.json" \
  -profile=kubernetes \
  $DATA_FOLDER"admin-csr.json" 2> /dev/null | cfssljson -bare admin

echo "-- Workers priv/pub keys and cert"  
#Generate a certificate and private key for each Kubernetes worker node:
while read WORKER_DATA; do	
	WORKER_NAME=$(echo $WORKER_DATA        |  cut -d" " -f2)
	WORKER_INTERNAL_IP=$(echo $WORKER_DATA |  cut -d" " -f3)
	WORKER_EXTERNAL_IP=$(echo $WORKER_DATA |  cut -d" " -f4)

	cat > $DATA_FOLDER$WORKER_NAME"-csr.json" <<EOF
	{
	  "CN": "system:node:$WORKER_NAME",
	  "key": {
		"algo": "rsa",
		"size": 2048
	  },
	  "names": [
		{
		  "C": "ES",
		  "L": "Madrid",
		  "O": "system:nodes",
		  "OU": "Kubernetes The Hard Way",
		  "ST": "Madrid"
		}
	  ]
	}
EOF

	cfssl gencert \
	  -ca=$DATA_FOLDER"ca.pem" \
	  -ca-key=$DATA_FOLDER"ca-key.pem" \
	  -config=$DATA_FOLDER"ca-config.json" \
	  -hostname=${WORKER_NAME},${WORKER_EXTERNAL_IP},${WORKER_INTERNAL_IP} \
	  -profile=kubernetes \
	 $DATA_FOLDER$WORKER_NAME"-csr.json" 2> /dev/null | cfssljson -bare ${WORKER_NAME}
	 
done <<< "$(cat $INVENTORY_FILE | grep WORKER_NODE)"

echo "-- Kube-proxy priv/pub keys and cert"
#Generate the kube-proxy client certificate and private key:
cat > $DATA_FOLDER"kube-proxy-csr.json" <<EOF
{
  "CN": "system:kube-proxy",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "ES",
      "L": "Madrid",
      "O": "system:node-proxier",
      "OU": "Kubernetes The Hard Way",
      "ST": "Madrid"
    }
  ]
}
EOF

cfssl gencert \
  -ca=$DATA_FOLDER"ca.pem" \
  -ca-key=$DATA_FOLDER"ca-key.pem" \
  -config=$DATA_FOLDER"ca-config.json" \
  -profile=kubernetes \
  $DATA_FOLDER"kube-proxy-csr.json" 2> /dev/null | cfssljson -bare kube-proxy

echo "-- Kube API priv/pub keys and cert"
#Generate the kube API certificate and private key:
cat > $DATA_FOLDER"kubernetes-csr.json" <<EOF
{
  "CN": "kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "ES",
      "L": "Madrid",
      "O": "Kubernetes",
      "OU": "Kubernetes The Hard Way",
      "ST": "Madrid"
    }
  ]
}
EOF

while read MASTER_INTERNAL_IP; do
	VM_IP_LIST="$VM_IP_LIST$MASTER_INTERNAL_IP,"
done <<< "$(cat $INVENTORY_FILE | grep MASTER_NODE | cut -d" " -f3)"

PRIMARY_MASTER_EXTERNAL_IP=$(grep PRIMARY_MASTER $INVENTORY_FILE | cut -d" " -f4)
VM_IP_LIST="$VM_IP_LIST$PRIMARY_MASTER_EXTERNAL_IP"

cfssl gencert \
  -ca=$DATA_FOLDER"ca.pem" \
  -ca-key=$DATA_FOLDER"ca-key.pem" \
  -config=$DATA_FOLDER"ca-config.json" \
  -hostname=${VM_IP_LIST},127.0.0.1,kubernetes.default \
  -profile=kubernetes \
  $DATA_FOLDER"kubernetes-csr.json" 2> /dev/null | cfssljson -bare kubernetes


mv *pem *csr $DATA_FOLDER
set -x
echo "-- Copying files to destination"
while read WORKER_DATA; do	
	WORKER_NAME=$(echo $WORKER_DATA        |  cut -d" " -f2)
	WORKER_EXTERNAL_IP=$(echo $WORKER_DATA |  cut -d" " -f4)
 
	scp -o StrictHostKeyChecking=no $DATA_FOLDER"ca.pem" $DATA_FOLDER${WORKER_NAME}-key.pem $DATA_FOLDER${WORKER_NAME}.pem $WORKER_EXTERNAL_IP:~/
done <<< "$(cat $INVENTORY_FILE | grep WORKER_NODE)"

while read MASTER_EXTERNAL_IP; do	
	scp -o StrictHostKeyChecking=no $DATA_FOLDER"ca.pem" $DATA_FOLDER"ca-key.pem" $DATA_FOLDER"kubernetes-key.pem" $DATA_FOLDER"kubernetes.pem" $MASTER_EXTERNAL_IP:~/
done <<< "$(cat $INVENTORY_FILE | grep MASTER_NODE | cut -d" " -f4)"
 