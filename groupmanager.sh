#!/bin/bash

LDAP_BASE="dc=corp,dc=local"
LDAP_ADMIN_DN="cn=Manager,$LDAP_BASE"
LDAP_ADMIN_PASS="admin123"
LDAP_URI="ldap://localhost"

# Function: list existing groups
list_groups() {
  echo "[INFO] Existing LDAP groups:"
  ldapsearch -x -LLL -H $LDAP_URI -b "ou=Groups,$LDAP_BASE" "(objectClass=posixGroup)" cn | grep '^cn:' | awk '{print " -", $2}'
}

# Function: list existing users
list_users() {
  echo "[INFO] Existing LDAP users:"
  ldapsearch -x -LLL -H $LDAP_URI -b "ou=People,$LDAP_BASE" "(objectClass=posixAccount)" uid | grep '^uid:' | awk '{print " -", $2}'
}

# Prompt for group name
read -p "Enter the new group name to create: " GROUP_NAME
read -p "Enter GID Number for the group (e.g., 3000+): " GID_NUM

# Check and create ou=Groups if not present
ldapsearch -x -H $LDAP_URI -b "ou=Groups,$LDAP_BASE" dn >/dev/null 2>&1
if [ $? -ne 0 ]; then
  echo "[INFO] Creating 'ou=Groups' container..."
  cat <<EOF | ldapadd -x -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASS"
dn: ou=Groups,$LDAP_BASE
objectClass: organizationalUnit
ou: Groups
EOF
fi

# Create the group
echo "[INFO] Creating group '$GROUP_NAME' with gidNumber=$GID_NUM..."
cat <<EOF | ldapadd -x -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASS"
dn: cn=$GROUP_NAME,ou=Groups,$LDAP_BASE
objectClass: top
objectClass: posixGroup
cn: $GROUP_NAME
gidNumber: $GID_NUM
EOF

# Show groups
list_groups

# Show users
list_users

# Ask if user should be added to group
read -p "Do you want to add users to '$GROUP_NAME'? (y/n): " ADD_USERS
if [[ "$ADD_USERS" =~ ^[Yy]$ ]]; then
  read -p "Enter comma-separated usernames to add to the group: " USER_LIST
  IFS=',' read -ra USERS <<< "$USER_LIST"

  LDIF_FILE="/tmp/add_users_to_${GROUP_NAME}.ldif"
  echo "dn: cn=$GROUP_NAME,ou=Groups,$LDAP_BASE" > "$LDIF_FILE"
  echo "changetype: modify" >> "$LDIF_FILE"
  echo "add: memberUid" >> "$LDIF_FILE"

  for user in "${USERS[@]}"; do
    echo "memberUid: $(echo "$user" | xargs)" >> "$LDIF_FILE"
  done

  ldapmodify -x -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASS" -f "$LDIF_FILE" && \
    echo "[SUCCESS] Users added to group '$GROUP_NAME'."
  rm -f "$LDIF_FILE"
else
  echo "[INFO] Skipping user addition."
fi
