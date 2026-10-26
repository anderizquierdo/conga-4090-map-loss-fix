# conga-4090-map-loss-fix

Evita que una Cecotec Conga 4090 (firmware 3irobotix) pierda sus mapas guardados.

Solo está probado con `sysProduct=CECOTECCRL300` y `sysVersion=S3.3.8` (`/etc/sysconf/sysVersion.ini`). Otras Conga probablemente tengan el mismo fallo, pero el parche solo vale para este binario exacto. Con cualquier otro, el script no toca nada.

## El problema

El robot pierde el mapa de repente. En el log aparece `Can not load scheme file /mnt/UDISK/log/scheme_data.info<id>` y empieza un mapa nuevo.

## La causa

El proceso principal del robot (`everest-server`) guarda los mapas en la carpeta de logs. La ruta va fija en el binario y no se puede cambiar por configuración:

- `/mnt/UDISK/log/scheme_data.info<id>`: el mapa.
- `/mnt/UDISK/log/customer_map_list_path.plan`: las habitaciones.

El limpiador de logs (`/usr/sbin/log-server`) mira cada segundo lo que ocupa esa carpeta. Si pasa de 40 MB, borra ficheros hasta bajar de 10 MB, en tres pasadas:

1. Los `.gz`, es decir, los logs comprimidos.
2. Lo que no tenga nombre de log conocido. **Aquí caen los mapas.**
3. Todo lo que quede sin `.temp` en el nombre.

Además, si al arrancar la carpeta pasa de 40 MB, la vacía entera.

Los logs que se están escribiendo pueden sumar ~13 MB durante una limpieza: rotan a los ~5 MB y puede haber dos grandes a la vez. Entonces, aunque borre todos los `.gz`, la carpeta no baja de 10 MB y la pasada 2 se lleva el mapa. Las pasadas 2 y 3 apenas liberan espacio de verdad: los logs vivos están abiertos, así que borrarlos no libera nada hasta que se cierran.

## La solución

Sacar los mapas de esa carpeta obligaría a parchear el proceso principal, que es mucho más arriesgado. En su lugar se parchea el limpiador para que solo borre `.gz`:

| Offset | Original → nuevo | Efecto |
|---|---|---|
| `0x68890` | `af0000aa` → `3d0100ea` | Solo borra `.gz`: sin pasadas 2 y 3 |
| `0x66f60` | `1e00002a` → `1e0000ea` | No vacía la carpeta al arrancar |
| `0x693c0` | `0a2ba0e3` → `052aa0e3` | Limpia hasta 20 MB en vez de 10, por encima de los logs vivos |

```sh
CONGA_IP=192.168.1.50 ./patch-log-server.sh  # la IP de tu robot (obligatoria para todos los scripts)
```

El script descarga el binario del robot, comprueba su sha256, lo parchea y vuelve a comprobar el hash. Después lo instala y verifica que el proceso en marcha usa el binario nuevo. Si ya está parcheado, no hace nada.

Probado el 26-oct-2026 en tres casos:
- Tras un reinicio completo.
- Con 50 MB al arrancar.
- Con 50 MB con el robot en marcha.

En todos los casos solo borró `.gz` y el mapa quedó intacto.

Para deshacerlo: `/usr` es un overlay, así que el original sigue debajo.

```sh
CONGA_IP=192.168.1.50 ./conga-ssh.sh 'rm /overlay/usr/sbin/log-server && sync && reboot'
```

## Acceso SSH

Usuario `root`, contraseña `@3I#sc$RD%xm^2S&` (la genérica de fábrica). La IP del robot se pasa en `CONGA_IP`, que es obligatoria.

```sh
export CONGA_IP=192.168.1.50
./conga-ssh.sh                      # shell
./conga-ssh.sh 'ls /mnt/UDISK/log'  # comando
./conga-ssh.sh 'cat /ruta' > local  # copiar ficheros (scp necesitaría -O)
```

Necesita `sshpass`. El robot solo admite `ssh-rsa` (SHA-1), que Fedora/RHEL rechaza (`error in libcrypto`). `sha1.cnf` lo vuelve a permitir solo para esta conexión.

## Licencia

Scripts y documentación: dominio público ([The Unlicense](LICENSE)). El binario `log-server` es del fabricante y no se incluye. El parche se aplica sin garantía y bajo tu responsabilidad.
