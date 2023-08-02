# ejabberd chart description

The chart's main focus is to achieve clustering in kubernetes, however, it may
be used to run a single server w/o any downsides as well.

## General hints

All configuration aspects can be found on ejabberd's [documentation page](https://docs.ejabberd.im/admin/configuration/).

### Persistence and database

In general, ejabberd admins should use a **SQL database** in production instead
of the build-in `mnesia` database. Ejabberd supports [these](https://docs.ejabberd.im/admin/configuration/database/)
SQL databases. SQL databases need a schema [ready to use](https://docs.ejabberd.im/admin/configuration/database/#database-schema) before the first ejabberd start.

A SQL database improves the reliability of a cluster, as the builtin `mnesia`
database is not reliable enough for data persistence, except for testing.

SQL databases can be defined within `values.yaml` in `.Values.sqlDatabase`. Also
check the `.Values.authentication` if you want to store users in SQL databases
as well.

### Domain TLS certificates and ACME client

This chart does not support ejabberd's **ACME client**. Instead the chart relies
on the admin to mount valid **TLS certificates** into the container. Those certs
must have the `.pem` format.

For example to create `.pem` certificates with [cert-manager](https://cert-manager.io/docs/usage/certificate/#additional-certificate-output-formats)
you need to enable `featureGates: 'AdditionalCertificateOutputFormats=true'`.

To use a sidecar for watching TLS certificate secrets, enable the sidecar in
`.Values.certFiles.sideCar.enabled`. This will make sure, that cert renewals are
automatically injected into ejabberd's runtime process.

**Important**: If you use the sidecar, the kubernetes TLS certificate secrets
are expected to have an annotation and label:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: secretName
  labels:
    helm-ejabberd/watcher: "true"
  annotations:
    k8s-sidecar-target-directory: "certs/secretName"
```

The `secretName` in the annotation must be identical to the secret name(s)
which is(are) referenced in `.Values.certFiles.secretName`. Also they must be in
the same namespace as the helm chart.

If you use cert-manager, use the [secretTemplate](https://cert-manager.io/docs/usage/certificate/#creating-certificate-resources) for specifying the annotation and label.

### STUN/TURN

Currently the chart does not deploy ejabberd's builtin TURN server correctly.
A solution for that is in progress. It may work with using `.Values.hostNetwork`
set to `true`, but that is completely untested. However, the STUN service works
as expected.

For deploying a standalone TURN server, you can check e.g. ejabberd's child
project [eturnal](https://github.com/processone/eturnal) which shares the same
code.

## Adding the helm repository

    helm repo add ejabberd https://sando38.github.io/helm-ejabberd

A minimal configuration would be:

```yaml
hosts:
  - example.com
certFiles:
  secretName:
    - examplecom-secret
```

Deploy with:

    helm install ejabberd ejabberd/ejabberd -f /path/to/minimal-config.yaml

**Note:**

ejabberd's HTTP listener is deployed as well, however, currently no default
[request_handler](https://docs.ejabberd.im/admin/configuration/listen-options/#request-handlers)
is configured. Therefore, please configure them in `.Values.listen.https.options`
to use the HTTP service.

### Interacting with the statefulset

You can interact with the statefulset by using e.g. `kubectl`:

```shell
kubectl exec sts/ejabberd -- ejabberdctl status
kubectl exec sts/ejabberd -- ejabberdctl register user example.com pass
kubectl exec sts/ejabberd -- ejabberdctl list_cluster
```

### Connecting with an XMPP account

On default, ejabberd's services are exposed with a `LoadBalancer`, hence you can
reach your server on port `5222` under your specified domain in `.Values.hosts`.

Alternatively, use the (public) IP address to connect with your XMPP client and
the corresponding user account. If you use `NodePort` you need to connect with
the exposed nodeport, which may be defined in `.Values.listen.c2s.nodePort`.

## Configuration items

t.b.d.
