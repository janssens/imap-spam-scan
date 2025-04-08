# 🕵️‍♂️ imap-spam-scan

Script Perl pour scanner une boîte mail IMAP à distance avec [SpamAssassin](https://spamassassin.apache.org/), apprendre des spams, et archiver les résultats dans une base SQLite. Le tout s'exécute dans un conteneur Docker autonome incluant Razor, Pyzor, DCC et les bibliothèques nécessaires.
Merci à David Maisonave pour le [script Perl](https://framagit.org/kepon/vrac/-/blob/master/imapSpamScan.pl?ref_type=heads) initial.

---

## 🚀 Fonctionnalités

- Connexion à une boîte mail distante via IMAP
- Analyse des messages avec SpamAssassin
- Apprentissage de nouveaux SPAMs en specialisant le dossier
- Persistance des résultats dans SQLite
- Support de :
  - **Razor**
  - **Pyzor**
  - **DCC**
- Configuration personnalisable de SpamAssassin
- Déploiement simple via Docker Compose

---

## 🧱 Structure du projet

```
.
├── Dockerfile                # Image Debian + Perl + SpamAssassin + outils
├── docker-compose.yml        # Lancement de l'image avec montages
├── imapSpamScan.pl           # Script principal (modifiable depuis l'hôte)
├── imapspamscan.db           # Base SQLite persistante
├── spamassassin/             # Configs SpamAssassin (v310.pre, local.cf)
└── README.md                 # this file

---

## 🐳 Lancer le projet

### 1. Construire l’image Docker

```bash
docker compose build
```

### 2. Exécuter le script avec des arguments

```bash
docker compose run spam-scan -help
```

Tu peux passer n’importe quel argument à `imapSpamScan.pl`.

---

## ⚙️ Configuration

### 📁 Configs SpamAssassin

Les fichiers `local.cf` et `v310.pre` sont montés depuis le dossier `./spamassassin` et sont donc facilement modifiables sans rebuild.

### 🗃️ Base SQLite

La base est stockée dans `./imapspamscan.db`. Ce fichier est monté en volume dans le container et doit être **accessible en écriture**.

---

## 📥 Dépendances techniques

- Debian (latest)
- Perl
- libmail-imapclient-perl
- libmail-spamassassin-perl
- libdbi-perl, libdbd-sqlite3-perl
- SpamAssassin
- Razor, Pyzor, DCC

---

## 📜 Licence

MIT – Tu peux en faire ce que tu veux !

---

## 🤝 Contribuer

Suggestions et pull requests bienvenus 🙌