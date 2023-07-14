# ejabberd chart description

This helm chart has the goal to achieve clustering, however, it can also be run
as a single server.

## General hints

All configuration aspects can be found on ejabberd's [documentation page](https://docs.ejabberd.im/admin/configuration/).

In general, an ejabberd admins should use a **SQL database** in production
instead of the build-in `mnesia` database. Ejabberd supports [these](https://docs.ejabberd.im/admin/configuration/database/)
SQL databases. SQL databases need must have schema [ready to use](https://docs.ejabberd.im/admin/configuration/database/#database-schema).

A SQL database improves the reliability of a cluster, as the `mnesia` database
is prone to be corrupted.

SQL databases can be defined with `values.yaml` in `.Values.sqlDatabase`. Also
check the `.Values.authentication` if you want to store users in SQL databases
as well.

This chart does not support ejabberd's **ACME client**. Instead the chart relies
on the admin to mount valid **TLS certificates** into the container. Those certs
must have the `.pem` format.

For example to create `.pem` certificates with [cert-manager](https://cert-manager.io/docs/usage/certificate/#additional-certificate-output-formats)
you need to enable `featureGates: 'AdditionalCertificateOutputFormats=true'`.
The mounted secret should contain all certificates for all domains defined in
`.Values.hosts`.

Currently the chart does not deploy ejabberd's builtin TURN server correctly. It
may work with using `.Values.hostNetwork` set to `true`, but that is completely
untested and only a potential lead. However, the STUN service works as expected.

For deploying a TURN server, you can check e.g. ejabberd's child project
[eturnal](https://github.com/processone/eturnal) which shares the same code.

## Adding the helm repository

    helm repo add ejabberd https://sando38.github.io/helm-ejabberd

A minimal configuration would be:

```yaml
hosts:
  - example.com
certFiles:
  secretName: "examplecom-tls"
listen:
  c2s:
    port: 5222
    expose: true
    options:
      ip: "::"
      module: ejabberd_c2s
```

Deploy with:

    helm install ejabberd ejabberd/ejabberd -f /path/to/minimal-config.yaml

This will also deploy [reloader](https://github.com/stakater/Reloader) which is
used to renew certificates mounted as secrets into the container. If you don't
want this, you can disable it in `.Values.reloader`.

### Interacting with the statefulset

You can interact with the statefulset by using e.g. `kubectl`:

```shell
kubectl exec statefulset/ejabberd -- ejabberdctl status
kubectl exec statefulset/ejabberd -- ejabberdctl register user example.com pass
kubectl exec statefulset/ejabberd -- ejabberdctl list_cluster
```

### Connecting with an XMPP account

On default, ejabberd's services are exposed with a `LoadBalancer`, hence you can
reach your server on port `5222` under your specified domain in `.Values.hosts`.

Alternatively, use the (public) IP address to connect with your XMPP client and
the corresponding user account. If you use `NodePort` you need to connect with
the exposed nodeport, which may be defined in `.Values.listen.c2s.nodePort`.

## Configuration items

t.b.d.
