.PHONY: build build-typoi build-typos test integration-test e2e-test

BUILD_COMMIT ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo unknown)

build: build-typoi

build-typoi:
	nim c -d:release -d:BuildCommitHash=$(BUILD_COMMIT) -o:typoi src/typoi.nim

build-typos:
	nim c -d:release -d:BuildCommitHash=$(BUILD_COMMIT) -o:typos src/Typos.nim

test:
	@found=0; \
	for f in tests/test_*.nim; do \
		[ -e "$$f" ] || continue; \
		found=1; \
		echo "--- $$f ---"; \
		nim r "$$f" || exit 1; \
	done; \
	if [ $$found -eq 0 ]; then \
		echo "No unit tests found in tests/test_*.nim"; \
	fi

integration-test:
	@found=0; \
	for f in tests/integration_*.nim; do \
		[ -e "$$f" ] || continue; \
		found=1; \
		echo "--- $$f ---"; \
		nim r "$$f" || exit 1; \
	done; \
	if [ $$found -eq 0 ]; then \
		echo "No integration tests found in tests/integration_*.nim"; \
	fi

e2e-test:
	@found=0; \
	for f in tests/e2e_*.nim; do \
		[ -e "$$f" ] || continue; \
		found=1; \
		echo "--- $$f ---"; \
		nim r "$$f" || exit 1; \
	done; \
	if [ $$found -eq 0 ]; then \
		echo "No e2e tests found in tests/e2e_*.nim"; \
	fi
