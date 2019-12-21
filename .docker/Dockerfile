FROM clearlinux:latest
LABEL maintainer="murilo.belluzzo@intel.com"

RUN swupd bundle-add --quiet make network-basic mixer clr-installer sudo
RUN swupd clean --all --quiet

ARG UID=1000

RUN useradd -G wheelnopw --uid ${UID} -U -m action

USER action

RUN git config --global user.email "action@ci-container.com"
RUN git config --global user.name "Action"

WORKDIR /mnt
