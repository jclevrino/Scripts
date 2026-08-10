<#
.SYNOPSIS
    Alta masiva de usuarios en Active Directory desde un archivo Excel/CSV.
.DESCRIPTION
    Lee un archivo (.xlsx o .csv) con los datos de los usuarios y los crea en AD.
    - Fuerza cambio de contraseña en el próximo inicio de sesion.
    - Deja que la caducidad de contraseña la gobierne la politica de dominio.
    - Salida por pantalla + archivo de log.
.NOTES
    Requiere: modulo ActiveDirectory (RSAT). Para .xlsx: modulo ImportExcel.
    Ejecutar en un equipo con las herramientas de administracion de AD.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RutaArchivo,

    # Sufijo UPN del dominio, por ejemplo: empresa.local
    [Parameter(Mandatory = $true)]
    [string]$DominioUPN,

    # Carpeta donde se guardan los logs
    [string]$CarpetaLog = "C:\Scripts\Logs\AltaUsuariosAD"
)

# ============================================================
#  1) CONFIGURACION: mapeo de Unidad_Organizativa -> DN real
#     Ajustar estos DN a la estructura del dominio.
# ============================================================
$MapaOU = @{
    "Casa_Central" = "OU=Casa_Central,OU=Usuarios,DC=empresa,DC=local"
    "Sucursales"   = "OU=Sucursales,OU=Usuarios,DC=empresa,DC=local"
    "Deposito"     = "OU=Deposito,OU=Usuarios,DC=empresa,DC=local"
}

# ============================================================
#  2) Preparacion de log
# ============================================================
if (-not (Test-Path $CarpetaLog)) {
    New-Item -ItemType Directory -Path $CarpetaLog -Force | Out-Null
}
$Timestamp   = Get-Date -Format "yyyyMMdd_HHmmss"
$ArchivoLog  = Join-Path $CarpetaLog "AltaUsuarios_$Timestamp.log"

function Write-Log {
    param(
        [string]$Mensaje,
        [ValidateSet("INFO", "OK", "WARN", "ERROR")]
        [string]$Nivel = "INFO"
    )
    $linea = "{0} [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Nivel, $Mensaje
    switch ($Nivel) {
        "OK"    { Write-Host $linea -ForegroundColor Green }
        "WARN"  { Write-Host $linea -ForegroundColor Yellow }
        "ERROR" { Write-Host $linea -ForegroundColor Red }
        default { Write-Host $linea -ForegroundColor Cyan }
    }
    Add-Content -Path $ArchivoLog -Value $linea -Encoding UTF8
}

# ============================================================
#  3) Validaciones iniciales
# ============================================================
Write-Log "===== Inicio del proceso de alta masiva de usuarios ====="
Write-Log "Archivo de entrada: $RutaArchivo"
Write-Log "Log de la tarea:   $ArchivoLog"

# Importar el modulo ActiveDirectory
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Log "Modulo ActiveDirectory cargado correctamente." "OK"
}
catch {
    Write-Log "No se pudo cargar el modulo ActiveDirectory. Favor de Instalar RSAT. Detalle: $($_.Exception.Message)" "ERROR"
    return
}

if (-not (Test-Path $RutaArchivo)) {
    Write-Log "El archivo '$RutaArchivo' no existe." "ERROR"
    return
}

# ============================================================
#  4) Lectura del archivo (xlsx o csv)
# ============================================================
$extension = [System.IO.Path]::GetExtension($RutaArchivo).ToLower()
$usuarios = @()

try {
    if ($extension -eq ".xlsx") {
        if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
            Write-Log "Para leer .xlsx se necesita el modulo ImportExcel: Install-Module ImportExcel -Scope CurrentUser" "ERROR"
            return
        }
        Import-Module ImportExcel -ErrorAction Stop
        $usuarios = Import-Excel -Path $RutaArchivo
        Write-Log "Archivo XLSX leido correctamente." "OK"
    }
    elseif ($extension -eq ".csv") {
        # Ajustar -Delimiter ';' si Excel exporta con punto y coma como separador
        $usuarios = Import-Csv -Path $RutaArchivo -Delimiter ";" -Encoding UTF8
        Write-Log "Archivo CSV leido correctamente." "OK"
    }
    else {
        Write-Log "Extension no soportada ($extension). Usá .xlsx o .csv" "ERROR"
        return
    }
}
catch {
    Write-Log "Error al leer el archivo: $($_.Exception.Message)" "ERROR"
    return
}

if (-not $usuarios -or $usuarios.Count -eq 0) {
    Write-Log "El archivo no contiene registros." "WARN"
    return
}

Write-Log "Se encontraron $($usuarios.Count) registros para procesar."

# ============================================================
#  5) Procesamiento de cada usuario
# ============================================================
$exitosos = 0
$fallidos = 0
$omitidos = 0

foreach ($u in $usuarios) {

    $nombre   = ($u.Nombre            | Out-String).Trim()
    $apellido = ($u.Apellido          | Out-String).Trim()
    $sam      = ($u.nombre_de_usuario | Out-String).Trim()
    $ou       = ($u.Unidad_Organizativa | Out-String).Trim()
    $direccion= ($u.Direccion         | Out-String).Trim()
    $telefono = ($u.Telefono          | Out-String).Trim()
    $puesto   = ($u.Puesto            | Out-String).Trim()
    $grupo    = ($u.Grupo_Principal   | Out-String).Trim()
    $password = ($u.password_temporal | Out-String).Trim()

    Write-Log "-----------------------------------------------------------"
    Write-Log "Procesando: '$sam' ($nombre $apellido)"

    # --- Validacion de campos obligatorios ---
    if ([string]::IsNullOrWhiteSpace($sam) -or
        [string]::IsNullOrWhiteSpace($nombre) -or
        [string]::IsNullOrWhiteSpace($apellido) -or
        [string]::IsNullOrWhiteSpace($password)) {
        Write-Log "Registro incompleto (faltan Nombre/Apellido/usuario/password). OMITIDO." "WARN"
        $omitidos++
        continue
    }

    # --- Validacion de OU ---
    if (-not $MapaOU.ContainsKey($ou)) {
        Write-Log "Unidad_Organizativa '$ou' no valida (permitidas: $($MapaOU.Keys -join ', ')). OMITIDO." "WARN"
        $omitidos++
        continue
    }
    $rutaOU = $MapaOU[$ou]

    # --- Verificar que la OU exista en AD ---
    try {
        Get-ADOrganizationalUnit -Identity $rutaOU -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Log "La OU '$rutaOU' no existe en AD. OMITIDO." "ERROR"
        $omitidos++
        continue
    }

    # --- Verificar que el usuario no exista ---
    $existe = Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue
    if ($existe) {
        Write-Log "El usuario '$sam' ya existe en AD. OMITIDO." "WARN"
        $omitidos++
        continue
    }

    # --- Construccion de atributos ---
    $nombreCompleto = "$nombre $apellido"
    $upn            = "$sam@$DominioUPN"

    try {
        $securePass = ConvertTo-SecureString $password -AsPlainText -Force

        $parametros = @{
            Name                  = $nombreCompleto
            GivenName             = $nombre
            Surname               = $apellido
            DisplayName           = $nombreCompleto
            SamAccountName        = $sam
            UserPrincipalName     = $upn
            Path                  = $rutaOU
            AccountPassword       = $securePass
            Enabled               = $true
            ChangePasswordAtLogon = $true       # Debe cambiar la password en el proximo login
            PasswordNeverExpires  = $false      # La caducidad la aplica la politica de dominio
            Title                 = $puesto
        }

        # Campos opcionales (solo si vienen cargados)
        if (-not [string]::IsNullOrWhiteSpace($direccion)) { $parametros.StreetAddress   = $direccion }
        if (-not [string]::IsNullOrWhiteSpace($telefono))  { $parametros.OfficePhone     = $telefono  }

        New-ADUser @parametros -ErrorAction Stop
        Write-Log "Usuario '$sam' creado en '$ou'. Puesto: $puesto" "OK"

        # --- Asignacion a grupo principal (como membresia) ---
        if (-not [string]::IsNullOrWhiteSpace($grupo)) {
            $grupoAD = Get-ADGroup -Filter "Name -eq '$grupo'" -ErrorAction SilentlyContinue
            if ($grupoAD) {
                try {
                    Add-ADGroupMember -Identity $grupoAD -Members $sam -ErrorAction Stop
                    Write-Log "Usuario '$sam' agregado al grupo '$grupo'." "OK"
                }
                catch {
                    Write-Log "No se pudo agregar '$sam' al grupo '$grupo': $($_.Exception.Message)" "WARN"
                }
            }
            else {
                Write-Log "El grupo '$grupo' no existe en AD. Se creó el usuario pero sin grupo." "WARN"
            }
        }

        $exitosos++
    }
    catch {
        Write-Log "Error al crear '$sam': $($_.Exception.Message)" "ERROR"
        $fallidos++
    }
}

# ============================================================
#  6) Resumen final
# ============================================================
Write-Log "==========================================================="
Write-Log "RESUMEN: Total=$($usuarios.Count) | Creados=$exitosos | Omitidos=$omitidos | Fallidos=$fallidos"
Write-Log "===== Fin del proceso ====="
Write-Host ""
Write-Host "Log completo disponible en: $ArchivoLog" -ForegroundColor Magenta