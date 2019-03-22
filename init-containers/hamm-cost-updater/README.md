# Building init container image

* Build the image
```
docker build -t "us.gcr.io/broad-dsp-gcr-public/hamm-cost-updater-config:<7-digit-git-hash>" .
```
* Push the image ro GCR
```
docker push us.gcr.io/broad-dsp-gcr-public/hamm-cost-updater-config:<7-digit-git-hash>
```