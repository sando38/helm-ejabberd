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
```

Deploy with:

    helm install ejabberd ejabberd -f /path/to/minimal-config.yaml

This will also deploy [reloader](https://github.com/stakater/Reloader) which is
used to renew certificates mounted as secrets into the container. If you don't
want this, you can disable it in `.Values.reloader`.


## Configuration items

t.b.d.
