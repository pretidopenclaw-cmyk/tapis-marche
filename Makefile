DERIVED := build
# Signing: ad-hoc by default. Put your own values in Local.mk (git-ignored), e.g.
#   DEVELOPMENT_TEAM := ABCDE12345
#   CODE_SIGN_IDENTITY := Apple Development
DEVELOPMENT_TEAM ?=
CODE_SIGN_IDENTITY ?= -
-include Local.mk
APP := $(DERIVED)/Build/Products/Release/TapisMarche.app

.PHONY: test project build install run

test:
	cd WalkingPadKit && swift test

project:
	xcodegen generate

build: project
	xcodebuild -project TapisMarche.xcodeproj -scheme TapisMarche -configuration Release \
		-derivedDataPath $(DERIVED) DEVELOPMENT_TEAM="$(DEVELOPMENT_TEAM)" CODE_SIGN_IDENTITY="$(CODE_SIGN_IDENTITY)" build

install:
	rm -rf /Applications/TapisMarche.app
	cp -R $(APP) /Applications/

run:
	open $(APP)
