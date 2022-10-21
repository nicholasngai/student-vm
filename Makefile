OUT_DIR = out
IMAGE_FILE_QCOW2 = $(OUT_DIR)/cs162-student-vm.qcow2
IMAGE_FILE_OVA = $(OUT_DIR)/cs162-student-vm.ova

DOCKER_IMAGE_NAME = cs162-student-vm
DOCKER_CONTAINER_NAME = cs162-student-vm

.PHONY: all
all: $(IMAGE_FILE_QCOW2) $(IMAGE_FILE_OVA)

# Touch the directory so it's up to date.
$(OUT_DIR):
	mkdir -p $(OUT_DIR)
	touch $(OUT_DIR)

# Copy the QCOW2 image from the docker image to the filesystem.
$(IMAGE_FILE_QCOW2): $(OUT_DIR) docker
	docker run --rm $(DOCKER_CONTAINER_NAME) cat cs162-student-vm.qcow2 > $(IMAGE_FILE_QCOW2)

# Copy the OVA image from the docker image to the filesystem.
$(IMAGE_FILE_OVA): $(OUT_DIR) docker
	docker run --rm $(DOCKER_CONTAINER_NAME) cat cs162-student-vm.ova > $(IMAGE_FILE_OVA)

.PHONY: docker
docker:
	docker build -t $(DOCKER_IMAGE_NAME)

.PHONY: clean
clean:
	rm -rf $(OUT_DIR)
	docker image rm \
		$(DOCKER_IMAGE_NAME) \
		2>/dev/null || :
	docker rm -f $(DOCKER_CONTAINER_NAME)
