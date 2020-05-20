# Master Node Replacement

This set of scripts need to run from the same folder
All of the windows nodes (Archive Master and workers) need to have the same Administrative credentials (username and password)

## Instructions

Deploy a new NetGovern 6.4 VM (Windows 2019) (assign IP address, New VM name, etc)
From the new VM, run the powershell script SingleTenantReplaceMaster.ps1 or MultiTenantReplaceMaster.ps1 depending on your cluster architecture.

Manual steps: [CLICK HERE](./ManualSteps.md)

### Multi Tenant example

```powershell
.\MultiTenantReplaceMaster.ps1 `
    -windowsAdminUser Administrator `
    -windowsAdminPassword 'The Password' `
    -oldMaster 2.2.2.2 `
    -remoteProvider 3.3.3.3 `
    -tenantId tenant01
```

### Single Tenant example

```powershell
.\SingleTenantReplaceMaster.ps1 `
    -windowsAdminUser Administrator `
    -windowsAdminPassword 'The Password' `
    -netmailPassword 'AnotherPassword'
```

