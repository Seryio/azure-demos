#!/bin/bash

source ./config.sh


echo "-- Generating encription keys" 
ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)

cat > $DATA_FOLDER"encryption-config.yaml" <<EOF
kind: EncryptionConfig
apiVersion: v1
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${ENCRYPTION_KEY}
      - identity: {}
EOF

while read MASTER_EXTERNAL_IP; do	
	scp -o StrictHostKeyChecking=no $DATA_FOLDER"encryption-config.yaml" $MASTER_EXTERNAL_IP:~/
done <<< "$(cat $INVENTORY_FILE | grep MASTER_NODE | cut -d" " -f4)"