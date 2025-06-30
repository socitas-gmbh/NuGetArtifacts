$MajorVersions = "NextMajor", "NextMinor"
$Countries = "DE","AT","W1"

$combinations = @()
foreach ($country in $Countries) {
    foreach ($version in $MajorVersions) {
        $combinations += [PSCustomObject]@{
            country = $country
            version = $version
        }
    }
}

$json = @{ versions = $combinations } | ConvertTo-Json -Compress
Write-Output "versions=$(@{ versions = $combinations } | ConvertTo-Json -Compress)" >> $Env:GITHUB_OUTPUT
Write-Output $json