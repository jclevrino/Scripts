#!/usr/bin/env bash
# =============================================================================
#  backup.sh — Backup con rotación de versiones y notificación por email
# =============================================================================
#
#  Uso:
#    sudo ./backup.sh
#
#  Requiere: tar, gzip, mail, find, df
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# 1. CONFIGURACIÓN
#    Editar esta sección antes de usar el script
# ---------------------------------------------------------------------------

# Directorios a respaldar: Colocar los que se desee
BACKUP_SOURCES=("/etc" "/var/www" "/home")

# Destino donde se guardan los backups
BACKUP_DEST="/var/backups/srvbackup"

# Máximo de versiones a conservar tipo logrotate
ROTATE_KEEP=7

# Email de notificación de errores
NOTIFY_EMAIL="admin@example.com"
NOTIFY_FROM="backup@$(hostname -f 2>/dev/null || echo localhost)"
NOTIFY_SUBJECT_PREFIX="[BACKUP ERROR]"

# Directorio de logs (un archivo por corrida)
LOG_DIR="/var/log/backup"

# Umbral mínimo de espacio libre en destino (MB)
MIN_FREE_MB=500

# Nivel de compresión gzip: 1 (rápido) – 9 (máximo) (ajustar segun el compromiso tiempo/espacio)
GZIP_LEVEL=6

# Prefijo del archivo tar generado
BACKUP_PREFIX="backup"

# Patrones a excluir (sintaxis tar --exclude)
EXCLUDES=(
  "*.tmp"
  "*.pid"
  ".cache"
  "node_modules"
  "__pycache__"
)

# ---------------------------------------------------------------------------
# 2. VARIABLES GLOBALES DE EJECUCIÓN
# ---------------------------------------------------------------------------

TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
HOSTNAME="$(hostname -s 2>/dev/null || echo unknown)"
BACKUP_NAME="${BACKUP_PREFIX}_${HOSTNAME}_${TIMESTAMP}"
BACKUP_FILE="${BACKUP_DEST}/${BACKUP_NAME}.tar.gz"

# Un archivo de log por cada corrida del script
LOG_FILE="${LOG_DIR}/backup_${TIMESTAMP}.log"

ERRORS=()
BACKUP_SIZE=""

# ---------------------------------------------------------------------------
# 3. UTILIDADES PARA CREAR EL LOG
# ---------------------------------------------------------------------------

_ts() { date '+%Y-%m-%d %H:%M:%S'; }

log()  { echo "$(_ts) [INFO ]  $*" | tee -a "${LOG_FILE}"; }
warn() { echo "$(_ts) [WARN ]  $*" | tee -a "${LOG_FILE}"; }
err()  { echo "$(_ts) [ERROR]  $*" | tee -a "${LOG_FILE}" >&2; }
ok()   { echo "$(_ts) [OK   ]  $*" | tee -a "${LOG_FILE}"; }
step() { echo "$(_ts) [STEP ]  $*" | tee -a "${LOG_FILE}"; }

# ---------------------------------------------------------------------------
# 4. FUNCIÓN: ENVIAR EMAIL DE ERROR
# ---------------------------------------------------------------------------

send_error_email() {
  local subject="${NOTIFY_SUBJECT_PREFIX} $(hostname -f 2>/dev/null || echo localhost) — ${TIMESTAMP}"
  local body
  body="$(cat <<EOF
Hostname  : ${HOSTNAME}
Fecha     : $(_ts)
Script    : ${BASH_SOURCE[0]}
Destino   : ${BACKUP_DEST}

ERRORES DETECTADOS
==================
$(printf '%s\n' "${ERRORS[@]}")

LOG COMPLETO DE ESTA CORRIDA
=============================
$(cat "${LOG_FILE}" 2>/dev/null || echo "(log no disponible)")
EOF
)"

  if command -v mail &>/dev/null; then
    echo "${body}" | mail -s "${subject}" -r "${NOTIFY_FROM}" "${NOTIFY_EMAIL}" && return 0
  fi

  warn "No se encontró agente de correo (mail). Email NO enviado."
}

# ---------------------------------------------------------------------------
# 5. FUNCIÓN: MANEJADOR DE ERRORES Y CLEANUP
# ---------------------------------------------------------------------------

on_error() {
  local exit_code=$? line_no="${1:-?}"
  local msg="Error inesperado en línea ${line_no} (exit code ${exit_code})"
  err "${msg}"; ERRORS+=("${msg}")
  cleanup_on_failure
  notify_and_exit 1
}

trap 'on_error ${LINENO}' ERR

cleanup_on_failure() {
  if [[ -f "${BACKUP_FILE}" ]]; then
    warn "Eliminando archivo de backup incompleto: ${BACKUP_FILE}"
    rm -f "${BACKUP_FILE}" 2>/dev/null || true
  fi
}

notify_and_exit() {
  local code="${1:-1}"
  if [[ ${#ERRORS[@]} -gt 0 ]]; then
    err "BACKUP FALLIDO — ${#ERRORS[@]} error(es)"
    send_error_email || warn "Fallo al enviar email de notificación."
  fi
  log "Script finalizado con código de salida: ${code}"
  echo "------------------------------------------" >> "${LOG_FILE}"
  exit "${code}"
}

# ---------------------------------------------------------------------------
# 6. FUNCIÓN: PREPARAR DIRECTORIOS
# ---------------------------------------------------------------------------

prepare_dirs() {
  for dir in "${BACKUP_DEST}" "${LOG_DIR}"; do
    if [[ ! -d "${dir}" ]]; then
      mkdir -p "${dir}" || { echo "ERROR: No se pudo crear: ${dir}" >&2; exit 1; }
    fi
  done
  step "Directorios listos. Log de esta corrida: ${LOG_FILE}"
}

# ---------------------------------------------------------------------------
# 7. FUNCIÓN: VERIFICAR ESPACIO EN DISCO
# ---------------------------------------------------------------------------

check_disk_space() {
  step "Verificando espacio libre en '${BACKUP_DEST}'..."
  local avail_mb
  avail_mb=$(df -m "${BACKUP_DEST}" 2>/dev/null | awk 'NR==2 {print $4}')
  log "Espacio disponible: ${avail_mb:-?} MB (mínimo: ${MIN_FREE_MB} MB)"
  if [[ -n "${avail_mb}" ]] && (( avail_mb < MIN_FREE_MB )); then
    local msg="Espacio insuficiente: ${avail_mb} MB < ${MIN_FREE_MB} MB requeridos"
    ERRORS+=("${msg}"); err "${msg}"; return 1
  fi
  ok "Espacio suficiente."
}

# ---------------------------------------------------------------------------
# 8. FUNCIÓN: VERIFICAR DIRECTORIOS FUENTES (origen)
# ---------------------------------------------------------------------------

check_sources() {
  step "Verificando directorios fuente..."
  local valid=()
  for src in "${BACKUP_SOURCES[@]}"; do
    if [[ -d "${src}" ]]; then ok "Fuente OK: ${src}"; valid+=("${src}")
    else warn "Omitida (no existe): ${src}"; fi
  done
  if [[ ${#valid[@]} -eq 0 ]]; then
    ERRORS+=("Sin fuentes válidas"); err "Sin directorios válidos. Abortando."; return 1
  fi
  BACKUP_SOURCES=("${valid[@]}")
}

# ---------------------------------------------------------------------------
# 9. FUNCIÓN: REALIZAR EL BACKUP
# ---------------------------------------------------------------------------

do_backup() {
  step "Iniciando backup → ${BACKUP_FILE}"
  local exclude_args=()
  for pat in "${EXCLUDES[@]}"; do exclude_args+=("--exclude=${pat}"); done

  tar --create --gzip --file="${BACKUP_FILE}" \
    --preserve-permissions --one-file-system \
    "${exclude_args[@]}" -- "${BACKUP_SOURCES[@]}" 2>>"${LOG_FILE}" || {
    ERRORS+=("tar falló: ${BACKUP_FILE}"); return 1
  }

  [[ -f "${BACKUP_FILE}" ]] || { ERRORS+=("Archivo no creado: ${BACKUP_FILE}"); return 1; }
  BACKUP_SIZE=$(du -sh "${BACKUP_FILE}" 2>/dev/null | cut -f1 || echo "?")
  ok "Backup creado: ${BACKUP_FILE} (${BACKUP_SIZE})"
}

# ---------------------------------------------------------------------------
# 10. FUNCIÓN: ROTAR VERSIONES ANTIGUAS (estilo logrotate)
# ---------------------------------------------------------------------------

rotate_backups() {
  step "Rotando versiones (conservando ${ROTATE_KEEP} más recientes)..."
  local -a all
  mapfile -t all < <(
    find "${BACKUP_DEST}" -maxdepth 1 -name "${BACKUP_PREFIX}_*.tar.gz" \
      -printf '%T@ %p\n' 2>/dev/null | sort -rn | awk '{print $2}'
  )
  local total=${#all[@]}
  log "Versiones encontradas: ${total}"
  (( total <= ROTATE_KEEP )) && { ok "Sin necesidad de rotación."; return 0; }

  for (( i = ROTATE_KEEP; i < total; i++ )); do
    rm -f "${all[$i]}" 2>>"${LOG_FILE}" \
      && log "Eliminado: $(basename "${all[$i]}")"
  done
  ok "Rotación completada."
}

# ---------------------------------------------------------------------------
# 11. FUNCIÓN: RESUMEN FINAL
# ---------------------------------------------------------------------------

print_summary() {
  {
    echo "=========================================="
    echo "  RESUMEN DEL BACKUP — $(_ts)"
    echo "=========================================="
    echo "  Estado  : $( [[ ${#ERRORS[@]} -eq 0 ]] && echo "EXITOSO" || echo "CON ERRORES" )"
    echo "  Host    : ${HOSTNAME}"
    echo "  Archivo : ${BACKUP_FILE}"
    echo "  Tamaño  : ${BACKUP_SIZE:-N/A}"
    echo "  Fuentes : ${BACKUP_SOURCES[*]:-N/A}"
    echo "  Log     : ${LOG_FILE}"
    echo "=========================================="
  } | tee -a "${LOG_FILE}"
}

# ---------------------------------------------------------------------------
# 12. MAIN
# ---------------------------------------------------------------------------

main() {
  prepare_dirs

  log "=========================================="
  log "  INICIO DEL BACKUP — ${TIMESTAMP}"
  log "=========================================="
  log "Script   : ${BASH_SOURCE[0]}"
  log "Usuario  : $(id -un)"
  log "Host     : ${HOSTNAME}"

  check_disk_space
  check_sources
  do_backup
  rotate_backups
  print_summary

  [[ ${#ERRORS[@]} -gt 0 ]] && notify_and_exit 1
  ok "Backup completado sin errores."
  notify_and_exit 0
}

main "$@"
