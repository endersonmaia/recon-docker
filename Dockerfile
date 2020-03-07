FROM alpine:3.11

RUN apk update                          \
    && apk upgrade --force              \
    && apk add --no-cache               \
        bind-tools                      \
        chromium                        \
        curl                            \
        diffutils                       \
        jq                              \
        nmap                            \
        nmap-ncat                       \
        nmap-nselibs                    \
        nmap-scripts                    \
        python3                         \
    && pip3 install --upgrade pip       \
    && rm -rf /tmp/* /var/cache/apk/*

RUN wget https://github.com/OWASP/Amass/releases/download/v3.4.4/amass_v3.4.4_linux_amd64.zip \
    && unzip -j amass_v3.4.4_linux_amd64.zip amass_v3.4.4_linux_amd64/amass -d /usr/local/bin \
    && rm amass_v3.4.4_linux_amd64.zip

RUN wget https://github.com/maurosoria/dirsearch/archive/v0.3.9.zip         \
    && unzip v0.3.9.zip -d /opt/                                            \
    && ln -s /opt/dirsearch-0.3.9/dirsearch.py /usr/local/bin/dirsearch.py  \
    && rm v0.3.9.zip

RUN wget https://github.com/michenriksen/aquatone/releases/download/v1.7.0/aquatone_linux_arm64_1.7.0.zip   \
    && unzip aquatone_linux_arm64_1.7.0.zip aquatone -d /usr/local/bin                                      \
    && rm aquatone_linux_arm64_1.7.0.zip

RUN wget https://github.com/darkoperator/dnsrecon/archive/0.9.1.zip \
    && unzip 0.9.1.zip -d /opt/                                     \
    && apk add --virtual builder                                    \
        build-base                                                  \
        libxml2-dev                                                 \
        libxslt-dev                                                 \
        python3-dev                                                 \
    && pip3 install -r /opt/dnsrecon-0.9.1/requirements.txt         \
    && apk del builder                                              \
    && rm 0.9.1.zip                                                 \
    && rm -rf /tmp/* /var/cache/apk/*                               \
    && ln -s /opt/dnsrecon-0.9.1/dnsrecon.py /usr/local/bin/dnsrecon.py

COPY recon.sh /usr/local/bin/recon.sh

CMD [ "/usr/local/bin/recon.sh" ]