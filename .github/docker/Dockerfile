FROM clearlinux:latest

RUN swupd bundle-add --quiet make network-basic mixer clr-installer sudo
RUN swupd clean --all --quiet

ARG UID=1000

RUN useradd -G wheelnopw --uid ${UID} -U -m github

USER github

RUN git config --global user.email "github@ci-container.com"
RUN git config --global user.name "Github Actions"

WORKDIR /mnt
