# Route53 Updater

**pure/route53-update** is small Docker image with simple Bash script used to update A records in AWS Route53 hoste zone.
Container should run only on AWS EC2 instances because it retrieves public IP address of host from AWS EC2 meta-data.

### What `pure/route53-updater` do:

- get `public IP` address from AWS EC2 Instance meta-data
- get A record  for hostname `test.example.com` from AWS Route53
- check if record mismatch public IP
- update Route53 record for hostname `test.example.com` with `public IP`

### Configration

`pure/route53-updater` need two environment variables:

- `ROUTE53_ZONE_ID` - AWS Route53 hosted zone Id
- `ROUTE53_HOSTNAME` - desired hostname

### Why use `pure/route53-updater`

There are several apps to manage AWS Rute53 resources in Kubernetes:

- Kubernetes [ExternalDNS](https://github.com/kubernetes-incubator/external-dns)
- Kops' [DNS Controller](https://github.com/kubernetes/kops/tree/master/dns-controller)
- Zalando's [Mate](https://github.com/zalando-incubator/mate)
- Molecule Software's [route53-kubernetes](https://github.com/wearemolecule/route53-kubernetes)

...but they all uses Kubernetes [Service](https://kubernetes.io/docs/concepts/services-networking/service/) and [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)
resources to manage DNS records. And main logic of these controllers is to set A (or ALIAS) record in AWS Route53 zone for AWS ELB
that was created for some Service.

AWS ELB is great service but sometimes it's bloody expensive. Traffic via ELB is $0.008 per Gb but traffic via EC2 Instance with public IP is $0.00

It could be critical for services with very high traffic, as example - private docker registry running in Kubernetes environment.
Workaround could be next:

- run Kubernetes pod with option `.spec.HostNetwork: true` over node with public IP
- set A record in AWS Route53 for your service with IP address of node where Pod was started

### Example for private docker registry

Kubernetes manifest:

```
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: docker-registry
  namespace: kube-system
  labels:
    app: docker-registry
spec:
  revisionHistoryLimit: 1
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: docker-registry
    spec:
      hostNetwork: true
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: kubernetes.io/role
                operator: NotIn
                values:
                - master
      initContainers:
      - name: docker-registry-dns
        image: pure/route53-updater
        env:
        - name: ROUTE53_ZONE_ID
          value: "R53ZONEIDHERE"
        - name: ROUTE53_HOSTNAME
          value: "registry.example.com"
      containers:
      - name: docker-registry
        image: registry:2
        ports:
        - containerPort: 443
        env:
        - name: REGISTRY_LOG_ACCESSLOG_DISABLED
          value: "true"
        - name: REGISTRY_LOG_LEVEL
          value: "error"
        - name: REGISTRY_STORAGE_DELETE_ENABLED
          value: "true"
        - name: REGISTRY_STORAGE
          value: "s3"
        - name: REGISTRY_STORAGE_S3_ACCESSKEY
          valueFrom:
            secretKeyRef:
              name: docker-registry-aws
              key: aws_access_key
        - name: REGISTRY_STORAGE_S3_SECRETKEY
          valueFrom:
            secretKeyRef:
              name: docker-registry-aws
              key: aws_secret_key
        - name: REGISTRY_STORAGE_S3_REGION
          value: "eu-west-1"
        - name: REGISTRY_STORAGE_S3_BUCKET
          value: "my-private-docker-registry"
        - name: REGISTRY_AUTH
          value: "htpasswd"
        - name: REGISTRY_AUTH_HTPASSWD_REALM
          value: "Registry Realm"
        - name: REGISTRY_AUTH_HTPASSWD_PATH
          value: "/auth/authdata"
        - name: REGISTRY_HTTP_ADDR
          value: "0.0.0.0:443"
        - name: REGISTRY_HTTP_TLS_LETSENCRYPT_CACHEFILE
          value: "/le/cache"
        - name: REGISTRY_HTTP_TLS_LETSENCRYPT_EMAIL
          value: "abuse@example.com"
        volumeMounts:
        - name: docker-registry-auth
          mountPath: /auth
        - name: docker-registry-le
          mountPath: /le
      volumes:
      - name: docker-registry-auth
        secret:
          secretName: docker-registry-auth
      - name: docker-registry-le
        emptyDir: {}
```

### IAM Policy to use `pure/route53-updater`

You should specify AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY as environment variables for `pure/route53-updater` but better
configure IAM Instance profile for Kubernetes nodes with netx IAM Policy:

```
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "route53:ListResourceRecordSets",
        "route53:ChangeResourceRecordSets"
      ],
      "Resource": [
        "arn:aws:route53:::hostedzone/*"
      ]
    }
  ]
}
```

or more strictly specify Zone_id in arn as example `"arn:aws:route53:::hostedzone/SOMEZONEID"`
