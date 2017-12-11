STEPS := $(patsubst %.sh,%,$(notdir $(wildcard $(CURDIR)/release/*.sh)))

all:
	@echo "use 'make release' to run all steps or 'make STEP'"
	@echo "where STEP is one of: ${STEPS}"

.PHONY: $(STEPS)
$(STEPS):
	mkdir -p $(CURDIR)/tmp/{build,release}
	BUILD_DIR=$(CURDIR)/tmp/build STAGING_DIR=$(CURDIR)/tmp/release release/$@.sh

.NOTPARALLEL: release
release: prologue mixer ister stage
