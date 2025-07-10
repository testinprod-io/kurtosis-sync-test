# Default wait time (in seconds)
WAIT_TIME ?= 1800

all: run clean

run:
	./synctest.sh -t $(WAIT_TIME)

# Run sync test with supernode enabled
run-supernode:
	./synctest.sh -t $(WAIT_TIME) -s

clean:
	kurtosis clean -a

# Add these new targets
run-no-wait:
	./synctest.sh -t 0

run-custom-wait:
	@read -p "Enter wait time in seconds: " wait_time; \
	./synctest.sh -t $$wait_time

# PeerDAS sync test targets
# Usage examples:
#   make peerdas-test                                    # Test all clients
#   make peerdas-test ARGS="-c lighthouse"              # Test specific client
#   make peerdas-test ARGS="-c teku --genesis-sync"     # Test with genesis sync
#   make peerdas-test ARGS="-c lighthouse -e nethermind" # Test with specific EL
#   make peerdas-test ARGS="-c lighthouse --supernode"  # Test with supernode enabled
#   make peerdas-test ARGS="-h"                         # Show help
peerdas-test:
	./peerdas-sync-test.sh $(ARGS)

.PHONY: all run clean run-no-wait run-custom-wait peerdas-test