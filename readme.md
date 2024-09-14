# Generic volume backup on Openshift

## Goal

Demonstrate how to use generic backup with kasten on openshift when your storage does not support snapshot (ie Nas economy, Azure file, simple NFS ...). 

We exercice here the most difficult condition of deployment for GVS which is Kasten deployed with the openshift operator.

If Kasten is deployed with the openshift operator you cannot use the mutating webhook to inject the kanister-sidecar into
your deployment or statefulset. Hence you'll have to use an exectable call `k10tool`. However the approach we describe here
still work in other environments.

Because we run a sidecar inside the workload we need to make sure the pods has the [necessary capabilities](https://docs.kasten.io/latest/install/generic.html#required-capabilities-for-generic-storage-backup) to do
backup and restore filesystem operation (using kopia). For that we create a specific `scc` (Security Context Constraint) with the minimum (but necessary) capabilities and authorize the service account of this namespace to use this `scc`.


## Deploy your application 

Open the file deployment-with-one-pvc.yaml and change 2 things
- Line 28: the image, use an image that you can pull from your cluster for instance docker.io/alpine:latest
- Line 51: change the names of the storage class use one storage class that exist in your cluster for instance managed-csi

```
oc create -f deployment-with-one-pvc.yaml
oc project basic-app
oc get po 
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

# Discover which scc your application is using

```
oc get po 
oc get po -o yaml |grep scc
```

in my case it's restricted-v2 which is the default scc that you get when you request no specific 
security context privilege for your pods.

create a copy of this scc adding this [necessary capabilities](https://docs.kasten.io/latest/install/generic.html#required-capabilities-for-generic-storage-backup) for Generic volume backup.

```
oc get scc restricted-v2 -o yaml > restricted-v2-gvs.yaml 
vi restricted-v2-gvs.yaml 
```

Change the name in the metadata section with `restricted-v2-gvs`

And add 
```
- CHOWN 
- DAC_OVERRIDE
- FOWNER
```
to the `allowedCapabilities` section.

submit it 
```
oc create -f restricted-v2-gvs.yaml 
```

and give the authorization to any service account in the namespace to use this scc 
```
namespace=basic-app
oc adm policy add-scc-to-group restricted-v2-gvs system:serviceaccounts:$namespace -n $namespace
```

# add the capabilities to the deployment 

So far we gave the authorization to the workload to take this capabilities but for the moment the 
workload did not claim them. That's what we're going to do now by changing the security context 
of the pods. Review `change-capabilities.json` and apply it to your workload.

```
oc patch deployment basic-app -n basic-app --type='json' -p "$(cat change-capabilities.json)"
```

Now you should see your pod restarting with the scc restricted-v2-gvs
```
oc get po -o yaml |grep scc
```

# Inject 

We need to inject the kanister-sidecar container into our deployment.
Download [k10tools](https://github.com/kastenhq/external-tools/releases) and execute

```
./k10tools k10genericbackup inject all -n basic-app
```

You should get this output 
```
./k10tools k10genericbackup inject all -n basic-app
Inject deployment:
  Injecting sidecar to deployment basic-app/basic-app
  Updating deployment basic-app/basic-app
  Waiting for deployment basic-app/basic-app to be ready
  Sidecar injection successful on deployment basic-app/basic-app!  -  OK

Inject statefulset:

Inject deploymentconfig:
```

check now that your deployment has 2 containers 
```
oc get deploy basic-app -o jsonpath='{.spec.template.spec.containers[*].name}'
```

you should  this output
```
basic-app-container kanister-sidecar
```

Also `oc get po` show 2/2 

```
oc get po 
NAME                         READY   STATUS    RESTARTS   AGE
basic-app-759d466dc9-sr6cf   2/2     Running   0          3m19s
```

and that also the kanister-sidecar has also the nessary capacity 
```
oc get deploy basic-app -o jsonpath='{.spec.template.spec.containers[1].securityContext.capabilities}'
{"add":["CHOWN","DAC_OVERRIDE","FOWNER"]}
```

you can also check that kopia is executable in the kanister-sidecar container  by just running `kopia` 
```
oc exec deploy/basic-app -c kanister-sidecar -- kopia
```

If the capabilities were not there that would not be possible, in this case you'll have `operation not permitted`.

# Configure Kasten to allow GVS 

Because [GVS is not crash consistent](https://docs.kasten.io/latest/install/gvs_restricted.html#restrict-gvs) 
Kasten want a strict control on who's deploying it and require that you provide a token that they generate for you. 

This token is linked to the UID of your cluster and must be added in your helm configuration. You provide the UID 
of your cluster `oc get ns default -ojsonpath='{.metadata.uid}` to the kasten team and they return this information

```
genericStorageBackup:
  token: <token>
```

If you are testing with the Kasten team a temporary test token can be provided in the form of 

```
genericStorageBackup:
  overridepubkey: <base64-tls-key-encrypted>
  token: <token>
```

This information must be added to your helm configuration directly in a "`values.yaml`" file or
in the k10 custom resource manisfest if you deploy Kasten with the operator.

# create a policy 

Create a policy `on demand` for the basic-app aplication and set up a location profile for 
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

delete the namespace and proceed a restore, check all your data are back.



