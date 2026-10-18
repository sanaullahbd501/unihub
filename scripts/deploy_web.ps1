# UniHub One-Click Cloudflare Web Deploy Script
Write-Host "Building Flutter Web Production Release..." -ForegroundColor Cyan
& "C:\Users\Admin\flutter\bin\flutter.bat" build web --release

if ($LASTEXITCODE -ne 0) {
    Write-Host "Web build failed!" -ForegroundColor Red
    exit 1
}

Write-Host "Pushing compiled web release to release-web branch..." -ForegroundColor Green
git --work-tree=build/web --git-dir=build/web/.git add -A
git --work-tree=build/web --git-dir=build/web/.git commit -m "deploy: update web release $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
git --work-tree=build/web --git-dir=build/web/.git push origin release-web -f

Write-Host "Successfully deployed to Cloudflare Pages branch (release-web)!" -ForegroundColor Cyan
