FROM alpine:latest

RUN apk update && \
    apk add \
    bind-tools \
    chromium \
    curl \
    diffutils \
    go \
    jq \
    nmap \
    nmap-ncat \
    nmap-nselibs \
    nmap-scripts \
    python3

RUN wget https://github.com/OWASP/Amass/releases/download/v3.4.4/amass_v3.4.4_linux_amd64.zip && \
    unzip -j amass_v3.4.4_linux_amd64.zip amass_v3.4.4_linux_amd64/amass -d /usr/local/bin && \
    rm amass_v3.4.4_linux_amd64.zip

RUN wget https://github.com/maurosoria/dirsearch/archive/v0.3.9.zip && \
    unzip v0.3.9.zip -d /opt/ && \
    ln -s /opt/dirsearch-0.3.9/dirsearch.py /usr/local/bin/dirsearch.py && \
    rm v0.3.9.zip

COPY recon.sh /usr/local/bin/recon.sh

CMD [ "/usr/local/bin/recon.sh" ]