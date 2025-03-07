.PHONY: all test clean build coverage gas-report sizes help

# Default target
all: clean build test

# Clean the repo
clean:
	forge clean
	rm -rf coverage/
	rm -rf .gas-report
	rm -rf sizes.txt

# Build the project
build:
	forge build

# Run tests
test:
	forge test -f $(RPC_URL) -vvv

# Run coverage
coverage:
	forge coverage -f $(RPC_URL) --report lcov
	genhtml --branch-coverage --dark-mode -o ./coverage/ lcov.info

# Generate gas report
gas-report:
	forge test -f $(RPC_URL) --gas-report --fuzz-seed 1 | grep '^|' > .gas-report

# Check contract sizes
sizes:
	forge build --sizes > sizes.txt