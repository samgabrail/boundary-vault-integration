# Boundary and Vault Integration Quickstart

This directory contains an example deployment of Boundary using docker-compose and Terraform. The lab environment is meant to accompany the Hashicorp Learn [Boundary Vault integration quickstart tutorial](https://learn.hashicorp.com/tutorials/boundary/vault-quickstart).

In this example, a demo postgres database target is deployed. A dev Vault server is then configured using the database secrets engine and policies allowing Boundary to request credentials for two roles, a DBA and an "analyst". Boundary is then run in dev mode, and the DBA and analyst targets are configured using a credential store that contains credential libraries for both targets. This enables credential brokering via Vault, which is demonstrated using the `boundary connect postgres` command.

1. Setup PostgreSQL Northwind demo database
2. Setup Vault
3. Setup Boundary
4. Use Boundary to connect to the Northwind demo database

## Setup PostgreSQL Northwind demo database


```shell
export PG_DB="northwind"
export PG_URL="postgres://postgres:secret@localhost:16001/${PG_DB}?sslmode=disable"
docker run -d -e POSTGRES_PASSWORD=secret -e POSTGRES_DB="${PG_DB}" --name ${PG_DB} -p 16001:5432 postgres
psql -d $PG_URL -f northwind-database.sql
psql -d $PG_URL -f northwind-roles.sql
```

## Setup Vault

### Run Vault in dev mode

```shell
export VAULT_ADDR="http://127.0.0.1:8200"; export VAULT_TOKEN="groot"
vault server -dev -dev-root-token-id=${VAULT_TOKEN} -dev-listen-address=0.0.0.0:8200
```

### Create boundary-controller policy

```shell
vault policy write boundary-controller boundary-controller-policy.hcl
```

### Configure database secrets engine

1. Enable the database secrets engine:

    ```shell
    vault secrets enable database
    ```

2. Configure Vault with the proper plugin and connection information:

    ```shell
    vault write database/config/northwind \
         plugin_name=postgresql-database-plugin \
         connection_url="postgresql://{{username}}:{{password}}@localhost:16001/postgres?sslmode=disable" \
         allowed_roles=dba,analyst \
         username="vault" \
         password="vault-password"
    ```

3. Create the DBA role that creates credentials with `dba.sql.hcl`:

    ```shell
    vault write database/roles/dba \
          db_name=northwind \
          creation_statements=@dba.sql.hcl \
          default_ttl=3m \
          max_ttl=60m
    ```

    Request DBA credentials from Vault to confirm:

    ```shell
    vault read database/creds/dba
    ```

4. Create the analyst role that creates credentials with `analyst.sql.hcl`:

    ```shell
    vault write database/roles/analyst \
          db_name=northwind \
          creation_statements=@analyst.sql.hcl \
          default_ttl=3m \
          max_ttl=60m
    ```

    Request analyst credentials from Vault to confirm:

    ```shell
    vault read database/creds/analyst
    ```

### Create northwind-database policy

```shell
vault policy write northwind-database northwind-database-policy.hcl
```

### Create vault token for Boundary credential store
A Vault token is needed to access the Boundary credential store that will be configured when setting up Boundary.

It's very important that the token is:

- periodic
- orphan
- renewable

Boundary may not be able to broker credentials unless the Vault token has these properties.

```shell
export VAULT_BOUNDARY_TOKEN=$(vault token create -no-default-policy=true -policy="boundary-controller" -policy="northwind-database" -orphan=true -period=20m -renewable=true -field token)
```
echo $VAULT_BOUNDARY_TOKE=s.k3enbuUGutM6T22dyZYuTZDA

## Setup Boundary

### Run Boundary in dev mode

```shell
boundary dev -cluster-listen-address=0.0.0.0 -api-listen-address=0.0.0.0
```

### Authenticate to Boundary

```shell
boundary authenticate password \
  -auth-method-id=ampw_1234567890 \
  -login-name=admin \
  -password=password -keyring-type=none
```
boundary token: 
```sh
export BOUNDARY_TOKEN=at_k98QtyD9ur_s125vnXMfegqWkketB8nvborryMt8gfvqcMsqKVJUmpJQ6tEzWA7quUAztMmSGzeGbJK8k6wTHx2fnDvjuFpgkjbfdcZT78x4ERkdtQTAJo1DMUoTi7AnfNcc
```
### Configure Database Target

1. Create target for analyst

    ```sh
    export ANALYST_TARGET_ID=$(boundary targets create tcp -scope-id "p_1234567890" -default-port=16001 -session-connection-limit=-1 -name "Northwind Analyst Database" -format json | jq .item.id)
    ```

    export ANALYST_TARGET_ID=ttcp_bXHPxBS0k2

2. Create target for DBA

    ```sh
    export DBA_TARGET_ID=$(boundary targets create tcp -scope-id "p_1234567890" -default-port=16001 -session-connection-limit=-1 -name "Northwind DBA Database" -format json | jq .item.id)
    ```

    export DBA_TARGET_ID=ttcp_x7l6TnF8lx

3. Add host set to both

    ```shell
    boundary targets add-host-sets -host-set=hsst_1234567890 -id=ANALYST_TARGET_ID
    boundary targets add-host-sets -host-set=hsst_1234567890 -id=DBA_TARGET_ID
    ```

### Test Connection to Database
Verify that Boundary can connect to the database target directly, without having a credential brokered from Vault. This is to ensure the target container is accessible to Boundary before attempting to broker credentials via Vault.

```shell
boundary connect postgres -target-id $ANALYST_TARGET_ID -username postgres
```

Password is `secret`.

### Create Vault Credential Store

```shell
export CS_ID=$(boundary credential-stores create vault -scope-id "p_1234567890" -vault-address "http://127.0.0.1:8200" -vault-token ${VAULT_BOUNDARY_TOKEN} -format json | jq -r .item.id)
```
export CS_ID=csvlt_0cnJmLY9Nh


### Create Credential Libraries
Vault credential libraries are the Boundary resource that maps to Vault secrets engines. A single credential store may have multiple types of credential libraries. For example, Vault credential store might include separate credential libraries corresponding to each of the Vault secret engine backends.

A credential library:

- is a Boundary resource
- belongs to one and only one credential store
- can be associated with zero or more targets
- can contain zero or more credentials
- is deleted when the credential store it belongs to is deleted

While there is only a single database target, two separate credential libraries should be created for the DBA and analyst roles within the credential store.

The DBA credential library is responsible for brokering credentials at the database/creds/dba vault path, while the analyst credential library brokers credentials at database/creds/analyst. Using two credential libraries allows for separation of privileges, and enables distinct lifecycle management for the different database roles.

1. Create library for analyst credentials

    ```shell
    export ANALYST_CRED_LIB_ID=$(boundary credential-libraries create vault -credential-store-id ${CS_ID} -vault-path "database/creds/analyst" -name "northwind analyst" -format json | jq -r .item.id)
    ```

    export $ANALYST_CRED_LIB_ID=clvlt_WgSQnuAwdI

2. Create library for DBA credentials

    ```shell
    export DBA_CRED_LIB_ID=$(boundary credential-libraries create vault -credential-store-id ${CS_ID} -vault-path "database/creds/dba" -name "northwind dba" -format json | jq -r .item.id)
    ```

    export $DBA_CRED_LIB_ID=clvlt_Zz68zQB5kr

### Add Credential Libraries to Targets

A credential is a data structure containing one or more secrets that binds an identity to a set of permissions or capabilities. Static credential and dynamic credential are two additional base types derived from the credential base type.

A credential:

- may be a Boundary resource
- belongs to one and only one credential store
- can be associated with zero or more targets directly if it is a resource
- can be associated with zero or more libraries directly if it is a resource
- is deleted when the credential store or credential library it belongs to is deleted

A target can have multiple credentials or credential libraries associated with it:

- one for the connection from a user to a worker (ingress)
- one for the connection from a worker to an endpoint (egress)
- multiple for application credentials (like username and password)

Application credentials are returned to the user from the controller. Ingress and egress credentials are only given to a worker from a controller, and users never have direct access to them.

1. Analyst target

    ```shell
    boundary targets add-credential-libraries -id=$ANALYST_TARGET_ID -application-credential-library=$ANALYST_CRED_LIB_ID
    ```

2. DBA target

    ```shell
    boundary targets add-credential-libraries -id=$DBA_TARGET_ID -application-credential-library=$DBA_CRED_LIB_ID
    ```
## Use Boundary to connect to the Northwind demo database

1. Analyst target

    ```shell
    boundary connect postgres -target-id ttcp_bXHPxBS0k2 -dbname northwind
    ```

2. DBA target
    ```sh
    boundary connect postgres -target-id ttcp_x7l6TnF8lx -dbname northwind
    ```