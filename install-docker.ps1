Function MyOrg-CheckAdminRights() {
    # Получение текущего контекста пользователя
    $CurrentUser = New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())
  
    # Проверка, имеет ли пользователь, запустивший скрипт, права администратора
    if ($CurrentUser.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
        Write-host "Скрипт запущен с правами администратора!"
    }
    else {
        # Создание нового процесса с повышенными привилегиями для запуска PowerShell
        $ElevatedProcess = New-Object System.Diagnostics.ProcessStartInfo "PowerShell";
 
        # Указание текущего пути и имени скрипта в качестве параметра
        $ElevatedProcess.Arguments = "& '" + $script:MyInvocation.MyCommand.Path + "'"
 
        # Установка процесса с повышенными привилегиями
        $ElevatedProcess.Verb = "runas"

        # Запуск нового процесса с повышенными привилегиями
        [System.Diagnostics.Process]::Start($ElevatedProcess)
 
        # Выход из текущего процесса без повышенных привилегий
        Exit
    }
}

# Проверка, запущен ли скрипт с повышенными привилегиями
MyOrg-CheckAdminRights

Write-Host "Настройка WSL2:Ubuntu..."
& wsl.exe --shutdown
& wsl.exe --install -d Ubuntu -n
& wsl.exe --set-default-version Ubuntu 2
& wsl.exe --set-default Ubuntu

$MyOrg_DockerPath = "$Env:ProgramFiles\MyOrg\Docker"

# Установка Docker
if (Test-Path -Path $MyOrg_DockerPath) {
    Write-Host "Движок Docker установлен: "
    (Start-Process -FilePath "$MyOrg_DockerPath\docker.exe" -ArgumentList "version" -PassThru -NoNewWindow).WaitForExit()
}
else {
    Write-Host "Установка Docker..."
}

# Конфигурация
$MyOrg_DockerConfigs = Get-ChildItem -Path $MyOrg_DockerPath, $(Split-Path -Parent $script:MyInvocation.MyCommand.Path) -Include "*daemon*.json" -Recurse

if ($MyOrg_DockerConfigs) {
    Write-Host "[0] Нет конфигурации"
    for ($i = 0; $i -lt $MyOrg_DockerConfigs.Length; $i++) {
        Write-Host "[$($i+1)] $($MyOrg_DockerConfigs[$i])"
    }
    
    do {
        $select = Read-Host -Prompt "Выберите конфигурацию"
    }while (!$select -or $MyOrg_DockerConfigs.Length -gt $i)
    Write-Host ""

    if ($select -eq 0) {
        $MyOrg_DockerConfig = $null
    }
    else {
        $MyOrg_DockerConfig = $MyOrg_DockerConfigs[$select - 1]
    }
}

if ($MyOrg_DockerConfig) {
    if (!$MyOrg_DockerConfig.DirectoryName.StartsWith($MyOrg_DockerPath)) {
        $MyOrg_DockerConfigDefault = Join-Path $MyOrg_DockerPath -ChildPath "daemon.json"
        Copy-Item -Path $MyOrg_DockerConfig -Destination $MyOrg_DockerConfigDefault -Force
        $MyOrg_DockerConfig = $MyOrg_DockerConfigDefault
    }

    Write-Host "Конфигурация Демона Docker: $MyOrg_DockerConfig"
}
else {
    Write-Host "Нет конфигурации Демона Docker"
}

# Установка переменной PATH
$machinePath = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::Machine)
if ($machinePath -notlike "*;$MyOrg_DockerPath") {
    Write-Host "Добавление $MyOrg_DockerPath в переменную среды Machine:Path"
    [Environment]::SetEnvironmentVariable("Path", "$machinePath;$MyOrg_DockerPath", [System.EnvironmentVariableTarget]::Machine)
}

# Добавление пользователя в группу
New-LocalGroup -Name myorg-docker-users -ErrorAction SilentlyContinue
Add-LocalGroupMember -Name myorg-docker-users -Member $Env:USERNAME -ErrorAction SilentlyContinue

# Конфигурация службы Docker
Stop-Service -Name "docker" -Force -ErrorAction SilentlyContinue

& $MyOrg_DockerPath\dockerd.exe --unregister-service

if ($MyOrg_DockerConfig) {
    Write-Host "Регистрация службы Docker с конфигурацией $MyOrg_DockerConfig"
    & $MyOrg_DockerPath\dockerd.exe --register-service -G myorg-docker-users --config-file $MyOrg_DockerConfig
}
else {
    Write-Host "Регистрация службы Docker без конфигурации"
    & $MyOrg_DockerPath\dockerd.exe --register-service -G myorg-docker-users 
}

Restart-Service -Name "docker" -Force

Write-Host "Служба Docker установлена"

Write-Host ""
Read-Host -Prompt "Нажмите любую клавишу для продолжения"
