# Building init container image

In current directory,

* Build the image
```
docker build -t "us.gcr.io/broad-dsp-gcr-public/hamm-cost-updater-config:<git-hash>" .
```
* Push the image ro GCR
```
docker push us.gcr.io/broad-dsp-gcr-public/hamm-cost-updater-config:<git-hash>
```