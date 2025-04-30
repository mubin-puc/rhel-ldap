#!/bin/bash
ROLE=$1  # Must be either: server or client

# ========= CONFIG ========= #
RPM_DIR="/root/ldap_rpms"
LDAP_DOMAIN="corp.local"
LDAP_BASE_DN="dc=corp,dc=local"
LDAP_ADMIN_DN="cn=Manager,$LDAP_BASE_DN"
LDAP_ADMIN_PASS="admin123"
LDAP_SERVER_IP="10.0.0.4"
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
  echo "[INFO] Creating DB_CONFIG file for optimal performance..."
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
  echo "[INFO] Wiping LDAP database for clean install..."
  systemctl stop slapd || service slapd stop
  rm -rf "$DB_DIR"/*
  create_db_config_file
  chown -R ldap:ldap "$DB_DIR"
  echo "[INFO] Database wiped and prepared."
}

configure_server() {
  echo "[INFO] Configuring LDAP server..."

  systemctl enable slapd --now 2>/dev/null || service slapd start

  HASHED_PASS=$(slappasswd -s "$LDAP_ADMIN_PASS")
  if [[ -z "$HASHED_PASS" ]]; then
    echo "[ERROR] Failed to generate hashed password"
    exit 1
  fi

  echo "[INFO] Applying olcSuffix and admin DN config..."

  cat > /tmp/db_config.ldif <<EOF
dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcSuffix
olcSuffix: $LDAP_BASE_DN

dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcRootDN
olcRootDN: $LDAP_ADMIN_DN

dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcRootPW
olcRootPW: $HASHED_PASS
EOF

  ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/db_config.ldif || {
    echo "[ERROR] Failed to apply DB config"
    exit 1
  }

  echo "[INFO] Restarting slapd to apply DB changes..."
  systemctl restart slapd || service slapd restart

  echo "[INFO] Waiting for slapd to reload changes..."
  sleep 3

  if ldap_entry_exists "$LDAP_BASE_DN"; then
    echo "[INFO] LDAP base DN already exists. Skipping base.ldif."
  else
    echo "[INFO] Creating base DN structure using slapadd..."

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

    systemctl stop slapd || service slapd stop

    echo "[INFO] Injecting base DN into database using slapadd..."
    slapadd -n 2 -l /tmp/base.ldif || {
      echo "[ERROR] slapadd failed"
      exit 1
    }

    echo "[INFO] Restoring permissions..."
    chown -R ldap:ldap "$DB_DIR"

    systemctl start slapd || service slapd start

    echo "[INFO] Base DN entries created successfully."
  fi
}

configure_client() {
  echo "[INFO] Configuring LDAP client with SSSD..."

  mkdir -p /etc/sssd
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
  authconfig --enablesssd --enablesssdauth --enablemkhomedir --update
  systemctl enable sssd --now 2>/dev/null || service sssd start

  echo "[INFO] LDAP client configured successfully."
}

# ---------- MAIN EXECUTION ---------- #
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

echo "[SUCCESS] LDAP $ROLE setup (Step 1) completed successfully."

