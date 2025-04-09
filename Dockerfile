FROM debian:latest

ENV DEBIAN_FRONTEND=noninteractive

RUN apt update && apt install -y \
    spamassassin \
    razor \
    pyzor \
    libmail-imapclient-perl \
    libmail-spamassassin-perl \
    libdbi-perl \
    libdbd-sqlite3-perl \
    perl \
    curl \
    vim \
    && apt clean

# Install dcc-client
RUN mkdir temp && \
    curl https://www.dcc-servers.net/dcc/source/dcc.tar.Z | tar xzC temp && \
    cd temp && \
    cd * && CFLAGS="-O2 -fstack-protector" DCC_CFLAGS="-O2 -fstack-protector" ./configure && \ 
    make && \
    make install && \
    cd ../../ && \ 
    rm -r temp


# Création des dossiers Razor/Pyzor
RUN mkdir -p /home/spam/.razor /home/spam/.pyzor

# Initialisation Razor & Pyzor
RUN razor-admin -create && razor-admin -register && pyzor discover

# Copie config SA
COPY spamassassin/* /etc/spamassassin/

# Répertoire de travail (où sera monté ton script)
WORKDIR /opt/app
