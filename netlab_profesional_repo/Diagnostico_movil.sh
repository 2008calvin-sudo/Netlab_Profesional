#!/usr/bin/env bash
# =====================================================================
#  NetLab Profesional - Diagnostico automatico de red (Termux / NetHunter sin root)
#  Version 0.1.0 (2026-10-05)
#  Probado con: pendiente de prueba en telefono real (ver README)
#
#  Recorre la checklist de diagnostico: enlace -> IP -> escalera de ping
#  -> ruta -> DNS -> puerto -> servicio -> (opcional) rendimiento.
#
#  SOLO PARA PROFESIONALES: automatiza pasos que deberias poder hacer a
#  mano. Si un paso falla, tenes que poder distinguir entre "la red esta
#  mal" y "el script/herramienta fallo". Si todavia estas aprendiendo,
#  usa la checklist manual (https://github.com/2008calvin-sudo/netlab/blob/main/manuales/checklist-diagnostico.md).
#
#  No cambia ninguna configuracion: solo lee y mide. No necesita root.
#  Limitaciones: sin root no hay ARP, captura ni escaneos SYN/UDP;
#  ip/traceroute pueden estar restringidos segun la version de Android.
#  Usalo solo en redes propias o con autorizacion.
# =====================================================================
VERSION="0.1.0"
export LC_ALL=C

usage() {
cat <<USO
Uso: $0 [opciones]
  -d, --destino HOST     Destino de prueba (dominio o IP)        [google.com]
  -p, --puerto N         Puerto TCP a probar en el destino       [443]
  -g, --gateway IP       Gateway (si no, se detecta)
  -e, --ip-externa IP    IP de Internet para el ping             [8.8.8.8]
  -D, --dns IP           DNS de referencia para comparar         [8.8.8.8]
  -u, --url URL          URL para el paso de servicio            [https://DESTINO]
  -P, --iperf SERVIDOR   Si se indica, mide con iperf3 contra ese servidor
  -o, --salida DIR       Carpeta del reporte                     [~/netlab_reportes]
  -s, --seguir           No cortar cuando falla una capa
  -y, --si               No pedir confirmacion inicial
  -h, --ayuda            Esta ayuda
Codigos de salida: 0 todo OK | 1 hubo FALLA | 2 error de uso | 3 incompleto (algun paso NO SE PUDO)
USO
}

DESTINO="google.com"; PUERTO=443; GATEWAY=""; IPEXT="8.8.8.8"
DNSREF="8.8.8.8"; URL=""; IPERF=""; SALIDA="$HOME/netlab_reportes"; SEGUIR=0; SI=0

while [[ $# -gt 0 ]]; do
  case $1 in
    -d|--destino) DESTINO=$2; shift 2 ;;
    -p|--puerto) PUERTO=$2; shift 2 ;;
    -g|--gateway) GATEWAY=$2; shift 2 ;;
    
    -e|--ip-externa) IPEXT=$2; shift 2 ;;
    -D|--dns) DNSREF=$2; shift 2 ;;
    -u|--url) URL=$2; shift 2 ;;
    -P|--iperf) IPERF=$2; shift 2 ;;
    -o|--salida) SALIDA=$2; shift 2 ;;
    -s|--seguir) SEGUIR=1; shift ;;
    -y|--si) SI=1; shift ;;
    -h|--ayuda) usage; exit 0 ;;
    *) echo "Opcion desconocida: $1" >&2; usage >&2; exit 2 ;;
  esac
done

# Validacion de entradas (evita inyeccion y errores tontos)
valido() { [[ "$1" =~ ^[A-Za-z0-9._:-]+$ && "$1" != -* ]]; }
for v in "$DESTINO" "$IPEXT" "$DNSREF" "$IPERF" "$GATEWAY"; do
  [[ -z "$v" ]] && continue
  valido "$v" || { echo "Valor no permitido: '$v'" >&2; exit 2; }
done
[[ "$PUERTO" =~ ^[0-9]+$ ]] && (( PUERTO >= 1 && PUERTO <= 65535 )) || { echo "Puerto invalido" >&2; exit 2; }
[[ -z "$URL" ]] && URL="https://$DESTINO"
[[ "$URL" =~ ^https?://[A-Za-z0-9._:/?=\&%~+-]+$ ]] || { echo "URL no permitida" >&2; exit 2; }

if [[ -t 1 ]]; then G=$'\e[32m'; R=$'\e[31m'; Y=$'\e[33m'; B=$'\e[1m'; N=$'\e[0m'; else G=; R=; Y=; B=; N=; fi
tiene() { command -v "$1" >/dev/null 2>&1; }

if [[ $SI -eq 0 ]]; then
  echo "${B}NetLab Profesional v$VERSION${N} - diagnostico automatico."
  echo "${Y}Solo para profesionales: si un paso falla, tenes que poder repetirlo a mano.${N}"
  echo "Solo lee y mide; no cambia configuracion. Destino: $DESTINO:$PUERTO"
  read -rp "Continuar? [s/N]: " r
  [[ "$r" =~ ^[sS]$ ]] || exit 0
fi

mkdir -p "$SALIDA" || { echo "No pude crear $SALIDA" >&2; exit 2; }
TS=$(date +%Y%m%d_%H%M%S)
MD="$SALIDA/reporte_$TS.md"
RAW="$SALIDA/crudo_$TS.txt"
: > "$RAW"; : > "$MD"

declare -a RES_PASO RES_ESTADO RES_DET
HAY_FALLA=0; CORTAR=0; INCOMPLETO=0

# run "etiqueta" comando...  -> guarda salida cruda en $RAW y en $SALIDA_CMD, devuelve el codigo
run() {
  local et=$1; shift
  { echo "### $et"; echo "\$ $*"; } >> "$RAW"
  SALIDA_CMD=$("$@" 2>&1); local rc=$?
  { echo "$SALIDA_CMD"; echo "[codigo de salida: $rc]"; echo; } >> "$RAW"
  return $rc
}

# resultado "paso" ESTADO "detalle"
resultado() {
  RES_PASO+=("$1"); RES_ESTADO+=("$2"); RES_DET+=("$3")
  local c=$G
  case $2 in FALLA) c=$R; HAY_FALLA=1 ;; "NO SE PUDO") c=$Y; INCOMPLETO=1 ;; AVISO) c=$Y ;; esac
  printf '  %s[%s]%s %s - %s\n' "$c" "$2" "$N" "$1" "$3"
}
titulo() { echo; echo "${B}== $1 ==${N}"; }
cortar_si_falla() { [[ $SEGUIR -eq 0 ]] && CORTAR=1 && echo "  ${Y}Se corta aca: las capas siguientes dependen de esta. Use --seguir para continuar igual.${N}"; }

# ---------------- 0. Entorno ----------------
titulo "0. Entorno"
if [[ "${PREFIX:-}" == *com.termux* ]]; then ENTORNO="Termux"; else ENTORNO="Linux/NetHunter"; fi
FALTAN=()
for t in ping curl dig traceroute iperf3 termux-wifi-connectioninfo; do tiene "$t" || FALTAN+=("$t"); done
run "entorno" bash -c 'uname -srm; date; getprop ro.build.version.release 2>/dev/null'
ANDROID=$(getprop ro.build.version.release 2>/dev/null)
resultado "Entorno" OK "$ENTORNO${ANDROID:+, Android $ANDROID}"
if [[ ${#FALTAN[@]} -gt 0 ]]; then
  resultado "Herramientas" AVISO "faltan: ${FALTAN[*]} (pkg install dnsutils traceroute iperf3 termux-api curl)"
else resultado "Herramientas" OK "todas presentes"; fi

# ---------------- 1. Wi-Fi ----------------
titulo "1. Wi-Fi (capa 1-2)"
MIIP=""
if tiene termux-wifi-connectioninfo; then
  if run "wifi" timeout 10 termux-wifi-connectioninfo && [[ -n "$SALIDA_CMD" ]]; then
    SSID=$(sed -n 's/.*"ssid": *"\([^"]*\)".*/\1/p' <<<"$SALIDA_CMD" | head -1)
    RSSI=$(sed -n 's/.*"rssi": *\(-\?[0-9]*\).*/\1/p' <<<"$SALIDA_CMD" | head -1)
    MIIP=$(sed -n 's/.*"ip": *"\([0-9.]*\)".*/\1/p' <<<"$SALIDA_CMD" | head -1)
    FREQ=$(sed -n 's/.*"frequency_mhz": *\([0-9]*\).*/\1/p' <<<"$SALIDA_CMD" | head -1)
    if [[ -z "$RSSI" ]]; then resultado "Wi-Fi" "NO SE PUDO" "sin datos (permiso de Ubicacion para Termux:API? Wi-Fi apagado?)"
    elif (( RSSI >= -60 )); then resultado "Wi-Fi" OK "${SSID:-?} senal $RSSI dBm (buena), ${FREQ:-?} MHz"
    elif (( RSSI >= -70 )); then resultado "Wi-Fi" AVISO "${SSID:-?} senal $RSSI dBm (aceptable), ${FREQ:-?} MHz"
    else resultado "Wi-Fi" FALLA "${SSID:-?} senal $RSSI dBm (mala): acercate al AP o cambia de banda"; cortar_si_falla; fi
  else resultado "Wi-Fi" "NO SE PUDO" "termux-wifi-connectioninfo no respondio (app Termux:API instalada?)"; fi
else
  resultado "Wi-Fi" "NO SE PUDO" "sin termux-api: no se mide la senal (pkg install termux-api + app Termux:API)"
fi

# ---------------- 2. IP ----------------
if [[ $CORTAR -eq 0 ]]; then
  titulo "2. Direccionamiento (capa 3)"
  if [[ -z "$MIIP" || "$MIIP" == "0.0.0.0" ]] && tiene python3; then
    MIIP=$(python3 -c "import socket;s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);s.connect(('$IPEXT',9));print(s.getsockname()[0])" 2>/dev/null)
  fi
  if [[ -z "$MIIP" || "$MIIP" == "0.0.0.0" ]]; then resultado "IP" FALLA "sin IP IPv4 (Wi-Fi desconectado o sin DHCP)"; cortar_si_falla
  elif [[ "$MIIP" == 169.254.* ]]; then resultado "IP" FALLA "$MIIP es APIPA: no hay DHCP"; cortar_si_falla
  else resultado "IP" OK "$MIIP"; fi
  if [[ -z "$GATEWAY" ]]; then GATEWAY=$(getprop dhcp.wlan0.gateway 2>/dev/null); fi
  if [[ -z "$GATEWAY" && "$MIIP" == *.*.*.* ]]; then GATEWAY="${MIIP%.*}.1"; GWEST=" (ESTIMADO: pasalo con --gateway)"; fi
  if [[ -n "$GATEWAY" ]]; then resultado "Gateway" OK "$GATEWAY${GWEST:-}"
  else resultado "Gateway" FALLA "no se pudo determinar"; cortar_si_falla; fi
fi

# ---------------- 3. Escalera de ping ----------------
ping_a() { # etiqueta destino -> 0 ok
  tiene ping || { resultado "$1" "NO SE PUDO" "no esta ping"; return 2; }
  if run "ping $2" ping -c 3 -W 2 "$2"; then
    local perd; perd=$(grep -oE '[0-9.]+% packet loss' <<<"$SALIDA_CMD")
    local rtt; rtt=$(sed -n 's/^rtt .* = [0-9.]*\/\([0-9.]*\)\/.*/\1/p' <<<"$SALIDA_CMD")
    resultado "$1" OK "$2 responde (${perd:-?}, rtt medio ${rtt:-?} ms)"; return 0
  fi
  resultado "$1" FALLA "$2 no responde (OJO: ICMP puede estar bloqueado; confirmar con el paso de puertos)"; return 1
}
if [[ $CORTAR -eq 0 ]]; then
  titulo "3. Escalera de ping"
  ping_a "Ping 1: loopback" 127.0.0.1 || cortar_si_falla
  [[ $CORTAR -eq 0 ]] && { ping_a "Ping 2: mi IP" "$MIIP" || cortar_si_falla; }
  [[ $CORTAR -eq 0 ]] && { ping_a "Ping 3: gateway" "$GATEWAY" || cortar_si_falla; }
  [[ $CORTAR -eq 0 ]] && ping_a "Ping 4: Internet por IP" "$IPEXT"
  [[ $CORTAR -eq 0 ]] && ping_a "Ping 5: Internet por nombre" "$DESTINO"
fi

# ---------------- 4. Ruta ----------------
if [[ $CORTAR -eq 0 ]]; then
  titulo "4. Ruta"
  if tiene traceroute; then
    run "traceroute" timeout 40 traceroute -n -m 15 -w 2 "$IPEXT"
    SALTOS=$(grep -cE '^ *[0-9]+ ' <<<"$SALIDA_CMD")
    if grep -qE ' (\*\s*){3}$' <<<"$SALIDA_CMD"; then resultado "Ruta" AVISO "$SALTOS saltos; hay saltos sin respuesta (normal en muchos routers; ver crudo)"
    else resultado "Ruta" OK "$SALTOS saltos hasta $IPEXT"; fi
  else resultado "Ruta" "NO SE PUDO" "no esta traceroute"; fi
fi

# ---------------- 5. DNS ----------------
if [[ $CORTAR -eq 0 ]]; then
  titulo "5. DNS"
  if tiene dig; then
    run "dig sistema" dig +short +time=3 +tries=1 "$DESTINO"; A1=$(head -1 <<<"$SALIDA_CMD")
    run "dig $DNSREF" dig +short +time=3 +tries=1 "@$DNSREF" "$DESTINO"; A2=$(head -1 <<<"$SALIDA_CMD")
    if [[ -n "$A1" && -n "$A2" ]]; then resultado "DNS" OK "sistema y $DNSREF resuelven $DESTINO"
    elif [[ -z "$A1" && -n "$A2" ]]; then resultado "DNS" FALLA "el DNS del sistema NO resuelve pero $DNSREF si: problema del DNS configurado"
    elif [[ -z "$A1" && -z "$A2" ]]; then resultado "DNS" FALLA "ninguno resuelve (revisar salida a UDP/53 o nombre mal escrito)"
    else resultado "DNS" AVISO "el sistema resuelve y $DNSREF no (UDP/53 externo bloqueado?)"; fi
  else resultado "DNS" "NO SE PUDO" "no esta dig (paquete dnsutils / bind9-dnsutils)"; fi
fi

# ---------------- 6. Puerto TCP ----------------
if [[ $CORTAR -eq 0 ]]; then
  titulo "6. Puerto TCP"
  run "tcp $DESTINO:$PUERTO" timeout 5 bash -c "exec 3<>/dev/tcp/$DESTINO/$PUERTO"; rc=$?
  if [[ $rc -eq 0 ]]; then resultado "Puerto $PUERTO" OK "$DESTINO acepta conexiones (servicio escuchando)"
  elif [[ $rc -eq 124 ]]; then resultado "Puerto $PUERTO" FALLA "timeout: firewall que descarta o host inalcanzable"
  elif grep -qi "refused" <<<"$SALIDA_CMD"; then resultado "Puerto $PUERTO" FALLA "rechazado: el host responde pero el servicio no escucha"
  else resultado "Puerto $PUERTO" FALLA "no se pudo conectar (ver crudo)"; fi
fi

# ---------------- 7. Servicio ----------------
if [[ $CORTAR -eq 0 ]]; then
  titulo "7. Servicio (capa 7)"
  if tiene curl; then
    if run "curl" curl -sS -o /dev/null -m 10 -w '%{http_code} %{time_total}' "$URL"; then
      COD=${SALIDA_CMD%% *}; TIEMPO=${SALIDA_CMD##* }
      case $COD in
        2??|3??) resultado "Servicio" OK "HTTP $COD en ${TIEMPO}s" ;;
        *) resultado "Servicio" FALLA "HTTP $COD (problema en servidor o aplicacion)" ;;
      esac
    else resultado "Servicio" FALLA "curl fallo: $(head -c 120 <<<"$SALIDA_CMD")"; fi
  else resultado "Servicio" "NO SE PUDO" "no esta curl"; fi
fi

# ---------------- 8. Rendimiento (opcional) ----------------
if [[ $CORTAR -eq 0 && -n "$IPERF" ]]; then
  titulo "8. Rendimiento"
  if tiene iperf3; then
    if run "iperf3" timeout 40 iperf3 -c "$IPERF" -t 10; then
      V=$(grep -E 'sender|receiver' <<<"$SALIDA_CMD" | tail -2 | tr -s ' ' | tr '\n' ' ')
      resultado "iperf3" OK "${V:-ver crudo}"
    else resultado "iperf3" FALLA "no conecto a $IPERF (servidor encendido? puerto 5201?)"; fi
  else resultado "iperf3" "NO SE PUDO" "no esta iperf3"; fi
fi

# ---------------- Reporte ----------------
{
  echo "# Reporte de diagnostico de red (movil)"
  echo
  echo "- **Fecha:** $(date '+%Y-%m-%d %H:%M:%S %z')"
  echo "- **Equipo:** $(hostname) ($(uname -sr))"
  echo "- **Interfaz / IP / Gateway:** Wi-Fi / ${MIIP:-?} / ${GATEWAY:-?}"
  echo "- **Destino de prueba:** $DESTINO:$PUERTO"
  echo "- **Herramienta:** NetLab Profesional v$VERSION"
  echo
  echo "## Resumen"
  echo
  echo "| Paso | Estado | Detalle |"
  echo "|---|---|---|"
  for i in "${!RES_PASO[@]}"; do echo "| ${RES_PASO[$i]} | **${RES_ESTADO[$i]}** | ${RES_DET[$i]//|/\\|} |"; done
  echo
  if [[ $CORTAR -eq 1 ]]; then echo "> El diagnostico se **corto** en la primera capa con falla; los pasos siguientes no se ejecutaron."; echo; fi
  echo "## Para escalar"
  echo
  echo "- Primer paso que falla: ______"
  echo "- Que se probo para descartar: ______"
  echo "- Salida cruda de cada comando: \`$RAW\`"
  echo
  echo "> Revisar a mano cualquier FALLA antes de concluir: ICMP o puertos filtrados pueden dar falsos positivos."
} > "$MD"

echo
echo "${B}Reporte:${N} $MD"
echo "${B}Salida cruda:${N} $RAW"
[[ $HAY_FALLA -eq 1 ]] && exit 1
[[ $INCOMPLETO -eq 1 ]] && exit 3
exit 0
