# Keeping Data Across Application Redeploys

## Deploy OpenDJ
use the `deploy-a-sam.sh` script
Get the IP of the opendj load balancer:

```
wm462-ad4:terraform-sam-solo rluckom$ kubectl -n rluckom get services
NAME             TYPE           CLUSTER-IP    EXTERNAL-IP     PORT(S)                       AGE
opendj-service   LoadBalancer   10.83.1.105   35.225.88.216   389:32726/TCP,636:32001/TCP   1h
sam-service      NodePort       10.83.0.26    <none>          80:31838/TCP,443:32438/TCP    1h
```

Check conectivity with `ldapsearch`

```
ldapsearch -LLL -H ldap://35.225.88.216:389 -D "cn=Directory Manager" -w <secret password>
```

## Add an arbitrary record

Create a file called `testUser.ldif` with the contents

```
dn: cn=chowder-head,ou=people,dc=dsde-dev,dc=broadinstitute,dc=org       
changetype: add                                                          
objectClass: inetOrgPerson                                               
objectClass: organizationalPerson                                        
objectClass: person                                                      
objectClass: top                                                         
cn: chowder-head                                                         
sn: chowder-head                                                         
mail: chowder-head                                                       
uid: 78                                                                  
userPassword: chowder
```

Add the testUser entry into opendj:

```
ldapadd -H ldap://<OpenDJ IP>:389 -D "cn=Directory Manager" -w <secret pass> -f testUser.ldif
```

Verify that the user is there

```
wm462-ad4:sam-solo-deploy rluckom$ ldapsearch -LLL -H ldap://35.225.88.216:389 -D "cn=Directory Manager" -w <secret password> | grep chowder
dn: cn=chowder-head,ou=people,dc=dsde-dev,dc=broadinstitute,dc=org
mail: chowder-head
sn: chowder-head
cn: chowder-head
```

## Tear down the opendj deployment

Delete the deployment

```
kubectl -n rluckom delete deployment opendj-deployment
```

validate that it's gone

```
wm462-ad4:sam-solo-deploy rluckom$ ldapsearch -LLL -H ldap://35.225.88.216:389 -D "cn=Directory Manager" -w <secret password> | grep chowder
ldap_sasl_bind(SIMPLE): Can't contact LDAP server (-1)
```

## Create a new opendj deployment using the same volume
Create the opendj deployment

```
wm462-ad4:sam-solo-deploy rluckom$ kubectl -n rluckom create -f k8s/opendj/opendj-deployment.yaml 
deployment.apps "opendj-deployment" created
Error from server (AlreadyExists): error when creating "k8s/opendj/opendj-deployment.yaml": persistentvolumeclaims "opendj-log-volume" already exists
Error from server (AlreadyExists): error when creating "k8s/opendj/opendj-deployment.yaml": persistentvolumeclaims "opendj-data-volume" already exists
```

## Verify that opendj comes up correctly and that the entry added in #2 is present.

Run the search command

```
wm462-ad4:sam-solo-deploy rluckom$ ldapsearch -LLL -H ldap://35.225.88.216:389 -D "cn=Directory Manager" -w <secret-pass> | grep chowder
dn: cn=chowder-head,ou=people,dc=dsde-dev,dc=broadinstitute,dc=org
mail: chowder-head
sn: chowder-head
cn: chowder-head
```

# Persistent Data Backup / Restore

Test

1. deploy OpenDJ - See previous
2. Add an arbitrary record - see previous
3. Tear down the opendj deployment -  see previous
4. Back up the volume
```bash
gcloud compute --project=broad-dsde-dev disks list | grep rluckom
gcloud compute --project=broad-dsde-dev disks snapshot --zone us-central1-a opendj101-data-disk-rluckom
# Probably a way to name this but...
gcloud compute --project=broad-dsde-dev snapshots list | grep opendj101-data-disk-rluckom
```
5. Delete the volume
```
./teardown-sam.sh rluckom
# Wait until no pvcs
kubectl -n rluckom get pvc
```

Persistent Volumes stick areound for some reason:

```bash
wm462-ad4:sam-solo-deploy rluckom$ kubectl -n rluckom get pv 
NAME                                       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS     CLAIM                                           STORAGECLASS   REASON    AGE
persistent-opendj-data-volume-rluckom      200G       RWO            Retain           Released   rluckom/persistent-opendj-data-volume-rluckom                            23m
pvc-1ffd9b65-40f3-11e9-9cc5-42010a800149   55Gi       RWO            Delete           Bound      gpolumbo/opendj-log-volume                      standard                 4d
pvc-2004c67f-40f3-11e9-9cc5-42010a800149   16Gi       RWO            Delete           Bound      gpolumbo/opendj-data-volume                     standard                 4d
pvc-75d82c42-442c-11e9-9666-42010a8000f5   55Gi       RWO            Retain           Released   rluckom/opendj-log-volume                       protect                  23m
```

Delete them

```bash
kubectl -n rluckom delete pv pvc-75d82c42-442c-11e9-9666-42010a8000f5
kubectl -n rluckom delete pv persistent-opendj-data-volume-rluckom
```

Wait for deletion

```bash
wm462-ad4:sam-solo-deploy rluckom$ kubectl -n rluckom get pv
NAME                                       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS    CLAIM                         STORAGECLASS   REASON    AGE
pvc-1ffd9b65-40f3-11e9-9cc5-42010a800149   55Gi       RWO            Delete           Bound     gpolumbo/opendj-log-volume    standard                 4d
pvc-2004c67f-40f3-11e9-9cc5-42010a800149   16Gi       RWO            Delete           Bound     gpolumbo/opendj-data-volume   standard                 4d
```

Delete the disk

```bash
gcloud compute --project=broad-dsde-dev disks delete --zone us-central1-a opendj101-data-disk-rluckom
```

Create a new disk from the snapshot

```bash
gcloud compute --project=broad-dsde-dev disks create --zone us-central1-a opendj101-data-disk-rluckom --size 200G --source-snapshot=ol4crx252q4m --type=pd-ssd
```

6. Restore a volume from the backup

Nothing k8s to do here--disk exists from the restore, should work

7. Create a new opendj deployment using the restored volume

```bash
./deploy-a-sam.sh rluckom
```

8. Verify that opendj comes up correctly and that the entry added in #2 is present.

```
# should have persistent-opendj-data-volume-rluckom claim
kubectl -n rluckom get pvc

# should have persistent-opendj-data-volume-rluckom
kubectl -n rluckom get pv

# should show in use by k8s
gcloud compute --project=broad-dsde-dev disks describe --zone us-central1-a opendj101-data-disk-rluckom

# get service
kubectl -n rluckom get svc

# moment of truth
ldapsearch -LLL -H ldap://35.202.100.182 -D "cn=Directory Manager" -w <secret-pass> | grep chowder
```

Works. Remember to reconcile  the disk swap in terraform:

```bash
./terraform.sh state rm google_compute_disk.k8s-opendj-100-data
./terraform.sh import google_compute_disk.k8s-opendj-100-data opendj101-data-disk-rluckom
```

# Persistent Storage Design

Add a disk to TF for OpenDJ in each environment. In the OpenDJ Deployment yaml, when the
namespace is one of `dev`, `alpha`, `staging`, `prod`, `perf`, set the PersistentVolumeClaim
to try to use that specific disk.

1. Do I need to manually make a PersistentVolume?

Yes. The `gcePersistentDisk` on the spec specifies the disk to use:

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-demo
spec:
  storageClassName: ""
  capacity:
    storage: 50G
  accessModes:
    - ReadWriteOnce
  gcePersistentDisk:
    pdName: pd-name
    fsType: ext4
```

Then set the PersistentVolumeClaim to use the PersistentVolume:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pv-claim-demo
spec:
  # It's necessary to specify "" as the storageClassName
  # so that the default storage class won't be used, see
  # https://kubernetes.io/docs/concepts/storage/persistent-volumes/#class-1
  storageClassName: ""
  volumeName: pv-demo
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 50G
```

These things can be made part of the yaml-rendering process.

2. What happens if someone else tries to use that disk while I'm using it? How do I restrict its use?

For that to happen, someone would need to specify the specific PersistentVolumeClaim in their
yaml. So it's not super likely, which is good. But it could still happen.

If it _does_ happen, the Deployment's request for the PersistentVolumeClaim
will get denied because the PersistentVolumeClaim is ReadWriteOnce, and it will
be bound to openDJ. If it happens _while_ we are migrating OpenDJ, the interloper
deployment will get the PersistentVolumeClaim and we'll have a problem. This is the
same as a situation in the current environment where we have OpenDJ shut down
for maintenance and someone attaches the data disk to a new instance.
