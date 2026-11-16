DERIVED := build
APP := $(DERIVED)/Build/Products/Release/TapisMarche.app

.PHONY: test project build install run

test:
	cd WalkingPadKit && swift test

project:
	xcodegen generate

build: project
	xcodebuild -project TapisMarche.xcodeproj -scheme TapisMarche -configuration Release \
		-derivedDataPath $(DERIVED) build

install:
	rm -rf /Applications/TapisMarche.app
	cp -R $(APP) /Applications/

run:
	open $(APP)
