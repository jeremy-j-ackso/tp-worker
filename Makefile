# tp-worker Makefile

# Variables
PROTO_DIR = proto
PROTO_FILES = $(wildcard $(PROTO_DIR)/*.proto)
PROTOC = protoc

# Default target
.PHONY: all
all: proto

# Generate protobuf files
.PHONY: proto
proto: $(PROTO_FILES)
	$(PROTOC) \
		--go_out=$(PROTO_DIR) \
		--go_opt=paths=source_relative \
		--go-grpc_out=$(PROTO_DIR) \
		--go-grpc_opt=paths=source_relative \
		--proto_path=$(PROTO_DIR) \
		$(PROTO_FILES)

# Clean generated files
.PHONY: clean
clean:
	rm -f $(PROTO_DIR)/*.pb.go
