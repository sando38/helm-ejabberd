# ejabberd chart description

The chart's main focus is to achieve clustering in kubernetes, however, it may
be used to run a single server w/o any downsides as well.

## General hints

All configuration aspects can be found on ejabberd's [documentation page](https://docs.ejabberd.im/admin/configuration/).

### Elector service to define a leader pod (chart version >= `0.6.0`)

This chart uses an elector service to define an ejabberd leader pod to improve
the robustness of the chart especially in the case of failures, etc. The elector
requires some `RBAC` to create `leases`. The elector may be disabled in
`.Values.elector.enabled`.

### Persistence and database

In general, ejabberd admins should use a **SQL database** in production instead
of the build-in `mnesia` database. Ejabberd supports [these](https://docs.ejabberd.im/admin/configuration/database/)
SQL databases. SQL databases need a schema [ready to use](https://docs.ejabberd.im/admin/configuration/database/#database-schema) before the first ejabberd start.

A SQL database improves the reliability of a cluster, as the builtin `mnesia`
database is not reliable enough for data persistence, except for testing.

SQL databases can be defined within `values.yaml` in `.Values.sqlDatabase`. Also
check the `.Values.authentication` if you want to store users in SQL databases
as well.

#### Use ejabberd's automatic sql migration function

Available since version `23.10` ([beta](https://www.process-one.net/blog/automatic-schema-update-in-ejabberd/)),
ejabberd can perform database migrations itself.

This can be enabled in the `.Values.sqlDatabase.updateSqlSchema`.

#### Use the inbuilt flyway integration to manage the SQL database

New in helm-ejabberd version `0.5.0`.

This feature is experimental. Currently, only `mysql`, `pgsql` and `mssql`
`sql_type`s are supported. Enable it in `.Values.sqlDatabase.flyway.enabled`.

[flyway](https://flywaydb.org/) is a SQL migration tool, which keeps track of
the database schema versions. We use it to manage ejabberd's SQL database, as
ejabberd does not perform SQL migrations. If you start with a clean database,
flyway will also migrate the first schema into the database.

It is also possible to use an existing ejabberd database and integrate it into
this chart. This may also become handy, if one needed to reset a database.

**Caution**: The database must comply exactly to the schemas from the respective
ejabberd version in use. The chart's first supported version is `23.04`.

This means, if you use a `postgresql` database, using ejabberd's new sql schema,
the schema of your database must be exactly like the schema of the respective
version. For `23.04`, it would be:
https://github.com/processone/ejabberd/blob/23.04/sql/pg.new.sql

To use an existing database, state your database ejabberd version in
`.Values.sqlDatabase.flyway.baselineVersion`, the rest will be handled by
`helm-hooks`.

### Domain TLS certificates and ACME client

This chart does not support ejabberd's **ACME client**. Instead the chart relies
on the admin to mount valid **TLS certificates** into the container. Those certs
must have the `.pem` format.

For example to create `.pem` certificates with [cert-manager](https://cert-manager.io/docs/usage/certificate/#additional-certificate-output-formats)
you need to enable `featureGates: 'AdditionalCertificateOutputFormats=true'`.

### SideCar (recommended)

Enable the sidecar in `.Values.certFiles.sideCar.enabled` to use it for watching
TLS certificate k8s secrets and helm-ejabberd related configmaps.

This will make sure, that all changes done in `values.yaml`, which become part
of the `ejabberd.yml` file, as well as cert renewals are automatically injected
into ejabberd's runtime process w/o pod restarts. To provide new configurations
into the running helm release, use the `helm upgrade` command.

**Important**: If you use the sidecar, the kubernetes TLS certificate secrets
are expected to contain this annotation and label:

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

<details><summary>Here is an example cert-manager certificate:</summary>
<p>

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: le-cert-examplecom
  namespace: ejabberd
spec:
  secretName: le-cert-examplecom
  privateKey:
    rotationPolicy: Always
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  commonName: "example.com"
  dnsNames:
  - "example.com"
  - "conference.example.com"
  - "proxy.example.com"
  - "upload.example.com"
  - "vjud.example.com"
  additionalOutputFormats:
  - type: CombinedPEM
  - type: DER
  secretTemplate:
    annotations:
      k8s-sidecar-target-directory: "certs/le-cert-examplecom"
    labels:
      helm-ejabberd/watcher: "true"
```

</p>
</details>

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

To define `Secrets` as environment variables, make use of the introduced feature
of the `EJABBERD_MACRO_*` variables. These will create macros and replace any
placeholder like in the below example:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: sensitive-variables
stringData:
  EJABBERD_MACRO_REDIS_PASSWORD: "red1sUnsecureP4ss"
  EJABBERD_MACRO_SQL_PASSWORD: "ejabberdTest1Pass"
```

And in the `values.yaml` file:

```yaml
redis:
  enabled: true
  config:
    redis_server: redis
    redis_password: REDIS_PASSWORD

sqlDatabase:
  enabled: true
  defaultDb: sql
  config:
    sql_database: ejabberd
    sql_username: ejabberd
    sql_password: SQL_PASSWORD

envFrom:
  - secretRef:
      name: "sensitive-variables"
```

t.b.d.
