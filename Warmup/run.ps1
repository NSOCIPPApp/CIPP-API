# CIPP warmup trigger — runs when a new instance is added, BEFORE it receives traffic.
# Goal: pay the "first call" tax here instead of on a real user's first dashboard load.
param($WarmupContext)

$ErrorActionPreference = 'SilentlyContinue'

# 1. Preload Graph/KeyVault authentication (SAM creds -> Graph token cache).
try { Get-CIPPAuthentication | Out-Null } catch {}

# 2. Warm the storage/table data path (AzBobbyTables assembly + connection).
try {
    $KA = Get-CippTable -tablename 'CippKeepAlive'
    $null = Get-CippAzDataTableEntity @KA -Filter "PartitionKey eq 'Ping'"
} catch {}

# 3. Warm the cached tenant read — the most common dashboard code path.
try { $null = Get-Tenants } catch {}

# 4. Warm the actual HTTP endpoint dispatch path. The dashboard's initial load fires ~13
# distinct Invoke-<Endpoint> functions in parallel; each pays its own PowerShell command
# resolution/JIT cost on first use, independent of the module import in profile.ps1.
# These Invoke-* functions return an [HttpResponseContext] rather than calling
# Push-OutputBinding themselves, so they're safe to call directly here (no function
# binding context is required) - we only care about triggering resolution/JIT, so the
# result is discarded and any error is non-fatal.
$WarmupRequest = [PSCustomObject]@{
    Headers = [PSCustomObject]@{ 'x-ms-client-principal-name' = 'warmup' }
    Params  = [PSCustomObject]@{}
    Query   = [PSCustomObject]@{}
    Body    = $null
}
$EndpointsToWarm = @(
    'Invoke-Me',
    'Invoke-ListFeatureFlags',
    'Invoke-GetCippAlerts',
    'Invoke-ListUserSettings',
    'Invoke-ListSnoozedAlerts',
    'Invoke-ListTestReports',
    'Invoke-ListAlertResults',
    'Invoke-ListAvailableTests'
)
foreach ($Endpoint in $EndpointsToWarm) {
    try {
        if (Get-Command -Name $Endpoint -Module CIPPHTTP -ErrorAction SilentlyContinue) {
            $null = & $Endpoint -Request $WarmupRequest -TriggerMetadata $null
        }
    } catch {}
}

Write-Information 'Warmup: auth + storage + tenant cache + HTTP dispatch path preloaded.'
