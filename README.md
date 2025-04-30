

---

```markdown
# 🛠️ Offline LDAP Server & Client Setup for RHEL (5 to 8)

This guide explains how to set up an **LDAP server and client offline** using pre-downloaded RPMs on RHEL/CentOS systems from version 5 to 8. It includes instructions for generating RPMs, directory structure, and configuring `setup1.sh`.

---

## 📁 Directory Structure

Place all required files under `/root` on your target machines:

```
/root/
├── setup1.sh                # Main setup script for server or client
├── add_user.sh              # Script to add LDAP users
├── restrict_to_ldap_only.sh # Optional: deny local logins
└── ldap_rpms/               # Pre-downloaded RPMs go here
    ├── openldap-servers-*.rpm
    ├── sssd-*.rpm
    └── ...others
```

---

## 📦 How to Generate Required RPMs

Perform this step **on an internet-connected RHEL 7+ system**:

### 🔹 For LDAP Server:
```bash
mkdir -p ~/ldap_rpms_server
cd ~/ldap_rpms_server

yumdownloader --resolve --archlist=x86_64 \
  openldap-servers openldap-clients migrationtools openldap
```

### 🔹 For LDAP Client:
```bash
mkdir -p ~/ldap_rpms_client
cd ~/ldap_rpms_client

yumdownloader --resolve --archlist=x86_64 \
  sssd sssd-ldap sssd-common sssd-client \
  libsss_idmap libsss_nss_idmap libsss_sudo libsss_autofs
```

### ❗ Important:

Ensure **no `.i686.rpm` (32-bit)** packages are included:

```bash
find . -name "*.i686.rpm" -delete
```

Then **copy all RPMs** to the offline machine at:
```
/root/ldap_rpms/
```

---

## 🚀 Using `setup1.sh`

### ✅ Make Executable:

```bash
chmod +x setup1.sh
```

### ✅ Run as Server:

```bash
./setup1.sh server
```

This will:
- Install OpenLDAP and dependencies
- Configure slapd with suffix `dc=corp,dc=local`
- Create admin user: `cn=Manager,dc=corp,dc=local` with password `admin123`
- Load required schemas (inetOrgPerson, cosine, nis)

### ✅ Run as Client:

```bash
./setup1.sh client
```

This will:
- Install SSSD and LDAP tools
- Generate `/etc/sssd/sssd.conf`
- Connect to LDAP server at `ldap://10.0.0.4`
- Enable home directory auto-creation
- Configure NSS and PAM

---

## ✏️ What to Edit in `setup1.sh`

Open `setup1.sh` and update these variables as needed:

```bash
LDAP_BASE="dc=corp,dc=local"
ADMIN_DN="cn=Manager,dc=corp,dc=local"
ADMIN_PASS="admin123"
LDAP_SERVER_IP="10.0.0.4"     # IP of the LDAP server
```

Optional:
```bash
# For firewall (add if using firewalld)
firewall-cmd --permanent --add-port=389/tcp
firewall-cmd --reload
```

---

## ➕ Adding Users

Use `add_user.sh` to add a user:

```bash
./add_user.sh <username> <numeric_password>
```

Example:
```bash
./add_user.sh mubin 23456
```

---

## 🔒 Restrict Logins to LDAP Users Only

To allow **only `root` and LDAP users**, and deny all local users:

```bash
./restrict_to_ldap_only.sh
```

---

## ✅ Verify From Client

```bash
getent passwd mubin     # Should return LDAP user info
su - mubin              # Should log in as LDAP user
```

To enable home directory creation:
```bash
authconfig --enablemkhomedir --update
```

---

## 🧪 Troubleshooting

| Check                     | Command                                      |
|--------------------------|----------------------------------------------|
| LDAP server is running   | `systemctl status slapd`                     |
| SSSD is working          | `systemctl status sssd`                      |
| LDAP base DN exists      | `ldapsearch -Y EXTERNAL -H ldapi:/// -b "dc=corp,dc=local"` |
| Login attempts           | `tail -f /var/log/secure`                    |
| See loaded schemas       | `ldapsearch -Y EXTERNAL -H ldapi:/// -b "cn=schema,cn=config"` |

---

## 🔁 Optional Cleanup

```bash
yum remove openldap* sssd*
rm -rf /etc/openldap /etc/sssd /var/lib/ldap /etc/security/access.conf
```

---

## 📌 Notes

- Default LDAP admin DN: `cn=Manager,dc=corp,dc=local`
- Default admin password: `admin123`
- Make sure DNS or `/etc/hosts` resolves `ldap.corp.local` if used

---

## 🧩 Future Enhancements

- Add script to delete LDAP users
- Add support for TLS/LDAPS
- Add bulk import from CSV

---
```

Let me know if you want this exported as a `.md` file or added to your GitHub repo structure.
