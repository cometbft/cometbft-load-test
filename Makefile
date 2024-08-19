GOPATH ?= $(shell go env GOPATH)
BUILD_DIR ?= $(CURDIR)/build
.DEFAULT_GOAL := build
BUILD_FLAGS ?= -mod=readonly

build:
	@go build $(BUILD_FLAGS) \
		-ldflags "-X github.com/cometbft/cometbft-load-test/pkg/loadtest.cliVersionCommitID=`git rev-parse --short HEAD`" \
		-o $(BUILD_DIR)/cometbft-load-test ./cmd/cometbft-load-test/main.go
.PHONY: build

build-linux:
	GOOS=linux GOARCH=amd64 $(MAKE) build
.PHONY: build-linux

test:
	go test -cover -race ./...
.PHONY: test

# Builds a Docker image called "cometbft/localnode", which is based on
# CometBFT. Takes the current system user and group ID as the user/group IDs
# for the cmtuser user within the container so as to eliminate permissions
# issues when generating testnet files in the localnet target.
localnode:
	@docker build -f ./test/localnode/Dockerfile \
		--build-arg UID=$(shell id -u) \
		--build-arg GID=$(shell id -g) \
		-t cometbft/localnode:latest \
		./test/localnode/
.PHONY: localnode

localnet: localnode
	@if ! [ -f build/node0/config/genesis.json ]; then \
		mkdir -p build && \
		docker run \
			--rm \
			-v $(BUILD_DIR):/cometbft:Z \
			cometbft/localnode \
			testnet --config /etc/cometbft/config-template.toml --o . --starting-ip-address 192.168.10.2; \
	fi
.PHONY: localnet

localnet-start: localnet
	@docker compose -f ./test/docker-compose.yml up -d
.PHONY: localnet-start

localnet-stop:
	@docker compose -f ./test/docker-compose.yml down
.PHONY: localnet-stop

integration-test:
	@./test/integration-test.sh
.PHONY: integration-test

bench:
	go test -bench="Benchmark" -run="notests" ./...
.PHONY: bench

clean:
	rm -rf $(BUILD_DIR)
.PHONY: clean

###############################################################################
###                  Formatting, linting, and vetting                       ###
###############################################################################

#? lint: Lint, format and fix typos
lint: pre-commit
	@pre-commit run
.PHONY: lint

#? vulncheck: Run latest govulncheck
vulncheck:
	@go run golang.org/x/vuln/cmd/govulncheck@latest ./...
.PHONY: vulncheck

#? pre-commit: Create pre-commit hook using the pre-commit framework.
pre-commit:
	@which pre-commit || pip3 install pre-commit
	@pre-commit install
.PHONY: pre-commit
