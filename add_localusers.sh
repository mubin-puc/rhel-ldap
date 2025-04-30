#!/bin/bash

USER_FILE="users.txt"

while IFS=: read -r username password; do
  if id "$username" &>/dev/null; then
    echo "[INFO] User '$username' already exists. Skipping."
  else
    useradd -m "$username"
    echo "$username:$password" | chpasswd
    echo "[SUCCESS] Created user: $username"
  fi
done < "$USER_FILE"

