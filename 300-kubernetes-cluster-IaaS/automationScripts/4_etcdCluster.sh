#!/bin/bash

source ./config.sh


echo "-- Creating etcd installer" 
cat > $DATA_FOLDER"etcd-installer.sh" <<EOF
	wget -q --https-only --timestamping https://github.com/coreos/etcd/releases/download/v3.2.7/etcd-v3.2.7-linux-amd64.tar.gz 
	tar -xf ~/etcd-v3.2.7-linux-amd64.tar.gz
	sudo mv ~/etcd-v3.2.7-linux-amd64/etcd* /usr/local/bin/
	sudo mkdir -p /etc/etcd /var/lib/etcd
	sudo cp ~/ca.pem ~/kubernetes-key.pem ~/kubernetes.pem /etc/etcd/
EOF

echo "-- Installing etcd in each master" 
#Then each etcd.service file is unique per cluster member, but we need a flag --initial-cluster with all IPs of cluster members
for MASTER_EXTERNAL_IP in $(cat $INVENTORY_FILE | grep MASTER_NODE | cut -d" " -f4); do
	scp -o StrictHostKeyChecking=no $DATA_FOLDER"etcd-installer.sh" $MASTER_EXTERNAL_IP:~/
	ssh -o StrictHostKeyChecking=no $MASTER_EXTERNAL_IP "sudo sh etcd-installer.sh"
done

#ETCD cluster connection string in etc service flag --initial-cluster
echo "-- Creating etcd linux service file - reading cluster addressing" 
while read MASTER_DATA; do	
	MASTER_NAME=$(echo $MASTER_DATA        |  cut -d" " -f2)
	MASTER_INTERNAL_IP=$(echo $MASTER_DATA |  cut -d" " -f3)

	CLUSTER_CONNECTION_STRING="$CLUSTER_CONNECTION_STRING$MASTER_NAME=http://$MASTER_INTERNAL_IP:$ETCD_PEER_API_PORT,"
	
done <<< "$(cat $INVENTORY_FILE | grep MASTER_NODE )"
CLUSTER_CONNECTION_STRING=$(echo $CLUSTER_CONNECTION_STRING | sed 's/,$//')

echo "-- Creating etcd linux service file - populating data" 
while read MASTER_DATA; do	
	MASTER_NAME=$(echo $MASTER_DATA        |  cut -d" " -f2)
	MASTER_INTERNAL_IP=$(echo $MASTER_DATA |  cut -d" " -f3)
	cat > $DATA_FOLDER$MASTER_NAME"-etcd.service" <<EOF
[Unit]
Description=etcd
Documentation=https://github.com/coreos

[Service]
ExecStart=/usr/local/bin/etcd \\
  --name ${MASTER_NAME} \\
  --cert-file=/etc/etcd/kubernetes.pem \\
  --key-file=/etc/etcd/kubernetes-key.pem \\
  --peer-cert-file=/etc/etcd/kubernetes.pem \\
  --peer-key-file=/etc/etcd/kubernetes-key.pem \\
  --trusted-ca-file=/etc/etcd/ca.pem \\
  --peer-trusted-ca-file=/etc/etcd/ca.pem \\
  --peer-client-cert-auth \\
  --client-cert-auth \\
  --initial-advertise-peer-urls https://${MASTER_INTERNAL_IP}:2380 \\
  --listen-peer-urls https://${MASTER_INTERNAL_IP}:2380 \\
  --listen-client-urls https://${MASTER_INTERNAL_IP}:2379,http://127.0.0.1:2379 \\
  --advertise-client-urls https://${MASTER_INTERNAL_IP}:2379 \\
  --initial-cluster-token etcd-cluster-0 \\
  --initial-cluster ${CLUSTER_CONNECTION_STRING} \\
  --initial-cluster-state new \\
  --data-dir=/var/lib/etcd
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
done <<< "$(cat $INVENTORY_FILE | grep MASTER_NODE )"

echo "-- Demonaizing etcd"
cat > $DATA_FOLDER"etcd-starter.sh" <<EOF
	sudo mv ~/etcd.service /etc/systemd/system/
	sudo systemctl daemon-reload
	sudo systemctl enable etcd
	sudo systemctl start etcd
EOF

for MASTER_NAME in $(cat $INVENTORY_FILE | grep MASTER_NODE | cut -d" " -f2); do
	MASTER_EXTERNAL_IP=$(grep $MASTER_NAME $INVENTORY_FILE |  cut -d" " -f4)
	
	scp -o StrictHostKeyChecking=no $DATA_FOLDER"etcd-starter.sh" $MASTER_EXTERNAL_IP:~/
	scp -o StrictHostKeyChecking=no $DATA_FOLDER$MASTER_NAME"-etcd.service" $MASTER_EXTERNAL_IP:~/etcd.service
	ssh -o StrictHostKeyChecking=no $MASTER_EXTERNAL_IP "sudo sh etcd-starter.sh"
done 
