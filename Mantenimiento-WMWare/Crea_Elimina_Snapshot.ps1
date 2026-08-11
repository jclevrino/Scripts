<#
.SYNOPSIS
    Crea snapshots de VMs antes de la instalacion de parches y elimina los antiguos.
.DESCRIPTION
    Pre-tarea ejecutada por el aplicativo PatchManager.
    - Se conecta al vCenter con credenciales encriptadas leidas desde archivo.
    - Por cada VM de la lista: elimina snapshots "PatchManager" de mas de 4 dias
      (apagados) y crea un snapshot nuevo con fecha y nombre del proceso.
    - Registra toda la tarea unicamente en un archivo de log.
.NOTES
    Requiere: VMware PowerCLI.
#>

# ============================================================
#  0) CONFIGURACION
# ============================================================
$RutaCredencial = "C:\scripts\usrcred.txt"
$RutaVMList     = "C:\scripts\PatchManager\vmsUpdate.txt"
$Usuario        = "empresa\usuariorpa"
$vCenter        = "vcenter01.empresa.int"
$DiasRetencion  = 4
$CarpetaLog     = "C:\scripts\PatchManager\Logs"

# ============================================================
#  1) PREPARACION DEL LOG
# ============================================================
if (-not (Test-Path $CarpetaLog)) {
    New-Item -ItemType Directory -Path $CarpetaLog -Force | Out-Null
}
$Timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$ArchivoLog = Join-Path $CarpetaLog "Snapshots_$Timestamp.log"

function Write-Log {
    param(
        [string]$Mensaje,
        [ValidateSet("INFO", "OK", "WARN", "ERROR")]
        [string]$Nivel = "INFO"
    )
    $linea = "{0} [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Nivel, $Mensaje
    Add-Content -Path $ArchivoLog -Value $linea -Encoding UTF8
}

Write-Log "===== Inicio del proceso de snapshots (PatchManager) ====="
Write-Log "Archivo de log: $ArchivoLog"

# ============================================================
#  2) CARGA DE POWERCLI
# ============================================================
try {
    Import-Module VMware.PowerCLI -ErrorAction Stop
    Write-Log "Modulo VMware.PowerCLI cargado correctamente." "OK"
}
catch {
    Write-Log "No se pudo cargar VMware.PowerCLI. Detalle: $($_.Exception.Message)" "ERROR"
    return
}

# ============================================================
#  3) CREDENCIALES ENCRIPTADAS
# ============================================================
# Para generar el archivo de credenciales (una sola vez):
#   $credential = Get-Credential
#   $credential.Password | ConvertFrom-SecureString | Set-Content C:\scripts\usrcred.txt

if (-not (Test-Path $RutaCredencial)) {
    Write-Log "No se encontro el archivo de credenciales '$RutaCredencial'." "ERROR"
    return
}
try {
    $encrypted = Get-Content $RutaCredencial | ConvertTo-SecureString -ErrorAction Stop
    $crd = New-Object System.Management.Automation.PsCredential($Usuario, $encrypted)
    Write-Log "Credenciales cargadas para el usuario '$Usuario'." "OK"
}
catch {
    Write-Log "Error al leer/desencriptar las credenciales: $($_.Exception.Message)" "ERROR"
    return
}

# ============================================================
#  4) LISTA DE VMs
# ============================================================
if (-not (Test-Path $RutaVMList)) {
    Write-Log "No se encontro la lista de VMs '$RutaVMList'." "ERROR"
    return
}
$VMlist = Get-Content $RutaVMList | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
if (-not $VMlist -or $VMlist.Count -eq 0) {
    Write-Log "La lista de VMs esta vacia." "WARN"
    return
}
Write-Log "Se procesaran $($VMlist.Count) VM(s)."

# Solo se borran snapshots de mas de N dias, para no borrar los creados en la corrida anterior.
$FechaDel = ((Get-Date).Date).AddDays(-$DiasRetencion)
Write-Log "Se eliminaran snapshots 'PatchManager' apagados anteriores a: $($FechaDel.ToString('yyyy-MM-dd'))"

# ============================================================
#  5) CONEXION AL vCENTER
# ============================================================
try {
    Connect-VIServer -Server $vCenter -Credential $crd -ErrorAction Stop | Out-Null
    Write-Log "Conectado al vCenter '$vCenter'." "OK"
}
catch {
    Write-Log "No se pudo conectar al vCenter '$vCenter': $($_.Exception.Message)" "ERROR"
    return
}

# ============================================================
#  6) PROCESAMIENTO POR VM
# ============================================================
$eliminados = 0
$creados    = 0
$fallidos   = 0

foreach ($vm in $VMlist) {

    $vm = $vm.Trim()
    Write-Log "-----------------------------------------------------------"
    Write-Log "Procesando VM: '$vm'"

    # --- Verificar que la VM exista ---
    $objVM = Get-VM -Name $vm -ErrorAction SilentlyContinue
    if (-not $objVM) {
        Write-Log "La VM '$vm' no existe en el vCenter. OMITIDA." "WARN"
        $fallidos++
        continue
    }

    # --- Eliminar snapshots antiguos ---
    try {
        $viejos = $objVM | Get-Snapshot |
                  Where-Object { $_.Name -match "PatchManager" } |
                  Where-Object { $_.PowerState -eq "PoweredOff" } |
                  Where-Object { $_.Created -lt $FechaDel }

        if ($viejos) {
            foreach ($snap in $viejos) {
                Remove-Snapshot -Snapshot $snap -Confirm:$false -ErrorAction Stop
                Write-Log "Snapshot antiguo eliminado: '$($snap.Name)' (creado $($snap.Created.ToString('yyyy-MM-dd'))) en '$vm'." "OK"
                $eliminados++
            }
        }
        else {
            Write-Log "No hay snapshots antiguos para eliminar en '$vm'." "INFO"
        }
    }
    catch {
        Write-Log "Error al eliminar snapshots en '$vm': $($_.Exception.Message)" "ERROR"
        $fallidos++
    }

    # --- Crear snapshot nuevo ---
    try {
        $desc = (Get-Date -Format "dd-MM-yyyy") + ' - Windows Update - PatchManager'
        New-Snapshot -VM $objVM -Name "PatchManager" -Description $desc -Confirm:$false -ErrorAction Stop | Out-Null
        Write-Log "Snapshot creado en '$vm'. Descripcion: $desc" "OK"
        $creados++
    }
    catch {
        Write-Log "Error al crear snapshot en '$vm': $($_.Exception.Message)" "ERROR"
        $fallidos++
    }
}

# ============================================================
#  7) DESCONEXION
# ============================================================
try {
    Disconnect-VIServer -Server $vCenter -Confirm:$false -ErrorAction Stop
    Write-Log "Desconectado del vCenter '$vCenter'." "OK"
}
catch {
    Write-Log "Advertencia al desconectar del vCenter: $($_.Exception.Message)" "WARN"
}

# ============================================================
#  8) RESUMEN
# ============================================================
Write-Log "==========================================================="
Write-Log "RESUMEN: VMs=$($VMlist.Count) | Snapshots creados=$creados | Eliminados=$eliminados | Errores=$fallidos"
Write-Log "===== Fin del proceso ====="
