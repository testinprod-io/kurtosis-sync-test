# Default wait time (in seconds)
WAIT_TIME ?= 1800

all: run clean

run:
	./synctest.sh -t $(WAIT_TIME)

clean:
	kurtosis clean -a

# Add these new targets
run-no-wait:
	./synctest.sh -t 0

run-custom-wait:
	@read -p "Enter wait time in seconds: " wait_time; \
	./synctest.sh -t $$wait_time

# PeerDAS sync test targets
peerdas-test:
	./peerdas-sync-test.sh

peerdas-test-client:
	@read -p "Enter CL client name (lighthouse/teku/prysm/nimbus/lodestar/grandine): " client; \
	./peerdas-sync-test.sh -c $$client

peerdas-test-custom:
	@read -p "Enter CL client name: " client; \
	read -p "Enter Docker image: " image; \
	./peerdas-sync-test.sh -c $$client -i $$image