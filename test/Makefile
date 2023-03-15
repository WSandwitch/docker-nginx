PLATFORM_TAG ?= amd64
DOCKER_TAG ?= latest_$(PLATFORM_TAG)
DOCKER_IMAGE ?= wsandwitch/nginx-extra:$(DOCKER_TAG)
TESTS = check jaeger njs proxy_connect redis sticky mruby

.PHONY: all build test clean $(TESTS)
all: build test
test: $(TESTS)

build:
	docker buildx build --platform linux/$(PLATFORM_TAG) -t $(DOCKER_IMAGE) --load ..

$(TESTS):
	cd $@; \
	DOCKER_IMAGE=$(DOCKER_IMAGE) docker-compose up --build --abort-on-container-exit

clean:
	rm -rf */node_modules
