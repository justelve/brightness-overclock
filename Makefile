APP_NAME   = BrightnessOverclock
BUILD_DIR  = .build/release
APP_BUNDLE = build/$(APP_NAME).app
IDENTITY  ?= $(shell security find-identity -v -p codesigning 2>/dev/null | grep -m1 "Apple Development" | sed -E 's/.*"(.+)".*/\1/')

.PHONY: build test app run install clean

build:
	swift build -c release

test:
	swift test

app: build
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	cp $(BUILD_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp Resources/Info.plist $(APP_BUNDLE)/Contents/Info.plist
ifneq ($(strip $(IDENTITY)),)
	codesign --force --sign "$(IDENTITY)" $(APP_BUNDLE)
else
	@echo "WARNING: no 'Apple Development' identity found - ad-hoc signing." \
	      "Accessibility grant will NOT survive rebuilds (see spec Build & signing)."
	codesign --force --sign - $(APP_BUNDLE)
endif

run: app
	open $(APP_BUNDLE)

install: app
	-killall $(APP_NAME) 2>/dev/null || true
	rm -rf /Applications/$(APP_NAME).app
	cp -R $(APP_BUNDLE) /Applications/
	open /Applications/$(APP_NAME).app

clean:
	rm -rf .build build
