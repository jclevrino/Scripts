######## Backup multi-directorio backup_linux.sh ###########

# Respalda cualquier cantidad de directorios en un único archivo tar.gz comprimido con gzip.
# Genera un archivo de log independiente por cada ejecución del script, nombrado con el timestamp de la corrida.
# Rotación automática. Elimina versiones antiguas conservando únicamente las N más recientes, igual que logrotate.

$ vi backup_linux.sh
# Modificar:
# BACKUP_SOURCES: los directorios a respaldar,
# BACKUP_DEST: el destino de los archivos de backup
# NOTIFY_EMAIL: a quien se envía el mail con las notificaciones. Debe existir un MTA configurado en el servidor.
# ROTATE_KEEP: Cuantos archivos de backup se guardan (estilo logrotate)

# Dar permisos de ejecución
# Hacerlo ejecutable y restringirlo solo al usuario root por seguridad.
$ chmod 700 backup_linux.sh

# Ejecutar manualmente
# Probar el script antes de automatizarlo con cron para verificar que todo funciona.
$ sudo ./backup_linux.sh

# Automatizar con cron
# Programar el backup diariamente a las 2:00 AM con crontab, por ejemplo.

$ sudo crontab -e
# Añadir esta línea:
0 2 * * * /ruta/absoluta/backup_linux.sh
