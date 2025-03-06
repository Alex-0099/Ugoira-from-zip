# PowerShell Script to Process Multiple ZIP Files in a Folder and Convert to MP4 with 2-Pass Encoding and Auto FPS Detection

# Step 1: Select a Folder Containing ZIP Files
Add-Type -AssemblyName System.Windows.Forms
$FolderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
$FolderBrowser.Description = "Select a folder containing ZIP files"
if ($FolderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
    $folderPath = $FolderBrowser.SelectedPath
} else {
    Write-Host "No folder selected. Exiting..." -ForegroundColor Red
    exit 1
}

# Step 2: Find all ZIP files in the selected folder
$zipFiles = Get-ChildItem -Path $folderPath -Filter "*.zip"
if ($zipFiles.Count -eq 0) {
    Write-Host "No ZIP files found in the selected folder. Exiting..." -ForegroundColor Red
    exit 1
}

# Save original directory
$originalLocation = Get-Location

foreach ($zipFile in $zipFiles) {
    Write-Host "Processing: $($zipFile.Name)"
    
    # Step 3: Extract ZIP file into a new folder
    $outputFolder = Join-Path $folderPath ("unzipped_" + $zipFile.BaseName)
    Write-Host "Extracting ZIP file to: $outputFolder"
    Expand-Archive -Path $zipFile.FullName -DestinationPath $outputFolder -Force
    
    # Step 4: Change directory to the extracted folder
    Set-Location -Path $outputFolder
    Write-Host "Changed directory to: $(Get-Location)"
    
    # Step 5: Detect FPS from metadata if available, otherwise estimate from image timestamps
    $metadataFile = Join-Path $outputFolder "metadata.json"
    $fps = 30  # Default FPS
    if (Test-Path $metadataFile) {
        Write-Host "Found metadata.json, extracting FPS..."
        try {
            $jsonContent = Get-Content $metadataFile | ConvertFrom-Json
            if ($jsonContent.frames) {
                $delays = $jsonContent.frames.delay
                if ($delays.Count -gt 0) {
                    $averageDelay = ($delays | Measure-Object -Average).Average
                    if ($averageDelay -gt 0) {
                        $fps = [math]::Round(1000 / $averageDelay, 2)
                    }
                }
            }
        }
        catch {
            Write-Host "Failed to extract FPS from metadata. Trying timestamp estimation..." -ForegroundColor Yellow
        }
    }
    
    # If metadata is missing, estimate FPS based on image timestamps
    if ($fps -eq 30) {
        $files = Get-ChildItem -Filter *.jpg | Sort-Object LastWriteTime
        if ($files.Count -gt 1) {
            $timeDifferences = @()
            for ($i = 1; $i -lt $files.Count; $i++) {
                $timeDifferences += ($files[$i].LastWriteTime - $files[$i-1].LastWriteTime).TotalMilliseconds
            }
            if ($timeDifferences.Count -gt 0) {
                $averageDelay = ($timeDifferences | Measure-Object -Average).Average
                if ($averageDelay -gt 0) {
                    $fps = [math]::Round(1000 / $averageDelay, 2)
                }
            }
        }
        Write-Host "Estimated FPS from timestamps: $fps"
    }
    
    Write-Host "Using FPS: $fps"
    
    # Step 6: Rename images if necessary
    Write-Host "Renaming images..."
    $files = Get-ChildItem -Filter *.jpg | Where-Object { -not $_.PSIsContainer } | Sort-Object Name
    $count = 0
    foreach ($file in $files) {
        $newName = "frame{0:D4}.jpg" -f $count
        try {
            Rename-Item -Path $file.FullName -NewName $newName -Force
            Write-Host "Renamed: $($file.Name) -> $newName"
        }
        catch {
            Write-Host "Failed to rename: $($file.FullName)" -ForegroundColor Yellow
        }
        $count++
    }
    
    # Step 7: Set MP4 output name based on ZIP file
    $outputVideo = Join-Path $folderPath "$($zipFile.BaseName).mp4"
    
    # Step 8: Convert images to MP4 using FFmpeg 2-Pass Encoding with auto FPS
    Write-Host "Performing first pass (analysis)..."
    $ffmpegPass1 = "ffmpeg -framerate $fps -i `"frame%04d.jpg`" -c:v libx264 -b:v 2M -pass 1 -f mp4 -y NUL"
    Write-Host "Running command: $ffmpegPass1"
    Invoke-Expression $ffmpegPass1
    
    Write-Host "Performing second pass (final encoding)..."
    $ffmpegPass2 = "ffmpeg -framerate $fps -i `"frame%04d.jpg`" -c:v libx264 -b:v 2M -pass 2 -pix_fmt yuv420p -colorspace bt709 -color_primaries bt709 -color_trc bt709 `"$outputVideo`""
    Write-Host "Running command: $ffmpegPass2"
    Invoke-Expression $ffmpegPass2
    
    # Step 9: Clean up 2-pass temporary files
    Write-Host "Cleaning up temporary files..."
    Remove-Item "ffmpeg2pass-0.log" -ErrorAction SilentlyContinue
    Remove-Item "ffmpeg2pass-0.log.mbtree" -ErrorAction SilentlyContinue
    Write-Host "Cleanup complete."
    
    # Step 10: Return to the original directory
    Set-Location -Path $originalLocation
    Write-Host "Returned to original directory: $(Get-Location)"
}

Write-Host "All ZIP files processed successfully!" -ForegroundColor Green
