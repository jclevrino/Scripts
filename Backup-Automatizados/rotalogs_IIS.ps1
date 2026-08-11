# -----------------------------------------------------------------------
# Este script se utiliza para rotar y hacer backup de los logs del IIS
# en los servidores de una granjaWeb. 
# Los logs se comprimen y mueven a la ubicacion de red $NetDrive.
# Se procesan los logs anteriores a $diasGuardar.
# La ubicacion de los logs es la definida en $LogPath
# siendo esta la carpeta madre, dentro de la cual se encuentran
# las carpetas correspondientes a los sitios.
# El log de la tarea es enviado por correo a la direccion $EmailTo
# Es necesario tener instalado 7zip en la ruta definida en $7ZIP
# -----------------------------------------------------------------------

# DEFINICION DE VARIABLES PRINCIPALES Y FUNCIONES
$HostLocal = $([system.environment]::MachineName)
$NetDrive = "\\gollum.example.int\backup"
$NetUser = "example\cron"
$CrLf = [char]13 + [char]10
$Inicio="Inicio:  {0:dd/MM/yyyy hh:mm:ss}" -f (get-date)
# SETEAR EL DIRECTORIO DEL SCRIPT 
$scriptRoot = "C:\scripts"
# CANTIDAD DE DIAS A GUARDAR LOS LOGS ANTES DE BORRARLOS
$diasGuardar= 3
# PATH A LAS CARPETAS DE LOGS DE
$LogPath = "C:\inetpub\logs\LogFiles" ## CORREGIR EL PATH SI LOS LOGS ESTAN EN OTRA UBICACION
# SETEO DE LA UTILIDAD DE COMPRESIÓN DE ARCHIVOS
$7ZIP = "C:\Program Files\7-Zip\7z.exe"
# SETEO DEL ARCHIVO DE LOG DEL SCRIP
$DlogFile = "$(get-date -f yyyyMMdd_HHmm)-RotaLogs.log"

function send_email {
$Emailbody = "Rotacion de logs de IIS de $HostLocal"
$EmailFrom = $HostLocal+"@example.int"
$EmailTo = "admin@example.com" # Para agregar nuevos recipientes separar con comas y colocar cada una entre ""
$EmailSubject = "Rotacion de logs de IIS"
$SMTPServer = "mailserver.example.int"
$emailattachment = $logFile 
$mailmessage = New-Object system.net.mail.mailmessage
$mailmessage.from = ($EmailFrom)
$mailmessage.To.add($EmailTo)
$mailmessage.Subject = $EmailSubject
$mailmessage.Body = $Emailbody
$attachment = New-Object System.Net.Mail.Attachment($emailattachment, 'text/plain')
$mailmessage.Attachments.Add($attachment)
$SMTPClient = New-Object Net.Mail.SmtpClient($SmtpServer, 25)
$SMTPClient.Send($mailmessage)
}
 
###### COMIENZO DEL SCRIPT ######
# CREO EL ARCHIVO DE LOG DE LA TAREA 
New-Item -Name $DlogFile -ItemType file
$logFile = $scriptRoot+"\"+$DlogFile
$tempo = $scriptRoot+"\temp"
if (!(Test-Path $tempo)) { New-Item -Name $tempo -ItemType Directory }
$Filetempo = $tempo+"\*.*"
if (Test-Path $FileTempo) {Remove-Item $FileTempo}
# FECHA A PARTIR DE LA CUAL SE BORRA
$fileAging = (Get-Date).AddDays(-$diasGuardar)
# ARCHIVOS TEMPORALES USADOS EN EL PROCESO
$CarpAprocTmp = $scriptRoot+"\temp\carpaproctmp.txt"
$CarpAprocesar = $scriptRoot+"\temp\carpaprocesar.txt"
# ENCABEZADO DEL LOG
Write-Output ($Encabezado = @"
$("-"*52)$CrLf
Rotación/Backup de logs de IIS$CrLf
$("-"*52)$CrLf
$Inicio$CrLf
"@)
Out-File $logFile -InputObject $Encabezado

# IR AL DIRECTORIO DE LOGS Y LISTAR LAS CARPETAS DE LOS SITIOS
Set-Location $LogPath
Get-ChildItem | ?{ $_.PSIsContainer } | Select-Object Name | ft -HideTableHeaders | Out-File $CarpAproctmp
# ELIMINAR LAS LINEAS EN BLANCO
cat $CarpAproctmp | where {$_ -ne ""} > $CarpAprocesar
# LEER LAS CARPETAS A PROCESAR EN LA VARIABLE $Carpetas
$Carpetas = Get-content  $CarpAprocesar
$Carpetas = $Carpetas -replace (" ","")
# VERIFICAR QUE EXISTE/N CARPETAS A PROCESAR
$contCarpetas = ($Carpetas).Count
if ($contCarpetas -eq $null)
{
"No hay carpetas para procesar en la ubicacion $LogPath" | Out-File $logFile -Append
  }
else {
	"Carpeta\s a procesar:$CrLf" | Out-File $logFile -Append
	$Carpetas | Out-File $logFile -Append
	$CrLf | Out-File $logFile -Append
    foreach ($tmpDir in $Carpetas) {
                        "Procesando carpeta $tmpDir ..." | Out-File $logFile -Append
                        $ubicacion = $LogPath+"\"+$tmpDir
						$tmpDirFiles = $scriptRoot+"\temp\"+$tmpDir+".tmp"
						$DirFiles = $scriptRoot+"\temp\"+$tmpDir+".txt"
						# IR A LA CARPETA CORRESPONDIENTE
						Set-Location $ubicacion
						if ("$?" -eq "True" )
							{
							# FILTRAR EL NOMBRE DE LOS ARCHIVOS MAS ANTIGUOS QUE $fileAging
							Get-ChildItem -Path ./* -Include *.log -ErrorAction 'Stop' | Where-Object {$_.lastWriteTime -lt $fileAging} | Select-Object basename | ft -HideTableHeaders | Out-File $tmpDirFiles
							# ELIMINAR LAS LINEAS EN BLANCO
							cat $tmpDirFiles | where {$_ -ne ""} > $DirFiles
							$tmpFiles = Get-Content $DirFiles
							$contFiles = ($tmpFiles).Count
							# VERIFICAR SI HAY ARCHIVOS PARA PROCESAR
							if ($contFiles -eq $null)
								{
								"No hay archivos para procesar en la carpeta $ubicacion" | Out-File $logFile -Append
								$CrLf | Out-File $logFile -Append
								}
							else{
								foreach ($tmpFile in $tmpFiles) {
									$tmpFile = $tmpFile -replace (" ","")
									$archComp=$tmpDir+"_"+$tmpFile+".7z"
									$arch=$tmpFile+".log"
									&$7ZIP a $archComp $arch -mx9 -sdel -y | Out-File $logFile -Append
									}
								}
						}else{
								"No se encuentra o no se puede acceder la carpeta $ubicacion" | Out-File $logFile -Append
							}
	}
$Fin ="Fin de la rotacion de logs:  {0:dd/MM/yyyy hh:mm:ss}" -f (get-date)
$CrLf | Out-File $logFile -Append
$Fin | Out-File $logFile -Append

# CONECTAR LA UNIDAD DE RED G: A $NetDrive, DONDE SE MOVERAN LOS LOGS COMPRIMIDOS
# LAS CREDENCIALES SE LEEN DESDE UN ARCHIVO BINARIO ENCRIPTADO
# EL SERVIDOR DE LOGS $NetDrive ES UN RECURSO COMPARTIDO POR SMB EN EL SERVIDOR GOLLUM
$encrytpedData = Get-Content -enc byte C:\scripts\seg\password.bin
$unencrytpedData = [System.Security.Cryptography.ProtectedData]::Unprotect( `
                       $encrytpedData, $entropy, 'CurrentUser')
$password = [System.Text.Encoding]::Unicode.GetString($unencrytpedData)
$net = new-object -ComObject WScript.Network
$net.MapNetworkDrive("G:", $NetDrive, $false, $NetUser, $password)

# MOVER LOS LOGS COMPRIMIDOS A LA UNIDAD DE RED G:

$PatMove = $LogPath+"\*"
$Destino = "G:\LOGS\"+$HostLocal
$Control = $Destino+"\control.txt"
$Rotacion = "Rotacion Dia {0:dd/MM/yyyy hh:mm:ss}" -f (get-date)
$Rotacion | Out-File $Control
if ("$?" -eq "True" )
	{
	$CrLf | Out-File $logFile -Append
	"Copiando los logs al servidor de backup (Gollum)" | Out-File $logFile -Append
	Get-ChildItem -Path $PatMove -include *.7z -recurse | Out-File $Control -Append
	Get-ChildItem -Path $PatMove -include *.7z -recurse | Out-File $logFile -Append
	Get-ChildItem -Path $PatMove -include *.7z -recurse | Move-Item -destination $Destino
	if ("$?" -eq "True" ) {
							# ESCRIBIR EN EL LOG Y SALIR
							$FinMove ="Se han movido los logs correctamente - {0:dd/MM/yyyy hh:mm:ss}" -f (get-date)
							$FinMove | Out-File $logFile -Append
						}
	# DESMONTAR LA UNIDAD DE RED G:
	$net = New-Object -ComObject WScript.Network;
	$unidades=$net.EnumNetworkDrives();
	if ($unidades -like "G:") { $net.removenetworkdrive("G:",$true)}
	} else {
			$CrLf | Out-File $logFile -Append
			"No se ha podido acceder a la unidad del server de backup - Favor de verificar" | Out-File $logFile -Append
			}
}

# ENVIAR EL LOG DE LA TAREA POR CORREO ELECTRONICO
send_email

# REMOVER LOS LOGS DEL SCRIPT
$GuardarLogs = 7
$Borrar = (Get-Date).AddDays(-$GuardarLogs)
$LogScript = $scriptRoot+"\*" 
Get-ChildItem -Path $LogScript -Include *.log -ErrorAction 'Stop' | Where-Object {$_.lastWriteTime -lt $Borrar} | Remove-Item -Force
###### FIN DEL SCRIPT ######
