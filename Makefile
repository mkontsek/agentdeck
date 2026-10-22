APP=AgentDeck
DERIVED=build
CONFIG?=Release
APP_PATH=$(DERIVED)/Build/Products/$(CONFIG)/$(APP).app

.PHONY: gen build run install clean icon

gen:
	xcodegen generate

build: gen
	xcodebuild -project $(APP).xcodeproj -scheme $(APP) -configuration $(CONFIG) \
	  -derivedDataPath $(DERIVED) -destination "platform=macOS" -skipPackagePluginValidation -skipMacroValidation CODE_SIGN_IDENTITY=- build | tail -5

run: build
	open $(APP_PATH)

install: build
	rm -rf /Applications/$(APP).app
	cp -R $(APP_PATH) /Applications/$(APP).app
	@echo "Installed to /Applications/$(APP).app"

clean:
	rm -rf $(DERIVED) $(APP).xcodeproj

# Re-render the app icon from scripts/make-icon.swift
icon:
	mkdir -p $(DERIVED)/icon/AppIcon.iconset
	swift scripts/make-icon.swift $(DERIVED)/icon/icon1024.png
	for sz in 16 32 128 256 512; do \
	  sips -z $$sz $$sz $(DERIVED)/icon/icon1024.png --out $(DERIVED)/icon/AppIcon.iconset/icon_$${sz}x$${sz}.png >/dev/null; \
	  sips -z $$((sz*2)) $$((sz*2)) $(DERIVED)/icon/icon1024.png --out $(DERIVED)/icon/AppIcon.iconset/icon_$${sz}x$${sz}@2x.png >/dev/null; \
	done
	iconutil -c icns $(DERIVED)/icon/AppIcon.iconset -o Resources/AppIcon.icns
