APP=AgentDeck
DERIVED=build
CONFIG?=Release
APP_PATH=$(DERIVED)/Build/Products/$(CONFIG)/$(APP).app

.PHONY: gen build run install clean

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
