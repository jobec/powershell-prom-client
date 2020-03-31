$module = "PrometheusExporter"
Set-Location $env:GITHUB_WORKSPACE
Update-ModuleManifest `
    -Path (Resolve-Path -Path ".\$module\$module.psd1").Path `
    -ModuleVersion $env:MODULE_VERSION
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
try {
    Publish-Module `
        -Path ".\$module" `
        -NuGetApiKey $env:PSGALLERY_TOKEN `
        -ErrorAction Stop `
        -Force
} catch {
    throw $_
}
