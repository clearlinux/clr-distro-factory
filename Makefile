STEPS := $(patsubst %.sh,%,$(notdir $(wildcard $(CURDIR)/release/*.sh)))

all:
	@echo "use 'make STEP'"
	@echo "where STEP is one of: ${STEPS}"

.PHONY: $(STEPS)
$(STEPS):
	mkdir -p $(CURDIR)/tmp/{build,release}
	BUILD_DIR=$(CURDIR)/tmp/build STAGING_DIR=$(CURDIR)/tmp/release release/$@.sh
