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

### Configure KV secrets engine

1. Enable the database secrets engine:

    ```shell
    vault secrets enable kv
    ```

2. Write a secret into kv:

    ```shell
    vault kv put kv/sam password=secret
    ```


### Create kv-password policy

```shell
vault policy write kv-password kv-password-policy.hcl
```

### Create vault token for Boundary credential store
A Vault token is needed to access the Boundary credential store that will be configured when setting up Boundary.

It's very important that the token is:

- periodic
- orphan
- renewable

Boundary may not be able to broker credentials unless the Vault token has these properties.

```shell
export VAULT_BOUNDARY_TOKEN=$(vault token create -no-default-policy=true -policy="boundary-controller" -policy="kv-password" -orphan=true -period=20m -renewable=true -field token)
```
<!-- export $VAULT_BOUNDARY_TOKEN=s.C8B3Rv5WspggAZxfuEmA9EZD -->

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

<!-- export BOUNDARY_TOKEN=at_k98QtyD9ur_s125vnXMfegqWkketB8nvborryMt8gfvqcMsqKVJUmpJQ6tEzWA7quUAztMmSGzeGbJK8k6wTHx2fnDvjuFpgkjbfdcZT78x4ERkdtQTAJo1DMUoTi7AnfNcc -->

### Configure Database Target

1. Create target for user sam

    ```sh
    export SAM_TARGET_ID=$(boundary targets create tcp -scope-id "p_1234567890" -default-port=16001 -session-connection-limit=-1 -name "Sam User" -format json | jq -r .item.id)
    ```

    <!-- export SAM_TARGET_ID=ttcp_EGg5tVugWI -->

2. Add host set to both

    ```shell
    boundary targets add-host-sets -host-set=hsst_1234567890 -id=$SAM_TARGET_ID
    ```

### Create Vault Credential Store

```shell
export CS_ID=$(boundary credential-stores create vault -scope-id "p_1234567890" -vault-address "http://127.0.0.1:8200" -vault-token ${VAULT_BOUNDARY_TOKEN} -format json | jq -r .item.id)
```
<!-- export CS_ID=csvlt_dU735xJJer -->


### Create Credential Libraries
Vault credential libraries are the Boundary resource that maps to Vault secrets engines. A single credential store may have multiple types of credential libraries. For example, Vault credential store might include separate credential libraries corresponding to each of the Vault secret engine backends.

A credential library:

- is a Boundary resource
- belongs to one and only one credential store
- can be associated with zero or more targets
- can contain zero or more credentials
- is deleted when the credential store it belongs to is deleted


1. Create library for sam credentials

    ```shell
    export SAM_CRED_LIB_ID=$(boundary credential-libraries create vault -credential-store-id ${CS_ID} -vault-path "kv/sam" -name "sam user" -format json | jq -r .item.id)
    ```

    <!-- export SAM_CRED_LIB_ID=clvlt_OuRukEolWb -->

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

1. Sam target

    ```shell
    boundary targets add-credential-libraries -id=$SAM_TARGET_ID -application-credential-library=$SAM_CRED_LIB_ID
    ```

## Use Boundary to connect via RDP

Sam target

    ```shell
    boundary connect postgres -target-id ttcp_bXHPxBS0k2 -dbname northwind
    ```
