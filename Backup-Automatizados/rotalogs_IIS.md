###### Script utilizado para realizar backup de logs de IIS en formato comprimido
#
# UTILIZACION: Backup y rotación de logs de IIS
# OBJETIVO: Reducir el espacio en disco de servidores web utilizados en un modelo de 
# granja con sitios de alta demanda. (logs de gran tamaño).
#
# El script toma los logs de todos los sitios alojados en el servidor, los comprime empleando la utilidad 7zip
# con los parametros:
# -mx9 : para la maxima compresión.
# -sdel : para que elimine el archivo original una vez realizada la compresión exitosa
# -y : para que responda "yes" a los interrogantes.
#
# Una vez realizada la compresión los archivos son movidos a un servidor de almacenamiento de logs
# montando una unidad de red por SMB. El nombre de usuario y contraseña para el montaje de la unidad de red
# son leídos de un archivo binario encriptado.
#
# El srcipt genera un log de las tareas y lo envía mediante correo electronico (debe poder acceder a un MTA).
#
# Para programar la tarea:
# En la pestaña Acciones: Nuevo.
# Acción: Iniciar un programa.
# En Programa o script, escribir la ruta exacta: C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe.
# En Agregar argumentos, escribir los parámetros de ejecución: -ExecutionPolicy Bypass -NoProfile -File "C:\scripts\rota# logs_IIS.ps1"
#
# El usuario para correr el script en segundo plano debe ser System
