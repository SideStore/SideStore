SHELL := /bin/bash
.PHONY: help ios update tvos

RUBY := $(shell command -v ruby 2>/dev/null)
HOMEBREW := $(shell command -v brew 2>/dev/null)
BUNDLER := $(shell command -v bundle 2>/dev/null)

default: help

# Add the following 'help' target to your Makefile
# And add help text after each target name starting with '\#\#'
# A category can be added with @category

# COLORS
GREEN  := $(shell tput -Txterm setaf 2)
YELLOW := $(shell tput -Txterm setaf 3)
WHITE  := $(shell tput -Txterm setaf 7)
RESET  := $(shell tput -Txterm sgr0)

## ----- Helper functions ------

# Helper target for declaring an external executable as a recipe dependency.
# For example,
#   `my_target: | _program_awk`
# will fail before running the target named `my_target` if the command `awk` is
# not found on the system path.
_program_%: FORCE
	@_=$(or $(shell which $* 2> /dev/null),$(error `$*` command not found. Please install `$*` and try again))

# Helper target for declaring required environment variables.
#
# For example,
#   `my_target`: | _var_PARAMETER`
#
# will fail before running `my_target` if the variable `PARAMETER` is not declared.
_var_%: FORCE
	@_=$(or $($*),$(error `$*` is a required parameter))

_tag: | _var_VERSION
	make --no-print-directory -B README.md
	git commit -am "Tagging release $(VERSION)"
	git tag -a $(VERSION) $(if $(NOTES),-m '$(NOTES)',-m $(VERSION))
.PHONY: _tag

_push: | _var_VERSION
	git push origin $(VERSION)
	git push origin master
.PHONY: _push

## ------ Commmands -----------

TARGET_MAX_CHAR_NUM=20
## Show help
help:
	@echo ''
	@echo 'Usage:'
	@echo '  ${YELLOW}make${RESET} ${GREEN}<target>${RESET}'
	@echo ''
	@echo 'Targets:'
	@awk '/^[a-zA-Z\-\_0-9]+:/ { \
		helpMessage = match(lastLine, /^## (.*)/); \
		if (helpMessage) { \
			helpCommand = substr($$1, 0, index($$1, ":")-1); \
			helpMessage = substr(lastLine, RSTART + 3, RLENGTH); \
			printf "  ${YELLOW}%-$(TARGET_MAX_CHAR_NUM)s${RESET} ${GREEN}%s${RESET}\n", helpCommand, helpMessage; \
		} \
	} \
	{ lastLine = $$0 }' \
	$(MAKEFILE_LIST)

## Install dependencies.
setup: \
	pre_setup

# check_for_homebrew \
# update_homebrew \

pull_request: \
	test \
	codecov_upload \
	danger

pre_setup:
	$(info Project setup…)

check_for_ruby:
	$(info Checking for Ruby…)

ifeq ($(RUBY),)
	$(error Ruby is not installed.)
endif

check_for_homebrew:
	$(info Checking for Homebrew…)

ifeq ($(HOMEBREW),)
	$(error Homebrew is not installed)
endif

update_homebrew:
	$(info Updating Homebrew…)

	brew update

install_swift_lint:
	$(info Install swiftlint…)

	brew unlink swiftlint || true
	brew install swiftlint
	brew link --overwrite swiftlint

install_bundler_gem:
	$(info Checking and installing bundler…)

ifeq ($(BUNDLER),)
	gem install bundler -v '~> 1.17'
else
	gem update bundler '~> 1.17'
endif

install_ruby_gems:
	$(info Installing Ruby gems…)

	bundle install

pull:
	$(info Pulling new commits…)

	git stash push || true
	git pull
	git stash pop || true

## -- Source Code Tasks --

## Pull upstream and update 3rd party frameworks
update: submodules

submodules:
	$(info Updating submodules…)

	git submodule update --init --recursive --remote

## -- QA Task Runners --

codecov_upload:
	curl -s https://codecov.io/bash | bash

danger:
	bundle exec danger

## -- Testing --

## Run test on all targets
test:
	bundle exec fastlane test

## -- Building --

build:
	@xcodebuild -workspace AltStore.xcworkspace \
				-scheme SideStore \
				-sdk iphoneos \
				archive -archivePath ./archive \
				CODE_SIGNING_REQUIRED=NO \
				AD_HOC_CODE_SIGNING_ALLOWED=YES \
				CODE_SIGNING_ALLOWED=NO \
				DEVELOPMENT_TEAM=XYZ0123456 \
				ORG_IDENTIFIER=com.SideStore \
				DWARF_DSYM_FOLDER_PATH="."

fakesign:
	rm -rf archive.xcarchive/Products/Applications/SideStore.app/Frameworks/AltStoreCore.framework/Frameworks/
	ldid -SAltStore/Resources/ReleaseEntitlements.plist archive.xcarchive/Products/Applications/SideStore.app/SideStore
	ldid -SAltWidget/Resources/ReleaseEntitlements.plist archive.xcarchive/Products/Applications/SideStore.app/PlugIns/AltWidgetExtension.appex/AltWidgetExtension

ipa:
	mkdir Payload
	mkdir Payload/SideStore.app
	cp -R archive.xcarchive/Products/Applications/SideStore.app/ Payload/SideStore.app/
	zip -r SideStore.ipa Payload

# Global Variables

# Ensure this is set by the environment or passed as an argument
CONFIGURATION_BUILD_DIR ?= # this is the path to your main app (possibly in derived-data unless changed manually)
CODESIGNING_FOLDER_PATH ?= # this is the path to your main app (possibly in derived-data unless changed manually)

# CONFIGURATION_BUILD_DIR = # this is the path to your main app (possibly in derived-data unless changed manually)
# CODESIGNING_FOLDER_PATH = # this is the path to your main app (possibly in derived-data unless changed manually)

ROOT_DIR 			:= $(CONFIGURATION_BUILD_DIR)
ROOT_DIR 			:= $(if $(ROOT_DIR),$(ROOT_DIR),$(CODESIGNING_FOLDER_PATH)/..)
VAR_USED			:= $(if $(CONFIGURATION_BUILD_DIR),"CONFIGURATION_BUILD_DIR","CODESIGNING_FOLDER_PATH")

TARGET_BUILD_DIR 	:= build
TARGET_ARCHIVE_DIR 	:= altbackup.xcarchive
TARGET_NAME 		:= AltBackup.app
TARGET_DSYM_NAME 	:= AltBackup.app.dSYM
TARGET_IPA_NAME 	:= AltBackup.ipa


ALT_APP_SRC_PARENT 	:= $(shell readlink -f "$(ROOT_DIR)")
ALT_APP_SRC 		:= $(ALT_APP_SRC_PARENT)/$(TARGET_NAME)
ALT_APP_DSYM_SRC 	:= $(ALT_APP_SRC_PARENT)/$(TARGET_DSYM_NAME)
ALT_APP_DST_ARCHIVE := "$(TARGET_BUILD_DIR)/$(TARGET_ARCHIVE_DIR)"
ALT_APP_DST 		:= "$(ALT_APP_DST_ARCHIVE)/Products/Applications/$(TARGET_NAME)"
ALT_APP_DSYM_DST 	:= "$(ALT_APP_DST_ARCHIVE)/dSYMs/$(TARGET_DSYM_NAME)"
ALT_APP_PAYLOAD_DST := "$(ALT_APP_DST_ARCHIVE)/Payload"
ALT_APP_IPA_DST 	:= "$(TARGET_BUILD_DIR)/$(TARGET_IPA_NAME)"

checkPaths:
	@# Check if ALT_APP_SRC_PARENT is empty, abort if true
	@if [ -z "$(ALT_APP_SRC_PARENT)" ]; then \
		echo "Error: ALT_APP_SRC_PARENT is empty!"; \
		echo "       Environment variable $$VAR_USED = $$APP_PATH"; \
		echo "       Please set it to a valid build artifacts directory"; \
		echo ""; \
		exit 1; \
	fi


copy-altbackup: checkPaths
	@echo ''
	@echo "  CONFIGURATION_BUILD_DIR = '$(CONFIGURATION_BUILD_DIR)'"
	@echo "  CODESIGNING_FOLDER_PATH = '$(CODESIGNING_FOLDER_PATH)'"
	@echo "  Copying archive data from ALT_APP_SRC_PARENT = '$(ALT_APP_SRC_PARENT)'"
	@echo ''

	@bash -c '\
		SOURCES=("$(ALT_APP_SRC)" "$(ALT_APP_DSYM_SRC)"); \
		TARGETS=("$(ALT_APP_DST)" "$(ALT_APP_DSYM_DST)"); \
		TARGET_NAMES=("$(TARGET_NAME)" "$(TARGET_DSYM_NAME)"); \
		\
		for i in "$${!SOURCES[@]}"; do \
			SRC="$${SOURCES[$$i]}"; \
			TGT="$${TARGETS[$$i]}"; \
			TGT_NAME="$${TARGET_NAMES[$$i]}"; \
			\
			echo "  Copying $$TGT_NAME from \"$$SRC\""; \
			if [ ! -d "$$SRC" ]; then \
				echo "SRC=$$SRC ALT_APP_DSYM_SRC=$(ALT_APP_DSYM_SRC)"; \
				if [ "$$SRC" == "$(ALT_APP_DSYM_SRC)" ]; then \
					echo "Warning: $$TGT_NAME not found in \"$$SRC\" - IGNORED"; \
					echo ""; \
				else \
					echo "Error: $$TGT_NAME not found in \"$$SRC\""; \
					echo ""; \
					exit 1; \
				fi \
			else \
				rm -rf "$$TGT"; \
				mkdir -p "$$TGT"; \
				cp -R "$(ALT_APP_SRC_PARENT)/$(TGT_NAME)" "$$TGT"; \
				echo "  Copied  $$TGT_NAME into TARGET = $$TGT"; \
				echo ""; \
			fi; \
		done \
	'
	@find "$(ALT_APP_DST_ARCHIVE)" -maxdepth 3 -exec ls -ld {} + || true
	@echo ''

# fakesign-altbackup: copy-altbackup
# 	@echo "  Adding homebrew binaries to path and invoke ldid"
# 	@export PATH="/usr/local/bin:/opt/homebrew/bin:$$PATH"; \
# 	ldid -SAltBackup/Resources/ReleaseEntitlements.plist $(ALT_APP)
# 	@echo "  fakesign completed"
# 	@echo ""
	
# ipa-altbackup:
ipa-altbackup: checkPaths copy-altbackup 
# ipa-altbackup: checkPaths copy-altbackup fakesign-altbackup
	@echo "  Creating IPA for AltBackup"
	@rm -rf 	"$(ALT_APP_PAYLOAD_DST)"
	@mkdir -p 	"$(ALT_APP_PAYLOAD_DST)/$(TARGET_NAME)"
	@echo " Copying from $(ALT_APP_SRC) into $(ALT_APP_PAYLOAD_DST)"
	@cp -R -f	"$(ALT_APP_SRC)/" "$(ALT_APP_PAYLOAD_DST)/$(TARGET_NAME)"
	@pushd 		"$(ALT_APP_DST_ARCHIVE)" && zip -r "../../$(ALT_APP_IPA_DST)" Payload && popd
	@cp	   -f	"$(ALT_APP_IPA_DST)" AltStore/Resources
	@echo "  IPA created: AltStore/Resources/AltBackup.ipa"