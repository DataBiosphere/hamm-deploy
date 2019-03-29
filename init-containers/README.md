# Init Containers

Each sub-folder of this directory holds configuration files for the 
[Kubernetes Init Containers](https://kubernetes.io/docs/concepts/workloads/pods/init-containers/) used by the DSP 
Analysis Platform services. 

With the exception of Opendj, all services contain template configuration files for the 
[OIDC Proxy](https://github.com/broadinstitute/openidc-proxy) in addition to the template configuration files for the 
service itself.

In addition to template configuration files, each service also has a `Dockerfile` that is used to construct the Init 
Container Docker image for that service.

# Building init container image
* Build the image
```
docker build -t "us.gcr.io/broad-dsp-gcr-public/hamm-cost-updater-config:<git-hash>" init-containers/hamm/
```
* Push the image to GCR
```
docker push us.gcr.io/broad-dsp-gcr-public/hamm-cost-updater-config:<git-hash>
```