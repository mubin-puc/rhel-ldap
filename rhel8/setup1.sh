#!/bin/bash
ROLE=$1  # server or client

# ========= CONFIG ========= #
RPM_DIR="/root/ldap_rpms"
LDAP_DOMAIN="corp.local"
LDAP_BASE_DN="dc=corp,dc=local"
LDAP_ADMIN_DN="cn=Manager,$LDAP_BASE_DN"
LDAP_ADMIN_PASS="admin123"
LDAP_SERVER_IP="10.0.0.6"
LDAP_CLIENT_IP="10.0.0.5"
DB_DIR="/var/lib/ldap"
# ========================== #

if [[ "$EUID" -ne 0 ]]; then
  echo "[ERROR] Run this script as root"
  exit 1
fi

setup_hosts() {
  echo "[INFO] Updating /etc/hosts..."
  grep -q "ldap.$LDAP_DOMAIN" /etc/hosts || echo "$LDAP_SERVER_IP ldap.$LDAP_DOMAIN" >> /etc/hosts
  grep -q "client.$LDAP_DOMAIN" /etc/hosts || echo "$LDAP_CLIENT_IP client.$LDAP_DOMAIN" >> /etc/hosts
}

install_rpms_offline() {
  echo "[INFO] Installing RPMs from $RPM_DIR..."
  if [ ! -d "$RPM_DIR" ]; then
    echo "[ERROR] RPM directory $RPM_DIR not found"
    exit 1
  fi
  rpm -Uvh --quiet --force --nosignature "$RPM_DIR"/*.rpm || {
    echo "[ERROR] Failed to install RPMs from $RPM_DIR"
    exit 1
  }
}

ldap_entry_exists() {
  ldapsearch -Y EXTERNAL -H ldapi:/// -b "$1" -s base dn > /dev/null 2>&1
  return $?
}

create_db_config_file() {
  echo "[INFO] Creating DB_CONFIG file..."
  cat > "$DB_DIR/DB_CONFIG" <<EOF
set_cachesize 0 10485760 1
set_lg_regionmax 262144
set_lg_bsize 2097152
set_flags DB_LOG_AUTOREMOVE
EOF
  chown ldap:ldap "$DB_DIR/DB_CONFIG"
  chmod 640 "$DB_DIR/DB_CONFIG"
}

wipe_ldap_database() {
  echo "[INFO] Wiping LDAP database..."
  systemctl stop slapd || service slapd stop
  rm -rf "$DB_DIR"/*
  create_db_config_file
  chown -R ldap:ldap "$DB_DIR"
}

configure_server() {
  echo "[INFO] Configuring LDAP server..."
  systemctl enable slapd --now || service slapd start

  DB_DN=$(ldapsearch -Y EXTERNAL -H ldapi:/// -LLL -b cn=config '(objectClass=olcMdbConfig)' dn | awk '/^dn: /{print $2}')
  if [[ -z "$DB_DN" ]]; then
    echo "[ERROR] Cannot detect MDB database DN"
    exit 1
  fi

  HASHED_PASS=$(slappasswd -s "$LDAP_ADMIN_PASS")

  cat > /tmp/db_config.ldif <<EOF
dn: $DB_DN
changetype: modify
replace: olcSuffix
olcSuffix: $LDAP_BASE_DN

dn: $DB_DN
changetype: modify
replace: olcRootDN
olcRootDN: $LDAP_ADMIN_DN

dn: $DB_DN
changetype: modify
replace: olcRootPW
olcRootPW: $HASHED_PASS
EOF

  ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/db_config.ldif || {
    echo "[ERROR] Failed to apply DB config"
    exit 1
  }

  echo "[INFO] Restarting slapd..."
  systemctl restart slapd
  sleep 3

  if ldap_entry_exists "$LDAP_BASE_DN"; then
    echo "[INFO] Base DN exists, skipping."
  else
    echo "[INFO] Adding base DN..."

    cat > /tmp/base.ldif <<EOF
dn: $LDAP_BASE_DN
objectClass: top
objectClass: dcObject
objectClass: organization
o: CORP Directory
dc: corp

dn: cn=Manager,$LDAP_BASE_DN
objectClass: organizationalRole
cn: Manager
description: LDAP Administrator
EOF

    ldapadd -x -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASS" -f /tmp/base.ldif || {
      echo "[ERROR] Failed to add base DN"
      exit 1
    }
  fi
}

configure_client() {
  echo "[INFO] Configuring LDAP client with SSSD..."

  mkdir -p /etc/sssd /etc/sssd/conf.d
  echo "# dummy config" > /etc/sssd/conf.d/sssd-dummy.conf

  cat > /etc/sssd/sssd.conf <<EOF
[sssd]
domains = $LDAP_DOMAIN
services = nss, pam

[domain/$LDAP_DOMAIN]
id_provider = ldap
auth_provider = ldap
ldap_uri = ldap://ldap.$LDAP_DOMAIN
ldap_search_base = $LDAP_BASE_DN
ldap_default_bind_dn = $LDAP_ADMIN_DN
ldap_default_authtok = $LDAP_ADMIN_PASS
enumerate = true
cache_credentials = true
ldap_tls_reqcert = allow
EOF

  chmod 600 /etc/sssd/sssd.conf

  echo "[INFO] Running authconfig..."
  authconfig --enablesssd --enablesssdauth --enablemkhomedir --update

  echo "[INFO] Starting SSSD..."
  systemctl daemon-reexec
  systemctl daemon-reload
  systemctl restart sssd
  systemctl enable sssd

  echo "[INFO] Validating SSSD status..."
  if systemctl is-active --quiet sssd; then
    echo "[SUCCESS] SSSD is active."
  else
    echo "[ERROR] SSSD failed to start. Check logs:"
    journalctl -xeu sssd | tail -n 20
    exit 1
  fi
}

# ---------- MAIN ---------- #
setup_hosts
install_rpms_offline

case "$ROLE" in
  server)
    wipe_ldap_database
    configure_server
    ;;
  client)
    configure_client
    ;;
  *)
    echo "[ERROR] Usage: $0 server|client"
    exit 1
    ;;
esac

echo "[SUCCESS] LDAP $ROLE setup completed successfully."
