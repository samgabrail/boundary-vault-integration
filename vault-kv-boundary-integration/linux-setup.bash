## Setup Vault

### Run Vault in dev mode
export VAULT_ADDR="http://127.0.0.1:8200"; export VAULT_TOKEN="groot"
vault server -dev -dev-root-token-id=${VAULT_TOKEN} -dev-listen-address=0.0.0.0:8200

### Create boundary-controller policy
vault policy write boundary-controller boundary-controller-policy.hcl

### Configure KV secrets engine
# 1. Enable the database secrets engine:
    vault secrets enable -version=2 kv
# 2. Write a secret into kv:
    vault kv put kv/sam password=secret username=Administrator

### Create kv-password policy
vault policy write kv-password kv-password-policy.hcl

### Create vault token for Boundary credential store
export VAULT_BOUNDARY_TOKEN=$(vault token create -no-default-policy=true -policy="boundary-controller" -policy="kv-password" -orphan=true -period=20m -renewable=true -field token)

## Setup Boundary

### Run Boundary in dev mode
boundary dev -api-listen-address=0.0.0.0 -cluster-listen-address=0.0.0.0 -proxy-listen-address=0.0.0.0 -worker-public-address=192.168.1.90

### Authenticate to Boundary
boundary authenticate password -auth-method-id=ampw_1234567890 -login-name=admin -password=password -keyring-type=none

### Configure Boundary Catalogs, Host-sets, Hosts, and Targets
# 1. Create a host catalog
    export WIN_CATALOG_ID=$(boundary host-catalogs create static -name Windows_Catalog -description "Catalog for Windows Servers" -scope-id "p_1234567890" -format json | jq -r .item.id)

# 2. Add host
    export WINDOWS_HOST=$(boundary hosts create static -name backend_windows_server -description "Windows Server 192.168.1.7" -address="192.168.1.7" -host-catalog-id $WIN_CATALOG_ID -format json | jq -r .item.id)

# 3. Create a new host set
    export WINDOWS_HOST_SET=$(boundary host-sets create static -name backend_windows_servers -description "Host set for backend Windows servers" -host-catalog-id $WIN_CATALOG_ID -format json | jq -r .item.id)

# 4. Add the host to the host set
    boundary host-sets add-hosts -id $WINDOWS_HOST_SET -host $WINDOWS_HOST

# 5. Create target for user sam
    export WIN_TARGET_ID=$(boundary targets create tcp -scope-id "p_1234567890" -default-port=3389 -session-connection-limit=2 -name "Backend RDP" -description "Backend RDP target" -format json | jq -r .item.id)

# 6. Add host set
    boundary targets add-host-sets -host-set=$WINDOWS_HOST_SET -id=$WIN_TARGET_ID

### Create Vault Credential Store
export CS_ID=$(boundary credential-stores create vault -scope-id "p_1234567890" -vault-address "http://127.0.0.1:8200" -vault-token ${VAULT_BOUNDARY_TOKEN} -format json | jq -r .item.id)

### Create Credential Libraries
# Create library for sam credentials
export SAM_CRED_LIB_ID=$(boundary credential-libraries create vault -credential-store-id ${CS_ID} -vault-path "kv/data/sam" -name "sam user" -format json | jq -r .item.id)

### Add Credential Libraries to Targets
# 1. WINDOWS_HOST target
boundary targets add-credential-libraries -id=$WIN_TARGET_ID -application-credential-library=$SAM_CRED_LIB_ID

## Use Boundary to connect via RDP

# 1. Connect to Boundary via the Windows or Mac desktop app and click `connect` next to the target host. You can then reveal the username and password.

# 2. Copy the Proxy URL which looks like this: 127.0.0.1:53913 and run the following command:

mstsc /v:127.0.0.1:53537

## Use Boundary to connect via RDP
# Below assumes you have Boundary installed which is not usually the case. A better workflow is to use cmd or powershell with mstsc /v:127.0.0.1:53537 example below
    # export BOUNDARY_ADDR=http://gitlab-runner.home:9200
    # export BOUNDARY_TOKEN=at_WUO0cfnkDf_s13B9yLMG1dKyY8NPNW21dBo7mDaedBjNgDoffFMWkSjTzNq9tfxGvjVAWavhtdR8GdH6CCFvHtsS4UKs1pajMju6cYGPndiMvbjTWfBg1LXESFWVE
    # boundary connect rdp -target-id $WIN_TARGET_ID -host-id $WINDOWS_HOST