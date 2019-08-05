FROM clearlinux:latest
LABEL maintainer="murilo.belluzzo@intel.com"

RUN swupd bundle-add --quiet make network-basic mixer clr-installer
RUN swupd clean --quiet

ARG UID=1000

RUN useradd -G wheelnopw --uid ${UID} -U -m travis
RUN echo "%wheelnopw ALL=(ALL) NOPASSWD: ALL" > /usr/share/defaults/sudo/sudoers.d/wheelnopw

USER travis

RUN git config --global user.email "travis@ci-container.com"
RUN git config --global user.name "Travis"

WORKDIR /mnt
