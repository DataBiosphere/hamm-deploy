# Ways of exposing access to Kubernetes-resident Opendj


## Load Balancer

Steps to Deploy

1. Create a namespace
2. Deploy the `opendj-deployment.yaml` deployment
3. Deploy the `opendj-public-svc.yaml`
4. run `kubectl --namespace=dev get svc` to see a list of services. Wait until tou see a public IP appear for the `opendj-service`
5. run `ldapsearch -LLL -H ldap://<pub ip> -D "cn=Directory Manager" -w <secret password>` to confirm access to ldap.
6. Disconnect from VPN or internal wifi, run `ldapsearch -LLL -H ldap://<pub ip> -D "cn=Directory Manager" -w <secret password>` again to confirm no access from outside.
