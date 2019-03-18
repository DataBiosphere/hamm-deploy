Useful commands:

```
# "docker exec" equivalent
kubectl --namespace=dev exec -it <pod name> -- /bin/bash

# ldapsearch command that works from inside the deployed container
ldapsearch -LLL -H ldap://localhost -D "cn=Directory Manager" -w <pass>

# Forward port 389 from the pod to 6739 on your laptop:
kubectl --namespace=dev port-forward opendj-deployment-5d94b77ffc-4xjrx 6379:389

# Run ldapsearch on your laptop  against the forwarded port:
ldapsearch -LLL -H ldap://localhost:6379 -D "cn=Directory Manager" -w <pass>
```
