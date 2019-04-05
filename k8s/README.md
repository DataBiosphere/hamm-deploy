k8s directory provides k8s manifest files for hamm-api-server and hamm-cost-updater services.

hamm-api-server and hamm-cost-updater are deployed as separate deployment as they have different scalability requirements.

They share same ingress file which is defined in hamm-api-server.