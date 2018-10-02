STEPS := $(patsubst %.sh,%,$(notdir $(wildcard $(CURDIR)/release/*.sh)))

HOSTNAME := $(shell hostname -f)

BUILD_DIR ?= $(CURDIR)/tmp/build
STAGING_DIR ?= $(CURDIR)/tmp/release
DSTREAM_DL_URL ?= http://${HOSTNAME}:8000/update

all:
	@echo "use 'make release' to run all steps'"
	@echo "use 'make STEP' to run individual steps: ${STEPS}"
	@echo "use 'make serve' to run a webserver hosting updates"

${BUILD_DIR}:
	mkdir -p $@

${STAGING_DIR}:
	mkdir -p $@

.PHONY: $(STEPS)
$(STEPS): ${BUILD_DIR} ${STAGING_DIR}
	BUILD_DIR=${BUILD_DIR} \
	STAGING_DIR=${STAGING_DIR} \
	DSTREAM_DL_URL=${DSTREAM_DL_URL} \
	release/$@.sh

.NOTPARALLEL: release
release: prologue koji content mixer images stage

.PHONY: serve
serve: ${STAGING_DIR}
	cd ${STAGING_DIR}; python -mSimpleHTTPServer
