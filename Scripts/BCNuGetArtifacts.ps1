param(
    [string]$Country,
    [string]$Select
)

$FilesToRemove = [System.Collections.Generic.List[string]]::new()
dotnet tool install --global Microsoft.Dynamics.BusinessCentral.Development.Tools --version 16.0.22.35424-beta

function Download-Artifacts {
    param(
        [string]$Country,
        [string]$Select
    )
    Write-Host "Downloading artifacts for country: $Country, select: $Select"
    $url = Get-BCArtifactUrl -type Sandbox -country $Country -select $Select -accept_insiderEula
    Write-Host "Artifact URL: $url"

    # Create a temporary directory for downloads
    $tempPath = Join-Path $env:temp "BCArtifacts_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    New-Item -ItemType Directory -Path $tempPath -Force | Out-Null

    # Define the local file path
    $fileName = "BCArtifacts.zip"
    $localFilePath = Join-Path $tempPath $fileName

    Write-Host "Downloading artifact to: $localFilePath"
    # Download the file
        (New-Object System.Net.WebClient).DownloadFile($url, $localFilePath)
    $FilesToRemove.Add($localFilePath)

    $ArtifactFolder = (Join-Path $tempPath "BCArtifacts")
    Expand-Archive -Path $localFilePath -DestinationPath $ArtifactFolder -Force
    $FilesToRemove.Add($ArtifactFolder)

    Write-Host "Download completed successfully"
    return $ArtifactFolder
}


function Create-SymbolPackages {
    param(
        [string]$AppFolder,
        [string]$Country,
        [string]$Select
    )
    Write-Host "Creating symbol packages in folder: $AppFolder"
    $appsToBePublished = @{
        "Microsoft_Base Application"    = "{publisher}.{name}.{tag}.symbols.{id}";
        "Microsoft_Business Foundation" = "{publisher}.{name}.{tag}.symbols.{id}";
        "Microsoft_System Application"  = "{publisher}.{name}.{tag}.symbols.{id}";
        "Microsoft_Application"         = "{publisher}.{name}.{tag}.symbols";
    }

    if ($Country -eq "W1") {
        $Country = ""
    }

    # Determine if insider tag should be added
    $insiderTag = ($Select -eq "NextMajor" -or $Select -eq "NextMinor")

    foreach ($appKey in $appsToBePublished.Keys) {
        $files = Get-ChildItem -Path (Join-Path $AppFolder "Extensions") -Filter "$appKey*.app"
        foreach ($file in $files) {
            Write-Host "Processing file: $($file.FullName)"
            $symbolAppName = "$($file.FullName)$($Country).symbol.app"
            al CreateSymbolPackage $file.FullName $symbolAppName
            $FilesToRemove.Add($symbolAppName)

            $params = @{}
            if ($insiderTag) {
                $params = @{"prereleaseTag" = "insider"}
            }
            $appMetadata = al GetPackageManifest $symbolAppName | ConvertFrom-Json
            $packageId = Get-BcNuGetPackageId -packageIdTemplate $appsToBePublished[$appKey] -publisher $appMetadata.Publisher -name $appMetadata.Name -id $appMetadata.Id -tag $Country

            $NuGetPackageFullName = New-BcNuGetPackage @params -appfile $symbolAppName -packageId $packageId
            $FilesToRemove.Add($NuGetPackageFullName)

            Write-Host $NuGetPackageFullName
            dotnet nuget push $NuGetPackageFullName --api-key $Env:NUGET_API_KEY --source "https://nuget.pkg.github.com/socitas-gmbh/index.json" --skip-duplicate
        }
    }
}

function Cleanup-TemporaryFiles {
    param(
        [string]$TempFolder
    )
    $FilesToRemove | ForEach-Object {
        if (Test-Path $_) {
            Write-Host "Removing temporary file: $_"
            Remove-Item -Path $_ -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}


#https://github.com/microsoft/navcontainerhelper/blob/main/NuGet/Get-BcNuGetPackageId.ps1

try{
    Write-Host "Starting BC NuGet Artifacts process"
    $ArtifactPath = Download-Artifacts -Country $Country -Select $Select
    Create-SymbolPackages -AppFolder $ArtifactPath -Country $Country -Select $Select
    Cleanup-TemporaryFiles -TempFolder "PathToTempFolder"
    Write-Host "Process completed"
} catch {
    Write-Error "An error occurred during the BC NuGet Artifacts process: $($_.Exception.Message)"
    Cleanup-TemporaryFiles -TempFolder "PathToTempFolder"
    throw
}