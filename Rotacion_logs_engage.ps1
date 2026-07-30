## Rotacion de los logs de ENGAGE ( CRM y plataforma de Contact Center omnicanal )
## Se corre en el servidor principal de ENGAGE01
## Directorios de logs a rotar: Se leen del archivo C:\scripts\carpetas_logs.txt
## Dias a guardar 30 - Un archivo de log por día (para rastreo de fallas o problemas. Valor sugerido por el implementador)
## Dias sin comprimir 3 -  Un archivo de log por día(Para deteccion/resolucion rapida de incidencia)
## Para la compresion se utiliza la utilidad free 7zip
## El script genera un log el cual se guarda C:\scripts\logs. Si la carpeta no existe el script la crea. Los logs del script son autodepurados
## por el mismo script.

$7z = "C:\Program Files\7-Zip\7z.exe" 
$hoy = (Get-Date).date
$sincomprimir = $hoy.AddDays(-3)
$conservar = $hoy.AddDays(-30)
$dirslog = get-content "C:\scripts\carpetas_logs.txt"
$scriptdirlog = "C:\scripts\logs"
$fechalog = Get-Date -uformat "_%d%m%Y"
$nombrescriptlog = "RotaLogsEngage"+$fechalog+".log"
$scriptlog = $scriptdirlog+"\"+$nombrescriptlog

function StampTime()
{
return "[" + (Get-Date -uformat "%Y-%m-%d %H:%M:%S") + "] "
}

### Funcion para testear si un archivo esta bloqueado por algun proceso
function Test-FileLock {
  param (
    [parameter(Mandatory=$true)][string]$Path
  )

  $oFile = New-Object System.IO.FileInfo $Path

  if ((Test-Path -Path $Path) -eq $false) {
    return $false
  }

  try {
    $oStream = $oFile.Open([System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)

    if ($oStream) {
      $oStream.Close()
    }
    $false
  } catch {
    # el archivo esta bloqueado por un proceso.
    return $true
  }
}

## Si no existe el directorio de logs del script crearlo
if (!(Test-Path $scriptdirlog))
{
   New-Item -path C:\scripts -name logs -type "directory"
}
## Crear archivo de log diario si no existe
if (!(Test-Path $scriptlog))
{
   New-Item -path $scriptdirlog -name $nombrescriptlog -type "file"
}
## Depurar logs del script
$scrlogfiles = Get-ChildItem -Path $scriptdirlog\* -include *.log | Where-Object {-not $_.PsIsContainer} | % {$_.fullname}
if (![string]::IsNullOrEmpty($scrlogfiles))
   {
      if ($scrlogfiles.Count -gt 15 )
      {
         $scrlogfiles | Sort-Object lastwritetime | Select-Object -First ($scrlogfiles.Count - 15) | Remove-Item -Force 
      }
	}
## Procesar los logs en los directorios listados en $dirslog
$loggin = "============================================================================================================================================`r`n"
$loggin += (StampTime) + ("Iniciando la compresion/rotacion de logs de ENGAGE")
$loggin | Out-File -FilePath $scriptlog -Append
## Remover logs antiguos comprimidos
ForEach ( $dirlog in $dirslog )
{
   $aeliminar = (Get-ChildItem -path $dirlog\* -include "*.7z" | Where-Object {($_.lastwritetime -lt $conservar)} | % {$_.fullname})
   if (![string]::IsNullOrEmpty($aeliminar))
    {
        ForEach ( $file in $aeliminar )
	    {
			if ((Test-Path $file))
		    {
			   $loggin = (StampTime) + ("Eliminando archivo $file")
               $loggin | Out-File -FilePath $scriptlog -Append
			   Remove-Item -Path $file -Force 4>&1 | Add-Content $scriptlog
     		}	
	    }
    }

## Comprimir logs de más de 3 dias
   $acomprimir = (Get-ChildItem -path $dirlog\* -include "*.log" | Where-Object {($_.lastwritetime -lt $sincomprimir)} | % {$_.basename})
   if (![string]::IsNullOrEmpty($acomprimir))
    {
        ForEach ( $file in $acomprimir )
		{
		    $arch = $dirlog+"\"+$file+".log"
			if (!(Test-FileLock $arch))
			{
		        $comp = $dirlog+"\"+$file+".7z"
		        & $7z a $comp $arch -mx9 -sdel -y
		        if (!(Test-Path $comp))
                 {
                    $loggin = (StampTime) + ("ERROR en la compresion del archivo $comp")
                    $loggin | Out-File -FilePath $scriptlog -Append
                 }
		         else
		         {
		            $loggin = (StampTime) + (("Compresion del archivo $comp OK"))
                    $loggin | Out-File -FilePath $scriptlog -Append
		         }
			}
			else
			{
			    $loggin = (StampTime) + (("El archivo $arch esta bloqueado por otro proceso - No se puede comprimir"))
                $loggin | Out-File -FilePath $scriptlog -Append
			}
	    }
    }
}
