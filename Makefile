common_CHECKOPTS := --exclude=2034,2164
common_SRC := $(wildcard *.sh)

pipelines := build koji watcher

koji_SRC := $(wildcard $(CURDIR)/koji/*.sh)
koji_STEPS := $(patsubst %.sh,%,$(notdir $(koji_SRC)))

build_CHECKOPTS := --exclude=2013,2024,2155
build_SRC := $(wildcard $(CURDIR)/build/*.sh)
build_STEPS := init-env local content mixer mca-check images license_info release_notes stage #skipping: koji publish

watcher_SRC := $(wildcard $(CURDIR)/watcher/*.sh)
watcher_STEPS := $(patsubst %.sh,%,$(notdir $(watcher_SRC)))

SRC := $(common_SRC) $(koji_SRC) $(build_SRC) $(watcher_SRC)

all:
	@echo "Welcome to clr-distro-factory."
	@echo ""
	@echo "The 'make' targets of this project are for development purpose."
	@echo "Please, access the online documentation for information about how"
	@echo "to use and deploy this project in a production environment:"
	@echo ""
	@echo "    https://github.com/clearlinux/clr-distro-factory/wiki"
	@echo ""
	@echo "Usage:"
	@echo ""
	@echo "'make <pipeline>'        To run all steps of a pipeline'"
	@echo ""
	@echo "'make <pipeline>/<step>' To run an individual step. Steps may depend on"
	@echo "                         the output of previous steps. It is up for the"
	@echo "                         developer to fullfil its requirements."
	@echo ""
	@echo "'make serve'             To run a webserver hosting updates."
	@echo "                         Requires Python's SimpleHTTPServer."
	@echo ""
	@echo "pipelines: $(pipelines)"
	@echo ""
	@echo "build steps: $(build_STEPS)"
	@echo ""
	@echo "koji steps: $(koji_STEPS)"
	@echo ""
	@echo "watcher steps: $(watcher_STEPS)"

NAMESPACE ?= developer-distro
CONFIG_REPO_HOST ?= $(CURDIR)/builder/
CLR_BUNDLES ?= "bootloader kernel-native os-core os-core-update"

HOSTNAME := $(shell hostname -f)
DISTRO_URL ?= http://$(HOSTNAME):8000/

MIXER_DIR := $(CURDIR)/builder/mixer
CONFIG_REPO := $(CURDIR)/builder/$(NAMESPACE)
STAGING_DIR := $(CURDIR)/builder/stage
WORK_DIR := $(CURDIR)/builder/work

$(MIXER_DIR) $(STAGING_DIR) $(WORK_DIR):
	@mkdir -p $@

$(CONFIG_REPO):
	@mkdir -p $@
	@git init $@
	@echo "DISTRO_NAME=$(NAMESPACE)" > $@/config.sh
	@echo "DISTRO_URL=$(DISTRO_URL)" >> $@/config.sh
	@echo "MIXER_DIR=$(MIXER_DIR)" >> $@/config.sh
	@echo "STAGING_DIR=$(STAGING_DIR)" >> $@/config.sh
	@git -C $@ add config.sh
	@git -C $@ commit -m "Fake config.sh"

config: $(MIXER_DIR) $(STAGING_DIR) $(CONFIG_REPO)

.NOTPARALLEL: $(pipelines)
.PHONY: $(pipelines)

koji: $(addprefix koji/,$(koji_STEPS))
.PHONY: $(addprefix koji/,$(koji_STEPS))
$(addprefix koji/,$(koji_STEPS)):
	@NAMESPACE=$(NAMESPACE) \
	$@.sh

watcher: $(addprefix watcher/,$(watcher_STEPS))
.PHONY: $(addprefix watcher/,$(watcher_STEPS))
$(addprefix watcher/,$(watcher_STEPS)): config
	@NAMESPACE=$(NAMESPACE) \
	CONFIG_REPO_HOST=$(CONFIG_REPO_HOST) \
	$@.sh

build: $(addprefix build/,$(build_STEPS))
.PHONY: $(addprefix build/,$(build_STEPS))
$(addprefix build/,$(build_STEPS)): config $(WORK_DIR)
	@NAMESPACE=$(NAMESPACE) \
	CONFIG_REPO_HOST=$(CONFIG_REPO_HOST) \
	CLR_BUNDLES=$(CLR_BUNDLES) \
	WORK_DIR=$(WORK_DIR) \
	$@.sh

.PHONY: serve
serve: $(STAGING_DIR)
	cd $(STAGING_DIR); python3 -m http.server

.PHONY: clean
clean:
	rm -rf $(CURDIR)/builder

# Static Code Analysis
# ====================
check_CHECKOPTS := --exclude=1091
check_PIPELINES = check-common $(addprefix check-,$(pipelines))
$(check_PIPELINES): pipe = $(patsubst check-%,%,$@)
$(check_PIPELINES):
	shellcheck -x $(check_CHECKOPTS) $($(pipe)_CHECKOPTS) $($(pipe)_SRC)

check: check-common $(check_PIPELINES)
