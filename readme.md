# Generic volume backup on Openshift

## Goal

Demonstrate how to use generic backup with kasten on openshift when your storage does not support snapshot 
(ie Nas economy, Azure file, simple NFS ...). 

Because we run a sidecar inside the workload we need to make sure the pods has the necessary capabilities to do
backup and restore filesystem operation (using kopia). For that we create a specific scc with the minimum capabilities 
and we create the necessary binding to the service account of the namespaces.


## create a deployment

Open the file deployment-with-one-pvc.yaml and change 2 things
- Line 24: the image, use an image that you can pull from your cluster for instance docker.io/alpine:latest
- Line 44: change the names of the storage class use one storage class that exist in your cluster for instance managed-csi

```
oc delete ns test-sidecar
oc create ns test-sidecar
oc project test-sidecar
```

Give any service account in the test-sidecar namsespace the ability to consume the k10-generic-backup scc
```
oc create -f k10-generic-scc.yaml
oc adm policy add-scc-to-group k10-generic-backup system:serviceaccounts:test-sidecar -n test-sidecar
```

```
oc create -f deployment-with-one-pvc.yaml
oc get po
```

You should get this output
```
NAME                         READY   STATUS    RESTARTS   AGE
basic-app-8559b4dd74-2c8tt   1/1     Running   0          56s
```

exec the pod and create some data 
```
oc exec deploy/basic-app -it -- sh
/ # cd /data/
/data # echo "Some data" > some-file.dat
/data # ls 
lost+found     some-file.dat
/data # exit
```

Now run the injection, download [k10tools](https://docs.kasten.io/latest/operating/k10tools.html)
and execute
```
./k10tools k10genericbackup inject all -n test-sidecar
```

You should get this output 
```
Inject deployment:
  Injecting sidecar to deployment test-sidecar/basic-app
  Updating deployment test-sidecar/basic-app
  Waiting for deployment test-sidecar/basic-app to be ready
  Sidecar injection successful on deployment test-sidecar/basic-app!  -  OK

Inject statefulset:

Inject deploymentconfig:
```

check now that your pod has 2 containers 
```
oc get po
```

you should get this output 
```
NAME                         READY   STATUS    RESTARTS   AGE
basic-app-6cf9cc6784-npg6g   2/2     Running   0          106s
```

You can also check that the pods has pickup the right scc
```
oc get po -o yaml |grep scc
```

You should get 
```
      openshift.io/scc: k10-generic-backup
```

# create a policy 

Create a policy `on demand` for the test-sidecar, set up a location profile for 
- export 
- kanister action 

If you follow the pods in the kasten-io namespace 

```
oc get po -n kasten-io -w
```

You'll see the creation of the data-mover pod and create-repo pod
```
NAME                                     READY   STATUS    RESTARTS       AGE
aggregatedapis-svc-679465588d-smss4      1/1     Running   0              8d
auth-svc-589c55fbb4-rt54t                2/2     Running   0              8d
catalog-svc-66595949f4-nd2b9             2/2     Running   0              8d
controllermanager-svc-7fc5d74c94-wrts9   1/1     Running   0              8d
crypto-svc-d9b8cc999-2fmpb               4/4     Running   0              8d
dashboardbff-svc-64bd5d6b78-rxv6d        2/2     Running   0              8d
data-mover-svc-nn2qt                     2/2     Running   0              5d6h
executor-svc-c6b8d86c9-dw44r             2/2     Running   2 (5d5h ago)   5d16h
executor-svc-c6b8d86c9-hgmxr             2/2     Running   3 (5d3h ago)   5d16h
executor-svc-c6b8d86c9-mqzkb             2/2     Running   1 (5d5h ago)   5d16h
frontend-svc-6d945d44c4-pgd5h            1/1     Running   0              8d
gateway-b8f584f87-zkvls                  1/1     Running   0              8d
jobs-svc-7db459754c-9hscp                1/1     Running   0              8d
k10-grafana-56fcfd79dd-x9j2w             1/1     Running   0              8d
kanister-svc-cff94b499-nt7k9             1/1     Running   0              8d
logging-svc-7c76b698-bms7f               1/1     Running   0              8d
metering-svc-947998fc5-ld4tc             1/1     Running   0              8d
prometheus-server-786fb745ff-kzc7v       2/2     Running   0              8d
state-svc-78766db49f-d5ctf               2/2     Running   0              8d
data-mover-svc-c2gf4                     0/2     Pending   0              0s
data-mover-svc-c2gf4                     0/2     Pending   0              0s
data-mover-svc-c2gf4                     0/2     ContainerCreating   0              0s
data-mover-svc-c2gf4                     0/2     ContainerCreating   0              0s
data-mover-svc-c2gf4                     0/2     ContainerCreating   0              0s
data-mover-svc-c2gf4                     2/2     Running             0              2s
backup-data-stats-glvkz                  0/1     Pending             0              0s
backup-data-stats-glvkz                  0/1     Pending             0              1s
backup-data-stats-glvkz                  0/1     Pending             0              1s
backup-data-stats-glvkz                  0/1     ContainerCreating   0              1s
backup-data-stats-glvkz                  0/1     ContainerCreating   0              1s
backup-data-stats-glvkz                  1/1     Running             0              3s
backup-data-stats-glvkz                  1/1     Terminating         0              10s
backup-data-stats-glvkz                  1/1     Terminating         0              10s
data-mover-svc-c2gf4                     2/2     Terminating         0              33s
create-repo-mm4cp                        0/2     Pending             0              0s
create-repo-mm4cp                        0/2     Pending             0              0s
create-repo-mm4cp                        0/2     Pending             0              0s
create-repo-mm4cp                        0/2     ContainerCreating   0              0s
create-repo-mm4cp                        0/2     ContainerCreating   0              1s
data-mover-svc-c2gf4                     0/2     Terminating         0              34s
data-mover-svc-c2gf4                     0/2     Terminating         0              34s
data-mover-svc-c2gf4                     0/2     Terminating         0              34s
create-repo-mm4cp                        2/2     Running             0              2s
create-repo-mm4cp                        2/2     Terminating         0              4s
create-repo-mm4cp                        2/2     Terminating         0              4s
backup-data-stats-vwp2j                  0/1     Pending             0              0s
backup-data-stats-vwp2j                  0/1     Pending             0              1s
backup-data-stats-vwp2j                  0/1     Pending             0              1s
backup-data-stats-vwp2j                  0/1     ContainerCreating   0              1s
backup-data-stats-vwp2j                  0/1     ContainerCreating   0              1s
backup-data-stats-vwp2j                  1/1     Running             0              2s
data-mover-svc-9qncc                     0/2     Pending             0              0s
data-mover-svc-9qncc                     0/2     Pending             0              0s
data-mover-svc-9qncc                     0/2     Pending             0              0s
data-mover-svc-9qncc                     0/2     ContainerCreating   0              0s
data-mover-svc-9qncc                     0/2     ContainerCreating   0              1s
backup-data-stats-vwp2j                  1/1     Terminating         0              9s
backup-data-stats-vwp2j                  1/1     Terminating         0              9s
data-mover-svc-9qncc                     2/2     Running             0              2s
data-mover-svc-9qncc                     2/2     Terminating         0              28s
data-mover-svc-lnwfk                     0/2     Pending             0              0s
data-mover-svc-lnwfk                     0/2     Pending             0              0s
data-mover-svc-lnwfk                     0/2     Pending             0              0s
data-mover-svc-9qncc                     0/2     Terminating         0              29s
data-mover-svc-lnwfk                     0/2     ContainerCreating   0              0s
data-mover-svc-9qncc                     0/2     Terminating         0              29s
data-mover-svc-9qncc                     0/2     Terminating         0              29s
data-mover-svc-lnwfk                     0/2     ContainerCreating   0              1s
data-mover-svc-lnwfk                     2/2     Running             0              2s
data-mover-svc-lnwfk                     2/2     Terminating         0              16s
data-mover-svc-lnwfk                     0/2     Terminating         0              18s
data-mover-svc-lnwfk                     0/2     Terminating         0              18s
data-mover-svc-lnwfk                     0/2     Terminating         0              18s
```

- data-mover-svc-c2gf4 is for sending the data in the pvc 
- create-repo-mm4cp is to create the initial kopia repo 
- data-mover-svc-lnwfk if for sending the spec of all the namespace and all the metadata of the policy

delete the namespace and proceed a restore, check all your data are back.



