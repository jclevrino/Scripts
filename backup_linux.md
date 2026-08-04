Ayuda para el uso del script backup_linux.sh

vi backup_linux.sh
# Modificar: 
# BACKUP_SOURCES -> ajustar los directorios a respaldar.
# BACKUP_DEST -> el directorio de destino de los backups.
# NOTIFY_EMAIL -> a que destinatario/s se envía el mail de notificación.
# ROTATE_KEEP -> cuantas copias del backup se guardarán. El script esta pensado al estilo de logrotate y para una copia diaria.

# Dar los permisos de ejecución al script
# chmod 700 backup_linux.sh

# Ejecutar manualmente
# Probar el script antes de automatizarlo con cron para verificar que todo funciona.
# sudo ./backup.sh

# Automatizar con cron
# Programar el backup diariamente a las 2:00 AM con crontab.
# sudo crontab -e
# Añadir esta línea:
0 2 * * * /ruta/absoluta/al_script/backup_linux.sh
