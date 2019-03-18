# Hamm deployment

Before following these instructions, set up kubectl according to the instructions
in the [next section](#interacting-with-kubernetes). Remember to add your cluster-admin
rolebinding, or else role creation will fail in the setup script.

If you would like to start up your own Sam instance with its own Opendj

    ./deploy-a-sam.sh my-namespace

This will setup Sam and Opendj Deployments and corresponding Services to make them reachable.  They will be isolated in 
the Kubernetes namespace, `my-namespace`, which you can set to be whatever value you want.  **NOTE:** If you specify a
Namespace that already exists, it will possibly overwrite/redeploy existing Kubernetes objects.

If you are done using your Sam instance and would like to tear it down:

    ./teardown-sam.sh my-namespace
    
**WARNING:** This script will _**delete**_ the specified Namespace and all Kubernetes Objects within it.  This process
is permanent and you need to take caution to ensure you are deleting the correct Namespace.

# Interacting with Kubernetes

This is one way of deploying infrastructure to Kubernetes. 

As a demo, it uses infrastructure deployed by [terraform-firecloud](https://github.com/broadinstitute/terraform-firecloud)

```
Google project: broad-dsde-dev
Kubernetes cluster: firecloud-k8s
```

To set up your local kubectl to interact with this cluster, you should 
be able to just run 

```
gcloud container get-server-config --zone us-central1 ## not sure if needed
# Like instance SSH, you can find this command in the console by clicking on the "Connect" icon and copying the command
# Make sure you're using your @broadinstitute.org account
gcloud container clusters get-credentials firecloud-k8s --zone us-central1-a --project broad-dsde-dev
```

If that doesn't work, you can follow the [official instructions](https://cloud.google.com/kubernetes-engine/docs/how-to/cluster-access-for-kubectl)
but remember that you may want to add `--project` flags instead of configuring a default
gcloud project.

Once that is set up, you should see the entry for the sam-solo cluster when you run 

```
kubectl config get-contexts
```

Mine shows

```
CURRENT   NAME                                                CLUSTER                                             AUTHINFO                                            NAMESPACE
*         gke_broad-dsde-dev_us-central1-a_firecloud-k8s   gke_broad-dsde-dev_us-central1-a_firecloud-k8s   gke_broad-dsde-dev_us-central1-a_firecloud-k8s   
```

You should get in the habit of explicitly selecting the context you mean to use:

```
kubectl config use-context gke_broad-dsde-dev_us-central1-a_firecloud-k8s
```

We are using the `dev` namespace inside the cluster. Make sure you see it, or you may be
running against the wrong cluster:

```
wm462-ad4:init-containers rluckom$ kubectl get namespaces
NAME          STATUS    AGE
default       Active    2d
dev           Active    9h
kube-public   Active    2d
kube-system   Active    2d
```

Give yourself the `cluster-admin` role
```
kubectl create clusterrolebinding <your-username>-cluster-admin-binding --clusterrole cluster-admin --user <your username>@broadinstitute.org
```

You should specify the `--namespace` parameter whenever you run a command so that you are viewing and
interacting with resources in the correct place. A few commands that have been useful for me:

```
# Submit the deployment yaml file to  create the deployment
kubectl --namespace=dev create -f ./opendj-deployment.yaml

# list pods running, if any
kubectl --namespace=dev get pods

# get pod logs to see what went wrong
kubectl --namespace=dev logs opendj-deployment-64f6d5c58f-xw49h

# Delete the deployment so I can try again after fixing something
kubectl --namespace=dev delete deployment opendj-deployment

# Specifically get the init-container  logs so I can see what went wrong rendering
kubectl --namespace=dev logs opendj-deployment-85fd97d785-hwg7h -c opendj-config

# "docker exec" equivalent to "log in" to a running pod
kubectl --namespace=dev exec -it <pod name> -- /bin/bash
```

## PodSecurityPolicies, Roles, RoleBindings, and Service Accounts

### PodSecurityPolicies

PodSecurityPolicies control the conditions under which pods can be scheduled to run
within the cluster. If you have submitted a deployment or other resource and none of the pods
are starting up at all, or if you see errors like `pods "sam-deployment-7c785cb64d-" is forbidden: unable to validate against any pod security policy: []`, you probably need to make sure your resource
can use a pod security policy. An example of a policy is in this repo at `k8s/cluster/security-policy.yaml.ctmpl`.
That policy comes from [the docs](https://kubernetes.io/docs/concepts/policy/pod-security-policy/) and it allows
those who can use it to run non-privileged containers with access to all volumes. The PodSecurityPolicies are global
over the whole cluster; you can't create one in your namespace.

### RBAC - 30K'

Once a pod security policy has been created, you need to allow your deployment to use it.
This involves three parts:

1. A ServiceAccount to act as an identity for your service
2. A Role granting access to the PodSecurityPolicy
3. A RoleBinding allowing the ServiceAccount from #1 to assume the permissions given to #2

### Service Account

All you need to create a service account is a name:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: sam-sa
```

### Role

A Role controls access to many different kinds of k8s resources, including 
PodSecurityPolicies and secrets:

```yaml
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: use-pod-security-policy-role
rules:
- apiGroups: ['policy']
  resources: ['podsecuritypolicies']
  verbs: ["use"]
  resourceNames:
    - pod-running-policy 
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get"]
  resourceNames:
    - token
```

In order to create Roles, you need the `cluster-admin` role for your user. To get it, run

```
kubectl create clusterrolebinding <your-username>-cluster-admin-binding --clusterrole cluster-admin --user <your username>@broadinstitute.org
```

See the [docs](https://kubernetes.io/docs/reference/access-authn-authz/rbac/) for more details on
roles.

### RoleBinding

The RoleBinding document is a pretty straightforward mapping of the ServiceAccount subject
to the Role. If you're copying an existing one, remember to change the metadata name _and_ the service account
name to avoid conflicts.

```yaml
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: sam-sa-use-pod-security-policy
subjects:
- kind: ServiceAccount
  name: sam-sa
roleRef:
  kind: Role
  name: use-pod-security-policy-role
  apiGroup: rbac.authorization.k8s.io
```

## Persistent Storage in Kubernetes

Some applications, like OpenDJ and elasticsearch, need storage that persists
beyond the lifetime of any particular pod. We are targeting two specific use cases
to support for such applications:

1. It should be possible to deploy a new version of a data-dependent application without losing or corrupting existing data
2. It should be possible to back up a persistent volume and restore the volume from the backup and have the application use the restored volume.

### Keeping Data Across Application Redeploys

Test

1. deploy OpenDJ
2. Add an arbitrary record
3. Tear down the opendj deployment
4. Create a new opendj deployment using the same volume
5. Verify that opendj comes up correctly and that the entry added in #2 is present.

### Persistent Data Backup / Restore

Test

1. deploy OpenDJ
2. Add an arbitrary record
3. Tear down the opendj deployment
4. Back up  the volume
5. Delete the volume
6. Restore a volume from the backup
7. Create a new opendj deployment using the restored volume
8. Verify that opendj comes up correctly and that the entry added in #2 is present.

### Storage Classes, Reclamation Settings, Storage Object in Use Protection

Persistent Volumes are how storage resources are represented in k8s. Persistent Volume Claims
are requests for storage resources by a pod. A pod uses a PersistentVolumeClaim as an
attached drive; the k8s master provisions Persistent Volumes to meet PersistentVolumeClaim
requests. Storage Classes represent a defined type or class opf Persistent Volumes.

The pattern is this: When we create a new service that needs persistent data, one of the
things we create is a PersistentVolumeClaim representing that data. When the PersistentVolumeClaim
is created, k8s looks at the `storageClassName` (or lack thereof) provided in the PersistentVolumeClaim
spec, and provisions a PersistentVolume with the characteristics of that StorageClass. The most
important of those characteristics are the [`reclaimPolicy`](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#reclaiming) 
and the availability of ["Storage Object in Use Protection"](https://kubernetes.io/docs/tasks/administer-cluster/storage-object-in-use-protection/).

We've created a Storage Class called `protect` that uses the `Retain` reclaimPolicy
and also has Storage Object In Use Protection. The `Retain` reclaimPolicy means
that when a PersistentVolumeClaim is deleted, the PersistentVolume backing it is
retained until being [manually cleaned up](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#retain).
The Storage Object In Use Protection means that PersistentVolumeClaims cannot
be deleted while they are in use by at least one pod.

### Persistent Volume Snapshots

Kubernetes support for [snapshots](https://kubernetes.io/docs/concepts/storage/volume-snapshots/) is
not yet part of the drivers GKE includes, and the disclaimers on the [driver github](https://github.com/kubernetes-sigs/gcp-compute-persistent-disk-csi-driver)
are a little too strident for even me to think it's a good idea to start using them right now.
But they look pretty sweet, when the time comes. It sounds like it might be in google beta in
gke master 1.13 (we're on 1.12.5 now).

Instead, we need to rely on ordinary Google Volume snapshot APIs. PersistentVolumes in k8s
are just ordinary GCE Compute disks, so the same snapshot tools are available for them.
The basic pattern we're going to have to follow for now is snapshotting the GCE disks underlying
our PersistentVolumes, and if we ever need to restore from a snapshot, we'll need to create a
GCE Persistent disk from the snapshot, then use the [instructions](https://cloud.google.com/kubernetes-engine/docs/how-to/persistent-volumes/preexisting-pd)
to create a PersistentVolume from the disk. More details on the precise deployment
process for snapshotted volumes is in the [persistent-volume-tests.md](/persistent-volume-tests.md).
Note that the `protect` Storage class is _not_ applied to PersistentVolumes or PersistentVolumeClaims
using terraform-supplied volumes--since k8s does not manage the volume, it does not try
to clean them up.

# The Init-Container Shuffle

This version of the deployment process uses init containers. The startup process
for a service is:

1. Pull an init container image
2. Start the init comtainer image with a small number of env vars--usually the environment, project, and a vault token
3. The init container (which was built with the config templates and a render script) starts up, uses the provided vars to run its render script and renders the templates to a kubernetes volume
4. The init container exits
5. Pull the app container
6. The app container starts up, and can mount paths from the volume populates by the init container
7. The app runs

# Adding a new service

To add a new service, you need to create an init-container image with the 
service's configs, push your init container to GCR, and create a `deployment.yaml`
for your service deployment.

## Creating an init-container image

The init container should be based on [docker-configurator-base](https://github.com/broadinstitute/docker-configurator-base)
and its docker file should copy all of your configs into the `/configs` 
directory on the image and set the `CMD` to either the default (recommended)
or an override if you want to do something different:

```
FROM broadinstitute/configurator-base:1.0.2

COPY opendj /configs/opendj/
COPY logger /configs/logger/

CMD /usr/local/bin/cp-config.sh
```

The default [`cp-config.sh`](https://github.com/broadinstitute/docker-configurator-base/blob/master/cp-config.sh) script
uses a process very similar to the one used to render configs in the [firecloud-develop](https://github.com/broadinstitute/firecloud-develop)
repo. It looks in  the `/configs` directory and subdirectories and copies the contents into a `target` directory
(which happens  to be a mounted volume  when used correctly in kubernetes). Any `.ctmpl` files
are rendered and renamed; any .b64 or .p12 files are base64-decoded and moved to files without the
extension.

Another special file that can be included along with the configs is the `.env` or `.env.ctmpl`
file. This file is rendered or copied  the same as any of the other files, but by convention
it is used by the app container's startup script to set the environment variables for the
app container. An example `opendj.env.ctmpl`:

```bash
export DIR_MANAGER_PW_FILE=/var/secrets/opendj/dirmanager.pw
export SECRET_VOLUME=/var/secrets/opendj
export BASE_DN="dc=dsde-{{env "ENVIRONMENT"}},dc=broadinstitute,dc=org"
export OPENDJ_JAVA_ARGS="-d64 -server -Xms2g -Xmx5200m"
```

To use the `env` file, you'll need to include a special `entrypoint.sh` file
that sources it and then runs your app container's ordinary entrypoint. Note
that this file is included with your configs and is rendered or copied by your
init container, but it should be _executed_ by your app container as the `command`
specified in your deployment:

```bash
#!/bin/bash

# This script is intended to override the default 
# startup script built into the docker image.  The reason for it is so
# that an env file can be used to load the environment instead of
# relying on configmaps and env vars defined in kubernetes

# env file should be a shell export var compatible

# location of env file to load
OPENDJ_ENVFILE=${OPENDJ_ENVFILE:-"/etc/opendj.env"}

# If env file exists then load environment from file
if [ -r "${OPENDJ_ENVFILE}" ]
then
   # load shell exports into env
   .  "${OPENDJ_ENVFILE}"
fi

# exec startup as normal
exec /opt/opendj/run.sh
```

Note that this script relies on the `env` file being mounted into the container
at `/etc/opendj.env `, and that it specifies the application-container-specific
start script in the `exec` line at the end.

## What about the OpenID Proxy?

The pattern for the OpenID proxy container is the same as the rest in principle, but
because the OpenID container is based on the [Phusion Baseimage](https://github.com/phusion/baseimage-docker),
some of the details are a little different. The unique aspect of the Phusion
docker image is that it runs multiple processes similar to what you'd find
in an Ubuntu VM, rather than just a single pid-1 as you'd find in most docker containers.

Unlike the other containers, you won't find a distinct `CMD` or `ENTRYPOINT` in the docker
hierarchy of the OpenID image. Instead, like a regular Ubuntu system, the Phusion image
has a kind of init system that starts up individual services when it runs. This makes setting
environment variables via an `entrypoint.sh` tricky--if there's no single entrypoint to the
container, there is nothing to override. 

The solution is to notice that there's still only one process in the OpenID proxy container
that we actually care about--the apache server responsible for authentication and delivering
traffic to  the app container. All we care about is that _apache_ has the  correct environment
variables so that it can parameterize its `site.conf` correctly and do its job. This is accomplished
using an [override script](https://github.com/broadinstitute/openidc-baseimage#override-script). 
If you put environment variable assignments in a file at `/etc/apache2/override.sh`, those variables
will be set in apache's environment when it runs. For example, firecloud-ui uses an [override.sh](https://github.com/broadinstitute/firecloud-ui/blob/develop/src/docker/override.sh)
and mounts it in its [Dockerfile](https://github.com/broadinstitute/firecloud-ui/blob/develop/Dockerfile#L13),
which is also ultimately based on a Phusion image.

## Creating a deployment

For an example deployment file see the [opendj deployment](https://github.com/broadinstitute/sam-solo-deploy/blob/master/k8s/opendj-deployment.yaml) yaml.

Things to note:

1. The environment variables in the init container and volume mounts should stay the same unless you're deploying to a non-"dev" environment or know what you're doing
2. The `/opt/opendj/entrypoint.sh` that is the [command](https://github.com/broadinstitute/sam-solo-deploy/blob/master/k8s/opendj-deployment.yaml#L40) of the opendj container is the same as the one in the [config directory](sam-solo-deploy/init-containers/config_files/opendj/opendj/entrypoint.sh)
3. The `appdir` volume is the one on which the init container renders the configs, [unless you change it](https://github.com/broadinstitute/sam-solo-deploy/blob/master/k8s/opendj-deployment.yaml#L83)
4. The `subpath` in the app container volume mounts is the path to the file relative to the [`configs`](https://github.com/broadinstitute/sam-solo-deploy/blob/master/init-containers/opendj/Dockerfile#L3)  directory in the init container. the `mountPath` is the path where the file is mounted within the app container.
5. You can specify [persistent volume claims](https://github.com/broadinstitute/sam-solo-deploy/blob/master/k8s/opendj-deployment.yaml#L100) in the deployment and [mount them in the containers](https://github.com/broadinstitute/sam-solo-deploy/blob/master/init-containers/k8s/opendj-deployment.yaml#L94).
6. Separate yaml documents must be separated by `---` lines.

# Standing up a service that exists in firecloud-develop

Your service will need:

1. A directory in the `config_files` directory including everything needed for the config container for the service's pod.
2. For your openidc proxy, if applicable
   - create a `proxy` directory under the directory in #1.
   - Copy the `site.conf` from the base-configs directory for your service in firecloud-develop
     - you'll need to set the `RUN_CONTEXT`, `HOST_TAG` maybe `DNS_DOMAIN` env var on your deployment init container to `fiab`
   - Copy the `proxy-compose.yaml.ctmpl` and / or `docker-compose.yaml.ctmpl` from the `fiab/configs` directory for your service in firecloud-develop
     - use the environment variables defined for the proxy in the compose files to construct a `env-override.ctmpl` file that will contain the environment variables for your proxy mount it at `/etc/apache2/env-override`
     - need to set up DNS & an ingress rule giving the service the right name, need to decide what the name is -- for now it's `<service>.sam-solo-<k8s-namespace>.dsde-dev.broadinstitute.org`
     - the `DNS_DOMAIN` needs to be the hostname of the opendj service, I *think* that means just `opendj`
     - Create one-line ctmpl files for the `server.crt`, `server.key`, and `ca-bundle.crt`
     - copy in the tcell config and `mod_security_logging.conf ` from the common configs in fc
     - Add an `override.sh` that sources the env and uses the standard method of starting up the proxy container (found in the proxy container repo, or as overridden in compose file in fc-develop)
     - $ldapDc turns out to be `dc=dsde-{{env "ENVIRONMENT"}},dc=broadinstitute,dc=org`
     - $secret_source turns out to be env "ENVIRONMENT"
     - remember to mount the `server.crt`, `server.key`, `site.conf`, env file, `entrypoint.sh` and `ca-bundle.crt` in the deployment, and set the entrypoint as the command in the deployment.
3. For your app container
   - create an appropriately-named directory under the directory in #1.
   - copy your application's conf file and any other ctmpls it needs from the `base-configs` directory in firecloud-develop
   - For anything mounted into the container that uses `copy_secret_from_path` in the manifest, create a one-line ctmpl file teo pull it from vault.
   - not sure how to handle newrelic yet (don't have 'copy from google bucket` as a pattern yet) -- for now probably best to remove the `-javaagent` flag from the JAVA_ARGS & hope for the best
   - remember to mount all the stuff in the deployment when you make it.
   - using the `docker-compose` and `proxy-compose` files from the fiab run-context, put together an env ctmpl file that supplies the right variables
   - an `entrypoint.sh` for your app that correctly sources the env and starts your app container.
4. TODO sqlProxy container if applicable.
5. A `deployment.yaml` in the `k8s` directory.
   - appdir for your rendered  configs
   - Log dir? maybe not necessary?
   - init container specifying the right hash of your container and the environment vars it needs (`ENVIRONMENT`. `RUN_CONTEXT=fiab`, others?)
   - containers for your pod
     - correct mounts for all of your configs, proxy & otherwise
     - commands specify the erntrypoint files from the configs
     - linked with the correct intra-pod hostnames (TODO, should be similar to docker-compose?)
6. A `service.yaml` in the `k8s` directory.
7. An `ingress.yaml` in the `k8s` directory, if it is to be a publicly-accessible load-balanced HTTP/HTTPS service.

## Debugging issues with init containers

The following commands are examples of how to perform common tasks. You may have to modify object, 
namespace, or file names in them to suit your use case.

```
# Specifically get the init-container  logs so I can see what went wrong rendering
kubectl --namespace=dev logs opendj-deployment-85fd97d785-hwg7h -c opendj-config

# Test the validity of the vault token used to render the configs:
docker run --rm -it  -e VAULT_TOKEN=$(kubectl --namespace=dev get secret token -o  json | jq -r .data.token | base64 -D) broadinstitute/dsde-toolbox vault token-lookup

# To set a vault token, write the token to a local file, then run
kubectl --namespace=dev create secret generic token --from-file=./token
```

## Setting up an Ingress and DNS Record for your service

A k8s Ingress is very similar to a load balancer in our existing infrastructure.
Its job is to provide a static public IP that routes to a k8s service, and abstract
away the detail of what pods and instances are running the service itself. Setting
up an ingress requires:

1. A Static Public IP and DNS record provisioned for the service in terraform
2. An SSL certificate / key pair available as a secret in the cluster
3. An HTTP (not HTTPS) `readinessProbe` defined on the `deployment.yaml` for the service pods, and made accessible through the proxy
4. A `service.yaml` mapping ports exposed on the pods defined in the `deployment.yaml` to ports exposed on the service.
5. An `ingress.yaml` mapping ports exposed on the service to ports to be exposed on the public static IP for the service.

### Getting a Public Static IP and DNS record

We manage infrastructure using terraform in the [terraform-sam-solo](https://github.com/broadinstitute/terraform-sam-solo) repo.
Follow the instructions to set up the repo.

Add a public IP and DNS record for your service, noting the name you assign the public IP--you'll
need to reference it later in your `ingress.yaml`.

```
resource "google_compute_global_address" "sam-sam-solo-pub-ip" {
  provider            = "google.sam-solo"
  name = "sam-solo-100-pub-ip"
}

resource "google_dns_record_set" "sam-solo-100-sam-dns" {
  provider = "google.sam-solo"
  managed_zone = "${data.google_dns_managed_zone.dsde_zone.name}"
  name         = "${format("sam-solo.%s", data.google_dns_managed_zone.dsde_zone.dns_name)}"
  type         = "A"
  ttl          = "${var.dns_ttl}"
  rrdatas      = [ "${google_compute_global_address.sam-sam-solo-pub-ip.address}" ]
}
```

Run the terraform plan and terraform apply commands in the repo to add your
IP address and DNS record. Once you're happy that they're working, please prioritize
making a PR and getting it merged, because if anyone else who _doesn't_ have your
changes runs terraform apply, they will delete your resources. The infrastructure
created by terraform is a single shared resource, so it's important to commit frequently
and not leave your branches open too long to avoid inconvenieencing others.

### Saving your SSL Certificate and Key as a k8s secret

*You probably don't have to do this.* Before continuing, run

```
kubectl --namespace=dev get secrets
```

If you see a secret called `wildcard.dsde-<env>.broadinstitute.org`, then
someone probably added the certificate already and you should just use it. You
can verify this by running:

```
wm462-ad4:workspace rluckom$ kubectl --namespace=dev get secret wildcard.dsde-dev.broadinstitute.org -o json | jq -r '.data["tls.crt"]' | base64 -D | head -n 1
-----BEGIN CERTIFICATE-----
wm462-ad4:workspace rluckom$ kubectl --namespace=dev get secret wildcard.dsde-dev.broadinstitute.org -o json | jq -r '.data["tls.key"]' | base64 -D | head -n 1
-----BEGIN RSA PRIVATE KEY-----
```

If for some reason you need to add your own certificate, you'll need to save the certificate
and key in files named `tls.crt` (note no "e") and `tls.key` in the current directory, then run

```
kubectl --namespace=dev create secret generic <certificate name> --from-file=tls.key --from-file=tls.crt
```

Note the name you give your certificate--you'll need to use it in your `ingress.yaml`. Delete the
local certificate and key files.

### Setting up the `readinessProbe` on your deployment

The `readinessProbe` is analogous to a load balancer health check, but
more finicky to set up. In your deploymeent yaml, identify the container that
should accept traffic from outside (usually the openID proxy). You'll need 
to add an HTTP (not HTTPS) `readinessProbe` to this container spec:

```
          readinessProbe:
            httpGet:
              path: /status
              port: 80
            initialDelaySeconds: 20
            periodSeconds: 80
            timeoutSeconds: 10
```

The `readinessProbe` line should be indented the same amount as the `ports`
and `volumeMounts` lines. You can set the path to whatever is correct for your service.

You will likely also need to modify your `site.conf` to allow HTTP access to your
status endpoint and not redirect to HTTPS. For example, in Sam's proxy `site.conf`, I
had to replace the existing `<VirtualHost _default_:${HTTPD_PORT}>` block (configuring access through port 80)
with the following:

```
<VirtualHost _default_:${HTTPD_PORT}>
    ServerAdmin ${SERVER_ADMIN}
    ServerName ${SERVER_NAME}
    ErrorLog /dev/stdout
    CustomLog "/dev/stdout" combined
    RewriteEngine On
    RewriteCond  %{HTTP:X-Forwarded-Proto} !https
    RewriteCond %{REQUEST_URI}  !^/(version|status) [NC]
    RewriteRule (.*) https://${SERVER_NAME}%{REQUEST_URI}

    DocumentRoot /app

    <Directory "/app">
        AllowOverride All
        Options -Indexes

        Order allow,deny
        Allow from all
    </Directory>

    ErrorLog /dev/stdout
    CustomLog "/dev/stdout" combined

    <Location ${PROXY_PATH}>
        Header unset Access-Control-Allow-Origin
        Header always set Access-Control-Allow-Origin "*"
        Header unset Access-Control-Allow-Headers
        Header always set Access-Control-Allow-Headers "authorization,content-type,accept,origin,x-app-id"
        Header unset Access-Control-Allow-Methods
        Header always set Access-Control-Allow-Methods "GET,POST,PUT,PATCH,DELETE,OPTIONS,HEAD"
        Header unset Access-Control-Max-Age
        Header always set Access-Control-Max-Age 1728000

        RewriteEngine On
        RewriteCond %{REQUEST_METHOD} OPTIONS
        RewriteRule ^(.*)$ $1 [R=204,L]

        <Limit OPTIONS>
            Require all granted
        </Limit>

        ${AUTH_TYPE}
        ${AUTH_LDAP_URL}
        ${AUTH_LDAP_GROUP_ATTR}
        ${AUTH_LDAP_BIND_DN}
        ${AUTH_LDAP_BIND_PASSWORD}
        ${AUTH_REQUIRE}

        <Limit OPTIONS>
            Require all granted
        </Limit>

        ProxyPass ${PROXY_URL}
        ProxyPassReverse ${PROXY_URL}

        ${FILTER}
    </Location>
</VirtualHost>
```

At a first approximation, it's probably pretty close to what you'll need
to do for any non-cromwell, non-ui firecloud service.

### Making your Service Yaml

The k8s [service](https://kubernetes.io/docs/concepts/services-networking/service/) represents
an _internally_-routable pod or set of pods providing some kind of API. In order for other containers
within your k8s cluster to talk to your pods,  you need a service. Once you have a service, you can 
expose it _outside_ the container using an ingress.

The service yaml is a pretty simple document:

```
apiVersion: v1
kind: Service
metadata:
   name: sam-service
spec:
  ports:
    - name: http
      protocol: TCP
      port: 80
      targetPort: 80
    - name: https
      protocol: TCP
      port: 443
      targetPort: 443
  type: NodePort
  selector:
    service: sam
    environment: dev
    project: sam-solo
```

The important things to note here are:

1. The name of the service is the internal hostname at which the service can be reached. I.e., the service above can be reached from within the cluster with `curl https://sam-service/status`.
2. The individual `port` numbers correspond to ports on the service
3. The `targetPort` numbers coorespond to the ports on the individual pods that will recieve traffic set to the `port` defined in the same stanza. These _must_ be defined in the deployment yaml for the relevant containers.

### Making your Ingress YAML

The ingress defines your k8s load-balancer equivalent. It is also a pretty simple document.

```
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: sam-ingress
  annotations:
    kubernetes.io/ingress.global-static-ip-name: "sam-solo-100-pub-ip"
spec:
  tls:
    - secretName: wildcard.dsde-dev.broadinstitute.org
  backend:
    serviceName: sam-service
    servicePort: http
  rules:
  - host: "sam-solo.dsde-dev.broadinstitute.org"
    http:
      paths:
      - backend:
          serviceName: sam-service
          servicePort: http
```

Things to note:


1. The `kubernetes.io/ingress.global-static-ip-name` annotation value should be the name of the static IP you made in terraform
2. The TLS `secretName`  should be the name of the certificate secret you made or identified
3. The `host` is the way the load balancer will identify itself to incoming connections
4. The backend should point to  your service port.


# Other Stuff Of Varying Utility

```
DSP Public Docker repo project: broad-dsp-gcr-public
Public repo domain: us.gcr.io
Private repo domain: gcr.io
Image name for opendj configs: us.gcr.io/broad-dsp-gcr-public/sam-solo-opendj-config
```

You should be able to pull and push after simply running:

```
gcloud auth configure-docker
```

As always, if that doesn't work see the [official docs](https://cloud.google.com/container-registry/docs/quickstart)


A few commands that have been useful for me:

```
# build the opendj config container (manually set the tag to an appropriategit commit)
docker build -t us.gcr.io/broad-dsp-gcr-public/sam-solo-opendj-config:576f63d .

# Push the opendj container (use the tag you  built)
docker push us.gcr.io/broad-dsp-gcr-public/sam-solo-opendj-config:576f63d
```

When you push a new config container, remember to switch the [tag in the deployment file](https://github.com/broadinstitute/sam-solo-deploy/blob/576f63de7314482ea98988bb8ef764f3a7393800/k8s/opendj-deployment.yaml#L26)
before recreating your deployment with the yaml.

Running consul-template locally (uses your own token so not exactly the same)

```
# must run from the directory with the ctmpl, assumes your token is in ~/.vault-token
docker run --rm -it -v "$PWD":/working -e VAULT_TOKEN=$(cat ~/.vault-token) -e ENVIRONMENT=dev broadinstitute/dsde-toolbox /usr/local/bin/consul-template -once -config=/etc/consul-template/config/config.json -template=/working/dirmanager.pw.ctmpl:/working/target/dirmanager.pw
```

This will create a `target` directory in the current directory with the rendered file, or else display the vault error

# Port Forwarding a k8s service to another host

You can use `kubectl` to port forward a k8s service to localhost:

```bash
kubectl --namespace=dev port-forward svc/opendj-service 1247:389
```

See the [docs](https://kubernetes.io/docs/tasks/access-application-cluster/port-forward-access-application-cluster/#forward-a-local-port-to-a-port-on-the-pod) for similar
commands for forwarding deployments, replicasets, and pods. 

# Exposing a Kubernetes Service running on GCE
This is probably relevant only for testing.  The "correct" way to expose one of our Kubernetes services to the public
internet is using an Ingress object.  However, for testing, it may be handing to 
[expose your service](https://kubernetes.io/docs/tutorials/kubernetes-basics/expose/expose-intro/). 

    kubectl --namespace=dev expose deployment/opendj-deployment --type="NodePort" --port 389
    
After you have exposed a `NodePort` for the Service, if you want to be able to reach it from outside the GCE cluster,
you will need add a Google firewall rule to permit connections to that port from the Broad network:

    gcloud compute --project=broad-dsde-dev firewall-rules create opendj-k8s-test --description="Temporary ingress rule for testing opendj on k8s" --direction=INGRESS --priority=1000 --network=${K8S_CLUSTER_NETWORK} --action=ALLOW --rules=tcp:${NODE_PORT} --source-ranges=${BROAD_IP_RANGES}
    
Where the `K8S_CLUSTER_NETWORK` is the name of the network that your k8s cluster is running on.  `NODE_PORT` is the 
target port specified in `kubectl expose` command or the one that was automatically allocated for you.
`BROAD_IP_RANGES` is a comma separated list of CIDR network ranges that requests need to originate from in order to be 
permitted through the firewall. You can find the list of CIDRs  [in the terraform-firecloud](https://github.com/broadinstitute/terraform-firecloud/blob/309ade38315495cca5677db23972fe8d74e0fe4e/variables.tf#L6) repo.

When you have finished testing your service, disable or delete your firewall rule.  This can be done via the command
line or by logging into the GCP Console.


# Setting up a new Namespace

Kubernetes allows you to virtually isolate your pods in a cluster using namespacing.

1. Create the namespace
    1. Copy the existing `/k8s/common/namespace.yaml.ctmpl` into a new file, like `/k8s/personal-namespace.yaml` and
    replace the `ctmpl` markup with static values.
    1. Change the `name` fields in the `metadata` block  in that file to be whatever name you want for your namespace, for example change it to `foo`
    1. See if the namespace already exists:  
        
        `kubectl get namespaces`
        
    1. Create the namespace if it doesn't already exist: 
    
        `kubectl create -f personal-namespace.yaml`
        
    1. Check that your new namespace exists: 
    
        `kubectl get namespaces`
        
1. Add the Vault token secret for your namespace:
    1. See existing secrets (new namespaces will probably have 1 secret for the Kubernetes service-account-token): 
    
        `kubectl --namespace=foo get secrets`
        
    1. Create the secret in your namespace: 
    
        `kubectl --namespace=gpolumbo create secret generic token --from-literal=token=$(kubectl --namespace=dev get secret token -o  json | jq -r .data.token | base64 -D)`
       
       **NOTE:** We need to find a better way to store/share this secret and keep it up to date.  Just copying the
       secret from another namespace is not going to work.

    1. Ensure that your secret was created: 
    
        `kubectl --namespace=foo get secrets`
        
        1. You can inspect the value of your secret:  
        
            `kubectl --namespace=foo get secret token -o yaml`  
            
            The value of your secret is Base64 encoded, so if you want to decode it, you'll need to pass it through `base64 -D`
1. Create the Opendj Deployment:
    1. Check if what deployments already exist in the namespace:
    
        `kubectl --namespace=foo get deployments`
        
    1. Create the deployment:
    
        `kubectl --namespace=foo create -f opendj-deployment.yaml`
    
    1. Confirm that Opendj is running and handling requests (you will need to update this command with your pod name):
    
        `kubectl --namespace=gpolumbo exec opendj-deployment-564454bc86-q5lkr -c opendj -- ldapsearch -H ldap://localhost -D "cn=Directory Manager" -w $(cat ${DIR_MANAGER_PW_FILE}) -b "ou=people,dc=dsde-dev,dc=broadinstitute,dc=org"`
        
    1. Health check - When Opendj is created, it needs to be loaded with the _Proxy User_.  This is the user that 
    will be used by the OIDC Proxy hosts to bind to ldap and authorize whether users of our services are permitted
    to perform actions in the system.  If the _Proxy User_ is missing, then our services will be inaccessible.  Run 
    the following command to ensure that the _Proxy User_ is in Opendj:
        
        `kubectl --namespace=gpolumbo exec opendj-deployment-564454bc86-q5lkr -c opendj -- ldapsearch -H ldap://localhost -D "cn=Directory Manager" -w $(cat ${DIR_MANAGER_PW_FILE}) -b "cn=proxy-ro,ou=people,dc=dsde-dev,dc=broadinstitute,dc=org"`

1. Create the Opendj Service: 

    `kubectl --namespace=gpolumbo create -f opendj-svc.yaml`
    
    **NOTE:** Check the Kubernetes documentation on Services.  There is some discussion about how Services should be 
    created _before_ you create the pods/containers/Deployment.  

1. Create the Sam Deployment:
    
        `kubectl --namespace=gpolumbo create -f sam-deployment.yaml`
    
    1. Check that Sam is up and responding to the status endpoint:
    
        `kubectl --namespace=gpolumbo exec sam-deployment-76766d9794-ns2rz -c sam-app -- curl localhost:8080/status`
    
1. Create the Sam Service:

    `kubectl --namespace=gpolumbo create -f sam-svc.yaml`
    
1. Check that your Services are up and responding.
    1. Check that the `opendj-service` is reachable from the `sam-app` container:
    
        `kubectl --namespace=gpolumbo exec sam-deployment-76766d9794-ns2rz -c sam-app -- bash -c 'apt-get update && apt-get -y install ldap-utils && ldapsearch -H ldap://opendj-service -D "cn=Directory Manager" -w $(cat ${DIR_MANAGER_PW_FILE}) -b "ou=people,dc=dsde-dev,dc=broadinstitute,dc=org"'`
    
        **NOTE:** Let's update the Sam Docker image to be built with `ldap-utils` already installed maybe?

    1. Check that the `sam-service` is reachable from the Sam `companion` container:
    
        `kubectl --namespace=gpolumbo exec sam-deployment-76766d9794-ns2rz -c companion -- wget -qO- https://sam-service/status`
        
# Readiness and Liveness

Kubernetes documentation on [readiness and liveness](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-probes/)
    
## Opendj
 
* **Readiness** - OpenDJ is considered "ready" when an `ldapsearch` command is able to successfully find the
_proxy user_.  The thinking here was that the _proxy user_ gets loaded into opendj by the startup process towards the end
of the startup.  So if the _proxy user_ is found, then we know that opendj is up and responsive as well as having its
"init" data loaded.  No matter what, if the _proxy user_ is not found, then this opendj instance is not usable or ready 
to use.
* **Liveness** - OpenDJ may crash or become unresponsive.  The liveness check will run the same query as the readiness
check because this will tell us if opendj is non-responsive or timing out.  In addition, the query for the _proxy user_
should be quick and return a relatively small payload in order to avoid the liveness check from adding undo stress to
the system.

## Sam

The readiness/liveness of the Sam Pod/Deployment is contingent on 2 things:

1. The Sam Proxy is running, reachable, and able to communicate with the `sam-app` container.
1. The Sam app is running (and its `/status` endpoint is returning?  It is returning `200`?)

Perhaps a better question is under what conditions do we want Kubernetes to automatically restart Sam for us?

* **Readiness** - 
* **Liveness** - 

# TODOS:

* figure out how the vault token gets to the init container

# Proposed acceptance criteria

* diagram the deployment flow
* diagram the container replacement flow
* diagram the infrastructure lifecycle
* diagram / document how we expect a new developer
  * to work on an existing system
  * to create a new system
  * to migrate a GCE-based system to this model
* identify the security properties we want, and those we have
* identify the maintainability properties we want, and those we have
