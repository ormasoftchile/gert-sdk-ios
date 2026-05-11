# gert-sdk-ios developer commands.
#
# The compose example ships a copy of the gert-domain-home starter
# templates inside its bundle resources because Swift Package Manager's
# `.copy` rule does not follow symlinks. Run `make sync-templates`
# whenever the canonical templates change.

GERT_DOMAIN_HOME ?= ../gert-domain-home
COMPOSE_RESOURCES := Examples/ComposeExample/Resources/templates

.PHONY: sync-templates
sync-templates:
	@if [ ! -d "$(GERT_DOMAIN_HOME)/templates/routine" ]; then \
		echo "Cannot find $(GERT_DOMAIN_HOME)/templates/routine — set GERT_DOMAIN_HOME"; exit 1; \
	fi
	@mkdir -p $(COMPOSE_RESOURCES)/routine
	@cp $(GERT_DOMAIN_HOME)/templates/routine/*.template.yaml $(COMPOSE_RESOURCES)/routine/
	@echo "Copied $$(ls $(GERT_DOMAIN_HOME)/templates/routine | wc -l) templates from $(GERT_DOMAIN_HOME)"

.PHONY: check-templates
check-templates:
	@if [ ! -d "$(GERT_DOMAIN_HOME)/templates/routine" ]; then \
		echo "Cannot find $(GERT_DOMAIN_HOME)/templates/routine — set GERT_DOMAIN_HOME"; exit 1; \
	fi
	@diff -r $(GERT_DOMAIN_HOME)/templates/routine $(COMPOSE_RESOURCES)/routine \
		&& echo "Templates in sync." \
		|| (echo "Templates DIVERGED — run 'make sync-templates'"; exit 1)

.PHONY: test
test:
	swift test

.PHONY: build-examples
build-examples:
	swift build --target ComposeExample
	swift build --target HomeAutomationExample
