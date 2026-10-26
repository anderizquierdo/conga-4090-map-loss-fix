#!/bin/bash
# SSH al robot (root, contraseña genérica de fábrica). Uso: CONGA_IP=x.x.x.x ./conga-ssh.sh [comando]
# El robot solo ofrece ssh-rsa (SHA-1): sha1.cnf lo vuelve a permitir en Fedora/RHEL.
cd "$(dirname "$0")"
export SSHPASS='@3I#sc$RD%xm^2S&' OPENSSL_CONF="$PWD/sha1.cnf"
exec sshpass -e ssh -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa \
  -o PubkeyAuthentication=no -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 "root@${CONGA_IP:?Indica la IP del robot: CONGA_IP=x.x.x.x $0 ...}" "$@"
