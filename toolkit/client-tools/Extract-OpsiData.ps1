$ErrorActionPreference = "Stop"
$target = "C:\GitHub" + "\opsi_scripts"
$sourcePath = "C:\GitHub\scripts-and-tools-pol\OPSI"

Write-Host "Creating target folder..."
New-Item -ItemType Directory -Force -Path $target | Out-Null

Write-Host "Moving contents..."
Move-Item -Path "$sourcePath\*" -Destination $target -Force

Write-Host "Setting up WIP and dump..."
New-Item -ItemType Directory -Force -Path "$target\dump" | Out-Null
New-Item -ItemType Directory -Force -Path "$target\WIP" | Out-Null

Write-Host "Creating .agent junction..."
$masterAgentPath = "C:\GitHub\agents_and_prompts\agents\master\.agent"
New-Item -ItemType Junction -Path "$target\.agent" -Value $masterAgentPath -Force | Out-Null

Write-Host "Creating version.json and package.json..."
$versionJson = '{ "version": "1.0.0", "updated": "2026-03-18T13:23:36Z" }'
Set-Content -Path "$target\version.json" -Value $versionJson -Encoding utf8

$packageJson = @"
{
  "name": "opsi_scripts",
  "version": "1.0.0",
  "description": "opsi_scripts Repository",
  "author": "",
  "license": "ISC"
}
"@
Set-Content -Path "$target\package.json" -Value $packageJson -Encoding utf8

Write-Host "Initializing git in target..."
Set-Location $target
git init
git add .
git commit -m "feat(repo): initial extraction of OPSI to opsi_scripts"

Write-Host "Creating opsi_scripts.code-workspace..."
$wsPath = "C:\GitHub" + "\opsi_scripts.code-workspace"
$wsContent = @"
{
	"folders": [
		{
			"path": "opsi_scripts"
		}
	],
	"settings": {}
}
"@
Set-Content -Path $wsPath -Value $wsContent -Encoding utf8

Write-Host "Removing OPSI from source repo and committing..."
Set-Location "C:\GitHub\scripts-and-tools-pol"
Remove-Item -Path $sourcePath -Recurse -Force
git add OPSI
git commit -m "refactor(opsi): extracted OPSI to opsi_scripts repository"

Write-Host "Done."

