#!/bin/bash

source ./config.sh

#ETCD cluster connection string in etc service flag --initial-cluster
while read MASTER_INTERNAL_IP; do	
	ETCD_CLUSTER_CONNECTION_STRING=$ETCD_CLUSTER_CONNECTION_STRING"https://$MASTER_INTERNAL_IP:$ETCD_PEER_API_PORT,"
	
done <<< "$(cat $INVENTORY_FILE | grep MASTER_NODE | cut -d" " -f3)"
ETCD_CLUSTER_CONNECTION_STRING=$(echo $ETCD_CLUSTER_CONNECTION_STRING | sed 's/,$//')

#CIDR
CIDR=$(grep CIDR $INVENTORY_FILE | cut -d" " -f2)

while read MASTER_DATA; do	
	MASTER_NAME=$(echo $MASTER_DATA        |  cut -d" " -f2)
	MASTER_INTERNAL_IP=$(echo $MASTER_DATA |  cut -d" " -f3)
	MASTER_EXTERNAL_IP=$(echo $MASTER_DATA |  cut -d" " -f4)
	
#API SERVER FILE
cat > $MASTER_NAME-kube-apiserver.service <<EOF
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-apiserver \\
  --admission-control=NamespaceLifecycle,NodeRestriction,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota \\
  --advertise-address=${MASTER_INTERNAL_IP} \\
  --allow-privileged=true \\
  --apiserver-count=3 \\
  --audit-log-maxage=30 \\
  --audit-log-maxbackup=3 \\
  --audit-log-maxsize=100 \\
  --audit-log-path=/var/log/audit.log \\
  --authorization-mode=Node,RBAC \\
  --bind-address=0.0.0.0 \\
  --client-ca-file=/var/lib/kubernetes/ca.pem \\
  --enable-swagger-ui=true \\
  --etcd-cafile=/var/lib/kubernetes/ca.pem \\
  --etcd-certfile=/var/lib/kubernetes/kubernetes.pem \\
  --etcd-keyfile=/var/lib/kubernetes/kubernetes-key.pem \\
  --etcd-servers=${ETCD_CLUSTER_CONNECTION_STRING} \\
  --event-ttl=1h \\
  --experimental-encryption-provider-config=/var/lib/kubernetes/encryption-config.yaml \\
  --insecure-bind-address=0.0.0.0 \\
  --kubelet-certificate-authority=/var/lib/kubernetes/ca.pem \\
  --kubelet-client-certificate=/var/lib/kubernetes/kubernetes.pem \\
  --kubelet-client-key=/var/lib/kubernetes/kubernetes-key.pem \\
  --kubelet-https=true \\
  --runtime-config=rbac.authorization.k8s.io/v1alpha1 \\
  --service-account-key-file=/var/lib/kubernetes/ca-key.pem \\
  --service-cluster-ip-range=${CIDR} \\
  --service-node-port-range=30000-32767 \\
  --tls-ca-file=/var/lib/kubernetes/ca.pem \\
  --tls-cert-file=/var/lib/kubernetes/kubernetes.pem \\
  --tls-private-key-file=/var/lib/kubernetes/kubernetes-key.pem \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

#CONTROLLER MANAGER FILE
cat > $MASTER_NAME-kube-controller-manager.service <<EOF
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-controller-manager \\
  --address=0.0.0.0 \\
  --cluster-cidr=${CIDR} \\
  --cluster-name=kubernetes \\
  --cluster-signing-cert-file=/var/lib/kubernetes/ca.pem \\
  --cluster-signing-key-file=/var/lib/kubernetes/ca-key.pem \\
  --leader-elect=true \\
  --master=http://${MASTER_INTERNAL_IP}:8080 \\
  --root-ca-file=/var/lib/kubernetes/ca.pem \\
  --service-account-private-key-file=/var/lib/kubernetes/ca-key.pem \\
  --service-cluster-ip-range=${CIDR} \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat > $MASTER_NAME-kube-scheduler.service <<EOF
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-scheduler \\
  --leader-elect=true \\
  --master=http://${MASTER_INTERNAL_IP}:8080 \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

done <<< "$(cat $INVENTORY_FILE | grep MASTER_NODE)"


echo "-- Prepare installation script" 
cat > k8s-control-installer.sh <<EOF
wget -q --https-only --timestamping \
  "https://storage.googleapis.com/kubernetes-release/release/v1.7.4/bin/linux/amd64/kube-apiserver" \
  "https://storage.googleapis.com/kubernetes-release/release/v1.7.4/bin/linux/amd64/kube-controller-manager" \
  "https://storage.googleapis.com/kubernetes-release/release/v1.7.4/bin/linux/amd64/kube-scheduler" \
  "https://storage.googleapis.com/kubernetes-release/release/v1.7.4/bin/linux/amd64/kubectl"
chmod +x kube-apiserver kube-controller-manager kube-scheduler kubectl
mv kube-apiserver kube-controller-manager kube-scheduler kubectl /usr/local/bin/
  
#Install API Server
mkdir -p /var/lib/kubernetes/
sudo mv ca.pem ca-key.pem kubernetes-key.pem kubernetes.pem encryption-config.yaml /var/lib/kubernetes/

#Service files have been moved already to each master
sudo mv kube-apiserver.service kube-scheduler.service kube-controller-manager.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable kube-apiserver kube-controller-manager kube-scheduler
sudo systemctl restart kube-apiserver kube-controller-manager kube-scheduler
EOF


echo "-- Loading binaries and installing" 
for MASTER_NAME in $(cat $INVENTORY_FILE | grep MASTER_NODE | cut -d" " -f2); do
	MASTER_EXTERNAL_IP=$(grep $MASTER_NAME $INVENTORY_FILE |  cut -d" " -f4)
	scp -o StrictHostKeyChecking=no k8s-control-installer.sh $MASTER_EXTERNAL_IP:~/
  scp -o StrictHostKeyChecking=no $MASTER_NAME-kube-apiserver.service          $MASTER_EXTERNAL_IP:~/kube-apiserver.service
  scp -o StrictHostKeyChecking=no $MASTER_NAME-kube-controller-manager.service $MASTER_EXTERNAL_IP:~/kube-controller-manager.service
  scp -o StrictHostKeyChecking=no $MASTER_NAME-kube-scheduler.service          $MASTER_EXTERNAL_IP:~/kube-scheduler.service


	ssh -o StrictHostKeyChecking=no $MASTER_EXTERNAL_IP "sudo sh k8s-control-installer.sh"
	
done



