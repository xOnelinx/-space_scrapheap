# Прогон всех godot/tests/verify_*.gd. Ненулевой код останавливает прогон.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Godot = if ($env:GODOT) { $env:GODOT } else { "godot.exe" }
if (-not (Get-Command $Godot -ErrorAction SilentlyContinue) -and -not (Test-Path -LiteralPath $Godot)) {
	Write-Error "Godot не найден: $Godot. Задай GODOT или положи godot в PATH."
	exit 1
}
$scripts = @(Get-ChildItem -Path (Join-Path $Root "tests") -Filter "verify_*.gd" | Sort-Object Name)
if ($scripts.Count -eq 0) {
	Write-Error "Нет проверок: $Root\tests\verify_*.gd"
	exit 1
}
foreach ($script in $scripts) {
	Write-Host "== $($script.Name)"
	# Windows-сборка Godot — GUI-процесс: вызов через & не ждёт его и теряет код выхода.
	$proc = Start-Process -FilePath $Godot -ArgumentList @(
		"--headless", "--path", $Root, "-s", "res://tests/$($script.Name)"
	) -Wait -PassThru -NoNewWindow
	if ($proc.ExitCode -ne 0) {
		exit $proc.ExitCode
	}
}
Write-Host "ok $($scripts.Count)"
