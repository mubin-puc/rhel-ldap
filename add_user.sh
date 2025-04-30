#!/bin/bash

USERNAME="$1"
NUMERIC_PASS="$2"

# LDAP Config
LDAP_BASE="dc=corp,dc=local"
LDAP_ADMIN_DN="cn=Manager,${LDAP_BASE}"
LDAP_ADMIN_PASS="admin123"
USER_DN="uid=${USERNAME},ou=People,${LDAP_BASE}"
OU_LDIF="/tmp/ou_people.ldif"
USER_LDIF="/tmp/user_${USERNAME}.ldif"

# --- Checks ---
if [ -z "$USERNAME" ] || [ -z "$NUMERIC_PASS" ]; then
  echo "Usage: $0 <username> <numeric_password>"
  exit 1
fi

# --- Ensure ou=People exists ---
ldapsearch -x -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASS" -b "ou=People,$LDAP_BASE" dn >/dev/null 2>&1
if [ $? -ne 0 ]; then
  echo "[INFO] Creating ou=People organizational unit..."
  cat > "$OU_LDIF" <<EOF
dn: ou=People,$LDAP_BASE
objectClass: organizationalUnit
ou: People
EOF
  ldapadd -x -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASS" -f "$OU_LDIF" || {
    echo "[ERROR] Failed to create ou=People"
    exit 1
  }
fi

# --- Create hashed password ---
HASHED_PASS=$(slappasswd -s "$NUMERIC_PASS")

# --- Build user LDIF ---
cat > "$USER_LDIF" <<EOF
dn: $USER_DN
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: posixAccount
cn: $USERNAME
sn: $USERNAME
displayName: $USERNAME
uid: $USERNAME
uidNumber: $(shuf -i 20000-29999 -n 1)
gidNumber: 1000
homeDirectory: /home/$USERNAME
loginShell: /bin/bash
userPassword: $HASHED_PASS
EOF

# --- Add user ---
echo "[INFO] Adding LDAP user: $USERNAME"
ldapadd -x -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASS" -f "$USER_LDIF" || {
  echo "[ERROR] Failed to add user: $USERNAME"
  exit 1
}

# --- Clean up ---
rm -f "$OU_LDIF" "$USER_LDIF"

echo "[SUCCESS] LDAP user '$USERNAME' added successfully."

