PYTHON ?= python3

.PHONY: all build test
all: test build

build:
	$(PYTHON) tools/build.py

test:
	$(PYTHON) -m unittest discover -s tests -v
