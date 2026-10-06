# NetLab Profesional

Dos scripts que recorren la [checklist de diagnóstico](https://github.com/2008calvin-sudo/netlab/blob/main/manuales/checklist-diagnostico.md) **de forma automática** y generan un reporte listo para escalar:

| Script | Dónde corre |
|---|---|
| `Diagnostico_pc.sh` | PC con Linux (probado en Kali Purple) |
| `Diagnostico_movil.sh` | Termux / NetHunter **sin root** |

Repositorios hermanos: [netlab](https://github.com/2008calvin-sudo/netlab) (menús para estudiantes y manuales) · [netlab-termux](https://github.com/2008calvin-sudo/netlab-termux) (versión móvil para estudiantes).

> ## ⚠️ Solo para profesionales
> **Si estás aprendiendo, no empieces por acá.** Usá la [checklist manual](https://github.com/2008calvin-sudo/netlab/blob/main/manuales/checklist-diagnostico.md) y los menús de [netlab](https://github.com/2008calvin-sudo/netlab).
>
> Un script automático **esconde los pasos**. Cuando algo sale mal, quien lo usa tiene que saber distinguir entre *"la red está mal"* y *"el script o la herramienta falló"*, repetir el paso a mano y, si hace falta, corregir el script. **Regla práctica: si no podrías hacer cada paso a mano, usá la checklist manual primero.**

> **Origen:** diseñado y mantenido por un estudiante de redes, con Claude (IA de Anthropic) como asistente de programación. **Estado: v0.1.0.** Probados solo con herramientas simuladas: **pendientes de prueba en una red real y en un teléfono real**. Ver *Estado de las pruebas*.

## Qué hacen

Recorren en orden y se **cortan en la primera capa que falla** (porque las siguientes dependen de ella; `--seguir` lo evita):

1. Entorno y herramientas disponibles
2. Enlace: interfaz y velocidad/duplex (PC) · señal Wi-Fi (móvil)
3. IP y gateway
4. Escalera de ping: loopback → mi IP → gateway → Internet por IP → por nombre
5. Ruta (`traceroute`)
6. DNS: el del sistema contra uno de referencia
7. Puerto TCP (distingue *rechazado* de *timeout*)
8. Servicio HTTP (`curl`)
9. Rendimiento con `iperf3` (opcional, con `--iperf`)

**No cambian ninguna configuración**: solo leen y miden. El script móvil no necesita root.

Estados de cada paso:

| Estado | Significa |
|---|---|
| **OK** | Pasó la prueba |
| **FALLA** | La prueba falló (verificá a mano antes de concluir) |
| **AVISO** | Algo a mirar, sin ser un fallo claro |
| **NO SE PUDO** | No se pudo medir (falta herramienta, permiso o el sistema lo restringe) |

## Uso

```bash
# PC
./Diagnostico_pc.sh                                   # valores por defecto
./Diagnostico_pc.sh -d servidor.local -p 22           # probar SSH a un servidor
./Diagnostico_pc.sh -d google.com -P 192.168.1.20     # + iperf3 contra otro equipo
./Diagnostico_pc.sh --ayuda

# Teléfono (Termux / NetHunter sin root)
bash Diagnostico_movil.sh -y
bash Diagnostico_movil.sh -d servidor.local -p 22 -g 192.168.1.1
```

Opciones: `-d` destino · `-p` puerto · `-g` gateway · `-e` IP externa · `-D` DNS de referencia · `-u` URL · `-P` servidor iperf3 · `-o` carpeta · `-s` seguir · `-y` sin confirmación.

**Códigos de salida** (útiles para usarlos en otros scripts): `0` todo OK · `1` hubo FALLA · `2` error de uso · `3` incompleto (algún paso NO SE PUDO).

## El reporte

En `~/netlab_reportes/` se guardan dos archivos por ejecución:

- `reporte_FECHA.md`: tabla resumen + datos para escalar (se pega directo en un ticket).
- `crudo_FECHA.txt`: **salida real de cada comando**. Es lo primero que hay que mirar si un resultado no tiene sentido.

## Qué puede fallar (y cómo revisarlo)

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Ping 3/4 **FALLA** pero hay Internet | ICMP bloqueado por firewall | Confirmar con el paso de puertos o `curl` |
| `NO SE PUDO` en una herramienta | No está instalada | Instalarla (`apt` / `pkg`) y repetir |
| `ethtool` **NO SE PUDO** (PC) | Necesita `sudo` | Ejecutar ese paso a mano con `sudo` |
| Gateway "ESTIMADO" (móvil) | Android no expone el dato | Pasarlo con `--gateway` |
| Wi-Fi **NO SE PUDO** (móvil) | Falta Termux:API o el permiso de Ubicación | Instalar la app Termux:API y darle permiso |
| DNS **FALLA** con ping a IP OK | UDP/53 bloqueado o el DNS configurado | Probar `dig @IP dominio` a mano |
| Un valor raro en un paso | Cambió el formato de salida de una herramienta | Mirar `crudo_*.txt` y ajustar la función de ese paso |

Esta lista la va a completar quien use el proyecto: si te pasa algo que no está acá, abrí un *issue*.

## Estado de las pruebas

| Script | Estado |
|---|---|
| `Diagnostico_pc.sh` | Sintaxis verificada y lógica probada con herramientas simuladas (caso OK, falla con corte, error de uso). **Pendiente: red real.** |
| `Diagnostico_movil.sh` | Igual, con `termux-wifi-connectioninfo` simulado. **Pendiente: teléfono real.** |

Cuando los pruebes en un equipo real, anotá acá la versión de Kali / Android y el resultado.

## Mantenimiento

Estos scripts no se actualizan solos. Rutina sugerida:

- **Una vez al año**, o al actualizar el sistema: correr cada script y revisar que ningún paso falle por motivos ajenos a la red (unos 20 minutos).
- **Al actualizar Kali, Termux o Android**: probar solo lo que usás.
- **Ante un *issue***: arreglar ese caso.
- **Antes de publicar un cambio**: `shellcheck Diagnostico_pc.sh Diagnostico_movil.sh`.
- Actualizar `VERSION` y la fecha del encabezado del script.

Lo que más cambia entre versiones es el **formato de salida** de las herramientas. Por eso los scripts usan códigos de salida cuando pueden, guardan la salida cruda y marcan `NO SE PUDO` en lugar de inventar un resultado.

## Licencia

MIT. Ver [LICENSE](LICENSE).
