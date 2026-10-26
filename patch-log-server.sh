#!/bin/bash
# Descarga /usr/sbin/log-server del robot, lo parchea, comprueba hashes, lo sube y lo reinicia.
set -euo pipefail
cd "$(dirname "$0")"
ORIG=2dc3555fa39ca783ce767716033f26791a0682586a2b3daec90a0335678ebcb9
PATCHED=1f03acb1313f089207059b7e14cb480270c39d22cb4d70351ea9d6b076784f8c
f=$(mktemp); trap 'rm -f "$f"' EXIT

echo "1/5 Descargando /usr/sbin/log-server del robot ${CONGA_IP:-}..."
./conga-ssh.sh 'cat /usr/sbin/log-server' > "$f"
sum=$(sha256sum "$f" | cut -d' ' -f1)
[ "$sum" = "$PATCHED" ] && { echo "Ya está parcheado. Nada que hacer."; exit 0; }
[ "$sum" = "$ORIG" ] || { echo "Hash inesperado ($sum): ¿otro firmware? No toco nada." >&2; exit 1; }
echo "    sha256 original correcto."

echo "2/5 Parcheando..."
patch() { printf "$2" | dd of="$f" bs=1 seek=$(($1)) conv=notrunc status=none; }
patch 0x68890 '\x3d\x01\x00\xea'  # freeSpace: tras borrar .gz, return (sin pasadas 2 y 3)
patch 0x66f60 '\x1e\x00\x00\xea'  # initialize: nunca vaciar la carpeta al arrancar
patch 0x693c0 '\x05\x2a\xa0\xe3'  # TOption: objetivo de limpieza 10 MB -> 20 MB
sum=$(sha256sum "$f" | cut -d' ' -f1)
[ "$sum" = "$PATCHED" ] || { echo "El parche no da el hash esperado ($sum)." >&2; exit 1; }
echo "    sha256 parcheado correcto."

md5=$(md5sum "$f" | cut -d' ' -f1)
echo "3/5 Subiendo e instalando (solo si llega entero)..."
old=$(./conga-ssh.sh "set -e; cd /usr/sbin; cat > log-server.new; [ \"\$(md5sum < log-server.new)\" = '$md5  -' ]
  chmod 755 log-server.new; mv log-server.new log-server; sync; pidof log-server" < "$f")
echo "    Instalado. Proceso en marcha: PID $old (binario viejo)."

echo "4/5 Parando PID $old; Monitor lo relanzará..."
./conga-ssh.sh "kill $old"

echo "5/5 Esperando al proceso nuevo..."
# Hasta que Monitor lo recoge, pidof aún ve al viejo (zombi, sin /proc/<pid>/exe): reintentar.
new=$(./conga-ssh.sh "for i in \$(seq 30); do p=\$(pidof log-server)
  [ -n \"\$p\" ] && [ \"\$p\" != $old ] && [ \"\$(md5sum 2>/dev/null < /proc/\$p/exe)\" = '$md5  -' ] && { echo \$p; exit; }
  sleep 1; done; exit 1") || { echo "log-server no corre con el binario nuevo." >&2; exit 1; }
echo "OK: log-server parcheado y en marcha (PID $old -> $new)."
