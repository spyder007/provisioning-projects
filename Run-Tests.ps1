# Test Runner Script for RKE2 Provisioning Module
# This script provides a convenient way to run Pester tests

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("All", "Unit", "Integration")]
    [string]$TestType = "All",

    [Parameter(Mandatory=$false)]
    [switch]$CodeCoverage,

    [Parameter(Mandatory=$false)]
    [switch]$Detailed,

    [Parameter(Mandatory=$false)]
    [string]$OutputPath = ".\test-results"
)

# Ensure we're in the project root
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $projectRoot

Write-Host "=== RKE2 Provisioning Module Test Runner ===" -ForegroundColor Cyan
Write-Host ""

# Check if Pester is installed
$pesterModule = Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version -ge "5.0" }
if (-not $pesterModule) {
    Write-Host "Pester 5.x is not installed. Installing..." -ForegroundColor Yellow
    Install-Module -Name Pester -Force -SkipPublisherCheck -MinimumVersion 5.0
    Write-Host "Pester installed successfully." -ForegroundColor Green
    Write-Host ""
}

# Import Pester
Import-Module Pester -MinimumVersion 5.0

# Configure Pester
$configuration = [PesterConfiguration]::Default

# Set test paths based on test type
switch ($TestType) {
    "All" {
        $configuration.Run.Path = ".\tests\"
        Write-Host "Running all tests..." -ForegroundColor Cyan
    }
    "Unit" {
        $configuration.Run.Path = ".\tests\Rke2-ProxmoxProvisioning.Tests.ps1"
        Write-Host "Running unit tests..." -ForegroundColor Cyan
    }
    "Integration" {
        Write-Warning "Integration tests should be run manually using the guide at .\docs\phase1-manual-testing-guide.md"
        exit 0
    }
}

# Set output verbosity
if ($Detailed) {
    $configuration.Output.Verbosity = 'Detailed'
} else {
    $configuration.Output.Verbosity = 'Normal'
}

# Create output directory if it doesn't exist
if (-not (Test-Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory | Out-Null
}

# Configure test results
$configuration.TestResult.Enabled = $true
$configuration.TestResult.OutputPath = Join-Path $OutputPath "test-results.xml"
$configuration.TestResult.OutputFormat = 'NUnitXml'

# Configure code coverage
if ($CodeCoverage) {
    Write-Host "Code coverage enabled" -ForegroundColor Yellow
    $configuration.CodeCoverage.Enabled = $true
    $configuration.CodeCoverage.Path = @(
        ".\Rke2-ProxmoxProvisioning.psm1"
        ".\Proxmox-Provisioning.psm1"
        ".\Proxmox-Wrapper.psm1"
        ".\Unifi.psm1"
    )
    $configuration.CodeCoverage.OutputPath = Join-Path $OutputPath "coverage.xml"
    $configuration.CodeCoverage.OutputFormat = 'JaCoCo'
}

Write-Host ""

# Run tests
$result = Invoke-Pester -Configuration $configuration

# Display summary
Write-Host ""
Write-Host "=== Test Summary ===" -ForegroundColor Cyan

# Pester 5.x returns counts in the result object
# Access them carefully to handle different property structures
$passedCount = 0
$failedCount = 0
$skippedCount = 0
$totalCount = 0

if ($result) {
    # Try direct count properties first (Pester 5.3+)
    if ($null -ne $result.PassedCount) {
        $passedCount = $result.PassedCount
        $failedCount = $result.FailedCount
        $skippedCount = $result.SkippedCount
        $totalCount = $result.TotalCount
    }
    # Try collection counts (Pester 5.0-5.2)
    elseif ($result.Passed) {
        $passedCount = $result.Passed.Count
        $failedCount = $result.Failed.Count
        $skippedCount = $result.Skipped.Count
        $totalCount = $passedCount + $failedCount + $skippedCount + $result.NotRun.Count
    }
}

Write-Host "Total Tests:  $totalCount" -ForegroundColor White
Write-Host "Passed:       $passedCount" -ForegroundColor Green
Write-Host "Failed:       $failedCount" -ForegroundColor $(if ($failedCount -gt 0) { "Red" } else { "Green" })
Write-Host "Skipped:      $skippedCount" -ForegroundColor Yellow
Write-Host ""

# Display code coverage if enabled
if ($CodeCoverage -and $result.CodeCoverage) {
    $coveragePercent = [Math]::Round(($result.CodeCoverage.CoveragePercent), 2)
    Write-Host "Code Coverage: $coveragePercent%" -ForegroundColor $(if ($coveragePercent -ge 80) { "Green" } elseif ($coveragePercent -ge 60) { "Yellow" } else { "Red" })
    Write-Host ""
}

# Display output file locations
$resolvedOutputPath = Resolve-Path $configuration.TestResult.OutputPath -ErrorAction SilentlyContinue
if ($resolvedOutputPath) {
    Write-Host "Test results saved to: $resolvedOutputPath" -ForegroundColor Gray
} else {
    Write-Host "Test results saved to: $($configuration.TestResult.OutputPath)" -ForegroundColor Gray
}

if ($CodeCoverage) {
    $resolvedCoveragePath = Resolve-Path $configuration.CodeCoverage.OutputPath -ErrorAction SilentlyContinue
    if ($resolvedCoveragePath) {
        Write-Host "Coverage report saved to: $resolvedCoveragePath" -ForegroundColor Gray
    } else {
        Write-Host "Coverage report saved to: $($configuration.CodeCoverage.OutputPath)" -ForegroundColor Gray
    }
}
Write-Host ""

# Exit with appropriate code
if ($failedCount -gt 0) {
    Write-Host "TESTS FAILED" -ForegroundColor Red
    exit 1
} else {
    Write-Host "ALL TESTS PASSED" -ForegroundColor Green
    exit 0
}
