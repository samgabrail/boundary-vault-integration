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
    vault secrets enable -version=2 kv
    ```

2. Write a secret into kv:

    ```shell
    vault kv put kv/sam password=secret username=Administrator
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
boundary dev -api-listen-address=0.0.0.0 -cluster-listen-address=0.0.0.0 -proxy-listen-address=0.0.0.0 -worker-public-address=192.168.1.90
```

### Authenticate to Boundary

```shell
boundary authenticate password -auth-method-id=ampw_1234567890 -login-name=admin -password=password -keyring-type=none
```
boundary token: 

<!-- export BOUNDARY_TOKEN=at_WUO0cfnkDf_s13B9yLMG1dKyY8NPNW21dBo7mDaedBjNgDoffFMWkSjTzNq9tfxGvjVAWavhtdR8GdH6CCFvHtsS4UKs1pajMju6cYGPndiMvbjTWfBg1LXESFWVE -->

### Configure Boundary Catalogs, Host-sets, Hosts, and Targets

1. Create a host catalog

    ```sh
    export WIN_CATALOG_ID=$(boundary host-catalogs create static -name Windows_Catalog -description "Catalog for Windows Servers" -scope-id "p_1234567890" -format json | jq -r .item.id)
    ```

2. Add host

    ```sh
    export WINDOWS_HOST=$(boundary hosts create static -name backend_windows_server -description "Windows Server 192.168.1.7" -address="192.168.1.7" -host-catalog-id $WIN_CATALOG_ID -format json | jq -r .item.id)
    ```

3. Create a new host set

    ```sh
    export WINDOWS_HOST_SET=$(boundary host-sets create static -name backend_windows_servers -description "Host set for backend Windows servers" -host-catalog-id $WIN_CATALOG_ID -format json | jq -r .item.id)
    ```

4. Add the host to the host set

    ```sh
    boundary host-sets add-hosts -id $WINDOWS_HOST_SET -host $WINDOWS_HOST
    ```

5. Create target for user sam

    ```sh
    export WIN_TARGET_ID=$(boundary targets create tcp -scope-id "p_1234567890" -default-port=3389 -session-connection-limit=2 -name "Backend RDP" -description "Backend RDP target" -format json | jq -r .item.id)
    ```

6. Add host set

    ```sh
    boundary targets add-host-sets -host-set=$WINDOWS_HOST_SET -id=$WIN_TARGET_ID
    ```

### Create Vault Credential Store

```shell
export CS_ID=$(boundary credential-stores create vault -scope-id "p_1234567890" -vault-address "http://127.0.0.1:8200" -vault-token ${VAULT_BOUNDARY_TOKEN} -format json | jq -r .item.id)
```

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
    export SAM_CRED_LIB_ID=$(boundary credential-libraries create vault -credential-store-id ${CS_ID} -vault-path "kv/data/sam" -name "sam user" -format json | jq -r .item.id)
    ```

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

1. WINDOWS_HOST target

    ```shell
    boundary targets add-credential-libraries -id=$WIN_TARGET_ID -application-credential-library=$SAM_CRED_LIB_ID
    ```

## Use Boundary to connect via RDP

1. Connect to Boundary via the Windows or Mac desktop app and click `connect` next to the target host. You can then reveal the username and password.

2. Copy the Proxy URL which looks like this: 127.0.0.1:53913 and run the following command:

    ```shell
    mstsc /v:127.0.0.1:53537
    ```

<!-- ## Use Boundary to connect via RDP
# Below assumes you have Boundary installed which is not usually the case. A better workflow is to use cmd or powershell with mstsc /v:127.0.0.1:53537 example below
    # export BOUNDARY_ADDR=http://gitlab-runner.home:9200
    # export BOUNDARY_TOKEN=at_WUO0cfnkDf_s13B9yLMG1dKyY8NPNW21dBo7mDaedBjNgDoffFMWkSjTzNq9tfxGvjVAWavhtdR8GdH6CCFvHtsS4UKs1pajMju6cYGPndiMvbjTWfBg1LXESFWVE
    # boundary connect rdp -target-id $WIN_TARGET_ID -host-id $WINDOWS_HOST -->

<!-- Windows Powershell example:
PS C:\Users\Sam> $Env:BOUNDARY_TOKEN = "at_WUO0cfnkDf_s13B9yLMG1dKyY8NPNW21dBo7mDaedBjNgDoffFMWkSjTzNq9tfxGvjVAWavhtdR8GdH6CCFvHtsS4UKs1pajMju6cYGPndiMvbjTWfBg1LXESFWVE"
PS C:\Users\Sam> $Env:BOUNDARY_ADDR = "http://gitlab-runner.home:9200"
PS C:\Users\Sam> boundary connect rdp -target-id ttcp_pn0bqwD64X -host-id hst_HyfpgpZctf -->
