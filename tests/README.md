# RKE2 Provisioning Module Tests

This directory contains Pester tests for the RKE2 Proxmox Provisioning PowerShell modules.

## Prerequisites

### Install Pester

```powershell
# Install Pester (version 5.x)
Install-Module -Name Pester -Force -SkipPublisherCheck -MinimumVersion 5.0
```

### Verify Installation

```powershell
Get-Module -ListAvailable Pester
```

Expected output should show Pester version 5.x or higher.

## Running Tests

### Run All Tests

```powershell
# Navigate to the project root
cd D:\ops\provisioning-projects

# Run all tests
Invoke-Pester -Path .\tests\
```

### Run Specific Test File

```powershell
# Run only the RKE2 provisioning tests
Invoke-Pester -Path .\tests\Rke2-ProxmoxProvisioning.Tests.ps1
```

### Run Tests with Detailed Output

```powershell
# Verbose output
Invoke-Pester -Path .\tests\ -Output Detailed
```

### Run Tests with Code Coverage

```powershell
# Generate code coverage report
$configuration = [PesterConfiguration]::Default
$configuration.Run.Path = '.\tests\'
$configuration.CodeCoverage.Enabled = $true
$configuration.CodeCoverage.Path = '.\Rke2-ProxmoxProvisioning.psm1'
$configuration.CodeCoverage.OutputPath = '.\tests\coverage.xml'

Invoke-Pester -Configuration $configuration
```

## Test Structure

### Test Files

- `Rke2-ProxmoxProvisioning.Tests.ps1` - Unit tests for Phase 1 functions

### Test Organization

Tests are organized using Pester's `Describe`, `Context`, and `It` blocks:

```powershell
Describe "FunctionName" {
    Context "When testing scenario X" {
        It "Should do Y" {
            # Test assertion
        }
    }
}
```

## Mocking

Tests use PowerShell mocking to avoid making real API calls to:
- Kubernetes clusters
- Proxmox servers
- Unifi API

This allows tests to run quickly without external dependencies.

### Example Mock

```powershell
Mock Invoke-K8CommandJson {
    return @{
        items = @(
            @{ metadata = @{ name = "test-node" } }
        )
    }
}
```

## Test Coverage

Current test coverage for Phase 1 functions:

- ✅ Get-PodsOnNode (6 tests)
- ✅ Get-PDBBlockers (4 tests)
- ✅ Get-UnhealthyPods (3 tests)
- ✅ Wait-K8NodeReady (2 tests)
- ✅ Test-EtcdClusterHealth (3 tests)
- ⚠️ Get-ProxmoxStorageCapacity (4 tests + 1 info test - require Proxmox module)
- ✅ Test-ClusterHealth (2 tests)
- ✅ Get-Rke2NodeMachineName (4 tests)
- ✅ Get-PxVmSettings (4 tests)
- ✅ Get-ClusterVmPrefix (1 test)
- ✅ Test-ClusterInfo (2 tests)
- ✅ Test-ClusterConnectionInfo (2 tests)

**Total:** 39 tests (35 unit tests, 4 integration tests)

### Integration Tests

**Proxmox Storage Tests (4 tests + 1 info test):**
- These are integration tests that require the `Corsinvest.ProxmoxVE.Api` module
- Tests automatically skip if module not available
- Cannot be converted to pure unit tests due to complex [PveTicket] type dependencies
- These tests validate integration with the Proxmox API module

To enable these tests:
```powershell
Install-Module -Name Corsinvest.ProxmoxVE.Api
```

**Why keep integration tests?**
- Validate that the function correctly integrates with the Proxmox API
- Document external dependencies required by the function
- Automatically run when the module is available (no code changes needed)

### Functions Not Fully Unit Tested

The following functions are tested through integration tests in the manual testing guide:

- Start-NodeDrainWithMonitoring (requires actual cluster)
- Remove-NodeFromPxRke2Cluster (requires actual cluster and VM)
- Test-ClusterReadyForCycling (requires actual Proxmox and Unifi)
- Get-ClusterCyclingStatus (requires actual cluster)
- Get-DrainBlockersDiagnostics (requires actual cluster)

## CI/CD Integration

### Azure DevOps Pipeline Example

```yaml
trigger:
  branches:
    include:
      - main
  paths:
    include:
      - '*.psm1'
      - 'tests/**'

pool:
  vmImage: 'windows-latest'

steps:
- pwsh: |
    Install-Module -Name Pester -Force -SkipPublisherCheck -MinimumVersion 5.0
  displayName: 'Install Pester'

- pwsh: |
    $configuration = [PesterConfiguration]::Default
    $configuration.Run.Path = './tests/'
    $configuration.Output.Verbosity = 'Detailed'
    $configuration.TestResult.Enabled = $true
    $configuration.TestResult.OutputPath = 'test-results.xml'
    $configuration.CodeCoverage.Enabled = $true
    $configuration.CodeCoverage.Path = './*.psm1'
    $configuration.CodeCoverage.OutputPath = 'coverage.xml'

    Invoke-Pester -Configuration $configuration
  displayName: 'Run Pester Tests'

- task: PublishTestResults@2
  inputs:
    testResultsFormat: 'NUnit'
    testResultsFiles: 'test-results.xml'
  displayName: 'Publish Test Results'

- task: PublishCodeCoverageResults@1
  inputs:
    codeCoverageTool: 'JaCoCo'
    summaryFileLocation: 'coverage.xml'
  displayName: 'Publish Code Coverage'
```

## Troubleshooting

### Pester Not Found

**Error:** `The term 'Invoke-Pester' is not recognized`

**Solution:**
```powershell
# Ensure Pester is installed
Install-Module -Name Pester -Force -SkipPublisherCheck

# Import Pester
Import-Module Pester
```

### Old Pester Version

**Error:** Tests fail with syntax errors

**Solution:**
```powershell
# Uninstall old version
Uninstall-Module Pester -AllVersions

# Install Pester 5.x
Install-Module -Name Pester -Force -MinimumVersion 5.0
```

### Module Not Found During Tests

**Error:** `The specified module was not loaded because no valid module file was found`

**Solution:**
```powershell
# Verify module paths
Get-ChildItem *.psm1

# Run tests from project root directory
cd D:\ops\provisioning-projects
Invoke-Pester -Path .\tests\
```

## Writing New Tests

### Template for New Test

```powershell
Describe "YourFunctionName" {
    Context "When testing a specific scenario" {
        BeforeAll {
            # Setup mocks and test data
            Mock SomeExternalFunction {
                return "mocked value"
            }
        }

        It "Should return expected result" {
            $result = YourFunctionName -Parameter "value"
            $result | Should -Be "expected"
        }

        It "Should handle edge cases" {
            $result = YourFunctionName -Parameter $null
            $result | Should -BeNullOrEmpty
        }
    }
}
```

### Best Practices

1. **Test one thing per `It` block**
2. **Use descriptive test names** - "Should return true when node is ready"
3. **Mock external dependencies** - Don't make real API calls
4. **Test both success and failure paths**
5. **Test edge cases** - null values, empty arrays, etc.
6. **Use `BeforeAll` for setup** that applies to all tests in a Context
7. **Use `BeforeEach`** for setup that needs to run before each test

## Additional Resources

- [Pester Documentation](https://pester.dev/)
- [PowerShell Testing Guide](https://docs.microsoft.com/en-us/powershell/scripting/dev-cross-plat/testing/pester)
- [Pester GitHub Repository](https://github.com/pester/Pester)

---

**Last Updated:** 2026-01-28
**Related:** Phase 1 Implementation - RKE2 Cluster Cycling Automation
