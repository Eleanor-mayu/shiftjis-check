# Convert-ToShiftJIS.ps1
# 同ディレクトリの*.txtをShift-JIS変換するスクリプト

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$txtFiles = Get-ChildItem -Path $scriptDir -Filter "*.txt" | Where-Object { $_.Name -notlike "temp_*" }

if ($txtFiles.Count -eq 0) {
    Write-Host "TXTファイルが見つかりませんでした。"
    exit
}

$allShiftJIS = $true
$sjisEncoding = [System.Text.Encoding]::GetEncoding(932)

foreach ($file in $txtFiles) {
    $filePath = $file.FullName
    $fileName = $file.Name
    $dirPath  = $file.DirectoryName

    # バイト列を読み込んでエンコーディングを判定
    $bytes = [System.IO.File]::ReadAllBytes($filePath)

    # BOM判定
    $detectedEncoding = $null

    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $detectedEncoding = "UTF-8 (BOM付き)"
        $readEncoding = [System.Text.Encoding]::UTF8
    }
    elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        $detectedEncoding = "UTF-16 LE"
        $readEncoding = [System.Text.Encoding]::Unicode
    }
    elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
        $detectedEncoding = "UTF-16 BE"
        $readEncoding = [System.Text.Encoding]::BigEndianUnicode
    }
    else {
        # BOMなし：UTF-8かShift-JISかを判定
        # UTF-8の妥当性チェック
        try {
            $utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)
            $null = $utf8Strict.GetString($bytes)

            # Shift-JIS範囲のバイトが存在するか確認
            # （純粋なASCIIはShift-JISとも言えるため、0x80以上があるか見る）
            $hasHighByte = $bytes | Where-Object { $_ -gt 0x7F }

            if ($hasHighByte) {
                $detectedEncoding = "UTF-8 (BOMなし)"
                $readEncoding = [System.Text.Encoding]::UTF8
            }
            else {
                # 全てASCII範囲 → Shift-JISとして扱う
                $detectedEncoding = "Shift-JIS (ASCII互換)"
                $readEncoding = $null
            }
        }
        catch {
            # UTF-8として無効 → Shift-JISと判定
            $detectedEncoding = "Shift-JIS"
            $readEncoding = $null
        }
    }

    Write-Host "[$fileName] 検出エンコーディング: $detectedEncoding"

    if ($null -eq $readEncoding) {
        Write-Host "  → 既にShift-JISです。スキップします。"
        continue
    }

    # Shift-JIS以外なので変換処理へ
    $allShiftJIS = $false

    $tempName = "temp_" + $fileName
    $tempPath = Join-Path $dirPath $tempName

    try {
        # 1. 元ファイルをtempへリネーム
        Rename-Item -Path $filePath -NewName $tempName -ErrorAction Stop
        Write-Host "  → リネーム: $fileName → $tempName"

        # 2. 内容を正しいエンコーディングで読み込む
        $content = [System.IO.File]::ReadAllText($tempPath, $readEncoding)

        # 3. Shift-JISで表現できない文字を確認（任意：警告のみ）
        $testBytes = $sjisEncoding.GetBytes($content)
        $testBack  = $sjisEncoding.GetString($testBytes)
        if ($content -ne $testBack) {
            Write-Warning "  ！Shift-JISで表現できない文字が含まれています。一部が置換される可能性があります。"
        }

        # 4. 新しいShift-JISファイルを作成して書き込み
        [System.IO.File]::WriteAllText($filePath, $content, $sjisEncoding)
        Write-Host "  → Shift-JISで新規作成: $fileName"

        # 5. tempファイルを削除
        Remove-Item -Path $tempPath -ErrorAction Stop
        Write-Host "  → 削除: $tempName"

        Write-Host "  → 変換完了: $fileName"
    }
    catch {
        Write-Error "  エラーが発生しました: $_"
        # ロールバック：tempが残っていれば元に戻す
        if ((Test-Path $tempPath) -and -not (Test-Path $filePath)) {
            Rename-Item -Path $tempPath -NewName $fileName
            Write-Host "  → ロールバック: $tempName → $fileName"
        }
    }
}

if ($allShiftJIS) {
    Write-Host "`nすべてのTXTファイルは既にShift-JISです。変換は不要でした。"
}

# 末尾に追加
Write-Host "`n処理が完了しました。Enterキーを押すと終了します..."
Read-Host
