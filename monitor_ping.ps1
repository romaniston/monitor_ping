# Мониторинг пинга с интерактивным вводом параметров

# Заголовок
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "          МОНИТОРИНГ ПИНГА" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

# Функция для валидации IP/хоста
function Test-IsValidTarget {
    param([string]$Target)
    
    # Проверка на пустое значение
    if ([string]::IsNullOrWhiteSpace($Target)) {
        return $false
    }
    
    # Проверка на допустимые символы
    if ($Target -match '^[a-zA-Z0-9\.\-\:]+$') {
        return $true
    }
    
    return $false
}

# Функция для ввода с валидацией
function Read-ValidatedInput {
    param(
        [string]$Prompt,
        [scriptblock]$ValidationScript,
        [string]$ErrorMessage = "Неверный ввод. Попробуйте снова.",
        [string]$DefaultValue = $null
    )
    
    while ($true) {
        if ($DefaultValue) {
            $inputText = Read-Host "$Prompt [$DefaultValue]"
            if ([string]::IsNullOrWhiteSpace($inputText)) {
                $inputText = $DefaultValue
            }
        } else {
            $inputText = Read-Host $Prompt
        }
        
        if (& $ValidationScript $inputText) {
            return $inputText
        }
        Write-Host $ErrorMessage -ForegroundColor Red
    }
}

# Запрос параметров у пользователя
Write-Host "Введите параметры мониторинга:" -ForegroundColor Yellow
Write-Host ""

# 1. Целевой хост
$Target = Read-ValidatedInput -Prompt "IP адрес или имя узла" `
    -ValidationScript { param($v) Test-IsValidTarget $v } `
    -ErrorMessage "Введите корректный IP или имя хоста"

# 2. Порог задержки
$Threshold = Read-ValidatedInput -Prompt "Порог задержки (мс)" `
    -ValidationScript { param($v) ($v -as [int]) -and ([int]$v -gt 0) } `
    -ErrorMessage "Введите положительное число" `
    -DefaultValue "250"

# 3. Интервал проверки
$Interval = Read-ValidatedInput -Prompt "Интервал проверки (секунд)" `
    -ValidationScript { param($v) ($v -as [int]) -and ([int]$v -ge 1) } `
    -ErrorMessage "Введите число >= 1" `
    -DefaultValue "5"

# 4. Количество пингов за раз
$PingCount = Read-ValidatedInput -Prompt "Количество пингов за проверку" `
    -ValidationScript { param($v) ($v -as [int]) -and ([int]$v -ge 1 -and [int]$v -le 10) } `
    -ErrorMessage "Введите число от 1 до 10" `
    -DefaultValue "1"

# Подтверждение параметров
$LogFile = "$PSScriptRoot\monitor_ping_$Target.log"

Write-Host ""
Write-Host "==============================================" -ForegroundColor Green
Write-Host "НАСТРОЙКИ МОНИТОРИНГА:" -ForegroundColor Green
Write-Host "  Целевой узел: $Target" -ForegroundColor Green
Write-Host "  Порог задержки: $Threshold мс" -ForegroundColor Green
Write-Host "  Интервал проверки: $Interval сек" -ForegroundColor Green
Write-Host "  Пингов за раз: $PingCount" -ForegroundColor Green
Write-Host "  Файл лога: $LogFile" -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Green
Write-Host ""

# Подтверждение запуска
$choice = Read-Host "Нажмите Enter для запуска мониторинга или 'q' для выхода"
if ($choice -eq 'q' -or $choice -eq 'Q') {
    Write-Host "Мониторинг отменен." -ForegroundColor Yellow
    exit
}

# Создаем заголовок в лог-файле
$header = @"
==============================================
Мониторинг пинга начат: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Целевой узел: $Target
Порог задержки: $Threshold мс
Интервал: $Interval сек
==============================================
"@
Add-Content -Path $LogFile -Value $header

Write-Host ""
Write-Host "Запуск мониторинга..." -ForegroundColor Cyan
Write-Host "Для остановки нажмите Ctrl+C" -ForegroundColor Cyan
Write-Host ""

# Счетчики для статистики
$totalChecks = 0
$highLatencyCount = 0
$timeoutCount = 0
$startTime = Get-Date

try {
    while ($true) {
        $totalChecks++
        
        try {
            # Выполняем пинг
            $ping = Test-Connection -ComputerName $Target -Count $PingCount -ErrorAction Stop
            
            # Рассчитываем среднюю задержку
            $avgPingTime = [math]::Round(($ping.ResponseTime | Measure-Object -Average).Average)
            
            if ($avgPingTime -gt $Threshold) {
                $highLatencyCount++
                $Message = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ⚠ ВЫСОКАЯ ЗАДЕРЖКА: $avgPingTime мс (порог: $Threshold мс) к $Target"
                Add-Content -Path $LogFile -Value $Message
                Write-Host $Message -ForegroundColor Yellow
            } else {
                $Message = "$(Get-Date -Format 'HH:mm:ss') Норма: $avgPingTime мс к $Target"
                Write-Host $Message -ForegroundColor Green
            }

        } catch {
            $timeoutCount++
            $Message = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ❌ НЕТ СОЕДИНЕНИЯ с $Target"
            Add-Content -Path $LogFile -Value $Message
            Write-Host $Message -ForegroundColor Red
        }

        Start-Sleep -Seconds $Interval
    }
} 
catch {
    # Обработка прерывания Ctrl+C
    if ($_.Exception.GetType().Name -eq "PipelineStoppedException") {
        Write-Host ""
        Write-Host "Мониторинг остановлен пользователем." -ForegroundColor Yellow
        
        # Финальная статистика
        $elapsed = (Get-Date) - $startTime
        $successRate = if ($totalChecks -gt 0) {
            [math]::Round((($totalChecks - $timeoutCount) / $totalChecks * 100), 2)
        } else { 0 }
        
        $summary = @"

==============================================
Мониторинг завершен: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
ИТОГИ:
  Всего проверок: $totalChecks
  Высокая задержка: $highLatencyCount
  Таймаутов: $timeoutCount
  Успешных: $successRate%
  Общее время: $($elapsed.ToString('hh\:mm\:ss'))
==============================================
"@
        Add-Content -Path $LogFile -Value $summary
        Write-Host $summary -ForegroundColor Cyan
    }
}