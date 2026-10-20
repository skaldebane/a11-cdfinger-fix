PYTHON ?= python3

.PHONY: all build test monitor
all: test build

build:
	$(PYTHON) tools/build.py

test:
	$(PYTHON) -m unittest discover -s tests -v

monitor: test
	$(PYTHON) monitor/build.py
