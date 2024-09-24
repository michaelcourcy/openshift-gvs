#!/bin/bash
storageclass=managed-csi
for i in {1..11}
do
cat <<EOF | oc create -f -
apiVersion: v1
kind: Namespace
metadata:
  labels:
    role: test-scalability
  name: basic-app$i  
spec: {}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: basic-app
  namespace: basic-app$i
  labels:
    app: basic-app
spec:
  strategy:
    type: Recreate
  replicas: 1
  selector:
    matchLabels:
      app: basic-app
  template:
    metadata:
      labels:
        app: basic-app
    spec:
      containers:
      - name: basic-app-container   
        image: docker.io/alpine:latest
        resources:
            requests:
              memory: 256Mi
              cpu: 100m
        command: ["tail"]
        args: ["-f", "/dev/null"]         
        volumeMounts:
        - name: data
          mountPath: /data        
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: pvc-kasten
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-kasten
  namespace: basic-app$i
spec:
  # change for your storage class
  storageClassName: $storageclass
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
EOF
done