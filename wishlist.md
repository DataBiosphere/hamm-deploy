This file is to collect feature requests / design ideas that aren't 
high enough priority to spend time on right now but which we want to
remember for later.

## Deployment / Infrastructure

### HTTPS Status checks

The only way we've found of getting Google to use a readiness check as an LB
health check is to use HTTP. This is awkward and may force us to terminate HTTPS at the
LB instead of the instance (need further research). the HTTP health checks are annoying
and we should look at ways to fix them.

Alternatively, we can update the OIDC Proxy to allow `http` to `/status` and maybe even `/version`.  

### Secrets

**Vault Token Management** We need a way to distribute vault tokens and secrets where they're needed, as opposed to just copying between namespaces.

### Monitoring

Right now we've foregone New Relic monitoring for Sam--does k8s give us enough that we don't need it?
Should we put it back in?

#### Opendj

**Q:** _What conditions must be satisfied for us to be comfortable routing traffic to opendj?_

**A:** When the following conditions are met:

1. It is responding to `ldap` queries/bindings.
1. Its "init" data is loaded.  Confirm this by running queries for "init" data that is expected to be present, things
like the _proxy user_.  

**Q:** _What conditions must we see in order to want to trigger an automatic restart of the opendj container?_

**A:** ~~When it fails to respond to a basic `ldapsearch` command for any reason, timeout, auth(n/z), etc.~~ For now, we
do not ever want Kubernetes to automatically restart Opendj because we are unsure of the impacts of an Opendj restart.
For now, if we decide to restart Opendj, that decision should be made by a human.

#### Sam

As noted at the top of the [Kubernetes Readiness and Liveness docs](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-probes/):

> A Pod is considered ready when all of its Containers are ready. 

In other words, we should not necessarily have to concern ourselves with _readiness_ checks for each and every container 
in a pod, because if even one container in the pod is not ready, then the entire container will not be considered ready.

##### Sam App

**Q:** _What conditions must be satisfied for us to be comfortable routing traffic to Sam?_

**A:** If the swagger UI returns `200`

**Q:** _What conditions must we see in order to want to trigger an automatic restart of the sam container?_

**A:** If the app itself becomes unresponsive, as indicated by the swagger ui not even being reachable.

##### Sam OIDC Proxy

**Q:** _What conditions must be satisfied for us to be comfortable routing traffic to the Sam OIDC Proxy?_

**A:** If the proxy is able to satisfy the following conditions:

1. It can route requests through to the `sam-app` running in the pod.
1. It is able to successfully bind to Opendj using the _proxy user_ credentials

**Q:** _What conditions must we see in order to want to trigger an automatic restart of the Sam OIDC Proxy?_

**A:** The proxy is no longer able to connect/bind to opendj for any reason.  (Is this right?  Opendj binds might be failing
because the configs have changed and we changed the password or something for the _proxy user_.  Or Opendj might have 
had a hiccup and crashed and is in the process of being restarted, which is fine and should be expected, and this would
not require us to restart the proxy.)

There may not ever be a scenario where we want to automatically restart the proxy.  If Apache is running, then we should
be ok.  If Apache is not able to handle requests properly, that is most likely indicative of config file problems which 
will require developer intervention to resolve and automatically restarting Apache isn't going to fix it.


### Terrafform Resources

It would be nice if non-devops teams could own creating their own non-k8s infrastructure.
So far it seems like the only per-service infrastructure is DNS and global static IP. Can we make
a pattern for that?

This would also mean parameterizing the ingresses and load balancer services to use the provisioned
resources. The way it is now, they all try to use the same ones and whoever gets them first wins.

## Init Container system improvements

### Not needing to build a container every time configs change
The init containers are a compromise between wanting reproducible deployments
(i.e. having an immutable record of which configs were deployed with a given deployment)
and needing a way to version configs and code separately.

Other options for balancing these priorities:

1. Use an init container that pulls configs from a git commit and renders them.
   - **How it solves immutability** The git commit gives immutability
   - **How it allows code and configs to be versioned separately** pushing to git is easier than building a container.


## Collaboration

One purpose of this infrastructure is to enable teams and devs to have their own
environments for testing. We should make an easy, standard way to get such an environment.

### New Service Creation

Is there a way to templatize (or better, consolidate) our service-creation
boilerplate (proxy, etc) so that adding a new service is easy?

## scripts

Make the deployment script clean up rendered directories before running.

The opendj logger volume--is that actually doing anything?

Split out opendj volumes from the deployment yaml--we don't usually want to recreate them.
