# Hamm deployment

For more information about k8s setup, check out https://github.com/broadinstitute/dsp-k8s-deploy

* Run `git submodule update` to pull submodule
* Create your namespace: `./dsp-k8s-deploy/deploy-namespace.sh <your_namespace>`
* Deploy your application: `./dsp-k8s-deploy/application-deploy.sh <your_namespace>`

# Troubleshooting
* Make sure you delete `k8s/hamm/rendered` folder if you rename `yaml` files under `k8s/hamm/`