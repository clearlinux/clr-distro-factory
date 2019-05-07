HOSTNAME := $(shell hostname -f)
BUILD_DIR ?= $(CURDIR)/tmp/build
STAGING_DIR ?= $(CURDIR)/tmp/release
DSTREAM_DL_URL ?= http://${HOSTNAME}:8000/update

pipelines := common koji release watcher

common_CHECKOPTS := --exclude=2034,2164
common_SRC := $(wildcard *.sh)

koji_SRC := $(wildcard $(CURDIR)/koji/*.sh)

release_CHECKOPTS := --exclude=2013,2024,2155
release_SRC := $(wildcard $(CURDIR)/release/*.sh)

watcher_SRC := $(wildcard $(CURDIR)/watcher/*.sh)

SRC := $(common_SRC) $(koji_SRC) $(release_SRC) $(watcher_SRC)

release_STEPS := $(patsubst %.sh,%,$(notdir $(release_SRC)))

all:
	@echo "use 'make release' to run all steps'"
	@echo "use 'make STEP' to run individual steps: ${release_STEPS}"
	@echo "use 'make serve' to run a webserver hosting updates"

${BUILD_DIR}:
	mkdir -p $@

${STAGING_DIR}:
	mkdir -p $@

.PHONY: $(release_STEPS)
$(release_STEPS): ${BUILD_DIR} ${STAGING_DIR}
	BUILD_DIR=${BUILD_DIR} \
	STAGING_DIR=${STAGING_DIR} \
	DSTREAM_DL_URL=${DSTREAM_DL_URL} \
	release/$@.sh

.NOTPARALLEL: release
release: prologue koji content mixer images stage

.PHONY: serve
serve: ${STAGING_DIR}
	cd ${STAGING_DIR}; python -mSimpleHTTPServer

check_PIPELINES = $(addprefix check-,$(pipelines))
$(check_PIPELINES): pipe = $(patsubst check-%,%,$@)
$(check_PIPELINES):
	shellcheck -x $($(pipe)_CHECKOPTS) $($(pipe)_SRC)

check: $(check_PIPELINES)
